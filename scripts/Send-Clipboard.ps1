<#
.SYNOPSIS
    Sends the host (Windows) clipboard to the VM's Wayland clipboard over SSH.

.DESCRIPTION
    VirtualBox's shared clipboard works VM -> host under Hyprland, but host -> VM
    announcements do not reach a pure Wayland guest reliably. This copies the host
    clipboard straight into the VM with wl-copy, as UTF-8, detached from the SSH session.

    Copy on Windows, run this, then paste in the VM (Ctrl+Shift+V in the terminal,
    Ctrl+V in most apps). With -Once the VM clipboard clears itself after the first paste,
    which is what you want for a password.

.EXAMPLE
    .\scripts\Send-Clipboard.ps1 -Once
#>
[CmdletBinding()]
param(
    [switch]$Once,
    [string]$Key = (Join-Path $PSScriptRoot '..\.build\ssh\id_ed25519'),
    [int]$Port = 2222,
    [string]$User = 'omarchy'
)

$OutputEncoding = [Text.UTF8Encoding]::new($false)
$text = Get-Clipboard -Raw
if ([string]::IsNullOrEmpty($text)) { throw 'The host clipboard is empty.' }

$flags = if ($Once) { '--paste-once --trim-newline' } else { '--trim-newline' }
$remote = "WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/`$(id -u) setsid -f wl-copy $flags >/dev/null 2>&1"
$text | ssh -i $Key -p $Port -o UserKnownHostsFile=NUL -o StrictHostKeyChecking=no -o LogLevel=ERROR "$User@127.0.0.1" $remote
if ($LASTEXITCODE -ne 0) { throw "ssh exited with $LASTEXITCODE" }
Write-Host ('Sent to the VM clipboard' + $(if ($Once) { ' (clears after one paste).' } else { '.' }))
