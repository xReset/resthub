param(
    [string]$Source = (Join-Path $PSScriptRoot "..\..\Potassium"),
    [string]$Revision = "PENDING",
    [string]$Release = (Get-Date -Format "yyyy-MM-dd.HHmm")
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Copies = [ordered]@{
    "scripts\hub.lua" = "hub.lua"
    "scripts\r3st_ui.lua" = "r3st_ui.lua"
    "scripts\anims.lua" = "anims.lua"
    "lib\log.lua" = "log.lua"
    "games\bizarre-day-classic\scripts\abd_item_esp.lua" = "games\abd_item_esp.lua"
    "games\blue-lock-rivals\scripts\blr_hub.lua" = "games\blr_hub.lua"
    "games\ghost-driver\scripts\gd2.lua" = "games\gd2.lua"
    "games\dungeon-quest-reborn\scripts\dqr_hub.lua" = "games\dqr_hub.lua"
    "games\wideopen\scripts\wideopen_hub.lua" = "games\wideopen_hub.lua"
    "games\clover-rpg\scripts\clover_hub.lua" = "games\clover_hub.lua"
    "games\bike-universe\scripts\bike_universe_hub.lua" = "games\bike_universe_hub.lua"
    "games\backseat-rally\scripts\backseat_rally_hub.lua" = "games\backseat_rally_hub.lua"
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
$LocalNames = [ordered]@{
    "hub.lua" = "hub.lua"
    "r3st_ui.lua" = "r3st_ui.lua"
    "anims.lua" = "anims.lua"
    "log.lua" = "log.lua"
    "games/abd_item_esp.lua" = "abd_item_esp.lua"
    "telemetry.lua" = "resthub_telemetry.lua"
    "games/blr_hub.lua" = "blr_hub.lua"
    "games/gd2.lua" = "gd2.lua"
    "games/dqr_hub.lua" = "dqr_hub.lua"
    "games/wideopen_hub.lua" = "wideopen_hub.lua"
    "games/clover_hub.lua" = "clover_hub.lua"
    "games/bike_universe_hub.lua" = "bike_universe_hub.lua"
    "games/backseat_rally_hub.lua" = "backseat_rally_hub.lua"
}
foreach ($path in $LocalNames.Keys) {
    $native = Join-Path $Root ($path -replace '/', '\')
    $hash = (Get-FileHash $native -Algorithm SHA256).Hash.ToLowerInvariant()
    $Files[$path] = [ordered]@{ sha256 = $hash; localName = $LocalNames[$path] }
}
$Manifest = [ordered]@{
    schema = 1
    minLoader = 5
    release = $Release
    revision = $Revision
    files = $Files
    modules = @(
        [ordered]@{ id = "bizarre-day-classic"; gameId = 969567031; placeId = 120318126233314; path = "games/abd_item_esp.lua" },
        [ordered]@{ id = "blue-lock-rivals"; gameId = 6325068386; placeId = 18668065416; path = "games/blr_hub.lua" },
        [ordered]@{ id = "ghost-driver"; gameId = 10173311467; placeId = 137228775845999; path = "games/gd2.lua" },
        [ordered]@{ id = "dungeon-quest-reborn"; gameId = 9931749389; placeId = 77649408247578; path = "games/dqr_hub.lua" },
        [ordered]@{ id = "wideopen"; gameId = 10766812776; placeId = 109959833715820; path = "games/wideopen_hub.lua" },
        [ordered]@{ id = "clover-rpg"; gameId = 3164482049; placeId = 8248288152; path = "games/clover_hub.lua" },
        [ordered]@{ id = "bike-universe"; gameId = 10768284407; placeId = 98628861455414; path = "games/bike_universe_hub.lua" },
        [ordered]@{ id = "backseat-rally"; gameId = 10769543742; placeId = 94278659624110; path = "games/backseat_rally_hub.lua" }
    )
}
$json = $Manifest | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $Root "manifest.json"), $json, [Text.UTF8Encoding]::new($false))
Write-Host "MANIFEST release=$Release revision=$Revision"
if ($Revision -eq "PENDING") {
    Write-Warning "Commit executable files, then rerun with -Revision <full commit SHA> before publishing manifest.json."
}
