# Removes the "US Intl - TR" keyboard layout.
# Remove the layout from Settings (Language options > keyboards) and sign out first,
# otherwise ustr.dll may still be loaded and refuse to delete.
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    exit
}

$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts\a0000409'
$existing = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
if ($existing -and $existing.'Layout File' -eq 'ustr.dll') {
    Remove-Item -Path $regPath -Force
    Write-Host 'Registry entry removed.'
} else {
    Write-Host 'Layout registry entry not found (already removed?).'
}

foreach ($dll in "$env:SystemRoot\System32\ustr.dll", "$env:SystemRoot\SysWOW64\ustr.dll") {
    if (Test-Path $dll) {
        try {
            Remove-Item $dll -Force
            Write-Host "Deleted $dll"
        } catch {
            Write-Host "Could not delete $dll (still in use?). Sign out, sign in and run again."
        }
    }
}

Read-Host 'Press Enter to close'
