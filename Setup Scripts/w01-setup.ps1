# w01-setup.ps1
# Run this on W1 (172.16.1.104) as a domain admin.
# Applies GPOs and verifies RDP, wallpaper, and DFS profile are working.
# Run AFTER dc01-setup.ps1 has completed.

Write-Host "============================================"
Write-Host " STEP 1: Apply Group Policy"
Write-Host "============================================"

gpupdate /force

Write-Host ""
Write-Host "============================================"
Write-Host " STEP 2: Verify RDP is enabled"
Write-Host "============================================"

$rdpValue = Get-ItemProperty `
    -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
    -Name "fDenyTSConnections"

if ($rdpValue.fDenyTSConnections -eq 0) {
    Write-Host "RDP is ENABLED on this machine."
} else {
    Write-Warning "RDP is still DISABLED. GPO may not have applied yet. Try rebooting."
}

Write-Host ""
Write-Host "============================================"
Write-Host " STEP 3: Test RDP connection to W2"
Write-Host "============================================"

Write-Host "Testing connectivity to W2 on port 3389..."
$tcpTest = Test-NetConnection -ComputerName w02 -Port 3389

if ($tcpTest.TcpTestSucceeded) {
    Write-Host "RDP port 3389 is reachable on W2."
} else {
    Write-Warning "Cannot reach W2 on port 3389. Ensure w02-setup.ps1 has been run on W2."
}

Write-Host ""
Write-Host "============================================"
Write-Host " STEP 4: Verify DFS profile path"
Write-Host "============================================"

$currentUser = $env:USERNAME
$profilePath = (Get-ItemProperty `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\winlogon" `
    -Name "RoamingUserProfilePath" -ErrorAction SilentlyContinue).RoamingUserProfilePath

if ($profilePath) {
    Write-Host "Roaming profile path GPO is set to: $profilePath"
} else {
    Write-Warning "Roaming profile path GPO not detected. Check dc01-setup.ps1 ran successfully."
}

Write-Host ""
Write-Host "============================================"
Write-Host " STEP 5: Map H: drive to DFS profiles share"
Write-Host "============================================"

$dfsPath = "\\grok.local\profiles\$currentUser\Documents"

if (-not (Test-Path "H:\")) {
    try {
        New-PSDrive -Name H -PSProvider FileSystem -Root $dfsPath -Persist
        Write-Host "H: drive mapped to $dfsPath"
    } catch {
        Write-Warning "Could not map H: drive. DFS namespace may not be ready yet."
        Write-Warning "Error: $_"
    }
} else {
    Write-Host "H: drive already mapped."
}

Write-Host ""
Write-Host "============================================"
Write-Host " DONE - W1"
Write-Host "============================================"
Write-Host "Manual verification steps:"
Write-Host "  1. Right-click desktop -> Personalize: wallpaper should be locked"
Write-Host "  2. Open mstsc and connect to w02 — should succeed"
Write-Host "  3. Check H: drive maps to \\grok.local\profiles\$currentUser\Documents"
Write-Host "  4. Log off and back on — profile should load from DFS"
