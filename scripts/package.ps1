# HolyOrders release packaging
# Builds dist/HolyOrders-v<version>.zip containing a clean HolyOrders/ folder
# (game files + license + docs a user needs; no git, no internal notes).
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$toc = Get-Content (Join-Path $root "HolyOrders.toc")
$version = ($toc | Where-Object { $_ -match "^## Version:" }) -replace "## Version:\s*", ""
if (-not $version) { throw "version not found in TOC" }

$dist = Join-Path $root "dist"
$stage = Join-Path $dist "HolyOrders"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null

$include = @("*.lua", "*.toc", "LICENSE", "README.md", "CHANGELOG.md")
foreach ($pattern in $include) {
    Copy-Item (Join-Path $root $pattern) $stage -ErrorAction SilentlyContinue
}
Copy-Item (Join-Path $root "Icons") (Join-Path $stage "Icons") -Recurse

$zip = Join-Path $dist ("HolyOrders-v{0}.zip" -f $version)
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path $stage -DestinationPath $zip

Remove-Item -Recurse -Force $stage
Write-Output ("packaged: {0} ({1:n0} bytes)" -f $zip, (Get-Item $zip).Length)
