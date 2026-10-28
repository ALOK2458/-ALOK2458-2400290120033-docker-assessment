param(
    [switch]$RequireRunningStack
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$requiredFiles = @(
    "README.md",
    "compose.yaml",
    "compose.stage2.yaml",
    ".env.example",
    ".gitignore",
    "backend/app.py",
    "backend/requirements.txt",
    "backend/requirements.stage1.txt",
    "backend/Dockerfile",
    "backend/Dockerfile.stage1",
    "backend/.dockerignore",
    "frontend/index.html",
    "frontend/nginx.conf",
    "reports/trivy-before.txt",
    "reports/trivy-after.txt",
    "scripts/setup.ps1",
    "scripts/validate.ps1",
    "scripts/stage1.ps1",
    "scripts/stage2.ps1",
    "scripts/stage3.ps1",
    "scripts/stage4.ps1",
    "scripts/stage5.ps1",
    "tests/test_api.py"
)
$missingFiles = @($requiredFiles | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $projectRoot $_))
})
if ($missingFiles.Count -gt 0) {
    throw "Required files are missing: $($missingFiles -join ', ')"
}
Write-Output "PASS: required project files exist."

if (-not (Test-Path -LiteralPath (Join-Path $projectRoot ".env"))) {
    Write-Output "BLOCKED: .env is missing; run . .\scripts\setup.ps1."
}
else {
    . (Join-Path $PSScriptRoot "setup.ps1")
}

Push-Location $projectRoot
try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI is not installed."
    }
    $dockerClient = docker version --format "{{.Client.Version}}" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Docker CLI could not report its client version: $dockerClient"
    }
    Write-Output "PASS: Docker CLI is installed (client $dockerClient)."

    $dockerServer = docker version --format "{{.Server.Version}}" 2>&1
    $dockerServerReady = $LASTEXITCODE -eq 0
    if ($dockerServerReady) {
        Write-Output "PASS: Docker daemon is running (server $dockerServer)."
    }
    else {
        Write-Output "BLOCKED: Docker daemon is unavailable: $dockerServer"
    }

    $ignoredEnv = git check-ignore -q .env
    if ($LASTEXITCODE -ne 0) {
        throw ".env is not ignored by Git."
    }
    Write-Output "PASS: .env is ignored by Git."

    $trackedPrivateKey = git ls-files --error-unmatch cosign.key 2>$null
    if ($LASTEXITCODE -eq 0) {
        throw "cosign.key is tracked by Git. Remove it from the index safely before continuing."
    }
    Write-Output "PASS: cosign.key is not tracked."

    $composeOutput = docker compose config --quiet 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose validation failed: $composeOutput"
    }
    Write-Output "PASS: final Docker Compose configuration is valid."

    $secretPatterns = @(
        "dckr_pat_[A-Za-z0-9_-]{20,}",
        "gh[pousr]_[A-Za-z0-9_]{30,}",
        "-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"
    )
    $trackedFiles = @(git ls-files)
    foreach ($relativePath in $trackedFiles) {
        if ($relativePath -match "(?i)(^|/)(\.env|cosign\.key)$|\.pem$|\.p12$|\.pfx$") {
            throw "A private environment or key file is tracked: $relativePath"
        }
    }
    $textFiles = Get-ChildItem -LiteralPath $projectRoot -File -Recurse | Where-Object {
        $_.FullName -notmatch "[\\/]\.git([\\/]|$)|[\\/]\.venv([\\/]|$)|[\\/]screenshots([\\/]|$)" -and
        $_.Name -ne ".env" -and
        $_.Name -notmatch "\.(key|pem|p12|pfx)$" -and
        $_.Extension -match "^\.(py|ps1|yaml|yml|html|conf|txt|md|example|gitignore)$|^$"
    }
    foreach ($file in $textFiles) {
        $content = [System.IO.File]::ReadAllText($file.FullName)
        foreach ($pattern in $secretPatterns) {
            if ($content -match $pattern) {
                throw "A possible credential or private key was found in $($file.FullName)."
            }
        }
    }
    Write-Output "PASS: no obvious credential strings found in tracked files."

    if ($RequireRunningStack) {
        if (-not $dockerServerReady) {
            throw "A running Docker daemon is required for -RequireRunningStack."
        }
        $healthUri = "http://localhost:$env:PORT/api/health"
        $health = Invoke-RestMethod -Uri $healthUri -TimeoutSec 5
        if ($health.regno -ne $env:REGNO -or -not $health.database) {
            throw "Backend health did not report the configured REGNO and database connectivity."
        }
        Write-Output "PASS: backend health reports the configured REGNO and database connected."
        docker compose ps
    }
    else {
        if ($dockerServerReady) {
            foreach ($image in @("fest-backend:0.1", "fest-backend:0.2", "$($env:IMAGE_NAME):1.0.0")) {
                docker image inspect $image --format "{{.RepoTags}}"
                if ($LASTEXITCODE -eq 0) {
                    Write-Output "AVAILABLE IMAGE: $image"
                }
                else {
                    Write-Output "NOT BUILT/PULLED: $image"
                }
            }
            docker compose ps
        }
        else {
            Write-Output "SKIPPED: image and container checks require a running Docker daemon."
        }
    }

    foreach ($toolName in @("trivy", "cosign")) {
        if (Get-Command $toolName -ErrorAction SilentlyContinue) {
            Write-Output "AVAILABLE: $toolName"
        }
        if (Test-Path -LiteralPath (Join-Path $projectRoot "cosign.pub")) {
            Write-Output "AVAILABLE: cosign.pub"
        }
        else {
            Write-Output "NOT GENERATED: cosign.pub (generate the student's own key pair in Stage 5)."
        }
        else {
            Write-Output "NOT INSTALLED: $toolName"
        }
    }

    $requiredEvidence = @(
        "S1-2.png", "S1-3.png", "S2-2.png", "S2-3.png", "S2-4.png",
        "S3-1.png", "S3-3.png", "S4-1.png", "S4-2.png", "S4-3.png",
        "S5-1.png", "S5-2.png", "S5-3.png", "S5-4.png"
    )
    $missingEvidence = @($requiredEvidence | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $projectRoot "screenshots\$_"))
    })
    if ($missingEvidence.Count -gt 0) {
        Write-Output "MANUAL EVIDENCE STILL REQUIRED: $($missingEvidence -join ', ')"
    }
}
finally {
    Pop-Location
}
