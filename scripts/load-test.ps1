#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [int]$Votes = 100,
    [string]$BaseUrl = "http://localhost:8080",
    [int]$DelayMs = 35
)

$ErrorActionPreference = "Stop"
$choices = @("cats", "dogs")

for ($i = 1; $i -le $Votes; $i++) {
    $choice = $choices[(Get-Random -Maximum $choices.Count)]
    Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/vote" `
        -Method Post -Body @{ choice = $choice } -MaximumRedirection 0 -ErrorAction SilentlyContinue | Out-Null
    if (($i % 10) -eq 0) { Write-Host "$i/$Votes votes sent" }
    Start-Sleep -Milliseconds $DelayMs
}

Write-Host "Done. Open $BaseUrl and http://localhost:8081" -ForegroundColor Green
