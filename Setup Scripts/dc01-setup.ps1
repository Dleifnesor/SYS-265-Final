# dc01-setup.ps1
# Run this on dc01 as domain administrator.
# Prerequisites: dfs01-setup.ps1 and dfs02-setup.ps1 must be completed first.
#
# This script does everything on dc01:
#   1. Creates DFS namespace pointing at dfs01 + dfs02
#   2. Creates Workstations and Management OUs, moves computers in
#   3. GPO: RDP between W1 and W2
#   4. GPO: Corporate wallpaper for W1, W2, MGMT1
#   5. GPO: DFS roaming profiles for W1 and W2

Import-Module ActiveDirectory
Import-Module GroupPolicy
Import-Module DFSN -ErrorAction SilentlyContinue

$Domain          = "grok.local"
$DC              = "DC=grok,DC=local"
$ProfilesShare   = "\\grok.local\profiles"
$WorkstationsOU  = "OU=Workstations,$DC"
$ManagementOU    = "OU=Management,$DC"

# ── Place wallpaper in NETLOGON before creating wallpaper GPO ─────────────────
# Copies the default Windows wallpaper as a placeholder.
# Replace C:\Windows\SYSVOL\sysvol\grok.local\scripts\wallpaper.jpg
# with your actual corporate wallpaper image after this script runs.
$NetlogonScripts = "C:\Windows\SYSVOL\sysvol\$Domain\scripts"
$WallpaperDest   = "$NetlogonScripts\wallpaper.jpg"
$WallpaperUNC    = "\\dc01\NETLOGON\wallpaper.jpg"

if (-not (Test-Path $WallpaperDest)) {
    $DefaultWallpaper = "C:\Windows\Web\Wallpaper\Windows\img0.jpg"
    if (Test-Path $DefaultWallpaper) {
        Copy-Item $DefaultWallpaper $WallpaperDest
        Write-Host "Copied placeholder wallpaper to NETLOGON."
        Write-Host "*** Replace $WallpaperDest with your actual corporate wallpaper ***"
    } else {
        Write-Warning "No default wallpaper found. Place wallpaper.jpg in $NetlogonScripts manually before testing."
    }
}


Write-Host ""
Write-Host "============================================"
Write-Host " STEP 1: Create DFS namespace"
Write-Host "============================================"

# Verify both share targets are reachable before creating namespace
foreach ($target in @("\\dfs01\Profiles", "\\dfs02\Profiles")) {
    if (Test-Path $target) {
        Write-Host "$target - reachable"
    } else {
        Write-Warning "$target is NOT reachable. Ensure dfs01/dfs02 setup scripts have been run."
    }
}

# Create domain-based DFS namespace
$existingNS = Get-DfsnRoot -Path $ProfilesShare -ErrorAction SilentlyContinue
if (-not $existingNS) {
    New-DfsnRoot `
        -Path $ProfilesShare `
        -TargetPath "\\dfs01\Profiles" `
        -Type DomainV2 `
        -Description "Domain user roaming profiles"
    Write-Host "DFS namespace created: $ProfilesShare"
} else {
    Write-Host "DFS namespace already exists: $ProfilesShare"
}

# Add dfs02 as redundant target
$existingTarget = Get-DfsnRootTarget -Path $ProfilesShare -TargetPath "\\dfs02\Profiles" -ErrorAction SilentlyContinue
if (-not $existingTarget) {
    New-DfsnRootTarget -Path $ProfilesShare -TargetPath "\\dfs02\Profiles"
    Write-Host "Added dfs02 as redundant DFS target."
} else {
    Write-Host "dfs02 target already exists."
}


Write-Host ""
Write-Host "============================================"
Write-Host " STEP 2: Create OUs and move computers"
Write-Host "============================================"

# Create Workstations OU
if (-not (Get-ADOrganizationalUnit -Filter { DistinguishedName -eq $WorkstationsOU } -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name "Workstations" -Path $DC
    Write-Host "Created OU: Workstations"
} else {
    Write-Host "OU Workstations already exists."
}

# Create Management OU
if (-not (Get-ADOrganizationalUnit -Filter { DistinguishedName -eq $ManagementOU } -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name "Management" -Path $DC
    Write-Host "Created OU: Management"
} else {
    Write-Host "OU Management already exists."
}

# Move W1 and W2 to Workstations OU
foreach ($ws in @("w01", "w02")) {
    $computer = Get-ADComputer -Filter { Name -eq $ws } -ErrorAction SilentlyContinue
    if ($computer) {
        if ($computer.DistinguishedName -notlike "*$WorkstationsOU*") {
            Move-ADObject -Identity $computer.DistinguishedName -TargetPath $WorkstationsOU
            Write-Host "Moved $ws to Workstations OU"
        } else {
            Write-Host "$ws already in Workstations OU"
        }
    } else {
        Write-Warning "$ws not found in AD - ensure it is domain joined"
    }
}

# Move MGMT1 to Management OU
$mgmt1 = Get-ADComputer -Filter { Name -eq "mgmt01" } -ErrorAction SilentlyContinue
if ($mgmt1 -and ($mgmt1.DistinguishedName -notlike "*$ManagementOU*")) {
    Move-ADObject -Identity $mgmt1.DistinguishedName -TargetPath $ManagementOU
    Write-Host "Moved mgmt01 to Management OU"
} elseif ($mgmt1) {
    Write-Host "mgmt01 already in Management OU"
} else {
    Write-Warning "mgmt01 not found in AD"
}


Write-Host ""
Write-Host "============================================"
Write-Host " STEP 3: GPO - RDP between W1 and W2"
Write-Host "============================================"

$RDPGPOName = "Workstations-RDP-Policy"

if (-not (Get-GPO -Name $RDPGPOName -ErrorAction SilentlyContinue)) {
    New-GPO -Name $RDPGPOName -Domain $Domain | Out-Null
    Write-Host "Created GPO: $RDPGPOName"
}

# Enable Remote Desktop
Set-GPRegistryValue -Name $RDPGPOName `
    -Key "HKLM\System\CurrentControlSet\Control\Terminal Server" `
    -ValueName "fDenyTSConnections" -Type DWord -Value 0

# Require Network Level Authentication
Set-GPRegistryValue -Name $RDPGPOName `
    -Key "HKLM\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
    -ValueName "UserAuthentication" -Type DWord -Value 1

# Add Domain Users to Remote Desktop Users via Restricted Groups
$GpoId   = (Get-GPO -Name $RDPGPOName).Id.ToString()
$GpoPath = "\\$Domain\SYSVOL\$Domain\Policies\{$GpoId}\Machine\Microsoft\Windows NT\SecEdit"
if (-not (Test-Path $GpoPath)) {
    New-Item -Path $GpoPath -ItemType Directory -Force | Out-Null
}

$DomainUsersSID = (Get-ADGroup "Domain Users").SID.Value
$InfContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Group Membership]
*S-1-5-32-555__Memberof =
*S-1-5-32-555__Members = *$DomainUsersSID
"@
Set-Content -Path "$GpoPath\GptTmpl.inf" -Value $InfContent -Encoding Unicode

# Link to Workstations OU
$existingLink = Get-GPInheritance -Target $WorkstationsOU |
    Select-Object -ExpandProperty GpoLinks |
    Where-Object { $_.DisplayName -eq $RDPGPOName }
if (-not $existingLink) {
    New-GPLink -Name $RDPGPOName -Target $WorkstationsOU -LinkEnabled Yes
    Write-Host "Linked $RDPGPOName to Workstations OU"
}

Write-Host "RDP GPO done."


Write-Host ""
Write-Host "============================================"
Write-Host " STEP 4: GPO - Corporate wallpaper"
Write-Host "============================================"

$WallGPOName = "Corporate-Wallpaper-Policy"

if (-not (Get-GPO -Name $WallGPOName -ErrorAction SilentlyContinue)) {
    New-GPO -Name $WallGPOName -Domain $Domain | Out-Null
    Write-Host "Created GPO: $WallGPOName"
}

Set-GPRegistryValue -Name $WallGPOName `
    -Key "HKCU\Control Panel\Desktop" `
    -ValueName "Wallpaper" -Type ExpandString -Value $WallpaperUNC

Set-GPRegistryValue -Name $WallGPOName `
    -Key "HKCU\Control Panel\Desktop" `
    -ValueName "WallpaperStyle" -Type String -Value "10"

Set-GPRegistryValue -Name $WallGPOName `
    -Key "HKCU\Control Panel\Desktop" `
    -ValueName "TileWallpaper" -Type String -Value "0"

Set-GPRegistryValue -Name $WallGPOName `
    -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop" `
    -ValueName "NoChangingWallPaper" -Type DWord -Value 1

# Link to Workstations OU (W1 + W2)
foreach ($targetOU in @($WorkstationsOU, $ManagementOU)) {
    $existingLink = Get-GPInheritance -Target $targetOU |
        Select-Object -ExpandProperty GpoLinks |
        Where-Object { $_.DisplayName -eq $WallGPOName }
    if (-not $existingLink) {
        New-GPLink -Name $WallGPOName -Target $targetOU -LinkEnabled Yes
        Write-Host "Linked $WallGPOName to $targetOU"
    }
}

Write-Host "Wallpaper GPO done."


Write-Host ""
Write-Host "============================================"
Write-Host " STEP 5: GPO - DFS roaming profiles"
Write-Host "============================================"

$ProfileGPOName = "Workstations-DFS-Profiles"

if (-not (Get-GPO -Name $ProfileGPOName -ErrorAction SilentlyContinue)) {
    New-GPO -Name $ProfileGPOName -Domain $Domain | Out-Null
    Write-Host "Created GPO: $ProfileGPOName"
}

# Roaming profile path
Set-GPRegistryValue -Name $ProfileGPOName `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\winlogon" `
    -ValueName "RoamingUserProfilePath" -Type ExpandString `
    -Value "$ProfilesShare\%USERNAME%"

# Delete cached copy on logoff
Set-GPRegistryValue -Name $ProfileGPOName `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
    -ValueName "DeleteRoamingCachedProfiles" -Type DWord -Value 1

# Documents folder redirect
Set-GPRegistryValue -Name $ProfileGPOName `
    -Key "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
    -ValueName "Personal" -Type ExpandString `
    -Value "$ProfilesShare\%USERNAME%\Documents"

# Desktop folder redirect
Set-GPRegistryValue -Name $ProfileGPOName `
    -Key "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
    -ValueName "Desktop" -Type ExpandString `
    -Value "$ProfilesShare\%USERNAME%\Desktop"

# Write fdeploy.ini for folder redirection client-side extension
$GpoId   = (Get-GPO -Name $ProfileGPOName).Id.ToString()
$FRPath  = "\\$Domain\SYSVOL\$Domain\Policies\{$GpoId}\User\Documents & Settings"
if (-not (Test-Path $FRPath)) {
    New-Item -Path $FRPath -ItemType Directory -Force | Out-Null
}

$FdeployContent = @"
[Documents]
1=GROK\Domain Users, $ProfilesShare\%USERNAME%\Documents, 0, 1, 1, 0
[Desktop]
1=GROK\Domain Users, $ProfilesShare\%USERNAME%\Desktop, 0, 1, 1, 0
"@
Set-Content -Path "$FRPath\fdeploy.ini" -Value $FdeployContent

# Set profile path on all existing domain user objects
Write-Host "Updating AD user profile paths..."
Get-ADUser -Filter * -SearchBase "CN=Users,DC=grok,DC=local" | ForEach-Object {
    Set-ADUser $_ `
        -ProfilePath "$ProfilesShare\$($_.SamAccountName)" `
        -HomeDrive "H:" `
        -HomeDirectory "$ProfilesShare\$($_.SamAccountName)\Documents"
    Write-Host "  Updated: $($_.SamAccountName)"
}

# Link to Workstations OU
$existingLink = Get-GPInheritance -Target $WorkstationsOU |
    Select-Object -ExpandProperty GpoLinks |
    Where-Object { $_.DisplayName -eq $ProfileGPOName }
if (-not $existingLink) {
    New-GPLink -Name $ProfileGPOName -Target $WorkstationsOU -LinkEnabled Yes
    Write-Host "Linked $ProfileGPOName to Workstations OU"
}

Write-Host "DFS Profiles GPO done."


Write-Host ""
Write-Host "============================================"
Write-Host " DONE - dc01"
Write-Host "============================================"
Write-Host ""
Write-Host "Summary:"
Write-Host "  DFS namespace : $ProfilesShare"
Write-Host "  GPOs created  : $RDPGPOName"
Write-Host "                  $WallGPOName"
Write-Host "                  $ProfileGPOName"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. (Optional) Replace wallpaper.jpg in NETLOGON with your actual image"
Write-Host "  2. Run mgmt02-setup.sh on mgmt02"
Write-Host "  3. Run w01-setup.ps1 on W1 and w02-setup.ps1 on W2"
Write-Host "  4. Run mgmt01-setup.ps1 on MGMT1"
