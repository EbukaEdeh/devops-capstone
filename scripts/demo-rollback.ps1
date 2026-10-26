#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [string]$Release = "voting-app",
    [string]$Namespace = "voting"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "Current release history:" -ForegroundColor Cyan
helm -n $Namespace history $Release

Write-Host ""
Write-Host "Shipping a deliberately broken image tag. This should fail..." -ForegroundColor Yellow
helm upgrade $Release deploy/helm/voting-app `
    --namespace $Namespace `
    --reuse-values `
    --set images.vote.tag=broken-demo `
    --wait --timeout 90s

if ($LASTEXITCODE -eq 0) {
    throw "The broken release unexpectedly succeeded. Refusing to continue."
}

Write-Host ""
Write-Host "Release failed as intended. Rolling back to the previous revision..." -ForegroundColor Cyan
helm rollback $Release --namespace $Namespace --wait --timeout 5m
if ($LASTEXITCODE -ne 0) { throw "helm rollback failed." }

kubectl -n $Namespace rollout status deployment/$Release-vote --timeout=120s
Write-Host ""
Write-Host "Rollback complete." -ForegroundColor Green
helm -n $Namespace history $Release
