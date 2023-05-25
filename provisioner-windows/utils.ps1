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
      Show-Output "The script has been started in another window. You can close this window now." -ForegroundColor Green
    }
    exit
  }
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
