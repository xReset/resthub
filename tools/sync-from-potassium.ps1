param(
    [string]$Source = "C:\Users\croni\Downloads\OpXOyuApWKTlFzrV",
    [string]$Revision = "PENDING",
    [string]$Release = (Get-Date -Format "yyyy-MM-dd.HHmm")
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Copies = [ordered]@{
    "scripts\hub.lua" = "hub.lua"
    "scripts\r3st_ui.lua" = "r3st_ui.lua"
    "scripts\anims.lua" = "anims.lua"
    "games\blue-lock-rivals\scripts\blr_hub.lua" = "games\blr_hub.lua"
    "games\ghost-driver\scripts\gd2.lua" = "games\gd2.lua"
    "games\dungeon-quest-reborn\scripts\dqr_hub.lua" = "games\dqr_hub.lua"
}
foreach ($pair in $Copies.GetEnumerator()) {
    $from = Join-Path $Source $pair.Key
    $to = Join-Path $Root $pair.Value
    if (!(Test-Path $from -PathType Leaf)) { throw "Missing canonical source: $from" }
    Copy-Item $from $to -Force
    Write-Host "SYNCED $($pair.Key) -> $($pair.Value)"
}

$Files = [ordered]@{}
$LocalNames = [ordered]@{
    "hub.lua" = "hub.lua"
    "r3st_ui.lua" = "r3st_ui.lua"
    "anims.lua" = "anims.lua"
    "telemetry.lua" = "resthub_telemetry.lua"
    "games/blr_hub.lua" = "blr_hub.lua"
    "games/gd2.lua" = "gd2.lua"
    "games/dqr_hub.lua" = "dqr_hub.lua"
}
foreach ($path in $LocalNames.Keys) {
    $native = Join-Path $Root ($path -replace '/', '\')
    $hash = (Get-FileHash $native -Algorithm SHA256).Hash.ToLowerInvariant()
    $Files[$path] = [ordered]@{ sha256 = $hash; localName = $LocalNames[$path] }
}
$Manifest = [ordered]@{
    schema = 1
    minLoader = 3
    release = $Release
    revision = $Revision
    files = $Files
    modules = @(
        [ordered]@{ id = "blue-lock-rivals"; gameId = 6325068386; placeId = 18668065416; path = "games/blr_hub.lua" },
        [ordered]@{ id = "ghost-driver"; gameId = 10173311467; placeId = 137228775845999; path = "games/gd2.lua" },
        [ordered]@{ id = "dungeon-quest-reborn"; gameId = 9931749389; placeId = 77649408247578; path = "games/dqr_hub.lua" }
    )
}
$json = $Manifest | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $Root "manifest.json"), $json, [Text.UTF8Encoding]::new($false))
Write-Host "MANIFEST release=$Release revision=$Revision"
if ($Revision -eq "PENDING") {
    Write-Warning "Commit executable files, then rerun with -Revision <full commit SHA> before publishing manifest.json."
}
