### Constants
$RepoPath = $PSScriptRoot
New-Item -Path "$RepoPath" -Name "downloads" -ItemType "directory" -Force | Out-Null
New-Item -Path "$RepoPath" -Name "logs" -ItemType "directory" -Force | Out-Null
$DownloadsPath = "${RepoPath}\downloads"
$LogsPath = "${RepoPath}\logs"

### Functions
function Show-Output() {
  Write-Host "[provisioner] $args" -BackgroundColor White -ForegroundColor Black
}

function Test-CommandExists {
  [OutputType([bool])]
  Param(
    [Parameter(Mandatory = $true)][string]$command
  )
  $oldPreference = $ErrorActionPreference
  $ErrorActionPreference = "stop"
  try {
    if (Get-Command $command) { RETURN $true }
  }
  catch { return $false }
  finally { $ErrorActionPreference = $oldPreference }
}

function Test-Admin {
  <#
    .SYNOPSIS
        Test whether the script is being run as an administrator
    .LINK
        https://superuser.com/questions/108207/how-to-run-a-powershell-script-as-administrator
    #>
  [OutputType([bool])]
  $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
  return $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Elevate {
  <#
  .SYNOPSIS
      Elevate the current process to admin privileges.

      Instead of doing `#Requires -RunAsAdministrator` you can use this,
      so that just doing ".\scriptname.ps1" works too.
  .NOTES
      The script that uses this function should have the following code at the top:
      ```
      Param(
          [switch]$Elevated
      )
      ```
      and also the following in it's header comment section:
      ```
      .PARAMETER Elevated
          This parameter is for internal use to check whether an UAC prompt has already been attempted.
      ```

  .EXAMPLE
      Elevate($MyInvocation.MyCommand.Definition)
  .LINK
      https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-7.2#example-5--start-powershell-as-an-administrator
  #>
  Param(
    [Parameter(Mandatory = $true)][string]$command
  )
  if (! (Test-Admin)) {
    if ($elevated) {
      Show-Output "Elevation did not work."
    }
    else {
      Show-Output "This script requires admin access. Elevating."
      Show-Output "$command"
      # Use newer PowerShell if available.
      if (Test-CommandExists "pwsh") { $shell = "pwsh" } else { $shell = "powershell" }
      Start-Process -FilePath "$shell" -Verb RunAs -ArgumentList ('-NoProfile -NoExit -Command "cd {0}; {1}" -elevated' -f ($pwd, $command))
      Show-Output "The script has been started in another window. You can close this window now."
    }
    exit
  }
  Show-Output "Running as Administrator!"
}

function Test-RebootPending {
  <#
    .SYNOPSIS
        Test whether the computer has a reboot pending.
    .LINK
        https://4sysops.com/archives/use-powershell-to-test-if-a-windows-server-is-pending-a-reboot/
    #>
  [OutputType([bool])]
  $pendingRebootTests = @(
    @{
      Name     = "RebootPending"
      Test     = { Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing" -Name "RebootPending" -ErrorAction Ignore }
      TestType = "ValueExists"
    }
    @{
      Name     = "RebootRequired"
      Test     = { Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name "RebootRequired" -ErrorAction Ignore }
      TestType = "ValueExists"
    }
    @{
      Name     = "PendingFileRenameOperations"
      Test     = { Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction Ignore }
      TestType = "NonNullValue"
    }
  )
  foreach ($test in $pendingRebootTests) {
    $result = Invoke-Command -ScriptBlock $test.Test
    if ($test.TestType -eq "ValueExists" -and $result) {
      return $true
    }
    elseif ($test.TestType -eq "NonNullValue" -and $result -and $result.($test.Name)) {
      return $true
    }
    else {
      return $false
    }
  }
}

function Update-PathEnvironmentVariable() {
  <#
  .LINK
      https://stackoverflow.com/a/31845512/13953427
  #>
  # https://stackoverflow.com/questions/17794507/reload-the-path-in-powershell#comment70758762_31845512
  if (Test-CommandExists "refreshenv"){
    Show-Output "Refreshing PATH Environment Variable using 'refreshenv' function from chocolatey.."
    refreshenv
  } else {
    Show-Output "Refreshing PATH Environment Variable.."
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
  }
}

function Install-Winget {
  [OutputType([bool])]
  Param()

  if (Test-CommandExists "winget") {
    Show-Output "Microsoft App Install command ('winget') exists, skipping installation."
    return $true
  }

  if (Get-AppxPackage -Name "Microsoft.DesktopAppInstaller") {
    Show-Output "App Installer seems to be installed on your system, but Winget was not found."
    return $false
  }

  if (Get-AppxPackage -Name "Microsoft.WindowsStore") {
    # https://stackoverflow.com/a/75334942/13953427
    Show-Output "Downloading and installing latest release of winget from GitHub..."
    $URL = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
    $URL = (Invoke-WebRequest -Uri $URL).Content | ConvertFrom-Json |
    Select-Object -ExpandProperty "assets" |
    Where-Object "browser_download_url" -Match '.msixbundle' |
    Select-Object -ExpandProperty "browser_download_url"

    # Download $URL
    Invoke-WebRequest -Uri $URL -OutFile "Setup.msix" -UseBasicParsing
    # Install
    Add-AppxPackage -Path "Setup.msix"
    # Cleanup
    Remove-Item "Setup.msix"

    Update-PathEnvironmentVariable
    return (Test-CommandExists "winget");
  }
  Show-Output "Cannot install App Installer, as Microsoft Store appears not to be installed. This is normal on servers. Winget will not be available."
  return $false
}

function Install-Chocolatey() {
  <#
  .SYNOPSIS
      Execute command as seen in https://chocolatey.org/install#individual if "choco" command does not exist.
  #>
  param(
    [switch]$Force
  )
  if ($Force -Or (-Not (Test-CommandExists "choco"))) {
    Show-Output "Installing the Chocolatey package manager by downloading and running official install script"
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
  }
  # "Please use choco upgrade chocolatey to handle upgrades of Chocolatey itself."
  Show-Output "Chocolatey command ('choco') exists. Upgrading chocolatey using chocolatey.."
  choco upgrade chocolatey -y
  Write-Host ""
}

function Install-1PasswordCLI() {
  if (-Not (Test-CommandExists "op")){
    # From https://developer.1password.com/docs/cli/get-started/
    Show-Output "'Installing' 1Password CLI over PowerShell (Download / Unpack / Add to PATH).."
    $arch = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
    switch ($arch) {
      '64-bit' { $opArch = 'amd64'; break }
      '32-bit' { $opArch = '386'; break }
      Default { Write-Error "Sorry, your operating system architecture '$arch' is unsupported" -ErrorAction Stop }
    }
    $installDir = Join-Path -Path $env:ProgramFiles -ChildPath '1Password CLI'
    Invoke-WebRequest -Uri "https://cache.agilebits.com/dist/1P/op2/pkg/v2.4.1/op_windows_$($opArch)_v2.4.1.zip" -OutFile op.zip
    Expand-Archive -Path op.zip -DestinationPath $installDir -Force
    $envMachinePath = [System.Environment]::GetEnvironmentVariable('PATH', 'machine')
    if ($envMachinePath -split ';' -notcontains $installDir) {
      [Environment]::SetEnvironmentVariable('PATH', "$envMachinePath;$installDir", 'Machine')
    }
    Remove-Item -Path op.zip

    # Refresh PATH to get new `op` command
    Update-PathEnvironmentVariable
  }
  Show-Output "1Password CLI command ('op') exists, skipping installation."
}

function RunAntivirus() {
  param (
    [Parameter(Mandatory = $true)] [string] $ScanType
  )

  Show-Output ">> Run Antivirus"
  if (Test-CommandExists "Update-MpSignature") {
    Show-Output "Updating Windows Defender definitions. If you have another antivirus program installed, Windows Defender may be disabled, causing this to fail."
    Update-MpSignature
  }
  else {
    Show-Output "Virus definition updates are not supported - Check them manually."
  }
  if (Test-CommandExists "Start-MpScan") {
    Show-Output "Running Windows Defender full scan. If you have another antivirus program installed, Windows Defender may be disabled, causing this to fail."
    Start-MpScan -ScanType $ScanType
  }
  else {
    Show-Output "Virus scan is not supported - Run it manually."
  }
  Write-Host ""
}

function UpdateWindows() {
  Show-Output ">> Update Windows and Reboot if necessary."
  Install-Module -Name PSWindowsUpdate -Scope AllUsers -Force
  Import-Module -Name PSWindowsUpdate
  $updates = Get-WindowsUpdate -AcceptAll -AutoReboot -Install
  $rebootRequired = $updates.IsRebootRequired
  if ($rebootRequired) {
    Show-Output "Reboot required because of update! Aborting script."
    # reboot with a warning (curiously not always initiated by above command):
    shutdown /r
    Stop-Transcript
    exit 0
  }
  Show-Output "No Reboot required, at least not because of update!"
  Write-Host ""
}
