$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "setup.ps1")
Push-Location $projectRoot

try {
    if (-not (Get-Command trivy -ErrorAction SilentlyContinue)) {
        throw "Trivy is not installed. Install it from the official Trivy documentation before scanning; no report was generated."
    }

    docker build -f backend\Dockerfile.stage1 -t fest-backend:0.1 backend
    if ($LASTEXITCODE -ne 0) { throw "Could not build the Stage 1 image for the before scan." }

    trivy image --no-progress fest-backend:0.1 2>&1 | Tee-Object -FilePath reports\trivy-before.txt
    $beforeExitCode = $LASTEXITCODE
    if ($beforeExitCode -ne 0) { throw "The before scan failed with exit code $beforeExitCode; inspect reports\trivy-before.txt." }

    docker build --build-arg APP_VERSION=0.2 -f backend\Dockerfile -t fest-backend:0.2 backend
    if ($LASTEXITCODE -ne 0) { throw "Could not build fest-backend:0.2." }
    docker image inspect fest-backend:0.2 --format "Image={{.RepoTags}} SizeBytes={{.Size}}"

    trivy image --no-progress fest-backend:0.2 2>&1 | Tee-Object -FilePath reports\trivy-after.txt
    $afterExitCode = $LASTEXITCODE
    if ($afterExitCode -ne 0) { throw "The after scan failed with exit code $afterExitCode; inspect reports\trivy-after.txt." }

    trivy image --severity CRITICAL --ignore-unfixed --exit-code 1 fest-backend:0.2
    $criticalExitCode = $LASTEXITCODE
    Write-Output "Critical-with-fix scan exit code: $criticalExitCode"
    if ($criticalExitCode -ne 0) {
        throw "The critical-vulnerability threshold was not met. Review the real report, update compatible dependencies/base image, rebuild, and rescan."
    }
    Write-Output "Both report files contain actual Trivy output. Record actual counts and image sizes in README before committing."
}
finally {
    Pop-Location
}
