param([switch]$CheckRemote)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Compiler = Join-Path $PSScriptRoot "..\..\Potassium\tools\luau-compile.exe"
$manifestPath = Join-Path $Root "manifest.json"
if (!(Test-Path $manifestPath -PathType Leaf)) { throw "GATE FAIL missing manifest.json" }
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$Lua = @("loader.lua") + @($manifest.files.PSObject.Properties.Name)
foreach ($required in @("hub.lua", "r3st_runtime.lua", "r3st_ui.lua", "anims.lua", "log.lua")) {
    if (!$manifest.files.PSObject.Properties[$required]) { throw "GATE FAIL missing dependency $required" }
}
foreach ($path in $Lua) {
    $full = Join-Path $Root ($path -replace '/', '\')
    if (!(Test-Path $full -PathType Leaf)) { throw "GATE FAIL missing $path" }
    & $Compiler --binary $full *> $null
    if ($LASTEXITCODE -ne 0) { throw "GATE FAIL compile $path" }
    Write-Host "COMPILE_OK $path"
}
$loaderText = [IO.File]::ReadAllText((Join-Path $Root "loader.lua"))
$versionMatch = [regex]::Match($loaderText, 'local LOADER_VERSION = (\d+)')
if (!$versionMatch.Success) { throw "GATE FAIL missing loader version" }
if ($manifest.schema -ne 1 -or $manifest.minLoader -gt [int]$versionMatch.Groups[1].Value) {
    throw "GATE FAIL manifest schema/loader"
}
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
$patterns = 'https?://[^\s"<>]*\.ts\.net(?:/[^\s"<>]*)?|gh[pousr]_[A-Za-z0-9]+|Authorization\s*[:=]\s*Bearer\s+[A-Za-z0-9._-]+|discord(?:app)?\.com/api/webhooks/|BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY|password\s*[:=]\s*(?!%s\b)[^\s\[]+'
$hits = foreach ($file in $tracked) {
    $full = Join-Path $Root $file
    if (Test-Path $full -PathType Leaf) { Select-String -Path $full -Pattern $patterns -AllMatches -CaseSensitive:$false }
}
if ($hits) { $hits | ForEach-Object { Write-Host $_ }; throw "GATE FAIL possible secret" }
Write-Host "SECRET_SCAN_OK"
python -m unittest discover -s (Join-Path $Root "tests") -v
if ($LASTEXITCODE -ne 0) { throw "GATE FAIL loader tests" }
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
