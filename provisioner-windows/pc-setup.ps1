<#
.SYNOPSIS
   Jonas Pammer's PC Setup Script.
   This script aims to be fully automated and not ask anything.

.EXAMPLE
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\pc-setup.ps1

.NOTES
  Author:         Jonas Pammer
  Creation Date:  2022-03-02

.PARAMETER Elevated
    This parameter is for internal use to check whether an UAC prompt has already been attempted.
#>
Param(
  [switch]$Elevated
)

### Init
. ".\utils.ps1"
Start-Transcript -Path "${LogsPath}\$($MyInvocation.MyCommand.Name)--$(Get-Date -Format "yyyy-MM-dd--HH_mm_ss").txt"
Elevate($MyInvocation.MyCommand.Definition)
$Config = InitializeYAMLConfig

### Functions
function InstallAndUpdateApplications() {
  Show-Output ">> Install and Update Applications"
  Install-Chocolatey
  Install-Winget

  $applications_update = if($Config.applications_update -ne $null) { $Config.applications_update } else { $true }
  if ($applications_update -eq $false){
    Show-Output "'applications_update' is set to false. Not updating any already installed application!"
  }

  Show-Output "Reading .\applications.yml"
  $_content = Get-Content -Raw ".\applications.yml"
  $applicationsYAML = ConvertFrom-YAML -Ordered $_content

  Show-Output "Updating all winget sources"
  winget source update
  Write-Host ""

  ForEach ($app in $applicationsYAML.applications) {
    #$app
    Show-Output "-> Looping: $($app.display_name) ($($app.description_short))"
    if ($app.status -eq "not-used") {
      Show-Output "--> Skipping (status: not-used)"
    }
    elseif ($app.provider -eq "winget") {
      $listApp = winget list  --accept-source-agreements --exact -q $app.winget_id
      if (![String]::Join("", $listApp).Contains($app.winget_id) -And !$app.uninstall) {
        # if ($app.interactive) {
        #   Show-Output "[WINGET] --> Installing " $app.winget_id " in interactive mode..."
        #   winget install --accept-source-agreements --accept-package-agreements --exact --id $app.winget_id --interactive --scope $app.winget_scope
        # }
        # else
        if ($null -eq $app.winget_scope) {
          Show-Output "--> Installing " $app.winget_id " in silent, non-interactive mode [ambigious scope]..."
          winget install --accept-source-agreements --accept-package-agreements --exact --id $app.winget_id --silent
        }
        else {
          Show-Output "--> Installing " $app.winget_id " in silent, non-interactive mode..."
          winget install --accept-source-agreements --accept-package-agreements --exact --id $app.winget_id --silent --scope $app.winget_scope
        }
      }
      else {
        if ($app.uninstall) {
          Show-Output "--> Uninstalling " $app.winget_id "..."
          winget uninstall $app.winget_id
        }
        elseif ($applications_update) {
          Show-Output "--> Updating " $app.winget_id "..."
          winget upgrade $app.winget_id
        }
      }
    }
    elseif ($app.provider -eq "chocolatey") {
      $listApp = choco list --exact $app.chocolatey_name --by-id-only --idonly --no-progress --limitoutput
      # `allowGlobalConfirmation` to not get stuck at "The package packer wants to run 'chocolateyInstall.ps1'." message (and maybe others).
      choco feature enable -n=allowGlobalConfirmation
      if (!$app.uninstall -And ($listApp -eq $null -Or ![String]::Join("", $listApp).Contains($app.chocolatey_name))) {
        Show-Output "Installing " $app.chocolatey_name "..."
        choco install -y $app.chocolatey_name
      } else {
        if ($app.uninstall) {
          Show-Output "--> Uninstalling " $app.chocolatey_name "..."
          choco uninstall $app.chocolatey_name
        }
        elseif ($applications_update) {
          Show-Output "--> Updating " $app.chocolatey_name "..."
          choco upgrade $app.chocolatey_name
        }
      }
      choco feature disable -n=allowGlobalConfirmation
    }
    else {
      Show-Output "--> Application does not have an installation provider!"
      if ([bool]($app.PSobject.Properties.name -match "link") -And ($app.link)) {
        Show-Output "--> Install/Download yourself at " $app.link
      }
    }
    Write-Host ""
  }
  Write-Host ""
}

function InstallAndUpdateApplicationsPostCommands() {
  Add-ToSystemPath "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg"
}

function SetupPowershellProfile() {
  Show-Output ">> Setup Powershell Profile"

  ## PowerShell environment for Git (e.g. adds tab completion)
  Show-Output "Adding PoshGit to PowerShell Profile"
  Set-ExecutionPolicy RemoteSigned -Scope Process
  PowerShellGet\Install-Module posh-git -Scope AllUsers -Force
  PowerShellGet\Update-Module posh-git
  # This will add a line containing Import-Module posh-git to the file $profile.CurrentUserAllHosts:
  # Would display the following Warning Message when used multiple times, if not for '-SilentlyContinue':
  # "Skipping add of posh-git import to file 'C:\Users\priva\Documents\WindowsPowerShell\profile.ps1'"
  # "posh-git appears to already be imported in one of your profile scripts."
  Add-PoshGitToProfile -AllHosts -WarningAction SilentlyContinue

  ## PowerShell helpers for SSH (e.g. Start-SshAgent -Quiet)
  Show-Output "Adding PoshSshell to PowerShell Profile"
  PowerShellGet\Install-Module posh-sshell -Scope AllUsers -Force
  PowerShellGet\Update-Module posh-sshell
  # This will add a line containing Import-Module posh-sshell to the file $profile.CurrentUserAllHosts:
  # Would display the following Warning Message when used multiple times, if not for '-SilentlyContinue':
  # "Skipping add of posh-posh-sshell import to file 'C:\Users\priva\Documents\WindowsPowerShell\profile.ps1'"
  # "posh-posh-sshell appears to already be imported in one of your profile scripts."
  Add-PoshSshellToProfile -AllHosts -WarningAction SilentlyContinue

  Show-Output "Adding StartSshAgent Command to PowerShell Profile"
  Get-Service -Name ssh-agent | Set-Service -StartupType Manual
  $SEL = Select-String -Path $profile.CurrentUserAllHosts -Pattern "Start-SshAgent -Quiet"
  if ($null -eq $SEL) {
    Add-Content -Path $profile.CurrentUserAllHosts -Value "`r`nStart-SshAgent -Quiet"
  }
  Write-Host ""
}

function ConfigureGit() {
  Show-Output ">> Configure Git"
  Show-Output "Changing max-cache-ttl in gpg-agent.conf..."
  # (assigning to a variable to make output silent)
  Set-Content -Path "${env:APPDATA}\gnupg\gpg-agent.conf" -Value "default-cache-ttl 86400$([System.Environment]::NewLine)max-cache-ttl 86400"
  gpgconf.exe --reload gpg-agent
  # Verify with: gpgconf.exe --list-options gpg-agent

  Show-Output "Executing commands to alter git config..."
  $gpg_program = $(Get-Command gpg | Select-Object source)
  $gpg_program_source = $gpg_program.Source # i don't have much ps1 knowledge
  git config --global gpg.program "$gpg_program_source"

  git config --global pull.rebase true

  git config --global user.name "Jonas Pammer"
  git config --global user.email "opensource@jonaspammer.at"

  git config --global diff.colorMoved "zebra"
  # Use better, descriptive initials (c, i, w) instead of a/b.
  git config --global diff.mnemonicPrefix "true"
  # Show renames/moves as such
  git config --global diff.renames "true"

  # Auto-fetch submodule changes (sadly, won't auto-update)
  git config --global fetch.recurseSubmodules "on-demand"

  git config --global grep.break "true"
  git config --global grep.heading "true"
  git config --global grep.lineNumber "true"

  # Use abbrev SHAs whenever possible/relevant instead of full 40 chars
  git config --global log.abbrevCommit "true"
  # Automatically --follow when given a single path
  git config --global log.follow "true"
  # Disable decorate for reflog
  # (because there is no dedicated `reflog` section available)
  git config --global log.decorate "false"

  # Clean up backup files created by merge tools on tool exit
  git config --global mergetool.keepBackup "false"
  # Clean up temp files created by merge tools on tool exit
  git config --global mergetool.keepTemporaries "false"
  # Put the temp files in a dedicated dir anyway
  git config --global mergetool.writeToTemp "true"
  # Auto-accept file prompts when launching merge tools
  git config --global mergetool.prompt "false"

  git config --global diff.tool vscode
  git config --global "difftool.vscode.cmd" "code --wait --diff $LOCAL $REMOTE"

  git config --global merge.tool "vscode"
  git config --global "mergetool.vscode.cmd" "code --wait --merge $REMOTE $LOCAL $BASE $MERGED"

  # Recursively traverse untracked directories to display all contents
  git config --global status.showUntrackedFiles "all"

  git config --global --add --bool push.autoSetupRemote true
  Write-Host ""
}

function AddGodMode() {
  Show-Output ">> Add Windows God Mode Icon to desktop"
  $GodModeSplat = @{
    Path     = "$HOME\Desktop"
    Name     = "GodMode.{ED7BA470-8E54-465E-825C-99712043E01C}"
    ItemType = 'Directory'
  }
  $null = New-Item @GodModeSplat -ErrorAction Ignore
  Write-Host ""
}

function Install-WSL() {
  param (
    [Parameter(Mandatory = $true)] [string] $distribution
  )
  Show-Output ">> Install WSL"
  Show-Output "Enabling WSL features"
  dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
  dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
  # no longer needed:
  #.\wsl_update_x64.msi /quiet
  # no longer exists, ""replaced"" by --enable-wsl1 as wsl2 is now default
  #wsl --set-default-version 2
  Show-Output "Install WSL Distribution '$distribution'"
  wsl --install --distribution "$distribution"
  Write-Host ""
}

function TweakRegistry(){
  Show-Output 'Disabling "Show recently used files in Quick access" & "Show frequently used folders in Quick access" (Windows Explorer)'
  Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -Value 0
  Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -Value 0
  # Restart explorer.exe to apply the changes
  Stop-Process -Name explorer -Force
  Start-Process explorer

  Show-Output "Disabling Bing Search in Start Menu..."
	Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Type DWord -Value 0
	Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Type DWord -Value 0
}

### Main
$allow_reboot = if($Config.allow_reboot -ne $null) { $Config.allow_reboot } else { $true }
$exit_anyways_if_reboot_required = if($Config.exit_anyways_if_reboot_required -ne $null) { $Config.exit_anyways_if_reboot_required } else { $false }
UpdateWindows $allow_reboot $exit_anyways_if_reboot_required
Install-1PasswordCLI

# won't uninstall otherwhise
Stop-Process -Name "Greenshot" -Force -ErrorAction SilentlyContinue

InstallAndUpdateApplications
InstallAndUpdateApplicationsPostCommands

SetupPowershellProfile
ConfigureGit

RunAntivirus -ScanType "QuickScan"

if ($Config.wsl_install) {
  Install-WSL "$Config.wsl_distro"
}
else {
  Show-Output ">> Skipping WSL Install (disabled by configuration option)"
  Write-Host ""
}

TweakRegistry
AddGodMode

### End
Stop-Transcript
