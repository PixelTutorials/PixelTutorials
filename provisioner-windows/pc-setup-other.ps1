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
. ".\utils.ps1"
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
  $1password_pk_item_name = $Config.gpg_1password_pk_item_name.Replace("{{ gpg_email }}", "$gpg_email")
  $1password_passphrase_item_name = $Config.gpg_1password_passphrase_item_name.Replace("{{ gpg_email }}", "$gpg_email")
  $tempdir = New-TemporaryDirectory
  $tempfile = Join-Path $tempdir "$gpg_email_filesafe-private.key"

  try {
    op document get "$1password_pk_item_name" --output "$tempfile"
    Show-Output "Importing GPG key (passphrase gathered from 1Password)..."
    gpg --passphrase $(op item get "$1password_passphrase_item_name" --fields password) --import "$tempfile"
    Show-Output "Deleting GPG key from the local system again..."
    Remove-Item "$tempfile"

    Write-Host ""
    Show-Output "Opening Menu to edit the imported GPG key..."
    Show-Output "Please enter 5<return> and y<return> in the following prompts!"
    Start-Sleep 2
    #! Prompts:
    gpg --edit-key $(op item get "$1password_pk_item_name" --fields key) trust quit

    Show-Output "Executing commands to alter git config..."
    git config --global commit.gpgSign true
    git config --global user.signingKey $(op item get "$1password_pk_item_name" --fields key)
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
else {
  Show-Output ">> Skipping 1Password-sourced GPG Setup (disabled by configuration option)"
  Write-Host ""
}

### End
Stop-Transcript
