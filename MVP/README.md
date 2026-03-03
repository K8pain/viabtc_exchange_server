# MVP Lab (Windows 11 ready)

Este directorio contiene los artefactos mínimos para levantar un laboratorio MVP del exchange desde una máquina Windows 11.

## Modo soportado
**Soportado y probado a nivel de scripts:**
- Windows 11 + Docker Desktop + WSL2 (Ubuntu).

> Nota: el backend C del repositorio usa toolchain/headers POSIX; por eso la ruta estable para Windows 11 es compilar y ejecutar dentro de WSL2, orquestado desde PowerShell.

## Quick start
1. Copiar variables:
   - `copy MVP\.env.example MVP\.env`
2. Arrancar stack:
   - `powershell -ExecutionPolicy Bypass -File .\MVP\windows\Start-MvpLab.ps1`
3. Verificar salud:
   - `powershell -ExecutionPolicy Bypass -File .\MVP\windows\Test-MvpLab.ps1`
4. Detener:
   - `powershell -ExecutionPolicy Bypass -File .\MVP\windows\Stop-MvpLab.ps1`

## Scripts bash usados bajo WSL
- `MVP/scripts/build_backend.sh`
- `MVP/scripts/bootstrap_db.sh`
- `MVP/scripts/seed_data.sh`
- `MVP/scripts/run_backend.sh`
- `MVP/scripts/stop_backend.sh`
- `MVP/scripts/healthcheck.sh`
- `MVP/scripts/reset_lab.sh`

## Infra
- MySQL 8
- Redis 7
- Kafka single node (ZooKeeper + broker)

Definida en `MVP/docker-compose.yml`.
