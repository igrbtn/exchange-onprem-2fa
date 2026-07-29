<#
.SYNOPSIS
    Configure adfsmfa for TOTP-only self-enrollment.
.DESCRIPTION
    Registers the MFA system (first run), then leaves ONLY the TOTP (Code) provider enabled and
    sets up forced self-registration without the email/biometric steps.
.NOTES
    RUN THIS IN A LOCAL SESSION ON THE AD FS SERVER (RDP or a scheduled task as local/domain
    admin). The *-MFA* cmdlets are NOT remotable (PS0033) - WinRM/PowerShell remoting refuses them.
    -Confirm:$false is required or Set-MFAConfig hangs on a prompt in a non-interactive session.
    In adfsmfa's enum, the TOTP provider is called "Code".
#>
$ErrorActionPreference = 'Continue'

# First-time only (idempotent to re-run):
if (-not (Get-AdfsGlobalAuthenticationPolicy).AdditionalAuthenticationProvider -contains 'MultiFactorAuthenticationProvider') {
    Register-MFASystem
    Enable-MFASystem
}

# Enable ONLY TOTP (Code); disable the other methods so enrollment goes straight to the QR.
Set-MFAProvider -ProviderType Code -Enabled:$true -ForceWizard Enabled -Confirm:$false
foreach ($t in 'Email','Azure','Biometrics') {
    try { Set-MFAProvider -ProviderType $t -Enabled:$false -Confirm:$false } catch { Write-Warning "$t : $($_.Exception.Message)" }
}

# Default method = TOTP; allow self-registration; skip the "provide email/phone" step.
Set-MFAConfig -DefaultProviderMethod Code -Confirm:$false
Set-MFAConfig -UserFeatures 'AllowUnRegistered, AllowChangePassword, AllowManageOptions, AllowEnrollment' -Confirm:$false
Update-MFAConfigurationCache

Write-Host ("UserFeatures : {0}" -f (Get-MFAConfig).UserFeatures)
Write-Host ("Code enabled : {0}" -f (Get-MFAProvider -ProviderType Code).Enabled)
Write-Host "Done. Restart AD FS: Restart-Service adfssrv -Force"
