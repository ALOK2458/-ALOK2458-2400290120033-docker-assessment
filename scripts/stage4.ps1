$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "setup.ps1")
Push-Location $projectRoot

try {
    Write-Output "Docker Hub authentication is interactive. At the Docker prompt, use a Docker Hub access token as the password."
    docker login --username $env:DOCKERHUB_USER
    if ($LASTEXITCODE -ne 0) { throw "Docker Hub login did not succeed; no image will be pushed." }

    $imageVersioned = "$($env:IMAGE_NAME):1.0.0"
    $imageAlias = "$($env:IMAGE_NAME):1.0"
    docker build --build-arg APP_VERSION=1.0.0 -f backend\Dockerfile -t $imageVersioned -t $imageAlias backend
    if ($LASTEXITCODE -ne 0) { throw "Could not build the 1.0.0 release image." }

    docker push $imageVersioned
    $pushExitCode = $LASTEXITCODE
    if ($pushExitCode -ne 0) { throw "Pushing $imageVersioned failed." }
    Write-Output "Copy the actual digest shown by the successful 1.0.0 push into README.md."

    docker push $imageAlias
    if ($LASTEXITCODE -ne 0) { throw "Pushing $imageAlias failed." }

    docker compose pull backend
    if ($LASTEXITCODE -ne 0) { throw "Could not pull the published backend image." }
    docker compose up -d
    if ($LASTEXITCODE -ne 0) { throw "Could not start the published-image Compose stack." }

    $health = Invoke-RestMethod -Uri "http://localhost:$($env:PORT)/api/health" -TimeoutSec 10
    $health | ConvertTo-Json -Depth 4
    if ($health.version -ne "1.0.0" -or $health.regno -ne $env:REGNO -or -not $health.database) {
        throw "The registry deployment did not report version 1.0.0, the configured REGNO, and a connected database."
    }
    Invoke-RestMethod -Uri "http://localhost:$($env:PORT)/api/registrations" -TimeoutSec 10 |
        ConvertTo-Json -Depth 5
    Write-Output "Confirm the existing registrations, then capture S4-1.png, S4-2.png, and S4-3.png."
}
finally {
    Pop-Location
}
