param(
  [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path.Replace("\\", "/")

wsl -d $Distro bash -lc "cd $repo && ./MVP/scripts/stop_backend.sh"
docker compose -f "$repo/MVP/docker-compose.yml" down

Write-Host "MVP Lab stopped."
