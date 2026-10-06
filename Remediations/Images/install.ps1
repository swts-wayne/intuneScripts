# ============================================================================
# SWTS - Immich Folder Watch Configuration
# Platform Script - User Context
# Runs at every sign-in
# ============================================================================

# ----------------------------------------------------------------------------
# CONFIGURATION
# ----------------------------------------------------------------------------

$ImmichApiUrl = "https://YOUR_URL_HERE/api"
$ImmichApiKey = "REPLACE_WITH_API_KEY"

# ----------------------------------------------------------------------------
# PATHS
# ----------------------------------------------------------------------------

$ImageFolder  = "C:\resources\images"

$ConfigFolder = Join-Path `
    $env:LOCALAPPDATA `
    "Immich Folder Watch"

$ConfigFile = Join-Path `
    $ConfigFolder `
    "config.yaml"

# ----------------------------------------------------------------------------
# EXIT IF ALREADY CONFIGURED
# ----------------------------------------------------------------------------

if (Test-Path $ConfigFile) {
    Write-Host "Immich Folder Watch already configured."
    exit 0
}

# ----------------------------------------------------------------------------
# CREATE IMAGE FOLDER
# ----------------------------------------------------------------------------

if (-not (Test-Path $ImageFolder)) {

    New-Item `
        -ItemType Directory `
        -Path $ImageFolder `
        -Force | Out-Null
}

# ----------------------------------------------------------------------------
# CREATE DESKTOP SHORTCUT
# ----------------------------------------------------------------------------

$DesktopPath = [Environment\]::GetFolderPath("Desktop")

$ShortcutPath = Join-Path `
    $DesktopPath `
    "Images.lnk"

if (-not (Test-Path $ShortcutPath)) {

    $Shell = New-Object -ComObject WScript.Shell

    $Shortcut = $Shell.CreateShortcut($ShortcutPath)

    $Shortcut.TargetPath = $ImageFolder
    $Shortcut.WorkingDirectory = $ImageFolder
    $Shortcut.IconLocation = "shell32.dll,4"

    $Shortcut.Save()
}

# ----------------------------------------------------------------------------
# CREATE CONFIG FOLDER
# ----------------------------------------------------------------------------

if (-not (Test-Path $ConfigFolder)) {

    New-Item `
        -ItemType Directory `
        -Path $ConfigFolder `
        -Force | Out-Null
}

# ----------------------------------------------------------------------------
# WRITE CONFIG
# ----------------------------------------------------------------------------

$Config = @"
immich:
  serverApiUrl: $ImmichApiUrl
  apiKey: $ImmichApiKey

watch:
  sources:
  - path: C:\resources\images
    albumName: AI Showcase
    includeSubdirectories: false
    extensions:
    - .3fr
    - .3gp
    - .3gpp
    - .ari
    - .arw
    - .avi
    - .avif
    - .bmp
    - .cap
    - .cin
    - .cr2
    - .cr3
    - .crw
    - .dcr
    - .dng
    - .erf
    - .fff
    - .flv
    - .gif
    - .heic
    - .heif
    - .hif
    - .iiq
    - .insp
    - .insv
    - .jp2
    - .jpe
    - .jpeg
    - .jpg
    - .jxl
    - .k25
    - .kdc
    - .m2t
    - .m2ts
    - .m4v
    - .mkv
    - .mov
    - .mp4
    - .mpe
    - .mpeg
    - .mpg
    - .mrw
    - .mts
    - .nef
    - .nrw
    - .orf
    - .ori
    - .pef
    - .png
    - .psd
    - .raf
    - .raw
    - .rw2
    - .rwl
    - .sr2
    - .srf
    - .srw
    - .svg
    - .tif
    - .tiff
    - .vob
    - .webm
    - .webp
    - .wmv
    - .x3f
    excludeDirectories: []
    excludeFileNames: []
    syncMode: uploadNew
    deleteAfterUpload: false

  transferOrder: newestFirst
  batchIntervalSeconds: 5
  maxBatchSize: 25
  fileReadyTimeoutSeconds: 30

retry:
  maxAttempts: 5
  baseDelayMilliseconds: 500

logging:
  level: Information
  target: eventLog

localization:
  language: auto
"@

$Config | Set-Content `
    -Path $ConfigFile `
    -Encoding UTF8 `
    -Force

Write-Host "Immich Folder Watch configuration created."

exit 0