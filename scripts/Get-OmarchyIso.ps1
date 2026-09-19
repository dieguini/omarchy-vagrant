<#
.SYNOPSIS
    Downloads the official Omarchy ISO into .build\ and verifies its SHA-256.
.DESCRIPTION
    The download resumes (curl -C -), so a dropped connection doesn't mean
    starting the ~6 GB over. If the file is already there and the hash matches,
    it does nothing.
#>
[CmdletBinding()]
param([switch] $Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

$cfg = Get-OmarchyConfig
$iso = Get-IsoPath $cfg
$url = $cfg['iso_url']

# The hash published next to the ISO, unless config.json pins one.
$expected = $cfg['iso_sha256']
if (-not $expected) {
    Write-Host "Fetching the published SHA-256 from $url.sha256"
    $body = (Invoke-WebRequest -Uri "$url.sha256" -UseBasicParsing).Content
    # The bucket serves the .sha256 as binary, and Windows PowerShell hands
    # back .Content as byte[] whenever the Content-Type isn't text.
    if ($body -is [byte[]]) { $body = [Text.Encoding]::UTF8.GetString($body) }
    $expected = ([string] $body).Trim() -split '\s+' | Select-Object -First 1
}
$expected = $expected.Trim().ToLowerInvariant()
if ($expected -notmatch '^[0-9a-f]{64}$') {
    throw "The expected SHA-256 does not look valid: '$expected'"
}

if ((Test-Path $iso) -and -not $Force) {
    Write-Host "Verifying the ISO already on disk..."
    if ((Get-FileHash $iso -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expected) {
        Write-Host "ISO OK: $iso"
        return
    }
    Write-Warning "The local ISO does not match the hash; resuming the download."
}

Write-Host "Downloading $url"
Write-Host "(about 6 GB; you can interrupt it and resume by running this again)"
Invoke-Native -FilePath 'curl.exe' -Arguments @(
    '--location', '--fail', '--retry', '3', '--continue-at', '-',
    '--output', $iso, $url
)

Write-Host "Verifying SHA-256..."
$actual = (Get-FileHash $iso -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) {
    throw "SHA-256 mismatch.`n  expected: $expected`n  got:      $actual`nDelete $iso and try again."
}
Write-Host "ISO verified: $iso"
