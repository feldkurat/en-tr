# Installs the "US Intl - TR" keyboard layout (ustr.dll) system-wide.
# Registers the same registry entries an MSKLC-built MSI would create.
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    exit
}

$here = Split-Path -Parent $PSCommandPath
$klid = 'a0000409'
$layoutsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts'
$regPath = Join-Path $layoutsKey $klid

$existing = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
if ($existing -and $existing.'Layout File' -ne 'ustr.dll') {
    Write-Host "Registry slot $klid is already used by '$($existing.'Layout File')'. Aborting."
    Read-Host 'Press Enter to close'
    exit 1
}

if ([Environment]::Is64BitOperatingSystem) {
    Copy-Item (Join-Path $here 'amd64\ustr.dll') (Join-Path $env:SystemRoot 'System32\ustr.dll') -Force
    Copy-Item (Join-Path $here 'wow64\ustr.dll') (Join-Path $env:SystemRoot 'SysWOW64\ustr.dll') -Force
} else {
    Copy-Item (Join-Path $here 'i386\ustr.dll') (Join-Path $env:SystemRoot 'System32\ustr.dll') -Force
}

# "Layout Id" must be unique among all installed layouts; pick the first free one.
$used = Get-ChildItem $layoutsKey | ForEach-Object { (Get-ItemProperty $_.PSPath).'Layout Id' } | Where-Object { $_ }
$id = 0xc8
while (('{0:x4}' -f $id) -in $used) { $id++ }

New-Item -Path $regPath -Force | Out-Null
New-ItemProperty -Path $regPath -Name 'Layout File' -Value 'ustr.dll' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regPath -Name 'Layout Text' -Value 'US Intl - TR' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regPath -Name 'Layout Id' -Value ('{0:x4}' -f $id) -PropertyType String -Force | Out-Null

Write-Host ''
Write-Host 'Installed. Now add the layout to your language:'
Write-Host '  Settings > Time & Language > Language & region > English (United States)'
Write-Host '  > Language options > Add a keyboard > "US Intl - TR"'
Write-Host 'Sign out and back in if it does not show up in the list.'
Read-Host 'Press Enter to close'
