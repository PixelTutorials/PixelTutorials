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

. ".\utils.ps1"
Elevate($MyInvocation.MyCommand.Definition)


function UpdateWindows() {
  Show-Output "Update Windows and Reboot if necessary..."
  Install-Module PSWindowsUpdate -Scope AllUsers -Confirm:$false -Force
  Import-Module PSWindowsUpdate
  $updates = Get-WindowsUpdate -AcceptAll -AutoReboot -Install
  $rebootRequired = $updates.IsRebootRequired
  if ($rebootRequired) {
    Show-Output "Reboot required because of update! Aborting..."
    # reboot with a warning (curiously not always initiated by above command):
    shutdown /r
    exit 0
  }
  Show-Output "No Reboot required because of update!"
}

function Install1PasswordCLI() {
  # From https://developer.1password.com/docs/cli/get-started/
  Write-Host ""
  Show-Output "Installing 1Password CLI over PowerShell"
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
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function InstallAndUpdateApplications() {
  # TODO re-implement
}

function SetupPowershellProfile() {
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
}


function ConfigureGit() {
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
}

function RunBleachBit() {
  $bleachbit_path_native = "${env:ProgramFiles}\BleachBit\bleachbit_console.exe"
  $bleachbit_path_x86 = "${env:ProgramFiles(x86)}\BleachBit\bleachbit_console.exe"
  $bleachbit_path = $bleachbit_path_native
  if (Test-Path $bleachbit_path_x86) {
    $bleachbit_path = $bleachbit_path_x86
  }

  # The list of cleaners can be obtained with the parameter --list-cleaners
  $bleachbit_cleaners = @(
    "adobe_reader.*",
    #    "amule.backup",
    #    "amule.known_clients",
    #    "amule.known_files",
    #    "amule.logs",
    #    "amule.temp",
    "brave.cache",
    #    "brave.cookies",
    #    "brave.dom",
    "brave.form_history",
    "brave.history",
    "brave.passwords",
    "brave.search_engines",
    #    "brave.session",
    "brave.site_preferences",
    "brave.sync",
    "brave.vacuum",
    "chromium.*",
    #    "chromium.cache",
    #    "chromium.cookies",
    #    "chromium.dom",
    #    "chromium.form_history",
    #    "chromium.history",
    #    "chromium.passwords",
    #    "chromium.search_engines",
    #    "chromium.session",
    #    "chromium.site_preferences",
    #    "chromium.sync",
    #    "chromium.vacuum",
    #    "deepscan.backup",
    #    "deepscan.ds_store",
    #    "deepscan.thumbs_db",
    #    "deepscan.tmp",
    #    "deepscan.vim_swap_root",
    #    "deepscan.vim_swap_user",
    "discord.cache",
    #    "discord.cookies",
    "discord.history",
    "discord.vacuum",
    #    "filezilla.mru",
    #    "firefox.backup",
    "firefox.cache",
    #    "firefox.cookies",
    "firefox.crash_reports",
    #    "firefox.dom",
    "firefox.forms",
    "firefox.passwords",
    #    "firefox.session_restore",
    #    "firefox.site_preferences",
    #    "firefox.url_history",
    #    "firefox.vacuum",
    "flash.*",
    #    "flash.cache",
    #    "flash.cookies",
    "gimp.tmp",
    "google_chrome.*",
    #    "google_chrome.cache",
    #    "google_chrome.cookies",
    #    "google_chrome.dom",
    #    "google_chrome.form_history",
    #    "google_chrome.history",
    #    "google_chrome.passwords",
    #    "google_chrome.search_engines",
    #    "google_chrome.session",
    #    "google_chrome.site_preferences",
    #    "google_chrome.sync",
    #    "google_chrome.vacuum",
    "google_earth.*",
    #    "google_earth.temporary_files",
    "google_toolbar.*",
    #    "google_toolbar.search_history",
    #    "gpodder.cache",
    #    "gpodder.downloaded_podcasts",
    #    "gpodder.logs",
    #    "gpodder.vacuum",
    #    "hexchat.logs",
    #    "hippo_opensim_viewer.cache",
    #    "hippo_opensim_viewer.logs",
    "internet_explorer.*",
    #    "internet_explorer.cache",
    #    "internet_explorer.cookies",
    #    "internet_explorer.downloads",
    #    "internet_explorer.forms",
    #    "internet_explorer.history",
    #    "internet_explorer.logs",
    "java.cache",
    #    "libreoffice.history",
    "microsoft_edge.*",
    #    "microsoft_edge.cache",
    #    "microsoft_edge.cookies",
    #    "microsoft_edge.dom",
    #    "microsoft_edge.form_history",
    #    "microsoft_edge.history",
    #    "microsoft_edge.passwords",
    #    "microsoft_edge.search_engines",
    #    "microsoft_edge.session",
    #    "microsoft_edge.site_preferences",
    #    "microsoft_edge.sync",
    #    "microsoft_edge.vacuum",
    #    "microsoft_office.debug_logs",
    #    "microsoft_office.mru",
    #    "midnightcommander.history",
    #    "miro.cache",
    #    "miro.logs",
    #    "octave.history",
    #    "openofficeorg.cache",
    #    "openofficeorg.recent_documents",
    #    "opera.cache",
    #    "opera.cookies",
    #    "opera.dom",
    #    "opera.form_history",
    #    "opera.history",
    #    "opera.passwords",
    #    "opera.session",
    #    "opera.site_preferences",
    #    "opera.vacuum",
    #    "paint.mru",
    #    "palemoon.backup",
    #    "palemoon.cache",
    #    "palemoon.cookies",
    #    "palemoon.crash_reports",
    #    "palemoon.dom",
    #    "palemoon.forms",
    #    "palemoon.passwords",
    #    "palemoon.session_restore",
    #    "palemoon.site_preferences",
    #    "palemoon.url_history",
    #    "palemoon.vacuum",
    #    "pidgin.cache",
    #    "pidgin.logs",
    #    "realplayer.cookies",
    #    "realplayer.history",
    #    "realplayer.logs",
    #    "safari.cache",
    #    "safari.cookies",
    #    "safari.history",
    #    "safari.vacuum",
    #    "screenlets.logs",
    #    "seamonkey.cache",
    #    "seamonkey.chat_logs",
    #    "seamonkey.cookies",
    #    "seamonkey.download_history",
    #    "seamonkey.history",
    #    "secondlife_viewer.Cache",
    #    "secondlife_viewer.Logs",
    #    "silverlight.cookies",
    #    "silverlight.temp",
    #    "skype.chat_logs",
    #    "skype.installers",
    #    "slack.cache",
    #    "slack.cookies",
    #    "slack.history",
    #    "slack.vacuum",
    #    "smartftp.cache",
    #    "smartftp.log",
    #    "smartftp.mru",
    #    "system.clipboard",
    #    "system.custom",
    #    "system.free_disk_space",
    #    "system.logs",
    #    "system.memory_dump",
    #    "system.muicache",
    #    "system.prefetch",
    "system.recycle_bin",
    "system.tmp",
    #    "system.updates",
    "teamviewer.logs",
    #    "teamviewer.mru",
    #    "thunderbird.cache",
    #    "thunderbird.cookies",
    #    "thunderbird.index",
    #    "thunderbird.passwords",
    #    "thunderbird.sessionjson",
    #    "thunderbird.vacuum",
    #    "tortoisesvn.history",
    #    "vim.history",
    #    "vlc.memory_dump",
    #    "vlc.mru",
    #    "vuze.backup",
    #    "vuze.cache",
    #    "vuze.logs",
    #    "vuze.stats",
    #    "vuze.temp",
    #    "warzone2100.logs",
    #    "waterfox.backup",
    #    "waterfox.cache",
    #    "waterfox.cookies",
    #    "waterfox.crash_reports",
    #    "waterfox.dom",
    #    "waterfox.forms",
    #    "waterfox.passwords",
    #    "waterfox.session_restore",
    #    "waterfox.site_preferences",
    #    "waterfox.url_history",
    #    "waterfox.vacuum",
    #    "winamp.mru",
    #    "windows_defender.backup",
    #    "windows_defender.history",
    #    "windows_defender.logs",
    #    "windows_defender.quarantine",
    #    "windows_defender.temp",
    #    "windows_explorer.mru",
    "windows_explorer.recent_documents",
    #    "windows_explorer.run",
    "windows_explorer.search_history",
    #    "windows_explorer.shellbags",
    #    "windows_explorer.thumbnails",
    "windows_media_player.cache",
    #    "windows_media_player.mru",
    #    "winrar.history",
    #    "winrar.temp",
    #    "winzip.mru",
    #    "wordpad.mru",
    #    "yahoo_messenger.cache",
    #    "yahoo_messenger.chat_logs",
    #    "yahoo_messenger.logs",
    "zoom.cache"
    #    "zoom.logs",
    #    "zoom.recordings"
  )

  Show-Output "Run BleachBit cleaners..."
  & $bleachbit_path --clean $bleachbit_cleaners
}

function RunAntivirus() {
  if (Test-CommandExists "Update-MpSignature") {
    Show-Output "Updating Windows Defender definitions. If you have another antivirus program installed, Windows Defender may be disabled, causing this to fail."
    Update-MpSignature
  }
  else {
    Show-Output "Virus definition updates are not supported - Check them manually."
  }
  if (Test-CommandExists "Start-MpScan") {
    Show-Output "Running Windows Defender full scan. If you have another antivirus program installed, Windows Defender may be disabled, causing this to fail."
    Start-MpScan -ScanType "FullScan"
  }
  else {
    Show-Output "Virus scan is not supported - Run it manually."
  }
}

UpdateWindows
Install1PasswordCLI
#InstallAndUpdateApplications
SetupPowershellProfile
ConfigureGit
RunBleachBit
RunAntivirus
