# Update 2026/03/04
# -----------------------------
# CONFIG
# -----------------------------
$logDir  = 'C:\xperts-ai-setup'
$logFile = Join-Path $logDir 'managed-favorites.log'

# Ensure log directory exists
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logFile -Value "$ts [$Level] $Message"
}

# -----------------------------
# MAIN
# -----------------------------
try {
    Write-Log "===== START Managed Favorites Setup ====="

    # Define bookmarks (ORDERED)
    $managedFavoritesObject = @(
        @{ toplevel_name = 'FortiWeb Labs' }
        @{ name = 'XPERTS Hands-on-Labs'; url = 'https://canada.amerintlxperts.com/hands-on-labs.html' }
        @{ name = 'FortiWeb Admin';       url = 'https://fwb-xperts.labsec.ca:8443' }
        @{ name = 'Demo Tool';            url = 'http://demotool-xperts.labsec.ca:8080' }
        @{ name = 'DVWA';                 url = 'http://dvwa-xperts.labsec.ca' }
        @{ name = 'Banking Application';  url = 'http://bank-xperts.labsec.ca' }
        @{ name = 'MCP Server';           url = 'http://mcp-xperts.labsec.ca' }
        @{ name = 'Juiceshop';            url = 'http://juiceshop-xperts.labsec.ca' }
        @{ name = 'Petstore';             url = 'http://petstore3-xperts.labsec.ca' }
        @{ name = 'Speedtest';            url = 'http://speedtest-xperts.labsec.ca' }
        @{ name = 'CSP Server';           url = 'http://csp-xperts.labsec.ca' }
    )

    $managedFavoritesJson = $managedFavoritesObject | ConvertTo-Json -Compress -Depth 10

    $edgePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    $propertyName   = 'ManagedFavorites'

    # Ensure policy path exists
    if (-not (Test-Path $edgePolicyPath)) {
        New-Item -Path $edgePolicyPath -Force | Out-Null
        Write-Log "Created registry path: $edgePolicyPath"
    }

    # -----------------------------
    # CHECK & REPLACE LOGIC
    # -----------------------------
    $existingValue = $null

    if (Get-ItemProperty -Path $edgePolicyPath -Name $propertyName -ErrorAction SilentlyContinue) {
        $existingValue = (Get-ItemProperty -Path $edgePolicyPath -Name $propertyName).$propertyName
        Write-Log "Existing ManagedFavorites policy FOUND"

        # Log existing value (truncated for safety)
        $preview = $existingValue.Substring(0, [Math]::Min(200, $existingValue.Length))
        Write-Log "Existing value preview: $preview..."

        # Remove old policy (clean replace)
        Remove-ItemProperty -Path $edgePolicyPath -Name $propertyName -Force
        Write-Log "Removed existing ManagedFavorites policy"
    }
    else {
        Write-Log "No existing ManagedFavorites policy found"
    }

    # -----------------------------
    # WRITE NEW POLICY
    # -----------------------------
    New-ItemProperty `
        -Path $edgePolicyPath `
        -Name $propertyName `
        -PropertyType String `
        -Value $managedFavoritesJson `
        -Force | Out-Null

    Write-Log "New ManagedFavorites policy written"

    # Validate write
    $verify = (Get-ItemProperty -Path $edgePolicyPath -Name $propertyName).$propertyName

    if ($verify -eq $managedFavoritesJson) {
        Write-Log "Verification SUCCESS: Policy matches expected value" "SUCCESS"
        Write-Output "SUCCESS: Managed favorites deployed and replaced."
    }
    else {
        throw "Verification failed: registry value mismatch"
    }

    Write-Log "===== END Managed Favorites Setup ====="
}
catch {
    Write-Log "FAILED: $($_.Exception.Message)" "ERROR"
    Write-Output "ERROR: Deployment failed. Check log at $logFile"
    exit 1
}
