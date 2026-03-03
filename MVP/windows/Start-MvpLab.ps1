param(
  [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path.Replace("\\", "/")

Write-Host "[1/5] Starting infra with Docker Desktop compose..."
docker compose -f "$repo/MVP/docker-compose.yml" up -d

Write-Host "[2/5] Building backend inside WSL..."
wsl -d $Distro bash -lc "cd $repo && ./MVP/scripts/build_backend.sh"

Write-Host "[3/5] Bootstrapping DB..."
wsl -d $Distro bash -lc "cd $repo && ./MVP/scripts/bootstrap_db.sh"

Write-Host "[4/5] Seeding DB..."
wsl -d $Distro bash -lc "cd $repo && ./MVP/scripts/seed_data.sh"

Write-Host "[5/5] Starting backend..."
wsl -d $Distro bash -lc "cd $repo && ./MVP/scripts/run_backend.sh"

Write-Host "MVP Lab started on Windows 11 (Docker Desktop + WSL2)."
