$ErrorActionPreference = 'Stop'

$cert = New-SelfSignedCertificate `
    -Type Custom `
    -Subject 'CN=Stocksi' `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(10) `
    -FriendlyName 'Stocksi Ultimate' `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3','2.5.29.19={text}')

$pwd = ConvertTo-SecureString -String 'stocksi2026' -Force -AsPlainText
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pfxPath = Join-Path $dir 'stocksi.pfx'
$cerPath = Join-Path $dir 'stocksi.cer'

Export-PfxCertificate -cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" -FilePath $pfxPath -Password $pwd | Out-Null
Export-Certificate    -cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" -FilePath $cerPath | Out-Null

# Убираем временный сертификат из хранилища пользователя — мы его сохранили в файлах
Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force

Write-Host "Cert created:"
Write-Host "  PFX: $pfxPath"
Write-Host "  CER: $cerPath"
Write-Host "  Thumbprint: $($cert.Thumbprint)"
