<powershell>

# Optional: enable logging to track script behavior
Start-Transcript -Path "C:\Windows\Temp\userdata.log" -Append

Write-Output "Starting user creation for: ${windows_username}"

# Disable password complexity temporarily (optional)
Write-Output "Disabling password complexity requirements..."
secedit /export /cfg C:\secpol.cfg
(Get-Content C:\secpol.cfg).Replace("PasswordComplexity = 1", "PasswordComplexity = 0") | Set-Content C:\secpol.cfg
secedit /configure /db C:\Windows\security\local.sdb /cfg C:\secpol.cfg /areas SECURITYPOLICY
Remove-Item C:\secpol.cfg -Force

# Define variables
$newUser = "${windows_username}"
$passwordPlain = "${windows_password}"

# Convert to secure string
$securePass = ConvertTo-SecureString -String $passwordPlain -AsPlainText -Force

# Create or reset local user
if (-not (Get-LocalUser -Name $newUser -ErrorAction SilentlyContinue)) {
    Write-Output "Creating new local user: $newUser"
    New-LocalUser -Name $newUser -Password $securePass -PasswordNeverExpires:$true -AccountNeverExpires:$true
} else {
    Write-Output "User $newUser already exists. Updating password..."
    Set-LocalUser -Name $newUser -Password $securePass
}

# Add user to the 'Users' group
Write-Output "Adding $newUser to local groups"
Add-LocalGroupMember -Group "Users" -Member $newUser -ErrorAction SilentlyContinue

# Grant RDP access (optional)
Write-Output "Granting RDP access to $newUser"
net localgroup "Remote Desktop Users" $newUser /add

# Create app folder and set ACLs
$folderPath = "C:\app"
if (-not (Test-Path $folderPath)) {
    Write-Output "Creating folder: $folderPath"
    New-Item -Path $folderPath -ItemType Directory | Out-Null
}

Write-Output "Setting ACLs for $folderPath"
icacls $folderPath /grant "${newUser}:(OI)(CI)F" /T
icacls $folderPath /grant "Users:(OI)(CI)F" /T
icacls $folderPath /grant "Everyone:(OI)(CI)RX" /T

Write-Output "User $newUser setup and ACL configuration complete."

# Re-enable password complexity
Write-Output "Re-enabling password complexity requirements..."
secedit /export /cfg C:\secpol.cfg
(Get-Content C:\secpol.cfg).Replace("PasswordComplexity = 0", "PasswordComplexity = 1") | Set-Content C:\secpol.cfg
secedit /configure /db C:\Windows\security\local.sdb /cfg C:\secpol.cfg /areas SECURITYPOLICY
Remove-Item C:\secpol.cfg -Force

Stop-Transcript
</powershell>
