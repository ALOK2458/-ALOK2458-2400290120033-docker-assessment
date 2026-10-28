param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^sha256:[0-9a-f]{64}$")]
    [string]$Digest1000,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^sha256:[0-9a-f]{64}$")]
    [string]$Digest1001
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "setup.ps1")
Push-Location $projectRoot

try {
    if (-not (Get-Command cosign -ErrorAction SilentlyContinue)) {
        throw "Cosign is not installed. Install the official Cosign release before signing."
    }
    if (Test-Path -LiteralPath "cosign.key") {
        $keyIgnored = git check-ignore -q cosign.key
        if ($LASTEXITCODE -ne 0) { throw "cosign.key is not ignored by Git." }
    }
    $stagedFiles = @(git diff --cached --name-only)
    if ($stagedFiles | Where-Object { $_ -match "(?i)(^|/)(\.env|cosign\.key)$|\.pem$|\.p12$|\.pfx$" }) {
        throw "A local environment or private-key file is staged. Unstage it safely before signing."
    }
    $trackedCredentials = @(git ls-files .env cosign.key)
    if ($trackedCredentials.Count -gt 0) {
        throw "A local environment or private-key file is already tracked: $($trackedCredentials -join ', '). Remove it from tracking safely before signing."
    }
    git status --short
    Write-Output "Staged-file safety check passed. No .env or private-key file is staged."

    $publicKey = Join-Path $projectRoot "cosign.pub"
    $privateKey = Join-Path $projectRoot "cosign.key"
    if (-not (Test-Path -LiteralPath $publicKey) -or -not (Test-Path -LiteralPath $privateKey)) {
        Write-Output "Cosign will prompt for a key password. Do not copy or screenshot the private key or password."
        cosign generate-key-pair
        if ($LASTEXITCODE -ne 0) { throw "Cosign key generation failed." }
    }
    if (-not (Test-Path -LiteralPath $publicKey) -or -not (Test-Path -LiteralPath $privateKey)) {
        throw "Cosign did not create both expected key files."
    }

    $signedReference = "$($env:IMAGE_NAME)@$Digest1000"
    cosign sign --yes --key $privateKey $signedReference
    $signExitCode = $LASTEXITCODE
    if ($signExitCode -ne 0) { throw "Signing $signedReference failed with exit code $signExitCode." }

    cosign verify --key $publicKey $signedReference
    $verifyExitCode = $LASTEXITCODE
    if ($verifyExitCode -ne 0) { throw "Positive verification failed with exit code $verifyExitCode." }
    Write-Output "Positive verification succeeded for the signed 1.0.0 digest."

    $unsignedReference = "$($env:IMAGE_NAME)@$Digest1001"
    $negativeOutput = cosign verify --key $publicKey $unsignedReference 2>&1
    $negativeExitCode = $LASTEXITCODE
    $negativeOutput
    if ($negativeExitCode -eq 0) {
        throw "Unexpected result: the unsigned 1.0.1 digest verified successfully."
    }
    if (($negativeOutput -join "`n") -notmatch "(?i)no matching signatures|no signatures found|no signatures") {
        throw "Verification failed for a reason other than a confirmed missing signature. Inspect the output and retry after checking registry access and both digests."
    }
    Write-Output "Negative verification failed specifically because no matching signature exists for 1.0.1."
    Write-Output "Capture S5-1.png through S5-4.png. Commit cosign.pub only; never stage cosign.key."
}
finally {
    Pop-Location
}
