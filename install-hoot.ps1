$ErrorActionPreference = 'Stop'

# =========================
# Install Portkey Hoot + guarantee supported Node.js
# Windows / Azure VM Run Command friendly
# =========================

# ---- Config ----
$BaseLogDir        = 'C:\xperts-ai-setup'
$TimeStamp         = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogPath           = Join-Path $BaseLogDir "install-hoot-$TimeStamp.log"
$TempDir           = Join-Path $env:TEMP 'hoot-install'
$NodeVersionMin    = [Version]'18.0.0'

# Pin current official LTS MSI. Update this occasionally if you want the newest LTS.
$NodeVersionTarget = '24.14.1'
$NodeMsiUrl        = "https://nodejs.org/dist/v$NodeVersionTarget/node-v$NodeVersionTarget-x64.msi"
$NodeMsiPath       = Join-Path $TempDir "node-v$NodeVersionTarget-x64.msi"

$NodeExeDefault    = 'C:\Program Files\nodejs\node.exe'
$NpmCmdDefault     = 'C:\Program Files\nodejs\npm.cmd'
$HootCmdDefault    = 'C:\Program Files\nodejs\hoot.cmd'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format s), $Message
    $line | Out-File -FilePath $LogPath -Append -Encoding utf8
    Write-Output $line
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-CommandPathOrNull {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-InstalledNodeVersion {
    $nodePath = Get-CommandPathOrNull -Name 'node'
    if (-not $nodePath -and (Test-Path -LiteralPath $NodeExeDefault)) {
        $nodePath = $NodeExeDefault
    }

    if (-not $nodePath) {
        return $null
    }

    $raw = & $nodePath --version
    if (-not $raw) {
        return $null
    }

    # Converts v24.14.1 -> 24.14.1
    return [Version]($raw.Trim().TrimStart('v'))
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')

    if ([string]::IsNullOrWhiteSpace($userPath)) {
        $env:Path = $machinePath
    }
    else {
        $env:Path = "$machinePath;$userPath"
    }
}

try {
    Ensure-Directory -Path $BaseLogDir
    Ensure-Directory -Path $TempDir

    Write-Log '=================================================='
    Write-Log 'Starting Portkey Hoot installation'
    Write-Log "Identity: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Log "UserProfile: $env:USERPROFILE"
    Write-Log "TempDir: $TempDir"
    Write-Log "LogPath: $LogPath"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Log 'TLS 1.2 enabled'

    # ---- Ensure supported Node.js ----
    $installedNodeVersion = Get-InstalledNodeVersion
    if ($installedNodeVersion -and $installedNodeVersion -ge $NodeVersionMin) {
        Write-Log "Supported Node.js already present: $installedNodeVersion"
    }
    else {
        if ($installedNodeVersion) {
            Write-Log "Node.js present but too old: $installedNodeVersion. Installing $NodeVersionTarget LTS."
        }
        else {
            Write-Log "Node.js not found. Installing $NodeVersionTarget LTS."
        }

        Write-Log "Downloading Node.js MSI from: $NodeMsiUrl"
        Invoke-WebRequest -Uri $NodeMsiUrl -OutFile $NodeMsiPath -UseBasicParsing

        if (-not (Test-Path -LiteralPath $NodeMsiPath)) {
            throw "Node.js MSI download failed: $NodeMsiPath"
        }

        $msiSize = (Get-Item -LiteralPath $NodeMsiPath).Length
        Write-Log "Node.js MSI downloaded successfully ($msiSize bytes)"

        $msiArgs = @(
            '/i'
            "`"$NodeMsiPath`""
            '/qn'
            '/norestart'
        )

        Write-Log 'Starting silent Node.js MSI install'
        $nodeInstall = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -WindowStyle Hidden
        Write-Log "Node.js MSI exit code: $($nodeInstall.ExitCode)"

        if ($nodeInstall.ExitCode -ne 0) {
            throw "Node.js MSI install failed with exit code $($nodeInstall.ExitCode)"
        }

        Refresh-ProcessPath
        Start-Sleep -Seconds 3

        $installedNodeVersion = Get-InstalledNodeVersion
        if (-not $installedNodeVersion -or $installedNodeVersion -lt $NodeVersionMin) {
            throw "Node.js verification failed after install. Found: $installedNodeVersion"
        }

        Write-Log "Node.js verified successfully: $installedNodeVersion"
    }

    # ---- Resolve npm ----
    $npmPath = Get-CommandPathOrNull -Name 'npm.cmd'
    if (-not $npmPath -and (Test-Path -LiteralPath $NpmCmdDefault)) {
        $npmPath = $NpmCmdDefault
    }

    if (-not $npmPath) {
        throw 'npm.cmd not found after Node.js install'
    }

    Write-Log "npm resolved to: $npmPath"
    $npmVersion = & $npmPath --version
    Write-Log "npm version: $npmVersion"

    # ---- Install / update Hoot ----
    Write-Log 'Installing Hoot globally from npm'
    $npmInstall = Start-Process `
        -FilePath $npmPath `
        -ArgumentList 'install', '-g', '@portkey-ai/hoot' `
        -Wait `
        -PassThru `
        -WindowStyle Hidden

    Write-Log "npm install exit code: $($npmInstall.ExitCode)"
    if ($npmInstall.ExitCode -ne 0) {
        throw "Global Hoot install failed with exit code $($npmInstall.ExitCode)"
    }

    Refresh-ProcessPath
    Start-Sleep -Seconds 2

    # ---- Verify Hoot ----
    $hootPath = Get-CommandPathOrNull -Name 'hoot.cmd'
    if (-not $hootPath -and (Test-Path -LiteralPath $HootCmdDefault)) {
        $hootPath = $HootCmdDefault
    }

    if (-not $hootPath) {
        throw 'hoot.cmd not found after npm install'
    }

    Write-Log "hoot resolved to: $hootPath"

    $hootVersionOutput = & $hootPath --version 2>&1
    Write-Log "hoot version output: $hootVersionOutput"

    Write-Log 'Portkey Hoot installation completed successfully'
    Write-Log '=================================================='
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    if ($_.ScriptStackTrace) {
        Write-Log "StackTrace: $($_.ScriptStackTrace)"
    }
    Write-Log 'Installation failed'
    Write-Log '=================================================='
    throw
}
