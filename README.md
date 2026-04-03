# 🎬 AI YouTube Video Summarizer

**Two powerful scripts that use local LLMs to summarize YouTube videos - one for text, one for video.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![LM Studio](https://img.shields.io/badge/LM%20Studio-Ready-purple.svg)](https://lmstudio.ai/)

---

## 📖 Description

This project provides two automated tools that leverage **local LLMs** (via LM Studio) to summarize YouTube content without sending any data to the cloud:

### 1. **Text Summarizer** (`ytts.ps1`)
- Downloads video subtitles
- Uses AI to analyze the transcript
- Creates a detailed text summary with key points and conclusions
- Perfect for quickly understanding long videos

### 2. **Video Summarizer** (`yttv.ps1`)
- Downloads video and subtitles
- Uses AI to identify the most important segments
- Creates a short summary video (30-90 seconds)
- Ideal for creating highlights or previews

Both tools are **100% local** - your data never leaves your machine.

---

## ✨ Features

| Feature | Text Summarizer | Video Summarizer |
|---------|:---------------:|:----------------:|
| Extracts subtitles | ✅ | ✅ |
| AI-powered analysis | ✅ | ✅ |
| Creates text summary | ✅ | ❌ |
| Creates summary video | ❌ | ✅ |
| Smart segment selection | ❌ | ✅ |
| Multiple language support | ✅ | ✅ |
| Preserves video metadata | ✅ | ✅ |
| Custom output naming | ✅ | ✅ |

---

## 🎯 About

### Why I built this

YouTube videos are often longer than necessary. Whether you want to:
- Quickly understand a tutorial without watching 30 minutes
- Create highlight reels from long lectures
- Extract key insights from interviews or podcasts
- Generate video summaries for content curation

These tools solve these problems using **local AI models** - no API keys, no cloud costs, no privacy concerns.

### How it works
YouTube URL → yt-dlp download → Subtitle extraction → LLM analysis → Summary output
↓
(Video mode) → Timestamp selection → ffmpeg cutting → Summary video


### Tested Models

This project has been successfully tested with **small, efficient models** that run on modest hardware (Core i3 4th gen):

| Model | Size | Performance | Text Quality | Video Quality |
|-------|------|-------------|--------------|---------------|
| **Qwen3.5-0.8B** | 0.8B | ⚡ Very Fast | 🟡 Good | 🟡 Good |
| **LFM2.5-1.2B** | 1.2B | 🟢 Fast | 🟢 Very Good | 🟢 Very Good |
| **Gemma 3-1B** | 1B | 🟢 Fast | 🟢 Excellent | 🟢 Excellent |

*Note: The 0.8B model works but produces shorter summaries; 3B+ models recommended for best results.*
In my example, LFM2 model create best youtube video summary where Gemma 3 creates best text summary.

---

## 🛠️ Prerequisites

### Required Software

| Tool | Purpose | Download |
|------|---------|----------|
| **PowerShell 5.1+** | Script runtime | Built into Windows |
| **LM Studio** | Local LLM server | [lmstudio.ai](https://lmstudio.ai/) |
| **yt-dlp** | YouTube downloading | [github.com/yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp) |
| **ffmpeg** | Video processing | [ffmpeg.org](https://ffmpeg.org/download.html) |

### LM Studio Setup

1. Download and install [LM Studio](https://lmstudio.ai/)
2. Download a model (e.g., `Qwen3.5-0.8B`, `LFM2.5-1.2B`, or `Gemma 3-1B`)
3. Load the model in the chat pane
4. **Start the Local Inference Server**:
   - Click Settings (gear icon)
   - Find "Local Inference Server"
   - Toggle switch **ON**
   - Ensure port is `1234`

### File Structure

Place all files in the same directory like this:
C:\YourFolder
├── yt-dlp.exe
├── ffmpeg.exe
├── ffprobe.exe
├── ytts.ps1
├── yttv.ps1
├── ytts.bat
└── yttv.bat

## Note:
Example summarize video and its text is added. Please do not absue this code and use it wisely. Thanks.

