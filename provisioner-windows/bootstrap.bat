@echo off

set ACCOUNT="JonasPammer"
set REPO="JonasPammer"
set BRANCH="pc-setup-windows"
set PARENT_DESTINATION="%USERPROFILE%\Documents\Programmieren"
set SUBFOLDER_TO_OPEN="provisioner-windows"

WHERE choco
IF %ERRORLEVEL% EQU 0 (
    echo ... Chocolatey seems to be already installed.
) ELSE (
    echo ... Installing Chocolatey
    powershell -command "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    REM Load Chocolatey command
    CALL %PROGRAMDATA%\chocolatey\bin\RefreshEnv.cmd
)

WHERE git
IF %ERRORLEVEL% EQU 0 (
    echo ... Git seems to be already installed.
) ELSE (
    echo ... Installing Git
    choco upgrade git -y
    REM Load Git command
    CALL %PROGRAMDATA%\chocolatey\bin\RefreshEnv.cmd
)

IF exist %PARENT_DESTINATION% (
    echo ... The Git folder seems to already exist.
) ELSE (
    echo ... Creating a folder for Git repositories.
    mkdir %PARENT_DESTINATION%
)
IF exist %PARENT_DESTINATION%\%REPO% (
    echo ... The repository seems to already exist.
    cd %PARENT_DESTINATION%\%REPO%
    echo ... Checking out the correct branch.
    git checkout %BRANCH%
    echo ... Performing "git pull" to update the scripts.
    git pull
) ELSE (
    echo ... Cloning the repository
    cd %PARENT_DESTINATION%
    git clone "https://github.com/%ACCOUNT%/%REPO%"
    cd %PARENT_DESTINATION%\%REPO%
    echo ... Checking out the correct branch.
    git checkout %BRANCH%
)


echo ... Configuring the repository directory to be safe.
git config --global --add safe.directory %PARENT_DESTINATION%\%REPO%

echo ... Opening the scripts folder in File Explorer.
%SYSTEMROOT%\explorer.exe %PARENT_DESTINATION%\%REPO%\%SUBFOLDER_TO_OPEN%
echo ... The setup is ready. You can close this window now.
