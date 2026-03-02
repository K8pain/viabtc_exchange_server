# LLD — File-level design de `viabtc_exchange_server`

Este documento baja al nivel de módulos/archivos y describe responsabilidades, dependencias y flujos internos del repositorio.

## 1) Convenciones de diseño observadas

- Estructura por servicio con prefijos por dominio:
  - `me_*` (matchengine), `mp_*` (marketprice), `rh_*` (readhistory), `ah_*` (accesshttp), `aw_*` (accessws), `ac_*` (alertcenter).
- Separación recurrente de responsabilidades:
  - `*_config.*`: parse/configuración.
  - `*_main.c`: bootstrap del proceso.
  - `*_server.*`: networking RPC/HTTP/WS del servicio.
  - `*_message.*`, `*_history.*`, etc.: dominio específico.
- Librerías internas reutilizadas:
  - `network/` (event loop/sockets/timer/jobs).
  - `utils/` (rpc/http/ws/mysql/kafka/log/config y utilidades).

---

## 2) LLD por componente

## 2.1 `network/` (librería base de red)

### Responsabilidad
Proveer primitivas event-driven de bajo nivel para sockets, sesiones, timers, jobs y state machines.

### Archivos clave
- `nw_evt.*`: integración con loop de eventos.
- `nw_svr.*`: servidor TCP/UDP/UNIX.
- `nw_ses.*`: ciclo de vida de sesión/conexión.
- `nw_clt.*`: cliente de red reutilizable.
- `nw_timer.*`: timers periódicos y one-shot.
- `nw_job.*`: ejecución de jobs/thread pool.
- `nw_state.*`: máquina de estados genérica.
- `nw_sock.*`, `nw_buf.*`: sockets y buffers.

### Notas técnicas
- Diseñado para C10K/C100K+ según README del módulo.
- API expuesta por headers en `network/*.h`.

---

## 2.2 `utils/` (librería utilitaria)

### Responsabilidad
Capas transversales para todos los servicios: configuración, logging, RPC, HTTP, DB y utilidades de datos.

### Submódulos relevantes
- **Config/Log/CLI**: `ut_config.*`, `ut_log.*`, `ut_cli.*`.
- **RPC**: `ut_rpc.*`, `ut_rpc_clt.h`, `ut_rpc_svr.h`, `ut_rpc_cmd.h`.
- **HTTP/WS**: `ut_http.*`, `ut_http_svr.h`, `http_parser.*`.
- **Persistencia/colas**: `ut_mysql.h`, `ut_kafka.h`.
- **Datos y helpers**: `ut_skiplist.*`, `ut_misc.h`, `ut_sds.h`, `ut_base64.*`.

### Notas técnicas
- `libutils.a` se enlaza en todos los binarios de aplicación.

---

## 2.3 `matchengine/` (core transaccional)

### Responsabilidad
Motor central de matching y balances en memoria con persistencia en MySQL y publicación de eventos.

### Bootstrap y orden de inicialización (`me_main.c`)
1. `init_mpd`
2. `init_config`
3. `init_process`
4. `init_log`
5. `init_balance`
6. `init_update`
7. `init_trade`
8. daemon + keepalive
9. `init_from_db` (recovery)
10. `init_operlog`
11. `init_history`
12. `init_message`
13. `init_persist`
14. `init_cli`
15. `init_server`
16. `nw_loop_run`

### Archivos de dominio
- Configuración: `me_config.*`
- Modelo/mercado/trade: `me_market.*`, `me_trade.*`
- Balance y updates: `me_balance.*`, `me_update.*`
- Persistencia y recovery: `me_persist.*`, `me_load.*`, `me_dump.*`
- Históricos y logs operativos: `me_history.*`, `me_operlog.*`
- Mensajería/eventos: `me_message.*`
- Interfaces: `me_server.*` (RPC), `me_cli.*` (admin)

### Entradas/salidas
- Entrada: RPC desde gateways (`accesshttp`/`accessws`).
- Salida: MySQL (`trade_log`, `trade_history`) y Kafka (`deals`, `orders`, `balances`).

---

## 2.4 `marketprice/` (agregación de mercado)

### Responsabilidad
Consumir eventos de deals, mantener/servir indicadores de mercado (kline, price, etc.) y cachear en Redis.

### Bootstrap (`mp_main.c`)
- `init_mpd` -> `init_config` -> `init_process` -> `init_log` -> daemon
- `init_message` (Kafka) -> `init_server` (RPC) -> loop

### Archivos
- Config: `mp_config.*`
- Mensajes/consumo: `mp_message.*`
- Kline: `mp_kline.*`
- RPC server: `mp_server.*`

### Integraciones
- Kafka topic `deals`.
- Redis Sentinel para datos de mercado.
- Llamadas HTTP hacia `accesshttp` (según config).

---

## 2.5 `readhistory/` (consulta histórica)

### Responsabilidad
Responder consultas históricas desde MySQL para desacoplar lecturas del motor de matching.

### Bootstrap (`rh_main.c`)
- `init_config` -> `init_process` -> `init_log` -> daemon
- `init_server` -> loop

### Archivos
- Config: `rh_config.*`
- Reader SQL: `rh_reader.*`
- RPC server: `rh_server.*`

### Integración
- DB `trade_history`.

---

## 2.6 `accesshttp/` (gateway HTTP)

### Responsabilidad
Exponer API HTTP y enrutar operaciones/consultas a servicios internos por RPC.

### Arquitectura interna
- **Proceso listener** acepta conexiones.
- **N workers** procesan requests (fork por `worker_num`).

### Bootstrap (`ah_main.c`)
- `init_config` -> `init_process` -> `init_log`
- fork workers (cada worker: `init_server`)
- listener: `init_listener`
- loop en ambos roles

### Archivos
- Config: `ah_config.*`
- HTTP server y routing: `ah_server.*`
- Listener prefork: `ah_listener.*`

### Integración
- RPC a `matchengine`, `marketprice`, `readhistory`.

---

## 2.7 `accessws/` (gateway WebSocket)

### Responsabilidad
Servir canal WS para market data y eventos privados de usuario con auth/sign externos.

### Arquitectura interna
- **Listener process** + **worker processes** (fork por `worker_num`).
- Cada worker inicializa módulos de subscripción y push.

### Bootstrap (`aw_main.c`)
- Base: `init_mpd`, `init_config`, `init_process`, `init_log`
- Fork workers
  - worker init: `init_auth`, `init_sign`, `init_kline`, `init_depth`, `init_price`, `init_state`, `init_today`, `init_deals`, `init_order`, `init_asset`, `init_message`, `init_server`
- Listener init: `init_listener`
- loop

### Archivos funcionales
- Config: `aw_config.*`
- Seguridad: `aw_auth.*`, `aw_sign.*`
- Datos mercado: `aw_kline.*`, `aw_depth.*`, `aw_price.*`, `aw_state.*`, `aw_today.*`, `aw_deals.*`
- Datos de usuario: `aw_order.*`, `aw_asset.*`
- Messaging/servicio: `aw_message.*`, `aw_server.*`, `aw_listener.*`

### Integraciones
- RPC a `matchengine`, `marketprice`, `readhistory`.
- Kafka (`deals`, `orders`, `balances`) para push near-real-time.
- HTTP externo (`auth_url`, `sign_url`).

---

## 2.8 `alertcenter/` (alerting)

### Responsabilidad
Consumir eventos de alerta y persistirlos/publicarlos en Redis para notificación externa.

### Bootstrap (`ac_main.c`)
- `load_config` -> `init_process` -> `init_log` -> daemon
- `init_server` -> loop

### Archivos
- Config: `ac_config.*`
- Server: `ac_server.*`
- Script de entrega ejemplo: `send_alert.py`

---

## 2.9 `sql/` (modelo físico)

### Responsabilidad
DDL inicial para bases `trade_log` y `trade_history`.

### Archivos
- `create_trade_log.sql`: tablas de snapshots y operlog.
- `create_trade_history.sql`: tablas históricas de balances, órdenes y deals.
- `init_trade_history.sh`: script de inicialización.

---

## 2.10 `depends/hiredis/` (dependencia vendorizada)

### Responsabilidad
Implementación de cliente Redis C (sincronía/asincronía + adapters).

### Nota
Se recomienda explícitamente usar esta versión para compatibilidad.

---

## 2.11 `test/` (validación local)

### Responsabilidad
Pruebas utilitarias y harnesses manuales para módulos de API/matching.

### Estructura
- `test/utils/`: pruebas de estructuras (decimal/list/skiplist).
- `test/matchengine/`: scripts CLI para balances/órdenes.
- `test/accesshttp/`: scripts de llamada/autenticación.
- `test/marketprice/`: binario de prueba.

---

## 3) Flujos de runtime entre procesos

## 3.1 Colocación de orden
`Client -> accesshttp/accessws -> matchengine -> MySQL + Kafka -> accessws/marketprice/readhistory`

## 3.2 Push de market data
`matchengine(deals) -> Kafka -> marketprice/accessws -> websocket clients`

## 3.3 Recovery
`matchengine startup -> load slices + replay operlog -> estado en memoria consistente`

---

## 4) Seguridad y resiliencia al nivel de archivos

- Watchdog y daemonización en todos los `*_main.c`.
- Validación externa de identidad/firma en `aw_auth.*` y `aw_sign.*`.
- Logging/alertas centralizadas via `ut_log` + `alertcenter`.
- Configuración de límites de proceso (`file_limit`, `core_limit`) por servicio.

---

## 5) Inventario completo de archivos del repositorio

> Snapshot obtenido con `rg --files`.

LICENSE
README.md
accesshttp/ah_config.c
accesshttp/ah_config.h
accesshttp/ah_listener.c
accesshttp/ah_listener.h
accesshttp/ah_main.c
accesshttp/ah_server.c
accesshttp/ah_server.h
accesshttp/config.json
accesshttp/makefile
accesshttp/restart.sh
accessws/aw_asset.c
accessws/aw_asset.h
accessws/aw_auth.c
accessws/aw_auth.h
accessws/aw_config.c
accessws/aw_config.h
accessws/aw_deals.c
accessws/aw_deals.h
accessws/aw_depth.c
accessws/aw_depth.h
accessws/aw_kline.c
accessws/aw_kline.h
accessws/aw_listener.c
accessws/aw_listener.h
accessws/aw_main.c
accessws/aw_message.c
accessws/aw_message.h
accessws/aw_order.c
accessws/aw_order.h
accessws/aw_price.c
accessws/aw_price.h
accessws/aw_server.c
accessws/aw_server.h
accessws/aw_sign.c
accessws/aw_sign.h
accessws/aw_state.c
accessws/aw_state.h
accessws/aw_today.c
accessws/aw_today.h
accessws/config.json
accessws/makefile
accessws/restart.sh
alertcenter/ac_config.c
alertcenter/ac_config.h
alertcenter/ac_main.c
alertcenter/ac_server.c
alertcenter/ac_server.h
alertcenter/config.json
alertcenter/makefile
alertcenter/restart.sh
alertcenter/send_alert.py
depends/hiredis/CHANGELOG.md
depends/hiredis/COPYING
depends/hiredis/Makefile
depends/hiredis/README.md
depends/hiredis/adapters/ae.h
depends/hiredis/adapters/glib.h
depends/hiredis/adapters/ivykis.h
depends/hiredis/adapters/libev.h
depends/hiredis/adapters/libevent.h
depends/hiredis/adapters/libuv.h
depends/hiredis/adapters/macosx.h
depends/hiredis/adapters/qt.h
depends/hiredis/async.c
depends/hiredis/async.h
depends/hiredis/dict.c
depends/hiredis/dict.h
depends/hiredis/examples/example-ae.c
depends/hiredis/examples/example-glib.c
depends/hiredis/examples/example-ivykis.c
depends/hiredis/examples/example-libev.c
depends/hiredis/examples/example-libevent.c
depends/hiredis/examples/example-libuv.c
depends/hiredis/examples/example-macosx.c
depends/hiredis/examples/example-qt.cpp
depends/hiredis/examples/example-qt.h
depends/hiredis/examples/example.c
depends/hiredis/fmacros.h
depends/hiredis/hiredis.c
depends/hiredis/hiredis.h
depends/hiredis/net.c
depends/hiredis/net.h
depends/hiredis/read.c
depends/hiredis/read.h
depends/hiredis/sds.c
depends/hiredis/sds.h
depends/hiredis/test.c
depends/hiredis/win32.h
docs/HLD.md
docs/LLD_FILES.md
makefile.inc
marketprice/config.json
marketprice/makefile
marketprice/mp_config.c
marketprice/mp_config.h
marketprice/mp_kline.c
marketprice/mp_kline.h
marketprice/mp_main.c
marketprice/mp_message.c
marketprice/mp_message.h
marketprice/mp_server.c
marketprice/mp_server.h
marketprice/restart.sh
matchengine/config.json
matchengine/makefile
matchengine/me_balance.c
matchengine/me_balance.h
matchengine/me_cli.c
matchengine/me_cli.h
matchengine/me_config.c
matchengine/me_config.h
matchengine/me_dump.c
matchengine/me_dump.h
matchengine/me_history.c
matchengine/me_history.h
matchengine/me_load.c
matchengine/me_load.h
matchengine/me_main.c
matchengine/me_market.c
matchengine/me_market.h
matchengine/me_message.c
matchengine/me_message.h
matchengine/me_operlog.c
matchengine/me_operlog.h
matchengine/me_persist.c
matchengine/me_persist.h
matchengine/me_server.c
matchengine/me_server.h
matchengine/me_trade.c
matchengine/me_trade.h
matchengine/me_update.c
matchengine/me_update.h
matchengine/restart.sh
network/README.md
network/makefile
network/nw_buf.c
network/nw_buf.h
network/nw_clt.c
network/nw_clt.h
network/nw_evt.c
network/nw_evt.h
network/nw_job.c
network/nw_job.h
network/nw_ses.c
network/nw_ses.h
network/nw_sock.c
network/nw_sock.h
network/nw_state.c
network/nw_state.h
network/nw_svr.c
network/nw_svr.h
network/nw_timer.c
network/nw_timer.h
readhistory/config.json
readhistory/makefile
readhistory/restart.sh
readhistory/rh_config.c
readhistory/rh_config.h
readhistory/rh_main.c
readhistory/rh_reader.c
readhistory/rh_reader.h
readhistory/rh_server.c
readhistory/rh_server.h
sql/create_trade_history.sql
sql/create_trade_log.sql
sql/init_trade_history.sh
test/accesshttp/auth.py
test/accesshttp/call.py
test/marketprice/makefile
test/marketprice/mp_main.c
test/matchengine/cli.c
test/matchengine/get_balance.sh
test/matchengine/get_order.sh
test/matchengine/makefile
test/matchengine/set_balance.sh
test/matchengine/set_order.sh
test/utils/makefile
test/utils/test_decimal.c
test/utils/test_list.c
test/utils/test_skiplist.c
utils/http_parser.c
utils/http_parser.h
utils/makefile
utils/ut_alert.c
utils/ut_alert.h
utils/ut_base64.c
utils/ut_base64.h
utils/ut_cli.c
utils/ut_cli.h
utils/ut_config.c
utils/ut_config.h
utils/ut_crc32.c
utils/ut_crc32.h
utils/ut_decimal.c
utils/ut_decimal.h
utils/ut_define.h
utils/ut_dict.c
utils/ut_dict.h
utils/ut_http.c
utils/ut_http.h
utils/ut_http_svr.c
utils/ut_http_svr.h
utils/ut_kafka.c
utils/ut_kafka.h
utils/ut_list.c
utils/ut_list.h
utils/ut_log.c
utils/ut_log.h
utils/ut_misc.c
utils/ut_misc.h
utils/ut_mysql.c
utils/ut_mysql.h
utils/ut_pack.c
utils/ut_pack.h
utils/ut_redis.c
utils/ut_redis.h
utils/ut_rpc.c
utils/ut_rpc.h
utils/ut_rpc_clt.c
utils/ut_rpc_clt.h
utils/ut_rpc_cmd.h
utils/ut_rpc_svr.c
utils/ut_rpc_svr.h
utils/ut_sds.c
utils/ut_sds.h
utils/ut_signal.c
utils/ut_signal.h
utils/ut_skiplist.c
utils/ut_skiplist.h
utils/ut_title.c
utils/ut_title.h
utils/ut_ws_svr.c
utils/ut_ws_svr.h
