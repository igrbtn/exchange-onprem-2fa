<#
.SYNOPSIS
    Schannel/TLS hardening on the WAP box: disable legacy protocols and weak ciphers, force
    TLS 1.2 (TLS 1.3 stays at the WS2022 default), and set .NET strong crypto.
.NOTES
    Run on the WAP server as local admin. REQUIRES A REBOOT to take effect. All modern clients
    and backends support TLS 1.2, so nothing breaks.
#>
$ErrorActionPreference = 'Stop'

function Set-Proto($proto, $enabled, $disabledByDefault) {
    foreach ($role in 'Client','Server') {
        $p = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$proto\$role"
        New-Item -Path $p -Force | Out-Null
        New-ItemProperty -Path $p -Name Enabled           -Value $enabled           -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $p -Name DisabledByDefault -Value $disabledByDefault  -PropertyType DWord -Force | Out-Null
    }
}
function Disable-Cipher($name) {
    # Cipher key names contain '/', so use the .NET API (backslash is the only separator).
    $k = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey("SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\$name")
    $k.SetValue("Enabled", 0, [Microsoft.Win32.RegistryValueKind]::DWord); $k.Close()
}

# Protocols: disable legacy, enable TLS 1.2.
Set-Proto 'SSL 2.0' 0 1
Set-Proto 'SSL 3.0' 0 1
Set-Proto 'TLS 1.0' 0 1
Set-Proto 'TLS 1.1' 0 1
Set-Proto 'TLS 1.2' 1 0

# Weak ciphers off.
foreach ($c in 'RC4 40/128','RC4 56/128','RC4 64/128','RC4 128/128','DES 56/56','Triple DES 168','NULL') { Disable-Cipher $c }

# .NET 4: force strong crypto / system default TLS so the WAP service uses TLS 1.2 to AD FS.
foreach ($p in 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319','HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319') {
    New-Item -Path $p -Force | Out-Null
    New-ItemProperty -Path $p -Name SchUseStrongCrypto       -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $p -Name SystemDefaultTlsVersions -Value 1 -PropertyType DWord -Force | Out-Null
}

Write-Host "Schannel hardening applied. REBOOT required for it to take effect."
