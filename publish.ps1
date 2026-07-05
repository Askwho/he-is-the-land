#requires -Version 5.1
<#
.SYNOPSIS
    Publishes selected Obsidian notes to the "He Is The Land" player site.

.DESCRIPTION
    1. Finds every note in the vault whose frontmatter contains `publish: true`,
       strips any Obsidian `%% ... %%` comments (DM-only asides), and copies the
       result into Quartz's content folder.
    2. Copies the curated player-safe images from the vault's
       "z_Assets\Player Site" folder (put anything you want on the site there -
       ONLY player-safe images, the whole folder is published).
    3. Builds the site and generates the podcast RSS feed.
    4. With -Push: commits to GitHub (backup + old GitHub Pages URL) AND deploys
       to Cloudflare at https://heistheland.askwhocasts.com.
    5. With -UploadAudio: uploads any episode MP3s from Sessions\Podcast\out that
       aren't yet in R2 (requires .upload-token; see PUBLISHING.md). Remember to
       add the new episode to episodes.json and create its page in the vault.

.EXAMPLE
    .\publish.ps1
        Sync + local build only (safe preview, nothing goes public).

.EXAMPLE
    .\publish.ps1 -Push -Message "Add Session 6"
        Sync, build, publish live (GitHub + Cloudflare).

.EXAMPLE
    .\publish.ps1 -UploadAudio -Push
        Also upload any new podcast episodes to R2 first.
#>
[CmdletBinding()]
param(
    [switch]$Push,
    [switch]$UploadAudio,
    [string]$Message = "Update player site"
)

$ErrorActionPreference = 'Stop'

# --- Paths ------------------------------------------------------------------
$Vault      = 'C:\Users\askew\Documents\DnD\Barovia\Obsidian\HitL'
$Site       = 'C:\Users\askew\Documents\DnD\Barovia\PlayerSite'
$Content    = Join-Path $Site 'content'
$AssetsSrc  = Join-Path $Vault 'z_Assets\Player Site'
$PodcastOut = 'C:\Users\askew\Documents\DnD\Barovia\Sessions\Podcast\out'
$SiteHost   = 'https://heistheland.askwhocasts.com'

# Vault folders never scanned for publishable notes.
$ExcludeDirs = @('.git', '.obsidian', '.trash', 'z_Templates', 'z_Archive')

# Files in content\ that are part of the site itself (never wiped on sync).
$KeepFiles = @('index.md')

# --- 1. Find notes marked `publish: true` in their frontmatter --------------
function Test-Published {
    param([string]$Path)
    $lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') { return $false }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { return $false }   # reached end of frontmatter
        if ($lines[$i] -match '^\s*publish\s*:\s*true\s*$') { return $true }
    }
    return $false
}

Write-Host "Scanning vault for notes marked 'publish: true'..." -ForegroundColor Cyan

$published = Get-ChildItem -LiteralPath $Vault -Recurse -Filter *.md -File | Where-Object {
    $p = $_.FullName
    $excluded = $false
    foreach ($d in $ExcludeDirs) { if ($p -like "*\$d\*") { $excluded = $true; break } }
    (-not $excluded) -and (Test-Published $p)
}

if (-not $published) {
    Write-Warning "No notes marked 'publish: true' were found. Nothing to publish."
    return
}

# --- 2. Clear previously-synced markdown (keep site-native pages) -----------
Get-ChildItem -LiteralPath $Content -Recurse -Filter *.md -File |
    Where-Object { $KeepFiles -notcontains $_.Name } |
    Remove-Item -Force
# Remove any now-empty folders left behind.
Get-ChildItem -LiteralPath $Content -Recurse -Directory |
    Sort-Object { $_.FullName.Length } -Descending |
    Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force) } |
    Remove-Item -Force

# --- 3. Copy each published note, stripping %% DM-only comments %% -----------
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
foreach ($note in $published) {
    $rel     = $note.FullName.Substring($Vault.Length).TrimStart('\')
    $dest    = Join-Path $Content $rel
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    $text = Get-Content -LiteralPath $note.FullName -Raw -Encoding UTF8
    # Strip Obsidian comments %% ... %% (both inline and spanning multiple lines).
    $text = [regex]::Replace($text, '%%.*?%%', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    [System.IO.File]::WriteAllText($dest, $text, $utf8NoBom)

    Write-Host "  + $rel" -ForegroundColor Green
}

Write-Host ("Synced {0} note(s) to content\." -f @($published).Count) -ForegroundColor Cyan

# --- 4. Copy curated player-safe images --------------------------------------
if (Test-Path $AssetsSrc) {
    $assetDest = Join-Path $Content 'z_Assets\Player Site'
    if (-not (Test-Path $assetDest)) { New-Item -ItemType Directory -Path $assetDest -Force | Out-Null }
    Copy-Item -Path (Join-Path $AssetsSrc '*') -Destination $assetDest -Force
    $n = @(Get-ChildItem -LiteralPath $assetDest -File).Count
    Write-Host "Synced $n image(s) from z_Assets\Player Site." -ForegroundColor Cyan
}

# --- 5. Optionally upload new podcast audio to R2 ----------------------------
if ($UploadAudio) {
    $tokenFile = Join-Path $Site '.upload-token'
    if (-not (Test-Path $tokenFile)) { throw "Missing $tokenFile (see PUBLISHING.md)." }
    $token = (Get-Content $tokenFile -Raw).Trim()
    foreach ($mp3 in Get-ChildItem -LiteralPath $PodcastOut -Filter *.mp3 -File) {
        $head = $null
        try { $head = Invoke-WebRequest -Uri "$SiteHost/audio/$($mp3.Name)" -Method Head -UseBasicParsing -ErrorAction Stop } catch {}
        if ($head -and $head.StatusCode -eq 200) {
            Write-Host "  = $($mp3.Name) already in R2" -ForegroundColor DarkGray
            continue
        }
        Write-Host "  ^ uploading $($mp3.Name) ($([math]::Round($mp3.Length/1MB)) MB)..." -ForegroundColor Yellow
        & curl.exe -sS -f -X PUT "$SiteHost/upload/$($mp3.Name)" -H "Authorization: Bearer $token" --data-binary "@$($mp3.FullName)"
        if ($LASTEXITCODE -ne 0) { throw "Upload failed for $($mp3.Name)" }
        Write-Host ""
    }
    Write-Host "Audio upload check complete. Did you update episodes.json + add the episode page in the vault?" -ForegroundColor Cyan
}

# --- 6. Build locally to validate, then generate the podcast feed ------------
Push-Location $Site
try {
    Write-Host "Building site (validation)..." -ForegroundColor Cyan
    & npx quartz build
    if ($LASTEXITCODE -ne 0) { throw "Quartz build failed (exit $LASTEXITCODE). Fix the error above before publishing." }

    # Sanity check: a healthy build has one HTML page per published note (plus
    # folder/tag pages). If pages went missing (e.g. frontmatter parsing broke
    # and explicit-publish filtered everything), stop before anything deploys.
    $mdCount   = @(Get-ChildItem $Content -Recurse -Filter *.md -File).Count
    $htmlCount = @(Get-ChildItem (Join-Path $Site 'public') -Recurse -Filter *.html -File).Count
    if ($htmlCount -lt $mdCount) {
        throw "Build produced only $htmlCount HTML pages for $mdCount published notes - check the 'Filtered out' line above. NOT deploying."
    }

    & node scripts\generate-feed.mjs
    if ($LASTEXITCODE -ne 0) { throw "Feed generation failed." }

    # --- 7. Optionally publish: GitHub (backup) + Cloudflare (live site) -----
    if ($Push) {
        Write-Host "Committing to GitHub (backup)..." -ForegroundColor Cyan
        # git writes progress to stderr; don't let PowerShell treat that as fatal.
        $eap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & git add -A 2>&1 | ForEach-Object { "$_" } | Write-Host
        & git commit -m $Message 2>&1 | ForEach-Object { "$_" } | Write-Host
        & git push 2>&1 | ForEach-Object { "$_" } | Write-Host
        if ($LASTEXITCODE -ne 0) { $ErrorActionPreference = $eap; throw "git push failed." }
        $ErrorActionPreference = $eap

        Write-Host "Deploying to Cloudflare..." -ForegroundColor Cyan
        & npx wrangler deploy
        if ($LASTEXITCODE -ne 0) { throw "wrangler deploy failed." }
        Write-Host "Live at $SiteHost" -ForegroundColor Green
    }
    else {
        Write-Host "Local build OK. Preview with:  npx quartz build --serve" -ForegroundColor Yellow
        Write-Host "When ready to go live, re-run:  .\publish.ps1 -Push" -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}
