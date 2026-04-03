<#
.SYNOPSIS
Downloads a YouTube video (max 720p), analyzes subtitles with LLM, and creates a summarized version.
Compatible with the summarize.bat menu system.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$VideoUrl,
    [int]$SummaryDuration = 60,
    [int]$NumSegments = 5,
    [string]$OutputFile = "summary_output.mp4",
    [switch]$KeepFiles
)

#region Helper functions
function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-ErrorMsg($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-Success($msg) { Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-LLM($msg) { Write-Host "[LLM] $msg" -ForegroundColor Magenta }
function Write-Step($msg) { Write-Host "[STEP] $msg" -ForegroundColor Yellow }
#endregion

#region Check dependencies
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Step "Checking dependencies..."

# Check for yt-dlp
$ytdlp = $null
if (Test-Path (Join-Path $scriptDir "yt-dlp.exe")) {
    $ytdlp = Join-Path $scriptDir "yt-dlp.exe"
    Write-Info "Found yt-dlp.exe"
}
elseif (Get-Command "yt-dlp" -ErrorAction SilentlyContinue) {
    $ytdlp = "yt-dlp"
    Write-Info "Found yt-dlp in PATH"
}
else {
    Write-ErrorMsg "yt-dlp.exe not found. Download from: https://github.com/yt-dlp/yt-dlp/releases"
    exit 1
}

# Check for ffmpeg
$ffmpeg = $null
if (Test-Path (Join-Path $scriptDir "ffmpeg.exe")) {
    $ffmpeg = Join-Path $scriptDir "ffmpeg.exe"
    Write-Info "Found ffmpeg.exe"
}
elseif (Get-Command "ffmpeg" -ErrorAction SilentlyContinue) {
    $ffmpeg = "ffmpeg"
    Write-Info "Found ffmpeg in PATH"
}
else {
    Write-ErrorMsg "ffmpeg.exe not found. Download from: https://ffmpeg.org/download.html"
    exit 1
}

# Test LM Studio connection
$lmStudioUrl = "http://localhost:1234/v1/chat/completions"
Write-Step "Checking LM Studio connection..."

try {
    $testBody = '{"model":"local-model","messages":[{"role":"user","content":"test"}],"max_tokens":5}'
    $testResponse = Invoke-RestMethod -Uri $lmStudioUrl -Method Post -Headers @{"Content-Type"="application/json"} -Body $testBody -TimeoutSec 10 -ErrorAction Stop
    Write-Success "LM Studio is responding on port 1234"
}
catch {
    Write-ErrorMsg "LM Studio not responding! Please ensure:"
    Write-Info "  1. LM Studio is open"
    Write-Info "  2. Local Inference Server is ON (Settings -> Local Inference Server -> toggle ON)"
    Write-Info "  3. Port is set to 1234"
    Write-Info "  4. A model is loaded"
    exit 1
}
#endregion

#region Create temp directory
$tempDir = Join-Path $env:TEMP "youtube_summary_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
Write-Info "Working directory: $tempDir"
#endregion

#region Get video metadata
Write-Step "Fetching video information..."
try {
    $videoInfoJson = & $ytdlp --dump-json --skip-download --no-warnings $VideoUrl 2>$null | ConvertFrom-Json
    $videoTitle = $videoInfoJson.title
    $videoUploader = $videoInfoJson.uploader
    $videoDuration = $videoInfoJson.duration
    
    Write-Success "Title: $videoTitle"
    Write-Info "Channel: $videoUploader"
    Write-Info "Duration: $([math]::Round($videoDuration/60,1)) minutes"
    
    # Generate a clean filename from title
    $safeTitle = $videoTitle -replace '[^\w\s-]', '' -replace '\s+', '_' -replace '^.{0,50}', '$0'
    if ($OutputFile -eq "summary_output.mp4") {
        $OutputFile = "summary_${safeTitle}.mp4"
    }
}
catch {
    Write-Info "Could not fetch metadata, continuing anyway..."
    $videoTitle = "Unknown_Title"
}
#endregion

#region Download video (prioritize 720p or lower for speed)
Write-Step "Downloading video (720p or lower for fast download)..."
Write-Info "URL: $VideoUrl"
$videoFile = Join-Path $tempDir "video.mp4"

# Format selectors prioritized for speed and reasonable quality
$formatSelectors = @(
    "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720][ext=mp4]",
    "best[height<=720]",
    "bestvideo[height<=480]+bestaudio/best[height<=480]",
    "best[height<=480]",
    "best[height<=360]",
    "worst[ext=mp4]",
    "worst"
)

$downloaded = $false
foreach ($format in $formatSelectors) {
    Write-Info "Trying format: $format"
    
    try {
        & $ytdlp -f $format -o "$videoFile" --no-playlist --no-warnings $VideoUrl
        
        if (Test-Path $videoFile) {
            $fileSize = (Get-Item $videoFile).Length / 1MB
            Write-Success "Downloaded: $([math]::Round($fileSize,2)) MB"
            $downloaded = $true
            break
        }
    }
    catch {
        Write-Info "Format failed, trying next..."
    }
}

if (-not $downloaded -or -not (Test-Path $videoFile)) {
    Write-ErrorMsg "Failed to download video"
    exit 1
}
#endregion

#region Download subtitles
Write-Step "Downloading subtitles..."

& $ytdlp --write-subs --sub-lang en --sub-format srt --skip-download -o "$tempDir\sub" --no-playlist --no-warnings $VideoUrl 2>&1 | Out-Null

$srtFile = Get-ChildItem $tempDir -Filter "*.srt" | Select-Object -First 1
if (-not $srtFile) {
    Write-Info "No manual subtitles, trying auto-generated..."
    & $ytdlp --write-auto-subs --sub-lang en --sub-format srt --skip-download -o "$tempDir\sub" --no-playlist --no-warnings $VideoUrl 2>&1 | Out-Null
    $srtFile = Get-ChildItem $tempDir -Filter "*.srt" | Select-Object -First 1
}

if (-not $srtFile) {
    Write-ErrorMsg "No subtitles available for this video"
    Write-Info "Cannot create summary without subtitles"
    exit 1
}
Write-Success "Subtitles downloaded: $($srtFile.Name)"
#endregion

#region Parse subtitles
Write-Step "Parsing subtitles..."

function Parse-SRT {
    param([string]$path)
    $content = Get-Content $path -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return @() }
    
    $blocks = $content -split "`r`n`r`n"
    $result = @()
    
    foreach ($block in $blocks) {
        if ($block -match '(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})') {
            $start = $matches[1] -replace ',', '.'
            $end = $matches[2] -replace ',', '.'
            $text = ($block -split "`r`n" | Select-Object -Skip 2) -join " "
            
            $result += [PSCustomObject]@{
                Start = $start
                End = $end
                Text = $text.Trim()
            }
        }
    }
    return $result
}

$subtitles = Parse-SRT -path $srtFile.FullName
Write-Info "Parsed $($subtitles.Count) subtitle entries"

if ($subtitles.Count -eq 0) {
    Write-ErrorMsg "No valid subtitle entries found"
    exit 1
}

# Create condensed version for LLM (limit to 3000 chars for small model)
$condensedText = @()
$charCount = 0
foreach ($sub in $subtitles) {
    $line = "$($sub.Start) - $($sub.Text)"
    if ($charCount + $line.Length -gt 3000) { break }
    $condensedText += $line
    $charCount += $line.Length
}
$llmInput = $condensedText -join "`n"
Write-Info "LLM input: $charCount characters"
#endregion

#region Get timestamps from LLM
Write-Step "Analyzing with AI (LM Studio)..."
Write-LLM "Requesting LLM to find the $NumSegments most important segments..."

$prompt = @"
Select the $NumSegments most important parts from this video transcript for a $SummaryDuration-second summary.

Transcript with timestamps:
$llmInput

Output ONLY a JSON array like this (no other text, no markdown):
[
  {"start": "00:01:23.456", "end": "00:01:45.789"},
  {"start": "00:02:10.123", "end": "00:02:30.456"}
]

Rules:
- Use EXACT timestamps from the transcript above
- Each segment should be 10-30 seconds long
- Segments must be in chronological order
- Total duration should be approximately $SummaryDuration seconds
"@

$body = @{
    model = "local-model"
    messages = @(
        @{ role = "system"; content = "You are a helpful assistant that extracts timestamps from video transcripts. Output ONLY valid JSON arrays." }
        @{ role = "user"; content = $prompt }
    )
    temperature = 0.3
    max_tokens = 500
} | ConvertTo-Json -Depth 3

$segments = $null

try {
    Write-Info "Sending request to LM Studio (may take 30-60 seconds)..."
    $response = Invoke-RestMethod -Uri $lmStudioUrl -Method Post -Headers @{"Content-Type"="application/json"} -Body $body -TimeoutSec 120 -ErrorAction Stop
    
    $content = $response.choices[0].message.content
    Write-LLM "Raw response received"
    
    # Clean up response
    $content = $content -replace '```json\s*', '' -replace '```', '' -replace '`', ''
    
    # Try to extract JSON array
    if ($content -match '\[\s*\{.*\}\s*\]') {
        $jsonMatch = $matches[0]
        $segments = $jsonMatch | ConvertFrom-Json
    } else {
        $segments = $content | ConvertFrom-Json -ErrorAction SilentlyContinue
    }
    
    if ($segments -and $segments.Count -gt 0) {
        Write-Success "LLM selected $($segments.Count) segments"
        foreach ($seg in $segments) {
            Write-Info "  $($seg.start) → $($seg.end)"
        }
    } else {
        throw "No valid segments in response"
    }
}
catch {
    Write-ErrorMsg "LLM analysis failed: $($_.Exception.Message)"
    Write-Info "Using fallback - evenly spaced segments"
    
    # Fallback: evenly distribute segments throughout video
    $totalDuration = [TimeSpan]::Parse($subtitles[-1].End).TotalSeconds
    $segmentDuration = $totalDuration / $NumSegments
    
    $segments = @()
    for ($i = 0; $i -lt $NumSegments; $i++) {
        $targetTime = ($i + 0.5) * $segmentDuration
        $closest = $subtitles | Sort-Object { [Math]::Abs([TimeSpan]::Parse($_.Start).TotalSeconds - $targetTime) } | Select-Object -First 1
        
        $start = $closest.Start
        $endTime = [Math]::Min([TimeSpan]::Parse($closest.Start).TotalSeconds + 15, $totalDuration)
        $end = [TimeSpan]::FromSeconds($endTime).ToString("hh\:mm\:ss\.fff")
        
        $segments += [PSCustomObject]@{ start = $start; end = $end }
        Write-Info "  Fallback $($i+1): $start → $end"
    }
}

if (-not $segments -or $segments.Count -eq 0) {
    Write-ErrorMsg "No segments available to cut"
    exit 1
}
#endregion

#region Cut and concatenate segments
Write-Step "Cutting video segments..."

$concatFile = Join-Path $tempDir "concat.txt"
$segmentFiles = @()
$successCount = 0

for ($i = 0; $i -lt $segments.Count; $i++) {
    $seg = $segments[$i]
    $segmentFile = Join-Path $tempDir "seg_$i.mp4"
    
    Write-Info "Cutting segment $($i+1)/$($segments.Count): $($seg.start) to $($seg.end)"
    
    $cutArgs = @(
        "-i", "$videoFile",
        "-ss", $seg.start,
        "-to", $seg.end,
        "-c", "copy",
        "-avoid_negative_ts", "make_zero",
        "-y",
        "$segmentFile"
    )
    
    $process = Start-Process -FilePath $ffmpeg -ArgumentList $cutArgs -NoNewWindow -Wait -PassThru
    
    if ($process.ExitCode -eq 0 -and (Test-Path $segmentFile) -and (Get-Item $segmentFile).Length -gt 0) {
        $segmentFiles += $segmentFile
        Add-Content -Path $concatFile -Value "file '$segmentFile'"
        $successCount++
        Write-Success "  Segment $($i+1) cut successfully"
    } else {
        Write-ErrorMsg "  Failed to cut segment $($i+1)"
    }
}

if ($segmentFiles.Count -eq 0) {
    Write-ErrorMsg "No segments were successfully cut"
    exit 1
}

Write-Info "Successfully cut $successCount of $($segments.Count) segments"

# Concatenate all segments
Write-Step "Creating final summary video..."

$concatArgs = @(
    "-f", "concat",
    "-safe", "0",
    "-i", "$concatFile",
    "-c", "copy",
    "-y", "$OutputFile"
)

$process = Start-Process -FilePath $ffmpeg -ArgumentList $concatArgs -NoNewWindow -Wait -PassThru

if (Test-Path $OutputFile) {
    $size = [math]::Round((Get-Item $OutputFile).Length / 1MB, 2)
    
    Write-Success "=" * 60
    Write-Success "SUMMARY VIDEO CREATED SUCCESSFULLY!"
    Write-Success "File: $OutputFile"
    Write-Success "Size: ${size} MB"
    Write-Success "=" * 60
} else {
    Write-ErrorMsg "Failed to create summary video"
    exit 1
}
#endregion

#region Cleanup
if (-not $KeepFiles) {
    Write-Step "Cleaning up temporary files..."
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Info "Temporary files deleted"
} else {
    Write-Info "Temporary files kept in: $tempDir"
}
#endregion

Write-Success "Done!"