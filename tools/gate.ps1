param([switch]$CheckRemote)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Compiler = "C:\Users\croni\Downloads\OpXOyuApWKTlFzrV\tools\luau-compile.exe"
$Lua = @("loader.lua", "telemetry.lua", "hub.lua", "r3st_ui.lua", "games/blr_hub.lua", "games/gd2.lua")
foreach ($path in $Lua) {
    $full = Join-Path $Root ($path -replace '/', '\')
    if (!(Test-Path $full -PathType Leaf)) { throw "GATE FAIL missing $path" }
    & $Compiler --binary $full *> $null
    if ($LASTEXITCODE -ne 0) { throw "GATE FAIL compile $path" }
    Write-Host "COMPILE_OK $path"
}
$manifestPath = Join-Path $Root "manifest.json"
if (!(Test-Path $manifestPath -PathType Leaf)) { throw "GATE FAIL missing manifest.json" }
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1 -or $manifest.minLoader -gt 2) { throw "GATE FAIL manifest schema/loader" }
if ($manifest.revision -notmatch '^[0-9a-fA-F]{40}$') { throw "GATE FAIL manifest revision" }
foreach ($property in $manifest.files.PSObject.Properties) {
    $path = $property.Name
    $spec = $property.Value
    $full = Join-Path $Root ($path -replace '/', '\')
    if (!(Test-Path $full -PathType Leaf)) { throw "GATE FAIL manifest target $path" }
    $actual = (Get-FileHash $full -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $spec.sha256.ToLowerInvariant()) { throw "GATE FAIL hash $path" }
    Write-Host "HASH_OK $path"
}
$tracked = git -C $Root ls-files
$patterns = 'gh[pousr]_[A-Za-z0-9]+|Authorization\s*[:=]\s*Bearer\s+[A-Za-z0-9._-]+|discord(?:app)?\.com/api/webhooks/|BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY|password\s*[:=]\s*[^\s\[]+'
$hits = foreach ($file in $tracked) {
    $full = Join-Path $Root $file
    if (Test-Path $full -PathType Leaf) { Select-String -Path $full -Pattern $patterns -AllMatches -CaseSensitive:$false }
}
if ($hits) { $hits | ForEach-Object { Write-Host $_ }; throw "GATE FAIL possible secret" }
Write-Host "SECRET_SCAN_OK"
if ($CheckRemote) {
    $urls = @(
        "https://raw.githubusercontent.com/xReset/resthub/main/loader.lua",
        "https://raw.githubusercontent.com/xReset/resthub/main/manifest.json"
    )
    foreach ($url in $urls) {
        $response = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing
        if ($response.StatusCode -ne 200) { throw "GATE FAIL remote $url" }
        Write-Host "REMOTE_OK $url"
    }
}
Write-Host "RESTHUB_GATE_PASS"
