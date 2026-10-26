#Requires -Version 5.1
<#
.SYNOPSIS
    Enables the Windows features Docker Desktop needs for its WSL2 backend.

.DESCRIPTION
    Docker Desktop on this machine is configured to use the WSL2 engine, but
    "Microsoft-Windows-Subsystem-Linux" and "VirtualMachinePlatform" are
    disabled. Enabling them requires an elevated shell and a reboot.

    This script re-launches itself through UAC when run from a normal shell.

.NOTES
    Run:  powershell -ExecutionPolicy Bypass -File .\scripts\fix-docker.ps1
    Then: reboot, start Docker Desktop, verify with: docker run --rm hello-world
#>
[CmdletBinding()]
param(
    [switch]$SkipElevation
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    if ($SkipElevation) {
        throw 'This script must run from an elevated PowerShell window.'
    }

    Write-Step 'Requesting administrator rights (approve the UAC prompt)...'
    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', ('"{0}"' -f $PSCommandPath)
    )

    try {
        $process = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList $arguments `
            -Verb RunAs `
            -PassThru `
            -Wait
    }
    catch {
        throw "Elevation was cancelled or failed: $($_.Exception.Message)"
    }

    exit $process.ExitCode
}

Write-Step 'Stopping Docker Desktop so files are not locked during the update'
Get-Process -Name 'Docker Desktop', 'com.docker.backend', 'com.docker.build' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$features = @(
    'Microsoft-Windows-Subsystem-Linux'
    'VirtualMachinePlatform'
)

$rebootRequired = $false
$failed = @()

foreach ($feature in $features) {
    Write-Step "Enabling Windows feature: $feature"
    $output = & dism.exe /online /enable-feature /featurename:$feature /all /norestart 2>&1
    $exitCode = $LASTEXITCODE
    $output | Where-Object { $_ -match '\S' } | ForEach-Object { Write-Host "    $_" }

    switch ($exitCode) {
        0 { Write-Host "    $feature is enabled." -ForegroundColor Green }
        3010 {
            Write-Host "    $feature enabled; a reboot is required." -ForegroundColor Yellow
            $rebootRequired = $true
        }
        default {
            Write-Host "    Failed to enable $feature (exit code $exitCode)." -ForegroundColor Red
            $failed += $feature
        }
    }
}

if ($failed.Count -eq 0) {
    Write-Step 'Setting WSL default version to 2'
    try {
        & wsl.exe --set-default-version 2 2>&1 | ForEach-Object { Write-Host "    $_" }
    }
    catch {
        Write-Host '    Could not set the default WSL version yet; this will work after the reboot.' -ForegroundColor Yellow
        $rebootRequired = $true
    }
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host 'Docker cannot be fixed automatically.' -ForegroundColor Red
    Write-Host "Failed features: $($failed -join ', ')"
    Write-Host 'Enable them manually with "Turn Windows features on or off", then reboot.'
    exit 1
}

Write-Host 'Windows features are enabled.' -ForegroundColor Green
Write-Host 'Reboot the machine, then start Docker Desktop and run:' -ForegroundColor Green
Write-Host '    docker run --rm hello-world'
Write-Host ''
Write-Host 'Docker will keep failing until the machine is restarted.' -ForegroundColor Yellow

exit 0
