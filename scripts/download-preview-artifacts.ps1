param(
    [string]$Repo = "GitGayHub/Bebranoid-iOS",
    [string]$Branch = "main",
    [string]$RunId = "",
    [string]$OutputDir = "artifacts"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "download-preview.ps1") -Repo $Repo -Branch $Branch -RunId $RunId -OutputDir $OutputDir
