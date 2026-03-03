param(
  [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path.Replace("\\", "/")

wsl -d $Distro bash -lc "cd $repo && ./MVP/scripts/healthcheck.sh"
