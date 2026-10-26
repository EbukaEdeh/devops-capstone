#!/usr/bin/env pwsh
# Simulate a worker outage against the local Docker Compose stack, verify that
# votes queue instead of being lost, then restart the worker and prove it drains.
#
# Works with PowerShell 7 (pwsh) and Windows PowerShell 5.1:
#   powershell -ExecutionPolicy Bypass -File ./scripts/drill-worker-outage.ps1
[CmdletBinding()]
param(
    [int]$Votes = 80,
    [int]$OutageSeconds = 60,
    [int]$DelayMs = 35,
    [string]$VoteUrl = "http://localhost:8080",
    [string]$ResultUrl = "http://localhost:8081",
    [string]$EvidencePath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Get-UtcTimestamp {
    (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Invoke-Compose {
    param([string[]]$Arguments)
    # docker writes progress to stderr; with ErrorActionPreference=Stop that
    # would throw in Windows PowerShell 5.1 even when the command succeeds.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & docker compose @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0) {
        throw "docker compose $($Arguments -join ' ') failed: $output"
    }
    return $output
}

function Get-QueueDepth {
    $value = (Invoke-Compose @("exec", "-T", "redis", "redis-cli", "llen", "votes")).Trim()
    return [int]$value
}

function Get-DbCount {
    $sql = "select count(*) from votes;"
    $value = (Invoke-Compose @("exec", "-T", "db", "psql", "-U", "voting", "-d", "voting", "-t", "-A", "-c", $sql)).Trim()
    return [int]$value
}

function Get-ResultTotal {
    return [int](Invoke-RestMethod -Uri "$ResultUrl/api/results" -TimeoutSec 5).total
}

function Wait-ForDrain {
    param([int]$TimeoutSeconds = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ((Get-QueueDepth) -eq 0) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

Write-Host "Worker outage drill" -ForegroundColor Cyan
Write-Host "  Votes: $Votes | Outage: $OutageSeconds s | Delay: $DelayMs ms" -ForegroundColor DarkGray

$running = (Invoke-Compose @("ps", "--services", "--filter", "status=running")) -split "`n" | ForEach-Object { $_.Trim() }
if ($running -notcontains "worker") {
    throw "The worker is not running. Start the stack with scripts/run-local.ps1 first."
}
try {
    Invoke-RestMethod -Uri "$VoteUrl/readyz" -TimeoutSec 5 | Out-Null
    Invoke-RestMethod -Uri "$ResultUrl/readyz" -TimeoutSec 5 | Out-Null
} catch {
    throw "The vote or result service is not ready. Start the stack with scripts/run-local.ps1 first."
}

$startedAt = Get-UtcTimestamp
$baselineQueue = Get-QueueDepth
$baselineDb = Get-DbCount
$baselineTotal = Get-ResultTotal
Write-Host "Baseline: queue=$baselineQueue db=$baselineDb result_total=$baselineTotal"

if ($baselineQueue -ne 0) {
    throw "The queue already has $baselineQueue votes. Wait for the worker to drain it, then run the drill again."
}
if ($baselineTotal -ne $baselineDb) {
    throw "The result total ($baselineTotal) does not match the database ($baselineDb). Resolve that before drilling."
}

Write-Host "Stopping worker..." -ForegroundColor Yellow
Invoke-Compose @("stop", "worker") | Out-Null
$workerStoppedAt = Get-UtcTimestamp

$choices = @("cats", "dogs")
$failed = 0
for ($i = 1; $i -le $Votes; $i++) {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "$VoteUrl/vote" -Method Post `
            -Body @{ choice = $choices[(Get-Random -Maximum $choices.Count)] } `
            -TimeoutSec 10 | Out-Null
    } catch {
        $failed++
    }
    Start-Sleep -Milliseconds $DelayMs
}
$loadFinishedAt = Get-UtcTimestamp

Start-Sleep -Seconds 3
$queueWhileDown = Get-QueueDepth
$dbWhileDown = Get-DbCount
$totalWhileDown = Get-ResultTotal
Write-Host "During outage: queue=$queueWhileDown db=$dbWhileDown result_total=$totalWhileDown failed_requests=$failed"

if ($failed -gt 0) {
    throw "$failed vote requests failed; the vote service should still accept votes while the worker is down."
}
if ($dbWhileDown -ne $baselineDb) {
    throw "Database changed while the worker was stopped ($baselineDb -> $dbWhileDown)."
}
if ($queueWhileDown -lt ($baselineQueue + $Votes)) {
    throw "Expected at least $($baselineQueue + $Votes) queued votes, found $queueWhileDown."
}

$remaining = $OutageSeconds - [int]([datetimeoffset]::UtcNow.Subtract([datetimeoffset]::Parse($loadFinishedAt)).TotalSeconds)
if ($remaining -gt 0) {
    Write-Host "Holding the worker down for $remaining more seconds..." -ForegroundColor DarkGray
    Start-Sleep -Seconds $remaining
}

$queueBeforeRestart = Get-QueueDepth
$totalBeforeRestart = Get-ResultTotal
Write-Host "Before restart: queue=$queueBeforeRestart result_total=$totalBeforeRestart"

Write-Host "Starting worker..." -ForegroundColor Green
$workerStartedAt = Get-UtcTimestamp
Invoke-Compose @("start", "worker") | Out-Null

if (-not (Wait-ForDrain -TimeoutSeconds 90)) {
    throw "Queue did not drain within 90 seconds. Check: docker compose logs worker"
}
$recoveredAt = Get-UtcTimestamp

$finalQueue = Get-QueueDepth
$finalDb = Get-DbCount
$finalTotal = Get-ResultTotal
$written = $finalDb - $baselineDb

Write-Host "Recovered: queue=$finalQueue db=$finalDb result_total=$finalTotal written=$written"

if ($finalQueue -ne 0) {
    throw "Queue is not empty after recovery: $finalQueue"
}
if ($written -ne $Votes) {
    throw "Expected $Votes new votes, found $written. Check for duplicates or lost messages."
}
if ($finalTotal -ne $finalDb) {
    throw "Result total ($finalTotal) does not match the database ($finalDb)."
}

$recoverySeconds = [int]([datetimeoffset]::Parse($recoveredAt).Subtract([datetimeoffset]::Parse($workerStartedAt)).TotalSeconds)
$impactSeconds = [int]([datetimeoffset]::Parse($recoveredAt).Subtract([datetimeoffset]::Parse($loadFinishedAt)).TotalSeconds)
$downtimeSeconds = [int]([datetimeoffset]::Parse($recoveredAt).Subtract([datetimeoffset]::Parse($workerStoppedAt)).TotalSeconds)

Write-Host ""
Write-Host "Drill passed" -ForegroundColor Green
Write-Host "  $Votes votes queued, none lost, none duplicated."
Write-Host "  Worker downtime: $downtimeSeconds s."
Write-Host "  Last vote delayed: $impactSeconds s (stale totals while the worker was down)."
Write-Host "  Recovery: $recoverySeconds s after the worker started."

if ($EvidencePath) {
    $lines = @(
        "# Worker outage drill evidence",
        "",
        "| Field | Value |",
        "| --- | --- |",
        "| Started (UTC) | $startedAt |",
        "| Worker stopped (UTC) | $workerStoppedAt |",
        "| Load finished (UTC) | $loadFinishedAt |",
        "| Worker restarted (UTC) | $workerStartedAt |",
        "| Recovered (UTC) | $recoveredAt |",
        "| Votes sent | $Votes |",
        "| Failed vote requests | $failed |",
        "| Queue while down | $queueWhileDown |",
        "| DB rows while down | $dbWhileDown |",
        "| Result total while down | $totalWhileDown |",
        "| Final queue | $finalQueue |",
        "| Final DB rows | $finalDb |",
        "| Votes written | $written |",
        "| Worker downtime (s) | $downtimeSeconds |",
        "| Last vote delayed (s) | $impactSeconds |",
        "| Recovery after restart (s) | $recoverySeconds |"
    )
    $parent = Split-Path -Parent $EvidencePath
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    $lines | Set-Content -Encoding ascii $EvidencePath
    Write-Host "Evidence written to $EvidencePath" -ForegroundColor DarkGray
}
