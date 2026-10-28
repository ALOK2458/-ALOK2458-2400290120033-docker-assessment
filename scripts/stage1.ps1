$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "setup.ps1")

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker CLI is not installed."
}

Push-Location $projectRoot
try {
    docker build -f backend\Dockerfile.stage1 -t fest-backend:0.1 backend
    if ($LASTEXITCODE -ne 0) { throw "Stage 1 image build failed." }

    docker image ls fest-backend:0.1
    docker image inspect fest-backend:0.1 --format "Image={{.RepoTags}} SizeBytes={{.Size}}"

    $existing = docker container inspect backend 2>$null
    if ($LASTEXITCODE -eq 0) {
        throw "A container named backend already exists. Inspect it and remove it manually before rerunning this stage."
    }

    docker run -d --name backend -p "$($env:PORT):5000" -e "REGNO=$env:REGNO" fest-backend:0.1
    if ($LASTEXITCODE -ne 0) { throw "Could not start the Stage 1 backend container." }

    $health = $null
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        try {
            $health = Invoke-RestMethod -Uri "http://localhost:$($env:PORT)/api/health" -TimeoutSec 5
            break
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }
    if (-not $health) { throw "The Stage 1 /api/health endpoint did not respond." }

    $health | ConvertTo-Json -Depth 4
    if ($health.regno -ne $env:REGNO -or $health.database -ne $false) {
        throw "Stage 1 health did not show the configured REGNO and database=false."
    }
    docker ps --filter "name=backend"
    docker logs backend
    Write-Output "Capture S1-2.png and S1-3.png, then remove only this test container with: docker rm -f backend"
}
finally {
    Pop-Location
}
