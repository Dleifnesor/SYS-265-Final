# dfs01-setup.ps1
# Run this on dfs01 as administrator.
# Sets up the DFS role, creates the Profiles share, and sets permissions.
# Run this on dfs01 FIRST, then run dfs02-setup.ps1 on dfs02.
# dc01-setup.ps1 must be run AFTER both dfs01 and dfs02 are done.

$ProfilesPath = "C:\Shares\Profiles"

Write-Host "============================================"
Write-Host " STEP 1: Install DFS roles"
Write-Host "============================================"

Install-WindowsFeature `
    -Name FS-DFS-Namespace, FS-DFS-Replication, RSAT-DFS-Mgmt-Con `
    -IncludeManagementTools

Write-Host "DFS roles installed."

Write-Host ""
Write-Host "============================================"
Write-Host " STEP 2: Create Profiles directory"
Write-Host "============================================"

if (-not (Test-Path $ProfilesPath)) {
    New-Item -Path $ProfilesPath -ItemType Directory -Force | Out-Null
    Write-Host "Created $ProfilesPath"
} else {
    Write-Host "$ProfilesPath already exists."
}

Write-Host ""
Write-Host "============================================"
Write-Host " STEP 3: Create SMB share"
Write-Host "============================================"

if (-not (Get-SmbShare -Name "Profiles" -ErrorAction SilentlyContinue)) {
    New-SmbShare `
        -Name "Profiles" `
        -Path $ProfilesPath `
        -FullAccess "grok\Domain Admins" `
        -ChangeAccess "grok\Domain Users"
    Write-Host "Share created: \\$(hostname)\Profiles"
} else {
    Write-Host "Share Profiles already exists."
}

Write-Host ""
Write-Host "============================================"
Write-Host " STEP 4: Set NTFS permissions"
Write-Host "============================================"

# Disable inheritance and set explicit permissions
icacls $ProfilesPath /inheritance:r
icacls $ProfilesPath /grant "BUILTIN\Administrators:(OI)(CI)F"
icacls $ProfilesPath /grant "grok\Domain Admins:(OI)(CI)F"
icacls $ProfilesPath /grant "grok\Domain Users:(OI)(CI)M"
icacls $ProfilesPath /grant "CREATOR OWNER:(OI)(CI)F"

Write-Host "NTFS permissions set."

Write-Host ""
Write-Host "============================================"
Write-Host " DONE - dfs01"
Write-Host "============================================"
Write-Host "Share is available at: \\dfs01\Profiles"
Write-Host "Now run dfs02-setup.ps1 on dfs02, then dc01-setup.ps1 on dc01."
