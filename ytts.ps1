<#
.SYNOPSIS
Downloads YouTube subtitles, analyzes with LLM, and creates a text summary.
.DESCRIPTION
1. Downloads subtitles from a YouTube video
2. Sends subtitles to local LLM (LM Studio) for summarization
3. Creates a text file with the summary
.PARAMETER VideoUrl
YouTube URL to summarize
.PARAMETER OutputDir
Directory to save the summary file (default: current directory)
.PARAMETER Language
Subtitle language (default: en)
.PARAMETER KeepSubtitles
Keep the downloaded subtitle file (default: $false)
.EXAMPLE
.\ytts.ps1 -VideoUrl "https://youtu.be/dQw4w9WgXcQ"
.EXAMPLE
.\ytts.ps1 -VideoUrl "https://youtu.be/VIDEO_ID" -Language es -KeepSubtitles
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$VideoUrl,
    [string]$OutputDir = ".",
    [string]$Language = "en",
    [switch]$KeepSubtitles
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
$tempDir = Join-Path $env:TEMP "youtube_text_summary_$(Get-Random)"
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
    $videoViews = $videoInfoJson.view_count
    $videoDescription = $videoInfoJson.description
    
    Write-Success "Title: $videoTitle"
    Write-Info "Channel: $videoUploader"
    Write-Info "Duration: $([math]::Round($videoDuration/60,1)) minutes"
    Write-Info "Views: $([math]::Round($videoViews/1000,1))K"
    
    # Create safe filename from title
    $safeTitle = $videoTitle -replace '[^\w\s-]', '' -replace '\s+', '_' -replace '^.{0,50}', '$0'
    $outputFile = Join-Path $OutputDir "${safeTitle}_summary.txt"
}
catch {
    Write-ErrorMsg "Failed to fetch video metadata: $_"
    exit 1
}
#endregion

#region Download subtitles
Write-Step "Downloading subtitles in language: $Language"

# Try manual subtitles first
& $ytdlp --write-subs --sub-lang $Language --sub-format srt --skip-download -o "$tempDir\sub" --no-playlist --no-warnings $VideoUrl 2>&1 | Out-Null

$srtFile = Get-ChildItem $tempDir -Filter "*.srt" | Select-Object -First 1

# If no manual subtitles, try auto-generated
if (-not $srtFile) {
    Write-Info "No manual subtitles found, trying auto-generated..."
    & $ytdlp --write-auto-subs --sub-lang $Language --sub-format srt --skip-download -o "$tempDir\sub" --no-playlist --no-warnings $VideoUrl 2>&1 | Out-Null
    $srtFile = Get-ChildItem $tempDir -Filter "*.srt" | Select-Object -First 1
}

if (-not $srtFile) {
    Write-ErrorMsg "No subtitles available for language: $Language"
    Write-Info "Try changing the -Language parameter (e.g., -Language es for Spanish)"
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
        if ($block -match '\d+\r?\n\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}\r?\n(.*)') {
            $text = $matches[1] -replace "`r`n", " "
            if ($text.Trim()) {
                $result += $text.Trim()
            }
        }
    }
    return $result
}

$subtitleTexts = Parse-SRT -path $srtFile.FullName
Write-Info "Parsed $($subtitleTexts.Count) subtitle entries"

if ($subtitleTexts.Count -eq 0) {
    Write-ErrorMsg "No valid subtitle entries found"
    exit 1
}

# Combine all subtitle text
$fullTranscript = $subtitleTexts -join " "
Write-Info "Transcript length: $($fullTranscript.Length) characters"

# Limit transcript size for LLM (8000 chars should be fine for most models)
if ($fullTranscript.Length -gt 8000) {
    $fullTranscript = $fullTranscript.Substring(0, 8000)
    Write-Info "Truncated to 8000 characters for LLM processing"
}
#endregion

#region Send to LLM for summarization
Write-Step "Analyzing with AI (LM Studio)..."
Write-LLM "Requesting LLM to summarize the video content..."

$prompt = @"
You are a video content summarizer. Analyze the following transcript and provide a comprehensive summary.

Video Title: $videoTitle
Channel: $videoUploader
Duration: $([math]::Round($videoDuration/60,1)) minutes

Transcript:
$fullTranscript

Please provide a summary that includes:
1. Main topic/theme of the video
2. Key points covered (3-5 bullet points)
3. Any important conclusions or takeaways

Format your response as:

=== VIDEO SUMMARY ===
[2-3 sentence overview of what the video is about]

=== KEY POINTS ===
• Point 1
• Point 2
• Point 3

=== CONCLUSION ===
[Final thoughts or main takeaway]

Keep the total response under 500 words.
"@

$body = @{
    model = "local-model"
    messages = @(
        @{ role = "system"; content = "You are a helpful assistant that summarizes video transcripts. Provide clear, concise summaries in the requested format." }
        @{ role = "user"; content = $prompt }
    )
    temperature = 0.5
    max_tokens = 1000
} | ConvertTo-Json -Depth 3

try {
    Write-Info "Sending request to LM Studio (may take 30-60 seconds)..."
    $response = Invoke-RestMethod -Uri $lmStudioUrl -Method Post -Headers @{"Content-Type"="application/json"} -Body $body -TimeoutSec 120 -ErrorAction Stop
    
    $summary = $response.choices[0].message.content
    Write-Success "LLM generated summary successfully"
}
catch {
    Write-ErrorMsg "LLM analysis failed: $($_.Exception.Message)"
    Write-Info "Creating fallback summary with basic information"
    
    $summary = @"
=== VIDEO SUMMARY ===
Unable to generate AI summary for: $videoTitle

Channel: $videoUploader
Duration: $([math]::Round($videoDuration/60,1)) minutes
Views: $([math]::Round($videoViews/1000,1))K

=== ERROR ===
The LLM service was not available. Please check that LM Studio is running with a loaded model and the local inference server is enabled on port 1234.

=== VIDEO METADATA ===
Title: $videoTitle
URL: $VideoUrl
Transcript length: $($fullTranscript.Length) characters
Number of subtitle entries: $($subtitleTexts.Count)

=== RECOMMENDATION ===
Check LM Studio settings and ensure:
1. LM Studio is open
2. Local Inference Server is ON (Settings -> Local Inference Server -> toggle ON)
3. A model is loaded
4. Port is set to 1234
"@
}
#endregion

#region Create summary file
Write-Step "Creating summary file..."

# Add metadata header to summary
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$fullOutput = @"
================================================================================
YouTube Video Summary
Generated: $timestamp
================================================================================

$summary

================================================================================
Video Information
================================================================================
Title: $videoTitle
Channel: $videoUploader
URL: $VideoUrl
Duration: $([math]::Round($videoDuration/60,1)) minutes ($videoDuration seconds)
Views: $([math]::Round($videoViews/1000,1))K

================================================================================
Processing Details
================================================================================
Subtitle language: $Language
Subtitle entries processed: $($subtitleTexts.Count)
Transcript length: $($fullTranscript.Length) characters

================================================================================
"@

# Save to file
$fullOutput | Out-File -FilePath $outputFile -Encoding UTF8

if (Test-Path $outputFile) {
    $fileSize = [math]::Round((Get-Item $outputFile).Length / 1KB, 2)
    Write-Success "Summary saved to: $outputFile"
    Write-Info "File size: ${fileSize} KB"
    
    # Display preview
    Write-Step "Summary Preview:"
    Write-Host ""
    $summaryLines = $summary -split "`n" | Select-Object -First 15
    foreach ($line in $summaryLines) {
        Write-Host $line -ForegroundColor Gray
    }
    if (($summary -split "`n").Count -gt 15) {
        Write-Host "... (full summary saved to file)" -ForegroundColor Gray
    }
    Write-Host ""
} else {
    Write-ErrorMsg "Failed to create summary file"
    exit 1
}
#endregion

#region Cleanup
if (-not $KeepSubtitles) {
    Write-Step "Cleaning up temporary files..."
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Info "Temporary files deleted"
} else {
    Write-Info "Temporary files kept in: $tempDir"
    Write-Info "Subtitle file: $($srtFile.FullName)"
}
#endregion

Write-Success "Done! Summary saved to: $outputFile"