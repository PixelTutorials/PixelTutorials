<#
.SYNOPSIS
   Same purpose as pc-setup.ps1, but contains parts that require user interaction (prompts).

.EXAMPLE
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\pc-setup-other.ps1

.PARAMETER Elevated
    This parameter is for internal use to check whether an UAC prompt has already been attempted.
#>
Param(
  [switch]$Elevated
)

### Init
. "$PSScriptRoot\utils.ps1"
Start-Transcript -Path "${LogsPath}\$($MyInvocation.MyCommand.Name)--$(Get-Date -Format "yyyy-MM-dd--HH_mm_ss").txt"
Elevate($MyInvocation.MyCommand.Definition)
$Config = InitializeYAMLConfig


### Functions
function SetupGpgUsing1Password() {
  Show-Output ">> Download and Install GPG private key from 1Password"
  Write-Host ""
  Install-1PasswordCLI
  Write-Host ""
  Show-Output "Please SignIn to 1Password..."
  #! Prompts (or, given app integration, makes a popup with a blue "Authorize :)" button)
  op signin

  $gpg_email = $Config.gpg_email
  $gpg_email_filesafe = $gpg_email.Split([IO.Path]::GetInvalidFileNameChars()) -join '_'
  $1password_item_name = $Config.gpg_1password_item_name.Replace("{{ gpg_email }}", "$gpg_email")
  $tempdir = New-TemporaryDirectory
  $tempfile = Join-Path $tempdir "$gpg_email_filesafe-private.key"

  try {
    op document get "$1password_item_name" --output "$tempfile"
    Show-Output "Importing GPG key (passphrase gathered from 1Password)..."
    gpg --passphrase $(op item get "$1password_item_name" --fields passphrase) --import "$tempfile"
    Show-Output "Deleting GPG key from the local system again..."
    Remove-Item "$tempfile"

    # https://unix.stackexchange.com/a/392355
    Write-Host ""
    Show-Output "Opening Menu to edit the imported GPG key..."
    Show-Output "Please enter 5<return> and y<return> in the following prompts!"
    Start-Sleep 2
    #! Prompts:
    gpg --edit-key $(op item get "$1password_item_name" --fields key) trust quit

    Show-Output "Executing commands to alter git config..."
    git config --global commit.gpgSign true
    git config --global user.signingKey $(op item get "$1password_item_name" --fields key)
    Write-Host ""
  }
  finally {
    # ensure always deleted, even if something happened
    Remove-Item "$tempfile" -ErrorAction Ignore
  }
}


function SetupSshUsing1Password() {
  Show-Output ">> Download and Install SSH private key from 1Password"
  Write-Host ""
  Install-1PasswordCLI
  Write-Host ""
  Show-Output "Please SignIn to 1Password..."
  #! Prompts (or, given app integration, makes a popup with a blue "Authorize :)" button)
  op signin

  $ssh_name = $Config.ssh_name
  $ssh_name_filesafe = $ssh_name.Split([IO.Path]::GetInvalidFileNameChars()) -join '_'
  $1password_item_name = $Config.ssh_1password_item_name.Replace("{{ ssh_name }}", "$ssh_name")
  $tempdir = New-TemporaryDirectory
  $tempfile = Join-Path $tempdir "$ssh_name_filesafe-private.key"

  try {
    op document get "$1password_item_name" --output "$tempfile"
    Show-Output "Importing SSH key (passphrase gathered from 1Password)..."
    ssh-add "$tempfile"

    # https://blog.1password.com/git-commit-signing/
    Show-Output "Executing commands to alter git config..."
    git config --global core.sshCommand "C:/WINDOWS/System32/OpenSSH/ssh.exe"
    git config --global gpg.ssh.program "C:\\Users\\priva\\AppData\\Local\\1Password\\app\\8\\op-ssh-sign.exe"
    git config --global gpg.format "ssh"
    git config --global commit.gpgSign true
    git config --global user.signingKey $(op item get "$1password_item_name" --fields key)
    Write-Host ""
  }
  finally {
    # ensure always deleted, even if something happened
    Remove-Item "$tempfile" -ErrorAction Ignore
  }
}


### Main
if ($Config.setup_gpg) {
  SetupGpgUsing1Password
}
elseif ($Config.setup_ssh) {
  SetupSshUsing1Password
}
else {
  Show-Output ">> Skipping 1Password-sourced GPG Setup (disabled by configuration option)"
  Write-Host ""
}

### End
Stop-Transcript
