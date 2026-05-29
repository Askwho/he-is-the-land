#requires -Version 5.1
<#
.SYNOPSIS
    Publishes selected Obsidian notes to the Barovia player website (Quartz).

.DESCRIPTION
    Finds every note in the vault whose frontmatter contains `publish: true`,
    strips any Obsidian `%% ... %%` comments (your DM-only asides), copies the
    result into Quartz's content folder, then builds the site to validate it.

    Run with -Push to also commit and push to GitHub, which triggers the
    GitHub Actions deploy to your live site.

.EXAMPLE
    .\publish.ps1
        Sync + local build only (safe preview, nothing goes public).

.EXAMPLE
    .\publish.ps1 -Push -Message "Add Session 2 recap"
        Sync, build, then publish live.
#>
[CmdletBinding()]
param(
    [switch]$Push,
    [string]$Message = "Update player site"
)

$ErrorActionPreference = 'Stop'

# --- Paths ------------------------------------------------------------------
$Vault   = 'C:\Users\askew\Documents\DnD\Barovia\Obsidian\HitL'
$Site    = 'C:\Users\askew\Documents\DnD\Barovia\PlayerSite'
$Content = Join-Path $Site 'content'

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

# --- 4. Build locally to validate -------------------------------------------
Push-Location $Site
try {
    Write-Host "Building site (validation)..." -ForegroundColor Cyan
    & npx quartz build
    if ($LASTEXITCODE -ne 0) { throw "Quartz build failed (exit $LASTEXITCODE). Fix the error above before publishing." }

    # --- 5. Optionally commit & push to trigger the GitHub Pages deploy -----
    if ($Push) {
        Write-Host "Publishing to GitHub..." -ForegroundColor Cyan
        & git add -A
        & git commit -m $Message
        & git push
        Write-Host "Pushed. GitHub Actions will rebuild the live site in ~1-2 minutes." -ForegroundColor Green
    }
    else {
        Write-Host "Local build OK. Preview with:  npx quartz build --serve" -ForegroundColor Yellow
        Write-Host "When ready to go live, re-run:  .\publish.ps1 -Push" -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}
