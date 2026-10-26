param(
    [string]$ClusterName = "voting-capstone",
    [switch]$SkipKindCreate,
    [switch]$SkipRepoUpdate
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Require-Command($Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

Require-Command docker
Require-Command kind
Require-Command kubectl
Require-Command helm

$existing = (kind get clusters) -split "`r?`n" | Where-Object { $_ -eq $ClusterName }
if (-not $existing -and -not $SkipKindCreate) {
    Write-Host "Creating kind cluster '$ClusterName'..." -ForegroundColor Cyan
    kind create cluster --name $ClusterName --config .\deploy\kind-config.yaml --wait 120s
} elseif ($existing) {
    Write-Host "kind cluster '$ClusterName' already exists; reusing it." -ForegroundColor Yellow
}

Write-Host "Adding Helm repositories..." -ForegroundColor Cyan
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts | Out-Null
helm repo add grafana https://grafana.github.io/helm-charts | Out-Null
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts | Out-Null
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts | Out-Null
helm repo add istio https://istio-release.storage.googleapis.com/charts | Out-Null
helm repo add fluent https://fluent.github.io/helm-charts | Out-Null
if (-not $SkipRepoUpdate) {
    helm repo update | Out-Null
}

Write-Host "Installing Istio base and control plane..." -ForegroundColor Cyan
helm upgrade --install istio-base istio/base -n istio-system --create-namespace --wait --timeout 5m
helm upgrade --install istiod istio/istiod -n istio-system -f .\capstone2\observability\istio-values.yaml --wait --timeout 10m

kubectl create namespace robot-shop --dry-run=client -o yaml | kubectl apply -f - | Out-Null
kubectl label namespace robot-shop istio-injection=enabled --overwrite | Out-Null

Write-Host "Installing Robot Shop..." -ForegroundColor Cyan
helm upgrade --install robot-shop .\capstone2\robot-shop -n robot-shop -f .\capstone2\robot-shop\values-kind.yaml --wait --timeout 20m

Write-Host "Installing kube-prometheus-stack..." -ForegroundColor Cyan
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n observability --create-namespace -f .\capstone2\observability\kube-prometheus-stack-values.yaml --wait --timeout 15m

Write-Host "Installing Loki and Fluent Bit..." -ForegroundColor Cyan
helm upgrade --install loki grafana/loki -n observability -f .\capstone2\observability\loki-values.yaml --wait --timeout 10m
helm upgrade --install fluent-bit fluent/fluent-bit -n observability -f .\capstone2\observability\fluent-bit-values.yaml --wait --timeout 10m

Write-Host "Installing Jaeger and OTel Collector..." -ForegroundColor Cyan
kubectl apply -f .\capstone2\observability\jaeger.yaml
kubectl apply -f .\capstone2\observability\otel-collector.yaml
kubectl apply -f .\capstone2\observability\telemetry.yaml
foreach ($deployment in @("web", "catalogue", "cart", "payment")) {
    kubectl -n robot-shop rollout restart "deployment/$deployment" | Out-Null
}
foreach ($deployment in @("web", "catalogue", "cart", "payment")) {
    kubectl -n robot-shop rollout status "deployment/$deployment" --timeout=10m
}
kubectl apply -f .\capstone2\observability\robot-shop-alerts.yaml
kubectl apply -f .\capstone2\observability\robot-shop-dashboard.yaml

Write-Host "Waiting for the critical observability pods..." -ForegroundColor Cyan
kubectl -n observability rollout status deploy/kube-prometheus-stack-grafana --timeout=5m
kubectl -n observability rollout status deploy/kube-prometheus-stack-operator --timeout=5m
kubectl -n observability rollout status deploy/jaeger --timeout=5m
kubectl -n observability rollout status deploy/otel-collector --timeout=5m

Write-Host ""
Write-Host "Robot Shop is running at http://localhost:8090" -ForegroundColor Green
Write-Host "Grafana:   kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80" -ForegroundColor Green
Write-Host "Prometheus:kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090" -ForegroundColor Green
Write-Host "Jaeger:    kubectl -n observability port-forward svc/jaeger-query 16686:16686" -ForegroundColor Green
Write-Host "Grafana login: admin / admin (local demo only)" -ForegroundColor Green
