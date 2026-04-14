# mgmt01-setup.ps1
# Run this on MGMT1 (172.16.1.14) as a domain admin.
# Applies GPOs — mgmt01 only gets the wallpaper GPO (not RDP or profiles).
# Run AFTER dc01-setup.ps1 has completed.

Write-Host "============================================"
Write-Host " STEP 1: Apply Group Policy"
Write-Host "============================================"

gpupdate /force

Write-Host ""
Write-Host "============================================"
Write-Host " STEP 2: Verify wallpaper GPO applied"
Write-Host "============================================"

$wallpaper = (Get-ItemProperty `
    -Path "HKCU:\Control Panel\Desktop" `
    -Name "Wallpaper" -ErrorAction SilentlyContinue).Wallpaper

if ($wallpaper) {
    Write-Host "Wallpaper policy is set to: $wallpaper"
} else {
    Write-Warning "Wallpaper policy not detected yet."
    Write-Warning "Log off and back on, then re-run this script to verify."
}

$noChange = (Get-ItemProperty `
    -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop" `
    -Name "NoChangingWallPaper" -ErrorAction SilentlyContinue).NoChangingWallPaper

if ($noChange -eq 1) {
    Write-Host "Wallpaper change is LOCKED for this user (policy enforced)."
} else {
    Write-Warning "Wallpaper lock not detected. Policy may apply after logoff/logon."
}

Write-Host ""
Write-Host "============================================"
Write-Host " DONE - MGMT1"
Write-Host "============================================"
Write-Host "Manual verification:"
Write-Host "  1. Log off and back on as a domain user"
Write-Host "  2. Right-click desktop -> Personalize should be greyed out or restricted"
Write-Host "  3. Corporate wallpaper should be visible"
