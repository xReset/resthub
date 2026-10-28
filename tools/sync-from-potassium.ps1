param(
    [string]$Source = (Join-Path $PSScriptRoot "..\..\Potassium"),
    [string]$Revision = "PENDING",
    [string]$Release = (Get-Date -Format "yyyy-MM-dd.HHmm")
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$registry = & python (Join-Path $PSScriptRoot "registry.py") --source $Source
if ($LASTEXITCODE -ne 0) { throw "Cannot read canonical Hub registry" }
$Modules = $registry | ConvertFrom-Json
$Copies = [ordered]@{
    "scripts\hub.lua" = "hub.lua"
    "scripts\r3st_runtime.lua" = "r3st_runtime.lua"
    "scripts\r3st_ui.lua" = "r3st_ui.lua"
    "scripts\anims.lua" = "anims.lua"
    "lib\log.lua" = "log.lua"
}
$LocalNames = [ordered]@{
    "hub.lua" = "hub.lua"
    "r3st_runtime.lua" = "r3st_runtime.lua"
    "r3st_ui.lua" = "r3st_ui.lua"
    "anims.lua" = "anims.lua"
    "log.lua" = "log.lua"
    "telemetry.lua" = "resthub_telemetry.lua"
}
foreach ($module in $Modules) {
    $Copies[$module.source] = $module.path
    $LocalNames[$module.path] = $module.localName
}
foreach ($pair in $Copies.GetEnumerator()) {
    $from = Join-Path $Source $pair.Key
    $to = Join-Path $Root $pair.Value
    if (!(Test-Path $from -PathType Leaf)) { throw "Missing canonical source: $from" }
    # Hash the LF bytes GitHub will serve, not a CRLF development checkout.
    $text = [IO.File]::ReadAllText($from).Replace("`r`n", "`n")
    [IO.File]::WriteAllText($to, $text, [Text.UTF8Encoding]::new($false))
    Write-Host "SYNCED $($pair.Key) -> $($pair.Value)"
}
$Files = [ordered]@{}
foreach ($path in $LocalNames.Keys) {
    $native = Join-Path $Root ($path -replace '/', '\')
    $hash = (Get-FileHash $native -Algorithm SHA256).Hash.ToLowerInvariant()
    $Files[$path] = [ordered]@{ sha256 = $hash; localName = $LocalNames[$path] }
}
$Manifest = [ordered]@{
    schema = 1
    minLoader = 6
    release = $Release
    revision = $Revision
    files = $Files
    modules = @($Modules | ForEach-Object {
        [ordered]@{ id = $_.id; gameId = $_.gameId; placeId = $_.placeId; path = $_.path }
    })
}
$json = $Manifest | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $Root "manifest.json"), $json, [Text.UTF8Encoding]::new($false))
Write-Host "MANIFEST release=$Release revision=$Revision modules=$($Modules.Count)"
if ($Revision -eq "PENDING") {
    Write-Warning "Commit executable files, then rerun with -Revision <full commit SHA> before publishing manifest.json."
}
