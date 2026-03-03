# MVP TERM DEV SPEC SHEET — Laboratorio single-machine + UI de validación end-to-end

> Objetivo de este documento: **especificación implementable por Codex** (no plan de gestión), para montar un MVP técnico funcional dentro de `MVP/` que permita probar el stack completo en una sola máquina física.

## 1) Define what we are building

### 1.1 Qué es
Un entorno de laboratorio local que integra:
- infraestructura mínima (MySQL, Redis, Kafka),
- servicios del exchange (`matchengine`, `marketprice`, `readhistory`, `accesshttp`, `accessws`, `alertcenter`),
- una UI de test orientada a validar flujos de negocio reales.

### 1.2 Para quién
- Dev backend para validar integración de servicios.
- QA para ejecutar flujos end-to-end.
- Producto para demos técnicas internas.

### 1.3 Problema que resuelve
Permite verificar funcionalidad core sin depender de despliegue distribuido de producción ni infraestructura multi-nodo.

### 1.4 Cómo funciona (zoom-out)
1. `docker compose` levanta dependencias.
2. scripts de bootstrap crean schema y datos semilla.
3. scripts de orquestación lanzan binarios de backend en orden estable.
4. UI consume HTTP/WS y expone acciones de trading + observabilidad básica.
5. tests automáticos validan rutas críticas.

### 1.5 Distilled model (MVP real)
Se **elimina** del alcance inicial:
- HA/replicación/sentinel real,
- balanceador y TLS real,
- RBAC avanzado,
- dashboards “bonitos” de BI.

Se mantiene solo lo imprescindible para validar:
- lifecycle de orden,
- eventos de mercado en tiempo real,
- persistencia y lectura de historial.

---

## 2) UX spec (enfocada a validación, no a producto final)

### 2.1 Mapa de navegación mínimo
- `/login` (token de laboratorio)
- `/trade` (pantalla principal)
- `/market` (ticker + kline + trades)
- `/history` (orders/deals)
- `/system` (health + ws status + latencias)

### 2.2 User stories — happy path
1. Seleccionar mercado activo (ej. `BTCUSDT`).
2. Ver order book y último precio en tiempo real.
3. Enviar limit buy/sell válida.
4. Ver actualización de open orders y balances.
5. Cancelar orden abierta.
6. Ver trades ejecutados en historial.

### 2.3 User stories — alternative/error flows
- fondos insuficientes,
- cantidad/precio fuera de precisión permitida,
- mercado inválido/no habilitado,
- desconexión WS con reconexión automática,
- token inválido para canales privados.

### 2.4 Wireframe textual
```
+--------------------------------------------------------------------------------+
| Header: env=LAB | market selector | ws:connected/disconnected | user_id       |
+----------------------+-----------------------------------------+---------------+
| Left                 | Center                                  | Right         |
| - Markets list       | - Orderbook (bids/asks)                | - Order form  |
| - 24h ticker         | - Last trades tape                      | - Balances    |
|                      | - Mini kline                            | - Open orders |
+----------------------+-----------------------------------------+---------------+
| Bottom: technical event log (api errors, ws reconnect, order ack/reject)      |
+--------------------------------------------------------------------------------+
```

### 2.5 Criterio UX MVP
La UI no optimiza estética: optimiza **diagnóstico funcional** (estados explícitos, payloads de error visibles, timestamps, IDs de orden/deal).

---

## 3) Technical implementation specification

## 3.1 Estructura exacta a crear en `MVP/`
```
MVP/
  README.md
  .env.example
  docker-compose.yml
  scripts/
    bootstrap_db.sh
    seed_data.sh
    run_backend.sh
    stop_backend.sh
    reset_lab.sh
    healthcheck.sh
  config/
    accesshttp.config.json
    accessws.config.json
    matchengine.config.json
    marketprice.config.json
    readhistory.config.json
    alertcenter.config.json
  ui/
    package.json
    src/
      main.tsx
      app/
        routes.tsx
      core/
        api.ts
        ws.ts
        types.ts
        errors.ts
      features/
        auth/
        market/
        trade/
        history/
        system/
      components/
        Layout.tsx
        OrderForm.tsx
        OrderBook.tsx
        TradeTape.tsx
        BalancePanel.tsx
        OpenOrdersTable.tsx
```

## 3.2 Contrato de configuración
Variables mínimas en `.env.example`:
- `LAB_MYSQL_HOST`, `LAB_MYSQL_PORT`, `LAB_MYSQL_DB`, `LAB_MYSQL_USER`, `LAB_MYSQL_PASSWORD`
- `LAB_REDIS_HOST`, `LAB_REDIS_PORT`
- `LAB_KAFKA_BROKER`
- `LAB_HTTP_BASE_URL`
- `LAB_WS_URL`
- `LAB_AUTH_TOKEN`

Regla: **todo script debe fallar rápido** si falta una variable crítica (`set -euo pipefail` + validación explícita).

## 3.3 Infra local (`docker-compose.yml`)
Servicios obligatorios:
- mysql:8
- redis:7
- zookeeper + kafka (single broker)

Requisitos:
- puertos expuestos en localhost,
- healthchecks por servicio,
- volúmenes nombrados para persistencia,
- red interna única `mvp_lab_net`.

## 3.4 Bootstrap y seed
### `bootstrap_db.sh`
- crea schema requerido por módulos que escriben historial/log,
- ejecuta SQL idempotente (`CREATE TABLE IF NOT EXISTS`, índices explícitos).

### `seed_data.sh`
- inserta mercados mínimos (`BTCUSDT`, `ETHUSDT`),
- crea 2 usuarios de laboratorio,
- inicializa balances de prueba para ambos lados del libro.

Regla: seeds idempotentes con `INSERT ... ON DUPLICATE KEY UPDATE`.

## 3.5 Orquestación backend
### `run_backend.sh`
Orden de arranque requerido:
1. matchengine
2. marketprice
3. readhistory
4. accesshttp
5. accessws
6. alertcenter

- cada proceso en background con PID file en `MVP/run/*.pid`,
- logs separados en `MVP/run/logs/<service>.log`,
- wait/check tras cada arranque contra health endpoint o puerto.

### `stop_backend.sh`
- detiene por PID file,
- fallback `pkill -f` acotado por nombre de binario,
- limpia PID files huérfanos.

## 3.6 UI architecture (implementable)

### Stack
- React + TypeScript + Vite.
- Estado: store simple (Zustand o reducer local); evitar sobre-ingeniería.
- HTTP: wrapper `api.ts` con funciones puras por endpoint.
- WS: `ws.ts` con protocolo de reconexión exponencial y re-subscription automática.

### Tipos base (`core/types.ts`)
Definir enums/union types para evitar estados inválidos:
- `OrderSide = 'buy' | 'sell'`
- `OrderType = 'limit'`
- `OrderStatus = 'new' | 'partial' | 'filled' | 'cancelled' | 'rejected'`
- `WsConnectionState = 'connecting' | 'open' | 'closed' | 'error'`

### Separación de responsabilidades
- `core/api.ts`: solo transporte y parseo de respuestas.
- `features/*/model.ts`: reglas de dominio UI (validación, transformación).
- `components/*`: render puro sin lógica de red.

## 3.7 API/WS contract expected by UI

### HTTP mínimo
- `GET /markets`
- `GET /ticker?market=...`
- `GET /depth?market=...`
- `POST /order/put_limit`
- `POST /order/cancel`
- `GET /order/pending?user_id=...&market=...`
- `GET /order/history?user_id=...&market=...`
- `GET /balance/query?user_id=...`

### WebSocket mínimo
Suscripciones:
- market ticker updates
- market depth updates
- market deals updates
- user order updates (auth requerida)
- user balance updates (auth requerida)

### Auth de laboratorio
- header `Authorization: Bearer <LAB_AUTH_TOKEN>`
- endpoint interno de auth para `accessws` que responda `user_id`.

## 3.8 Edge cases obligatorios documentados/implementados
- retry en HTTP idempotente (`GET`) con máximo 2 intentos,
- no retry automático en `POST` de orden,
- deduplicación de eventos WS por `event_id`/`sequence`,
- resincronización tras reconexión: `pending orders + balance + recent trades`.

## 3.9 Criterios de aceptación técnicos
- comando único para levantar infra,
- comando único para bootstrap+seed,
- comando único para iniciar backend,
- UI funcional consumiendo HTTP+WS local,
- reset de laboratorio reproducible.

---



## 3.10 Windows 11 execution target (obligatorio)
- Target de ejecución: **Windows 11 host** con **Docker Desktop + WSL2 (Ubuntu)**.
- Orquestación desde PowerShell (`MVP/windows/*.ps1`).
- Compilación/ejecución backend C dentro de WSL2 (`MVP/scripts/*.sh`).
- No se asume compilación nativa MSVC debido a dependencias POSIX del código base.

Comandos operativos:
- `powershell -ExecutionPolicy Bypass -File .\MVP\windows\Start-MvpLab.ps1`
- `powershell -ExecutionPolicy Bypass -File .\MVP\windows\Test-MvpLab.ps1`
- `powershell -ExecutionPolicy Bypass -File .\MVP\windows\Stop-MvpLab.ps1`


---

## 4) Testing + Security specification

## 4.1 Testing matrix mínima
- Unit (UI): validaciones de formulario de orden + reducers/stores.
- Integration (API): create/cancel/query order.
- WS integration: connect/subscribe/reconnect/resync.
- E2E: journey completo create order -> update -> cancel/fill -> history visible.

## 4.2 Casos E2E obligatorios
1. Place limit buy válida y verla en abiertas.
2. Cancelar orden y ver estado `cancelled`.
3. Error por fondos insuficientes y mensaje visible.
4. WS reconnect y recuperación de estado sin duplicados.

## 4.3 Seguridad mínima para entorno MVP
- CORS explícito a origen de UI lab.
- No hardcode de secretos en repositorio.
- Sanitización básica de input en UI (número positivo, precisión, límites).
- Logging con redacción de token (`Authorization` nunca en claro).

## 4.4 Checks de ship interno
- `healthcheck.sh` exitoso en todos los servicios.
- tests E2E críticos en verde.
- revisión manual de logs sin errores fatales tras flujo completo.

---

## 5) Work package breakdown (sin plazos)

## 5.1 WP-1 Infra local
Implementar `docker-compose.yml`, `.env.example`, healthchecks y volúmenes.

## 5.2 WP-2 Bootstrap/Seed
Implementar `bootstrap_db.sh`, `seed_data.sh`, `reset_lab.sh` idempotentes.

## 5.3 WP-3 Backend orchestration
Implementar `run_backend.sh` y `stop_backend.sh` con gestión de PID/log.

## 5.4 WP-4 UI core
Scaffold Vite + rutas + layout + módulos `trade/market/history/system`.

## 5.5 WP-5 API/WS integration
Conectar contrato mínimo y robustecer reconexión/resync.

## 5.6 WP-6 Test harness
Montar tests unit/integration/e2e + scripts de ejecución local.

## 5.7 Definition of Done (estricto)
- todos los WP implementados,
- flujo E2E crítico verificable por script,
- documentación de uso en `MVP/README.md`.

---

## 6) Ripple effects to include in implementation

- Actualizar documentación raíz con enlace a `MVP/README.md`.
- Agregar sección “Lab limitations” para evitar uso accidental como producción.
- Agregar comandos de CI opcionales para smoke de laboratorio.

---

## 7) Broader context + constraints

### Limitaciones conocidas
- Rendimiento no representativo de entorno distribuido.
- Fallos de red interservicio no se reproducen igual en single-host.
- Riesgo de “works in lab, fails in prod” si no se validan suposiciones.

### Extensiones futuras (fuera del MVP)
- multinodo/staging-lite,
- auth real multiusuario,
- métricas Prometheus/Grafana,
- generación automática de escenarios de mercado.

---

## Preguntas bloqueantes (solo si se decide no asumir defaults)
Si se desea máxima precisión antes de implementar, responder:
1. ¿Par(es) obligatorios para seed además de `BTCUSDT`?
2. ¿Autenticación de UI será mock o integrada con endpoint real interno?
3. ¿Preferencia de framework UI: React o Vue?
4. ¿Priorizar fill real entre usuarios seed o basta flujo de create/cancel?

> Si no se responde, Codex asume defaults:
> - mercados: `BTCUSDT`, `ETHUSDT`
> - auth: token fijo de laboratorio
> - UI: React + TypeScript
> - E2E mínimo: create/cancel + errores + WS reconnect
