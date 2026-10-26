#!/usr/bin/env pwsh
[CmdletBinding()]
param([switch]$Volumes)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$args = @("compose", "-f", "compose.yaml", "-f", "compose.observability.yaml", "down", "--remove-orphans")
if ($Volumes) { $args += "--volumes" }

& docker @args
