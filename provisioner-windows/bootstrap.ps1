<#
.SYNOPSIS
    Standalone Invokeable Script to download this repository
    on a fresh windows machine (no git pre-required).
.EXAMPLE
  See README ("Git-free install")
#>

### Constants
# TODO change Branch when merged!
$Account = "JonasPammer"
$Repository = "JonasPammer"
$Branch = "pc-setup-windows"
$ParentDestination = "$USERPROFILE\Documents\Programmieren"
$SubfolderToOpen = "provisioner-windows"


### Init
Push-Location


### Functions
# ~ replica of function found in utils.ps1:
function Show-Output() {
  Write-Host "[bootstrap.ps1] $args" -BackgroundColor White -ForegroundColor Black
}

# replica of function found in utils.ps1:
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

# replica of function found in utils.ps1:
function Update-PathEnvironmentVariable() {
  if (Test-CommandExists "refreshenv") {
    Show-Output "Refreshing PATH Environment Variable using 'refreshenv' function from chocolatey.."
    refreshenv
  }
  else {
    Show-Output "Refreshing PATH Environment Variable.."
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
  }
}


### Main
if (Test-CommandExists "choco") {
  Show-Output "Chocolatey seems to be already installed."
} else {
  # replica of "Install-Chocolatey" function found in utils.ps1:
  Show-Output "Installing the Chocolatey package manager by downloading and running official install script"
  Set-ExecutionPolicy Bypass -Scope Process -Force
  [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
  Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
  Update-PathEnvironmentVariable
}

if (Test-CommandExists "git") {
  Show-Output "Git seems to be already installed."
} else {
  Show-Output "Installing Git"
  choco upgrade git -y
  Update-PathEnvironmentVariable
}

if (Test-Path "$ParentDestination") {
  Show-Output "The parent folder seems to already exist."
} else {
  Show-Output "Creating parent folder."
  mkdir $ParentDestination
}
if (Test-Path "$ParentDestination\$Repository") {
  Show-Output "The Repository seems to already exist."
  Set-Location "$ParentDestination\$Repository"
  Show-Output "Checking out the correct Branch."
  git checkout $Branch
  Show-Output "Performing 'git pull' to update the scripts."
  git pull
} else {
  Show-Output "Cloning the Repository"
  Set-Location "$ParentDestination"
  git clone "https://github.com/$Account/$Repository"
  Set-Location "$ParentDestination\$Repository"
  Show-Output "Checking out the correct Branch."
  git checkout $Branch
}


Show-Output "Configuring the Repository directory to be safe."
git config --global --add safe.directory "$ParentDestination\$Repository"

# TODO or open Windows Terminal (if available) / Powershell Terminal here instead?
Show-Output "Opening the scripts folder in File Explorer."
explorer.exe "$ParentDestination\$Repository\$SubfolderToOpen"
Show-Output "The setup is ready. You can close this window now."


### End
Pop-Location
