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

### Constants
$UpdateAppsIfInstalled = $true


### Init
. ".\utils.ps1"
Start-Transcript -Path "${LogsPath}\$($MyInvocation.MyCommand.Name)--$(Get-Date -Format "yyyy-MM-dd--HH_mm_ss").txt"
Elevate($MyInvocation.MyCommand.Definition)


### Functions
function InstallAndUpdateApplications() {
  Show-Output ">> Install and Update Applications"
  Install-Chocolatey
  Install-Winget

  Show-Output "Reading .\applications.yml"
  Install-Module -Name powershell-yaml -Force
  Import-Module -Name powershell-yaml
  $_content = Get-Content -Raw ".\applications.yml"
  $applicationsYAML = ConvertFrom-YAML -Ordered $_content

  Show-Output "Updating all winget sources"
  winget source update
  Write-Host ""

  ForEach ($app in $applicationsYAML.applications) {
    #$app
    Show-Output "-> Looping: " $app.display_name " (" $app.description_short ")"
    if ($app.status -eq "not-used"){
      Show-Output "--> Skipping (status: not-used)"
    } elseif ($app.provider -eq "winget") {
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
        elseif ($UpdateAppsIfInstalled) {
          Show-Output "--> Updating " $app.winget_id "..."
          winget upgrade $app.winget_id
        }
      }
    }
    elseif ($app.provider -eq "chocolatey") {
      Show-Output "Installing " $app.chocolatey_name "..."
      #choco feature enable -n=allowGlobalConfirmation#
      choco install -y $app.chocolatey_name
      #choco feature disable -n=allowGlobalConfirmation#
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

function SetupPowershellProfile() {
  Show-Output ">> Setup Powershell Profile"
  ## PowerShell environment for Git (e.g. adds tab completion)
  Show-Output "Adding PoshGit to PowerShell Profile"
  Set-ExecutionPolicy RemoteSigned -Scope Process
  PowerShellGet\Install-Module posh-git -Scope AllUsers -Force
  PowerShellGet\Update-Module posh-git
  # This will add a line containing Import-Module posh-git to the file $profile.CurrentUserAllHosts:
  Add-PoshGitToProfile -AllHosts

  ## PowerShell helpers for SSH (e.g. Start-SshAgent -Quiet)
  Show-Output "Adding PoshSshell to PowerShell Profile"
  PowerShellGet\Install-Module posh-sshell -Scope AllUsers -Force
  PowerShellGet\Update-Module posh-sshell
  # This will add a line containing Import-Module posh-sshell to the file $profile.CurrentUserAllHosts:
  Add-PoshSshellToProfile -AllHosts

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


### Main
UpdateWindows
Install-1PasswordCLI
InstallAndUpdateApplications
SetupPowershellProfile
ConfigureGit
RunAntivirus -ScanType "QuickScan"

### End
Stop-Transcript
