$ErrorActionPreference = 'Stop'

# =========================
# Cherry AI / Cherry Studio unattended install
# Intended to run under Azure VM Run Command using RunAsUser
# Logs to C:\xperts-ai-setup
# =========================

# ---- Config ----
$installerUrl = "https://www.cherry-ai.com/download"
$baseLogDir   = "C:\xperts-ai-setup"
$tempDir      = Join-Path $env:TEMP "cherry-ai-install"
$timestamp    = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath      = Join-Path $baseLogDir "cherry-ai-install-$timestamp.log"
$installerPath = Join-Path $tempDir "Cherry-Studio-setup.exe"
$expectedExe   = Join-Path $env:LOCALAPPDATA "Programs\Cherry-Studio\Cherry Studio.exe"

# Optional: set to $true only if you want to force reinstall
$forceReinstall = $false

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $entry = "[{0}] {1}" -f (Get-Date -Format "s"), $Message
    $entry | Out-File -FilePath $logPath -Append -Encoding utf8
    Write-Output $entry
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

try {
    Ensure-Directory -Path $baseLogDir
    Ensure-Directory -Path $tempDir

    Write-Log "=================================================="
    Write-Log "Starting Cherry Studio unattended install"
    Write-Log "Identity: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Log "UserProfile: $env:USERPROFILE"
    Write-Log "LocalAppData: $env:LOCALAPPDATA"
    Write-Log "LogPath: $logPath"
    Write-Log "TempDir: $tempDir"

    # Guard against accidental SYSTEM-context install
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($currentIdentity -match '\\SYSTEM$' -or $currentIdentity -eq 'SYSTEM') {
        throw "This script is running as SYSTEM. Cherry Studio should be installed with RunAsUser so it lands in the intended user's profile."
    }

    # Idempotency check
    if ((-not $forceReinstall) -and (Test-Path -LiteralPath $expectedExe)) {
        Write-Log "Cherry Studio is already installed at: $expectedExe"
        Write-Log "Skipping install because forceReinstall = $forceReinstall"
        Write-Log "Completed successfully"
        exit 0
    }

    # Clean previous installer if present
    if (Test-Path -LiteralPath $installerPath) {
        Write-Log "Removing existing installer: $installerPath"
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }

    # TLS
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Log "TLS 1.2 enabled"

    # Download
    Write-Log "Downloading installer from: $installerUrl"
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

    if (-not (Test-Path -LiteralPath $installerPath)) {
        throw "Installer download failed. File not found at $installerPath"
    }

    $installerSize = (Get-Item -LiteralPath $installerPath).Length
    Write-Log "Installer downloaded successfully: $installerPath"
    Write-Log "Installer size: $installerSize bytes"

    # Optional hash validation block
    # $expectedSha256 = "REPLACE_WITH_REAL_HASH"
    # $actualSha256 = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash
    # Write-Log "Installer SHA256: $actualSha256"
    # if ($actualSha256 -ne $expectedSha256) {
    #     throw "SHA256 mismatch. Expected $expectedSha256 but got $actualSha256"
    # }

    # Install
    Write-Log "Starting silent installer"
    $process = Start-Process `
        -FilePath $installerPath `
        -ArgumentList "/S" `
        -Wait `
        -PassThru `
        -WindowStyle Hidden

    Write-Log "Installer exited with code: $($process.ExitCode)"

    if ($process.ExitCode -ne 0) {
        throw "Installer failed with exit code $($process.ExitCode)"
    }

    # Give file system a moment in case installer exits slightly before shortcuts/files settle
    Start-Sleep -Seconds 3

    # Validate
    if (Test-Path -LiteralPath $expectedExe) {
        Write-Log "Install verified successfully"
        Write-Log "Executable found at: $expectedExe"
    }
    else {
        throw "Install completed, but expected executable was not found at: $expectedExe"
    }

    Write-Log "Cherry Studio unattended install completed successfully"
    Write-Log "=================================================="
    exit 0
}
catch {
    $errorMessage = $_.Exception.Message
    Write-Log "ERROR: $errorMessage"

    if ($_.ScriptStackTrace) {
        Write-Log "StackTrace: $($_.ScriptStackTrace)"
    }

    Write-Log "Cherry Studio unattended install failed"
    Write-Log "=================================================="
    throw
}
