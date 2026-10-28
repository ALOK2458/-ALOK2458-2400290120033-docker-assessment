$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "setup.ps1")
Push-Location $projectRoot
$composeFiles = @("-f", "compose.yaml", "-f", "compose.stage2.yaml")

try {
    docker compose @composeFiles config --quiet
    if ($LASTEXITCODE -ne 0) { throw "Stage 2 Compose configuration is invalid." }

    docker compose @composeFiles up --build -d
    if ($LASTEXITCODE -ne 0) { throw "Stage 2 stack startup failed." }

    $dbId = docker compose @composeFiles ps -q db
    if (-not $dbId) { throw "The database container was not created." }
    $healthy = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $healthState = docker inspect --format "{{.State.Health.Status}}" $dbId
        if ($healthState -eq "healthy") {
            $healthy = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $healthy) { throw "PostgreSQL did not become healthy within 60 seconds." }

    $health = Invoke-RestMethod -Uri "http://localhost:$($env:PORT)/api/health" -TimeoutSec 10
    $health | ConvertTo-Json -Depth 4
    if ($health.regno -ne $env:REGNO -or -not $health.database) {
        throw "Backend health did not confirm the configured REGNO and database connection."
    }

    $frontendId = docker compose @composeFiles ps -q frontend
    $networkNames = docker inspect --format '{{range $name, $network := .NetworkSettings.Networks}}{{println $name}}{{end}}' $frontendId
    $frontendNetwork = $networkNames | Where-Object { $_ -match "frontend-backend" } | Select-Object -First 1
    if (-not $frontendNetwork) { throw "Could not determine the frontend/backend network." }

    $backendDatabaseNetwork = $networkNames | Where-Object { $_ -match "backend-database" }
    if ($backendDatabaseNetwork) {
        throw "Network isolation failure: the frontend is attached to the backend/database network."
    }

    Write-Output "Testing DNS from a temporary container attached only to $frontendNetwork."
    $dnsOutput = docker run --rm --network $frontendNetwork busybox:1.36 nslookup db 2>&1
    $dnsExitCode = $LASTEXITCODE
    $dnsOutput
    if ($dnsExitCode -eq 0 -or ($dnsOutput -join "`n") -notmatch "(?i)can't resolve|server can't find|no such host|NXDOMAIN") {
        throw "The expected frontend-network DNS isolation was not demonstrated."
    }

    docker compose @composeFiles ps
    Write-Output "Add two registrations in the browser, then capture S2-2.png, S2-3.png, and S2-4.png per README."
}
finally {
    Pop-Location
}
