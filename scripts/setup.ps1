$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot ".env"
$examplePath = Join-Path $projectRoot ".env.example"

if (-not (Test-Path -LiteralPath $examplePath)) {
    throw "Missing .env.example at $examplePath"
}

if (-not (Test-Path -LiteralPath $envPath)) {
    $bytes = New-Object byte[] 24
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    $password = [BitConverter]::ToString($bytes).Replace("-", "").ToLowerInvariant()
    $contents = [System.IO.File]::ReadAllText($examplePath)
    $contents = [regex]::Replace(
        $contents,
        "(?m)^DB_PASSWORD=.*$",
        "DB_PASSWORD=$password"
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($envPath, $contents, $utf8NoBom)
    Write-Output "Created ignored .env with a new random local database password."
}
else {
    Write-Output "Using the existing local .env; it was not overwritten."
}

Get-Content -LiteralPath $envPath | ForEach-Object {
    if ($_ -match "^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$") {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
}

if (-not $env:REGNO -or -not $env:PORT -or -not $env:DOCKERHUB_USER -or -not $env:IMAGE_NAME) {
    throw "The local .env is missing REGNO, PORT, DOCKERHUB_USER, or IMAGE_NAME. Compare it with .env.example."
}

if ($env:REGNO -ne "2400290120033" -or $env:PORT -ne "8033") {
    throw "The .env REGNO/PORT do not match this assessment configuration (REGNO 2400290120033, PORT 8033)."
}

if ($env:DOCKERHUB_USER -ne "alok8756368244" -or $env:IMAGE_NAME -ne "alok8756368244/fest-backend") {
    throw "The .env Docker Hub username or IMAGE_NAME does not match the configured account."
}

Write-Output "Loaded project configuration for REGNO $env:REGNO on port $env:PORT."
