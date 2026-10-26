#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [switch]$WithObservability,
    [switch]$NoBuild,
    [switch]$Open
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function New-AlphanumericSecret {
    param([int]$Length = 40)
    $alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $bytes = New-Object byte[] $Length
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
}

if (-not (Test-Path ".env")) {
    $postgresPassword = New-AlphanumericSecret
    $grafanaPassword = New-AlphanumericSecret
    @"
# Generated locally by scripts/run-local.ps1. Never commit this file.
POSTGRES_USER=voting
POSTGRES_DB=voting
POSTGRES_PASSWORD=$postgresPassword
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$grafanaPassword
"@ | Set-Content -Encoding ascii ".env"
    Write-Host "Created .env with random local-only credentials." -ForegroundColor DarkGray
}

# Docker Desktop is often installed but not running on a fresh login.
docker info *> $null
if ($LASTEXITCODE -ne 0) {
    $desktop = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $desktop) {
        Write-Host "Starting Docker Desktop..." -ForegroundColor Yellow
        Start-Process $desktop | Out-Null
    }

    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 3
        docker info *> $null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    }
    if (-not $ready) {
        throw "Docker did not become ready. Start Docker Desktop and run this script again."
    }
}

$composeFiles = @("-f", "compose.yaml")
if ($WithObservability) {
    $composeFiles += @("-f", "compose.observability.yaml")
}

$upArgs = @("compose") + $composeFiles + @("up", "-d")
if (-not $NoBuild) { $upArgs += "--build" }

Write-Host "Starting the Voting App..." -ForegroundColor Cyan
& docker @upArgs
if ($LASTEXITCODE -ne 0) { throw "docker compose up failed." }

Write-Host "Waiting for vote and result to become ready..." -ForegroundColor Cyan
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    try {
        $vote = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8080/readyz" -TimeoutSec 2
        $result = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8081/readyz" -TimeoutSec 2
        if ($vote.StatusCode -eq 200 -and $result.StatusCode -eq 200) { $ready = $true; break }
    } catch {
        Start-Sleep -Seconds 2
    }
}

if (-not $ready) {
    Write-Warning "Services are not ready yet. Check: docker compose ps; docker compose logs --tail=100"
} else {
    Write-Host ""
    Write-Host "Voting App is ready" -ForegroundColor Green
    Write-Host "  Vote:     http://localhost:8080"
    Write-Host "  Results:  http://localhost:8081"
    if ($WithObservability) {
        Write-Host "  Grafana:  http://localhost:3000  (credentials: GRAFANA_ADMIN_* in .env)"
        Write-Host "  Jaeger:   http://localhost:16686"
        Write-Host "  Prom:     http://localhost:9090"
    }
    Write-Host ""
    if ($Open) { Start-Process "http://localhost:8080" }
}
