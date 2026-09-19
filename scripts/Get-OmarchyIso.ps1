<#
.SYNOPSIS
    Descarga la ISO oficial de Omarchy a .build\ y verifica su SHA-256.
.DESCRIPTION
    La descarga se reanuda (curl -C -), así que un corte de red no obliga a
    empezar de cero con los ~6 GB. Si el archivo ya está y el hash cuadra, no
    hace nada.
#>
[CmdletBinding()]
param([switch] $Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

$cfg = Get-OmarchyConfig
$iso = Get-IsoPath $cfg
$url = $cfg['iso_url']

# El hash publicado junto a la ISO, salvo que config.json fije uno.
$expected = $cfg['iso_sha256']
if (-not $expected) {
    Write-Host "Obteniendo SHA-256 publicado de $url.sha256"
    $body = (Invoke-WebRequest -Uri "$url.sha256" -UseBasicParsing).Content
    # El bucket sirve el .sha256 como binario, y Windows PowerShell entrega
    # .Content como byte[] cuando el Content-Type no es texto.
    if ($body -is [byte[]]) { $body = [Text.Encoding]::UTF8.GetString($body) }
    $expected = ([string] $body).Trim() -split '\s+' | Select-Object -First 1
}
$expected = $expected.Trim().ToLowerInvariant()
if ($expected -notmatch '^[0-9a-f]{64}$') {
    throw "El SHA-256 esperado no parece válido: '$expected'"
}

if ((Test-Path $iso) -and -not $Force) {
    Write-Host "Verificando la ISO que ya está en disco..."
    if ((Get-FileHash $iso -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expected) {
        Write-Host "ISO OK: $iso"
        return
    }
    Write-Warning "La ISO local no coincide con el hash; reanudando la descarga."
}

Write-Host "Descargando $url"
Write-Host "(son unos 6 GB; se puede interrumpir y reanudar volviendo a correr esto)"
Invoke-Native -FilePath 'curl.exe' -Arguments @(
    '--location', '--fail', '--retry', '3', '--continue-at', '-',
    '--output', $iso, $url
)

Write-Host "Verificando SHA-256..."
$actual = (Get-FileHash $iso -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) {
    throw "SHA-256 no coincide.`n  esperado: $expected`n  obtenido: $actual`nBorra $iso y vuelve a intentar."
}
Write-Host "ISO verificada: $iso"
