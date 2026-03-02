# HLD — ViaBTC Exchange Server

## 1) Qué se está construyendo

### Qué es la aplicación
`viabtc_exchange_server` es un backend de exchange de criptomonedas orientado a baja latencia y alto throughput, compuesto por múltiples procesos en C que colaboran por RPC, Kafka, Redis y MySQL. El repositorio declara explícitamente que `matchengine` es el núcleo de matching y balances, y que los módulos de acceso HTTP/WS, precios y lectura de histórico desacoplan el acceso externo del core transaccional.

### Para quién es
- Equipos de plataforma de exchanges cripto.
- Equipos de operaciones/infra que despliegan servicios de trading con observabilidad y alertas.
- Equipos de backend/API que exponen interfaces HTTP y WebSocket para clientes, bots y UIs.

### Qué problema resuelve
- Ejecutar órdenes de compra/venta y mantener balances consistentes en memoria con persistencia.
- Escalar lectura pública/privada separando paths críticos (matching) de paths de consulta/streaming.
- Publicar datos de mercado en tiempo real (deals, depth, kline, ticker) y consultar historial consolidado.

### Cómo funciona (visión sistémica)
1. **Ingreso de órdenes/comandos** por `accesshttp` o `accessws`.
2. **Delegación RPC** a `matchengine` para operaciones de cuenta y trading.
3. **Persistencia/event sourcing parcial** en MySQL (`trade_log`, `trade_history`) y snapshot/slices.
4. **Publicación de eventos** (deals/orders/balances) a Kafka.
5. **Consumo de eventos** por `marketprice` y `accessws` para caches y streaming.
6. **Consulta de histórico** por `readhistory` desde MySQL.
7. **Alerting** por `alertcenter`, que centraliza eventos fatales vía Redis para notificación externa.

### Conceptos principales y relaciones
- **Asset**: activo con precisión de almacenamiento y visualización.
- **Market**: par de trading (stock/money), precision y mínimo de orden.
- **Order**: estado de orden viva/finalizada, con side, fees y montos ejecutados.
- **Deal/Trade**: ejecución emparejada entre órdenes.
- **Balance**: saldo por usuario/activo, sujeto a freeze/unfreeze.
- **Operlog**: log de operaciones reejecutable para recuperación del estado.
- **Slices**: snapshots de estado para acelerar recovery.

Relaciones:
- `Market` referencia dos `Asset`.
- `Order` pertenece a (`user_id`, `market`) y produce `Deal`.
- `Deal` impacta `Balance` y genera eventos Kafka.
- `readhistory` consulta tablas históricas derivadas de `matchengine`.

### Notas de enfoque (zoom out/zoom in + MVP)
- **Zoom out**: arquitectura por procesos desacoplados, con core de consistencia (`matchengine`) y bordes de exposición (`accesshttp`/`accessws`).
- **Zoom in**: funciones pequeñas por módulo (`*_config`, `*_server`, `*_message`, `*_history`, etc.).
- **Distilling model**: mantener el modelo transaccional mínimo en el core y mover agregaciones/caches a módulos satélite (`marketprice`, `accessws`).

---

## 2) Diseño de experiencia de usuario (API consumers)

> En este repositorio la “UX” es de APIs y streams, no UI web embebida.

### User stories (happy flows)
1. **Trader coloca orden limit**
   - Cliente llama HTTP/WS en `accesshttp`/`accessws`.
   - Gateway valida/normaliza y envía a `matchengine`.
   - `matchengine` ejecuta matching, actualiza balances y emite eventos.
   - Cliente recibe respuesta síncrona + updates asíncronos (órdenes/deals/balance).

2. **Usuario consulta libro y ticker**
   - Cliente se suscribe por WebSocket (`accessws`).
   - `accessws` usa cache/mensajería para depth/kline/price/state/today/deals.
   - Se reciben pushes periódicos o por evento.

3. **Backoffice consulta histórico**
   - Cliente llama endpoint en `accesshttp`.
   - `accesshttp` enruta consulta a `readhistory`.
   - `readhistory` obtiene datos de MySQL y responde.

### Alternative flows
- **Timeout en backend RPC**: gateways (`accesshttp`/`accessws`) aplican timeout de backend y responden error controlado.
- **Caída de worker**: procesos usan watchdog/keepalive para reinicio automático.
- **Reinicio de matchengine**: reconstrucción de estado desde slices + operlog.
- **Fallo auth/sign externo en WS**: denegar subscripción/operación privada.

### Impacto en estructura de interfaz
- HTTP: endpoint único de entrada con enrutado por método.
- WS: canal con métodos server/client y suscripciones (privadas requieren auth).
- Nginx recomendado delante para WSS.

### Wireframe textual de flujos
- **HTTP trade**: `Client -> accesshttp(listener/worker) -> matchengine RPC -> response`
- **WS private**: `Client -> accessws(listener/worker) -> auth_url/sign_url -> subscribe -> kafka/rpc events -> push`
- **Market data**: `matchengine -> Kafka(deals/orders/balances) -> marketprice/accessws -> client push`

---

## 3) Necesidades técnicas

### Diseño técnico general
- Lenguaje C (GNU99), arquitectura multiproceso/event loop (`libev` y librerías internas `network`/`utils`).
- Patrón común por servicio:
  1. `init_config`
  2. `init_process` (límites de OS)
  3. `init_log` (+ alert)
  4. `daemon + keepalive`
  5. `init_*` de dominio
  6. `nw_loop_run`

### Componentes principales
- **network/**: sockets TCP/UDP/UNIX, eventos, timers, jobs/threadpool.
- **utils/**: config JSON, RPC client/server, HTTP/WS parsing, logging, MySQL/Kafka wrappers.
- **matchengine/**: core matching, balances, history, persistencia, mensajería, CLI admin.
- **marketprice/**: consume `deals` de Kafka, genera kline/market data, persiste cache en Redis Sentinel.
- **readhistory/**: consultas históricas en MySQL.
- **accesshttp/**: API HTTP para abstraer RPC internos.
- **accessws/**: WebSocket con auth/sign externos y push de mercado/cuenta.
- **alertcenter/**: recibe alertas y publica a Redis para pipeline de notificaciones.

### Modelo de datos (DB)
**`trade_log` (estado operativo / recovery):**
- `slice_balance_*`, `slice_order_*`, `slice_history`, `operlog_*`.

**`trade_history` (consulta histórica):**
- `balance_history_*`, `order_history_*`, `order_detail_*`, `deal_history_*`, `user_deal_history_*`.

### Algoritmos y librerías relevantes
- **Matching in-memory** con estructuras ordenadas por precio/tiempo (módulo `me_market`/`me_trade`).
- **Event-driven I/O** con loops y timers.
- **Mensajería Kafka** para fan-out de eventos.
- **Redis Sentinel** para datos de mercado y colas de alertas.
- **MySQL** para durabilidad e histórico consultable.
- **HTTP externo (cURL)** para auth/sign en `accessws`.

### Dependencias de terceros
`libev`, `jansson`, `mpdec`, `mysqlclient`, `rdkafka`, `hiredis`, `openssl`, `curl`, `lz4` (según módulo).

### Mantenibilidad aplicada al repo
- Separación “crear” vs “usar”: `*_config` y `init_*` encapsulan construcción de dependencias.
- Módulos cohesionados por concern (auth, depth, today, deals, etc.).
- Contratos internos por headers `*.h`.
- Edge cases críticos documentados aquí: timeout backend, failover Redis Sentinel, lag Kafka, replay incompleto de operlog.

---

## 4) Testing y seguridad

### Objetivos de cobertura (realistas)
- **Core numérico/estructuras**: cobertura media-alta (utils tests).
- **Servicios**: smoke/integration coverage orientada a contratos RPC y estabilidad de proceso.
- **Regresión**: flujos críticos de orden/balance/deal.

### Tipos de test recomendados
- **Unitarios**: decimal/list/skiplist (ya existen en `test/utils`).
- **Integración**: matchengine + Kafka + MySQL + Redis en entorno controlado.
- **Contract tests**: métodos HTTP/WS y payloads.
- **E2E**: crear orden -> match -> historial -> stream WS.
- **Chaos/recovery**: kill -9 de procesos y validación de reconstrucción.

### Side-effects potenciales
- Cambio en reglas de matching afecta: balances, history writer, eventos Kafka, marketprice, WS push.
- Cambio en schema SQL impacta readhistory y backfills.

### Checks de seguridad para release
- Validación estricta de parámetros (precio/monto/precision/límites).
- Firma/autorización para canales privados WS.
- Protección ante replay/manipulación de mensajes internos.
- Hardening operativo: límites FD/core, watchdog, rotación de logs.
- Secret management para credenciales DB/Kafka/Redis/Auth endpoints.

### Auditoría sugerida
- Auditoría externa del flujo de custodia lógica (balances/freeze/unfreeze).
- Revisión de integridad entre operlog, history y eventos Kafka.

---

## 5) Plan de trabajo (para evolución o adopción)

### Estimación macro
- **Onboarding técnico + despliegue dev**: 3–5 días.
- **Validación E2E de trading**: 3–7 días.
- **Hardening producción**: 1–2 semanas.

### Pasos por fase
1. Levantar dependencias (MySQL/Redis/Kafka) y compilar libs base.
2. Desplegar `matchengine`, luego `marketprice`/`readhistory`, finalmente gateways.
3. Cargar config de mercados/assets y validar conectividad RPC.
4. Ejecutar smoke tests de órdenes y consultas.
5. Validar recuperación tras reinicio.
6. Ajustar observabilidad, alerting y capacity.

### Milestones
- M1: Build reproducible y procesos vivos.
- M2: Ordenes y matching funcional.
- M3: Histórico y market data coherentes.
- M4: Seguridad/operación listas para producción.

### Migraciones
- Scripts SQL iniciales para `trade_log` y `trade_history`.
- Estrategia de particionado real (tablas `*_example` como plantilla).

### Riesgos y rutas alternativas
- **Riesgo alto**: integraciones externas (Kafka/Redis Sentinel/MySQL HA).
- **Riesgo alto**: consistencia numérica multi-activo.
- **Fallback**: desactivar features no críticas de push si hay lag, manteniendo matching estable.

### DoD (requerido vs opcional)
**Requerido**: matching consistente, persistencia mínima, APIs funcionales, recovery validado, alertas activas.  
**Opcional**: optimizaciones avanzadas de cache/particionado y paneles operativos extra.

---

## 6) Ripple effects (fuera de código)

- Actualizar runbooks de despliegue y incident response.
- Publicar changelog de contratos HTTP/WS para integradores.
- Coordinar con frontend/mobile por cambios de payload o auth.
- Ajustar sistemas satélite: notificaciones, BI, compliance, reconciliación.
- Verificar costes operativos (brokers Kafka, IOPS MySQL, memoria matchengine).

---

## 7) Contexto amplio

### Limitaciones actuales
- Fuerte dependencia en estado in-memory del core.
- Escalado horizontal limitado para `matchengine` por consistencia de libro por mercado.
- Parte de documentación protocolar está fuera del repo (wiki).

### Extensiones futuras
- Particionado por mercado en múltiples instancias de matching.
- Event sourcing más explícito con snapshots versionados.
- Gateways con rate-limit per user/API key.
- Auditoría criptográfica de eventos (hash chaining).

### Moonshots
- Motor multi-región activo-activo con reconciliación determinista.
- Pruebas formales de invariantes de balance/órdenes.
- DSL de reglas de mercado (fees, lot size, circuit breakers) hot-reloadable.

