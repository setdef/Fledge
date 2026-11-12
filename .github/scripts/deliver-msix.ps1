# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of a windowed app's MSIX package (Fledge::Msix) on Windows:
# the packages fledge build wrote for examples/windowed_app, unsigned as
# the Microsoft Store takes one and signed with a test certificate as a
# developer sideloads one, installed, run, and removed as a person
# would, with nothing of Fledge or Ruby on this computer.
#
#   pwsh -NoProfile -File deliver-msix.ps1 -Package "Hello Window-x64-mingw-ucrt.msix"
#     -Signed "signed/Hello Window-x64-mingw-ucrt.msix" -Certificate certificate.cer
#     [-Store Cert:\CurrentUser\TrustedPeople] [-Trusted]
#
# The unsigned package must hold the app's identity in its manifest, its
# logos, its program, and a fledge.cfg with no identifier, and Windows
# must refuse to install it. The signed one must be refused too until
# the certificate is trusted, in the store -Store names
# (Cert:\LocalMachine\TrustedPeople by default, as Microsoft's "Create a
# certificate for package signing" trusts one; -Trusted skips the
# refusal, when an earlier step trusted the certificate already). Then
# Add-AppxPackage must install it with the app's identity, list it in
# the Start menu's apps by its name, and register its file type in the
# extension's "Open with" without taking its default. Started through
# its AppUserModelID, as the Start menu starts it, given a folder, the
# app must write its report there, which says it ran with the package's
# identity, with no console, and with no AppUserModelID of its own in
# place of the package's. Removed, it must leave nothing registered.

param(
  [Parameter(Mandatory)] [string] $Package,
  [Parameter(Mandatory)] [string] $Signed,
  [Parameter(Mandatory)] [string] $Certificate,
  [string] $Store = 'Cert:\LocalMachine\TrustedPeople',
  [string] $Identifier = 'com.setdef.fledge.HelloWindow',
  [string] $Publisher = 'CN=Fledge Test Signing',
  [string] $Work = $env:RUNNER_TEMP,
  [switch] $Trusted
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Windows' Appx module is Windows PowerShell's; PowerShell 7 reaches it
# through a Windows PowerShell session of its own.
if ($PSVersionTable.PSEdition -eq 'Core') { Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue }

$appName = 'Hello Window'
# Hello Window-PLATFORM.msix: x64-mingw-ucrt, or aarch64-mingw-ucrt (ADR 035).
$platform = [IO.Path]::GetFileNameWithoutExtension($Package) -replace "^$appName-", ''
$architecture = if ($platform -eq 'aarch64-mingw-ucrt') { 'arm64' } else { 'x64' }

function Fail([string] $message) {
  Write-Host "::error::Delivery (msix): $message"
  exit 1
}

function Expect([string] $Label, $Actual, $Expected) {
  if ("$Actual" -cne "$Expected") { Fail "$Label is '$Actual', not '$Expected'" }
  Write-Host "ok: $Label is $Expected"
}

function WaitFor([scriptblock] $Condition, [string] $What, [int] $Seconds = 60) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  while (-not (& $Condition)) {
    if ((Get-Date) -gt $deadline) { Fail "$What did not happen within $Seconds seconds" }
    Start-Sleep -Milliseconds 500
  }
}

# The text of the entry NAME of the package at PATH, a zip, or $null.
function EntryText([string] $Path, [string] $Name) {
  $zip = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entry = $zip.GetEntry($Name)
    if (-not $entry) { return $null }
    $reader = [IO.StreamReader]::new($entry.Open())
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
  } finally { $zip.Dispose() }
}

function Entries([string] $Path) {
  $zip = [IO.Compression.ZipFile]::OpenRead($Path)
  try { return @($zip.Entries | ForEach-Object { $_.FullName }) } finally { $zip.Dispose() }
}

# Whether Add-AppxPackage installs the package at PATH; it should not.
function Refused([string] $Path) {
  try {
    Add-AppxPackage -Path $Path
    return $null
  } catch {
    return $_.Exception.Message
  }
}

# Starts the packaged app whose AppUserModelID is ID with ARGUMENTS, as
# the Start menu does, through the shell's IApplicationActivationManager
# (shobjidl_core.h), and returns its process ID.
Add-Type -Namespace Fledge -Name Activation -MemberDefinition @'
[ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IApplicationActivationManager {
  void ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string id, [MarshalAs(UnmanagedType.LPWStr)] string arguments, int options, out uint process);
  void ActivateForFile(System.IntPtr id, System.IntPtr items, System.IntPtr verb, out uint process);
  void ActivateForProtocol(System.IntPtr id, System.IntPtr items, out uint process);
}

public static uint Start(string id, string arguments) {
  System.Type type = System.Type.GetTypeFromCLSID(new System.Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C"));
  IApplicationActivationManager manager = (IApplicationActivationManager)System.Activator.CreateInstance(type);
  uint process;
  manager.ActivateApplication(id, arguments, 0, out process);
  return process;
}
'@

if (-not $Work) { Fail 'give -Work, a folder outside AppData, where Windows does not redirect what a package writes' }
$Package = (Resolve-Path -LiteralPath $Package).Path
$Signed = (Resolve-Path -LiteralPath $Signed).Path

# The runner has Rubies; the package and the app see only Windows'.
$system = $env:SystemRoot
$env:PATH = "$system\System32;$system;$system\System32\Wbem;$system\System32\WindowsPowerShell\v1.0"
if (Get-Command ruby -ErrorAction SilentlyContinue) { Fail "Get-Command still finds a Ruby on $env:PATH" }

if (Get-AppxPackage -Name $Identifier) { Fail "$Identifier is installed before the install" }

# What the unsigned package holds, as the Store takes it.
$entries = Entries $Package
foreach ($entry in 'AppxManifest.xml', 'AppxBlockMap.xml', 'Assets/StoreLogo.png', 'Assets/Square44x44Logo.png', 'Assets/Square150x150Logo.png', 'fledge.cfg', 'app/main.rb') {
  if ($entries -notcontains $entry) { Fail "the package has no $entry" }
}
if (-not ($entries | Where-Object { $_ -match '^Hello(%20| )Window\.exe$' })) { Fail 'the package has no Hello Window.exe' }
if ($entries -contains 'AppxSignature.p7x') { Fail 'the unsigned package has a signature' }
Write-Host 'ok: the unsigned package holds the manifest, the logos, the program, and the app, and no signature'
[xml] $manifest = EntryText $Package 'AppxManifest.xml'
$identity = $manifest.Package.Identity
Expect 'the identity' "$($identity.Name) $($identity.Publisher) $($identity.Version) $($identity.ProcessorArchitecture)" "$Identifier $Publisher 1.2.3.0 $architecture"
Expect 'the display name' $manifest.Package.Properties.DisplayName $appName
Expect 'the publisher display name' $manifest.Package.Properties.PublisherDisplayName 'setdef'
if ((EntryText $Package 'fledge.cfg') -match '(?m)^identifier') { Fail "the package's fledge.cfg names an identifier" }
Write-Host "ok: the package's fledge.cfg leaves the process the package's AppUserModelID"
$refusal = Refused $Package
if (-not $refusal) { Fail 'Windows installed the unsigned package' }
Write-Host "ok: Windows refuses the unsigned package: $($refusal.Trim())"

# The signed package: refused until its certificate is trusted.
if ((Entries $Signed) -notcontains 'AppxSignature.p7x') { Fail 'the signed package has no signature' }
if (-not $Trusted) {
  $refusal = Refused $Signed
  if (-not $refusal) { Fail 'Windows installed the signed package before it trusted the test certificate' }
  Write-Host "ok: before the certificate is trusted, Windows refuses the signed package: $($refusal.Trim())"
}
$certificate = Import-Certificate -FilePath $Certificate -CertStoreLocation $Store
Write-Host "Trusted $($certificate.Subject) in $Store"

try {
  Add-AppxPackage -Path $Signed
  $installed = Get-AppxPackage -Name $Identifier
  if (-not $installed) { Fail "Get-AppxPackage finds no $Identifier after the install" }
  Expect 'the installed publisher' $installed.Publisher $Publisher
  Expect 'the installed version' $installed.Version '1.2.3.0'
  Expect 'the installed architecture' "$($installed.Architecture)".ToLowerInvariant() $architecture
  Expect 'the signature kind' "$($installed.SignatureKind)" 'Developer'
  $aumid = "$($installed.PackageFamilyName)!App"

  # The Start menu's apps, which the shell's AppsFolder lists.
  $listed = (New-Object -ComObject Shell.Application).NameSpace('shell:AppsFolder').Items() | Where-Object { $_.Path -eq $aumid }
  if (-not $listed) { Fail "the Start menu's apps do not list $aumid" }
  Expect "the Start menu's name for it" $listed.Name $appName

  # Its file type, in the extension's "Open with", not its default.
  $classes = 'HKCU:\Software\Classes'
  WaitFor { Test-Path -LiteralPath "$classes\.hellowindow\OpenWithProgids" } '.hellowindow being registered' 30
  $progIds = @((Get-Item -LiteralPath "$classes\.hellowindow\OpenWithProgids").GetValueNames() | Where-Object { $_ -like 'AppX*' })
  Expect ".hellowindow's package ProgIDs, how many" $progIds.Count 1
  Expect 'the default of .hellowindow' (Get-Item -LiteralPath "$classes\.hellowindow").GetValue('') $null

  # Started as the Start menu starts it, given a folder outside the
  # folders Windows redirects a package's writes from.
  $folder = Join-Path ([IO.Path]::GetFullPath($Work)) 'msix report ü'
  New-Item -ItemType Directory -Force $folder | Out-Null
  $report = Join-Path $folder 'hello_window.json'
  Remove-Item -LiteralPath $report -ErrorAction SilentlyContinue
  $process = [Fledge.Activation]::Start($aumid, "`"$folder`"")
  Write-Host "Started $aumid as process $process"
  WaitFor { Test-Path -LiteralPath $report } 'the app writing its report after starting from its package'
  Start-Sleep -Seconds 3
  $facts = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
  Expect "the report's Ruby" $facts.ruby '4.1.0'
  Expect "the report's platform" $facts.platform $platform
  Expect 'whether it had a console' $facts.console $false
  Expect 'the package it ran in' $facts.package $installed.PackageFullName
  $explicit = $facts.PSObject.Properties['app_user_model_id']
  if ($explicit -and $explicit.Value -eq $Identifier) { Fail 'the app gave itself its identifier as its AppUserModelID, in place of the package''s' }
  Write-Host "ok: the app left the process the package's AppUserModelID"

  Remove-AppxPackage -Package $installed.PackageFullName
  if (Get-AppxPackage -Name $Identifier) { Fail "$Identifier is still installed" }
  Write-Host "ok: $Identifier is removed"
  WaitFor { -not ((Test-Path -LiteralPath "$classes\.hellowindow\OpenWithProgids") -and
      @((Get-Item -LiteralPath "$classes\.hellowindow\OpenWithProgids").GetValueNames() | Where-Object { $_ -like 'AppX*' }).Count) } '.hellowindow being unregistered' 30
  Write-Host 'ok: the file type is unregistered'
} finally {
  $left = Get-AppxPackage -Name $Identifier
  if ($left) { Remove-AppxPackage -Package $left.PackageFullName -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath (Join-Path $Store $certificate.Thumbprint) -ErrorAction SilentlyContinue
}

Write-Host "Delivered: $appName's MSIX package, installed, run, and removed"
