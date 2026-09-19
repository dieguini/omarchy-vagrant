# Helpers compartidos por los scripts de bootstrap.
# Se carga con: . "$PSScriptRoot\lib.ps1"

Set-StrictMode -Version Latest

function Get-RepoRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-BuildDir {
    $dir = Join-Path (Get-RepoRoot) '.build'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $dir
}

# config.json trae los valores por defecto; config.local.json (ignorado por git)
# sobrescribe las claves que declare. Así la contraseña real nunca se versiona.
function Get-OmarchyConfig {
    $root = Get-RepoRoot
    $cfg = @{}
    (Get-Content (Join-Path $root 'config.json') -Raw | ConvertFrom-Json).PSObject.Properties |
        ForEach-Object { $cfg[$_.Name] = $_.Value }

    $localPath = Join-Path $root 'config.local.json'
    if (Test-Path $localPath) {
        (Get-Content $localPath -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $cfg[$_.Name] = $_.Value }
    }

    if (-not $cfg['iso_url']) {
        $cfg['iso_url'] = "https://iso.omarchy.org/omarchy-$($cfg['omarchy_version']).iso"
    }
    $cfg
}

function Get-IsoPath {
    param([hashtable] $Config)
    Join-Path (Get-BuildDir) "omarchy-$($Config['omarchy_version']).iso"
}

function Get-CidataPath {
    Join-Path (Get-BuildDir) 'cidata.iso'
}

function Get-SshKeyPath {
    Join-Path (Get-BuildDir) 'ssh/id_ed25519'
}

function Get-BoxName {
    param([hashtable] $Config)
    "omarchy-empty-$($Config['disk_gb'])g"
}

function Get-VBoxManage {
    $candidates = @()
    if ($env:VBOX_MSI_INSTALL_PATH) { $candidates += (Join-Path $env:VBOX_MSI_INSTALL_PATH 'VBoxManage.exe') }
    if ($env:VBOX_INSTALL_PATH)     { $candidates += (Join-Path $env:VBOX_INSTALL_PATH 'VBoxManage.exe') }
    $candidates += 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
    $cmd = Get-Command VBoxManage.exe -ErrorAction SilentlyContinue
    if ($cmd) { $candidates = @($cmd.Source) + $candidates }

    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    throw "No encuentro VBoxManage.exe. Instala VirtualBox desde https://www.virtualbox.org/"
}

# openssl viene con Git para Windows aunque no esté en el PATH.
function Get-OpenSsl {
    $cmd = Get-Command openssl.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in @(
        'C:\Program Files\Git\mingw64\bin\openssl.exe',
        'C:\Program Files\Git\usr\bin\openssl.exe'
    )) { if (Test-Path $c) { return $c } }
    throw "No encuentro openssl.exe (hace falta para el hash SHA-512 de la contraseña). Instala Git para Windows."
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)] [string]   $FilePath,
        [Parameter(Mandatory)] [AllowEmptyString()] [string[]] $Arguments,
        [switch] $IgnoreExitCode
    )
    & $FilePath @Arguments
    if (-not $IgnoreExitCode -and $LASTEXITCODE -ne 0) {
        throw "Falló: $FilePath $($Arguments -join ' ') (exit $LASTEXITCODE)"
    }
}

# Crea una ISO ISO9660+Joliet con IMAPI2, la API de grabado que trae Windows.
# El kernel de Linux lee los nombres largos desde Joliet, que es lo que el
# instalador de Omarchy necesita para encontrar user_configuration.json.
function New-IsoImage {
    param(
        [Parameter(Mandatory)] [string] $SourceDir,
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $OutFile
    )

    if (-not ('OmarchyIsoWriter' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class OmarchyIsoWriter {
    public static void Write(string path, object stream, int blockSize, int totalBlocks) {
        IStream source = (IStream)stream;
        byte[] buffer = new byte[blockSize];
        IntPtr read = Marshal.AllocHGlobal(sizeof(int));
        try {
            using (FileStream output = File.Open(path, FileMode.Create, FileAccess.Write)) {
                while (totalBlocks-- > 0) {
                    source.Read(buffer, blockSize, read);
                    output.Write(buffer, 0, Marshal.ReadInt32(read));
                }
            }
        } finally {
            Marshal.FreeHGlobal(read);
        }
    }
}
'@
    }

    $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $fsi.FileSystemsToCreate = 3   # ISO9660 | Joliet
    $fsi.VolumeName = $Label
    $fsi.Root.AddTree((Resolve-Path $SourceDir).Path, $false)

    $image = $fsi.CreateResultImage()
    [OmarchyIsoWriter]::Write($OutFile, $image.ImageStream, $image.BlockSize, $image.TotalBlocks)

    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($image)
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($fsi)
}
