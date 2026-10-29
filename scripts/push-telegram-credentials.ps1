<#
.SYNOPSIS
  Pushes Telegram API keys (api_id / api_hash) from the desktop Bebranoid app to a USB-connected iPhone.

.DESCRIPTION
  Bebranoid iOS picks up Documents/telegram-credentials.json on launch, moves the keys into the Keychain
  and deletes the file. The secrets never touch git, the .ipa or GitHub Actions.
  Default source is %APPDATA%\bebranoid\config.json (the same file the Electron app uses).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\push-telegram-credentials.ps1
#>
param(
    [string]$ConfigPath = (Join-Path $env:APPDATA "bebranoid\config.json"),
    [string]$BundleId = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) { throw "Not found: $ConfigPath" }
$cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $cfg.apiId -or -not $cfg.apiHash) { throw "No apiId / apiHash in $ConfigPath" }

if (-not $BundleId) {
    $finder = @'
import asyncio
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.installation_proxy import InstallationProxyService

async def main():
    lockdown = await create_using_usbmux()
    apps = await InstallationProxyService(lockdown=lockdown).get_apps(application_type='User')
    for bundle in apps:
        if bundle.startswith('com.bebranoid.ios'):
            print(bundle)
            return

asyncio.run(main())
'@
    $finderPath = Join-Path $env:TEMP "bebranoid_find_bundle.py"
    [IO.File]::WriteAllText($finderPath, $finder, (New-Object Text.UTF8Encoding($false)))
    $BundleId = ("$(python $finderPath)").Trim()
    Remove-Item $finderPath -Force -ErrorAction SilentlyContinue
    if (-not $BundleId) { throw "Bebranoid not found on the iPhone (USB connected, trusted, app installed?)" }
}

$payload = @{ apiId = [int]$cfg.apiId; apiHash = [string]$cfg.apiHash } | ConvertTo-Json -Compress
$tmp = Join-Path $env:TEMP "telegram-credentials.json"
[IO.File]::WriteAllText($tmp, $payload, (New-Object Text.UTF8Encoding($false)))

try {
    python -m pymobiledevice3 apps push $BundleId $tmp "Documents/telegram-credentials.json" --no-documents
    if ($LASTEXITCODE -ne 0) { throw "pymobiledevice3 apps push exited with code $LASTEXITCODE" }
    Write-Host "Done: Telegram keys pushed to $BundleId. Restart the app on the iPhone."
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
