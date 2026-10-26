#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [string]$ClusterName = "voting-capstone",
    [switch]$Recreate
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

foreach ($command in @("docker", "kind", "kubectl", "helm")) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $command"
    }
}

docker info *> $null
if ($LASTEXITCODE -ne 0) { throw "Docker is not running." }

if ($Recreate) {
    kind delete cluster --name $ClusterName 2>$null
}

$existing = (kind get clusters) -split "`n" | ForEach-Object { $_.Trim() }
if ($existing -notcontains $ClusterName) {
    Write-Host "Creating kind cluster '$ClusterName'..." -ForegroundColor Cyan
    kind create cluster --name $ClusterName --config deploy/kind-config.yaml
}

Write-Host "Building local images..." -ForegroundColor Cyan
docker build -t voting-app-vote:local -f services/vote/Dockerfile .
docker build -t voting-app-result:local -f services/result/Dockerfile .
docker build -t voting-app-worker:local -f services/worker/Dockerfile .

Write-Host "Loading images into kind..." -ForegroundColor Cyan
kind load docker-image voting-app-vote:local --name $ClusterName
kind load docker-image voting-app-result:local --name $ClusterName
kind load docker-image voting-app-worker:local --name $ClusterName

if (-not (Test-Path ".env")) {
    throw "Run scripts/run-local.ps1 once to generate .env, or create it from .env.example."
}
$envValues = @{}
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]*)=(.*)$') { $envValues[$matches[1].Trim()] = $matches[2].Trim() }
}

kubectl create namespace voting --dry-run=client -o yaml | kubectl apply -f - | Out-Null
kubectl -n voting create secret generic voting-db-credentials `
    --from-literal=password=$envValues["POSTGRES_PASSWORD"] `
    --dry-run=client -o yaml | kubectl apply -f - | Out-Null

Write-Host "Installing the Helm chart..." -ForegroundColor Cyan
helm upgrade --install voting-app deploy/helm/voting-app `
    --namespace voting `
    --values deploy/helm/voting-app/values-kind.yaml `
    --wait --timeout 5m

Write-Host ""
Write-Host "Capstone cluster is ready" -ForegroundColor Green
Write-Host "  Vote:    http://localhost:8080"
Write-Host "  Results: http://localhost:8081"
Write-Host ""
Write-Host "Useful commands:"
Write-Host "  helm -n voting history voting-app"
Write-Host "  kubectl -n voting get pods,svc"
Write-Host "  kubectl -n voting logs deploy/voting-app-worker -f"
Write-Host "  pwsh ./scripts/demo-rollback.ps1"
