# GTA 6 Clipper setup (Windows): checks what this PC needs, installs what's missing, says when it's ready.
# Safe to re-run any time (it also updates yt-dlp, which fixes most download errors).
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest is 10x slower with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$SkillDir = Split-Path -Parent $PSScriptRoot
$Venv   = Join-Path $SkillDir ".venv"
$Models = Join-Path $SkillDir "models"
$Bin    = Join-Path $SkillDir "bin"
New-Item -ItemType Directory -Force -Path $Models, $Bin | Out-Null
$script:Failed = $false
function Ok($m)   { Write-Host "  [ok]      $m" }
function Inst($m) { Write-Host "  [install] $m" }
function Fail($m) { Write-Host "  [MISSING] $m"; $script:Failed = $true }
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
              [Environment]::GetEnvironmentVariable("Path", "User") + ";" + $env:Path
}
function Find-Exe($name, $extraDirs) {
  foreach ($d in $extraDirs) { $p = Join-Path $d "$name.exe"; if (Test-Path $p) { return $p } }
  $c = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  return $null
}
# Run a native tool quietly. (PowerShell 5.1 turns any stderr text into an error when you use 2>&1,
# and uv/pip print normal progress to stderr, so capture output to files instead.) Returns the exit code.
function Run-Quiet($exe, [string[]]$argv) {
  $o = [IO.Path]::GetTempFileName(); $e = [IO.Path]::GetTempFileName()
  $line = ($argv | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
  $p = Start-Process -FilePath $exe -ArgumentList $line -NoNewWindow -Wait -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  $code = $p.ExitCode
  if ($code -ne 0) { Get-Content $e -Tail 8 | ForEach-Object { Write-Host "            $_" } }
  Remove-Item $o, $e -Force -ErrorAction SilentlyContinue
  return $code
}
$HasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)

Write-Host "GTA 6 Clipper setup (Windows)"
if (-not [Environment]::Is64BitOperatingSystem) { Write-Host "Needs 64-bit Windows 10 or 11."; exit 1 }

# 1. FFmpeg + FFprobe (cutting, encoding, loudness)
$ffDirs = @((Join-Path $Bin "ffmpeg\bin"))
$ff = Find-Exe "ffmpeg" $ffDirs
if (-not $ff -and $HasWinget) {
  Inst "FFmpeg (winget)"
  Run-Quiet "winget" @("install", "--id", "Gyan.FFmpeg", "-e", "--silent", "--accept-source-agreements", "--accept-package-agreements") | Out-Null
  Refresh-Path; $ff = Find-Exe "ffmpeg" $ffDirs
}
if (-not $ff) {
  Inst "FFmpeg (direct download, ~150 MB)"
  $zip = Join-Path $env:TEMP "gta6-ffmpeg.zip"
  try {
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip" -OutFile $zip
    $tmp = Join-Path $env:TEMP "gta6-ffmpeg"; Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    Remove-Item -Recurse -Force (Join-Path $Bin "ffmpeg") -ErrorAction SilentlyContinue
    Move-Item $inner.FullName (Join-Path $Bin "ffmpeg")
    Remove-Item -Force $zip -ErrorAction SilentlyContinue
  } catch { }
  $ff = Find-Exe "ffmpeg" $ffDirs
}
$fp = $null
if ($ff) { $fp = Find-Exe "ffprobe" @((Split-Path $ff)) }
if ($ff -and $fp) { Ok "FFmpeg ($ff)" } else { Fail "FFmpeg (install from https://www.gyan.dev/ffmpeg/builds/ and re-run)" }

# 2. Deno (yt-dlp needs a JavaScript runtime for YouTube)
$denoDirs = @((Join-Path $env:USERPROFILE ".deno\bin"))
$deno = Find-Exe "deno" $denoDirs
if (-not $deno) {
  Inst "Deno"
  try { Invoke-RestMethod https://deno.land/install.ps1 | Invoke-Expression | Out-Null } catch { }
  Refresh-Path; $deno = Find-Exe "deno" $denoDirs
  if (-not $deno -and $HasWinget) {
    Run-Quiet "winget" @("install", "--id", "DenoLand.Deno", "-e", "--silent", "--accept-source-agreements", "--accept-package-agreements") | Out-Null
    Refresh-Path; $deno = Find-Exe "deno" $denoDirs
  }
}
if ($deno) { Ok "Deno" } else { Fail "Deno (https://deno.com, then re-run)" }

# 3. uv (fast Python + venv manager; also brings Python 3.12, no system Python needed)
$uvDirs = @((Join-Path $env:USERPROFILE ".local\bin"), (Join-Path $env:USERPROFILE ".cargo\bin"))
$uv = Find-Exe "uv" $uvDirs
if (-not $uv) {
  Inst "uv"
  try { Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression | Out-Null } catch { }
  Refresh-Path; $uv = Find-Exe "uv" $uvDirs
}
if ($uv) { Ok "uv" } else { Fail "uv (https://docs.astral.sh/uv/, then re-run)" }

# 4. Python environment: yt-dlp (always latest), faster-whisper (speech to text), OpenCV (facecam), Pillow (captions)
$Py = Join-Path $Venv "Scripts\python.exe"
if ($uv) {
  # ARM laptops (Snapdragon): the speech + video libraries only ship for x64, so use x64 Python (runs emulated)
  $PyVer = "3.12"
  if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or $env:PROCESSOR_ARCHITEW6432 -eq "ARM64") { $PyVer = "cpython-3.12-windows-x86_64-none"; Write-Host "  [info]    ARM PC: using x64 Python" }
  if (-not (Test-Path $Py)) { Inst "Python 3.12 environment"; Run-Quiet $uv @("venv", "--python", $PyVer, $Venv) | Out-Null }
  Inst "Python packages (first run downloads ~150 MB)"
  $code = Run-Quiet $uv @("pip", "install", "--python", $Py, "-q", "-U", "yt-dlp[default]", "faster-whisper", "opencv-python-headless", "pillow", "numpy")
  if ($code -eq 0) { Ok "Python packages (yt-dlp, faster-whisper, opencv, pillow, numpy)" } else { Fail "Python packages" }
}

# 5. Whisper model (speech -> text, runs on this PC). Downloaded once (~480 MB).
$WhisperDir = Join-Path $Models "whisper"
if (Test-Path $Py) {
  Inst "Whisper small.en model (skips if already downloaded)"
  $code = Run-Quiet $Py @("-c", "from faster_whisper import WhisperModel; WhisperModel('small.en', device='cpu', compute_type='int8', download_root=r'$WhisperDir')")
  if ($code -eq 0) { Ok "Whisper model" } else { Fail "Whisper model (check your internet and re-run)" }
}

# 6. Face detector (YuNet, ~230 KB) used to find the facecam box
$Yunet = Join-Path $Models "face_detection_yunet_2023mar.onnx"
if (-not (Test-Path $Yunet) -or (Get-Item $Yunet).Length -lt 100000) {
  Inst "YuNet face detector"
  try { Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx" -OutFile $Yunet } catch { }
}
if ((Test-Path $Yunet) -and (Get-Item $Yunet).Length -gt 100000) { Ok "Face detector" } else { Fail "Face detector" }

# 7. Caption font (Windows ships Arial Black)
$Fonts = Join-Path $env:WINDIR "Fonts"
if ((Test-Path (Join-Path $Fonts "ariblk.ttf")) -or (Test-Path (Join-Path $Fonts "impact.ttf"))) { Ok "Caption font (Arial Black)" } else { Write-Host "  [warn]    Arial Black not found, captions use a fallback font" }

# 8. Free space
$drive = (Get-Item $SkillDir).PSDrive
$freeGB = [math]::Floor($drive.Free / 1GB)
if ($freeGB -lt 3) { Write-Host "  [warn]    Only $freeGB GB free. Each stream needs ~0.5-1 GB while it runs." } else { Ok "Disk space ($freeGB GB free)" }

# config.json: absolute tool folders so it works before Claude Code / the terminal is restarted
$dirs = @()
foreach ($x in @($ff, $deno)) { if ($x) { $dirs += (Split-Path $x) } }
$cfg = @{ whisper_model = "small.en"; whisper_dir = $WhisperDir; yunet_model = $Yunet; path_dirs = $dirs }
[IO.File]::WriteAllText((Join-Path $SkillDir "config.json"), ($cfg | ConvertTo-Json -Compress))

if (-not $script:Failed) {
  [IO.File]::WriteAllText((Join-Path $SkillDir ".ready"), (Get-Date).ToString("s"))
  Write-Host ""; Write-Host "READY. Say: clip this stream <link>   or   find me today's biggest GTA 6 streams and clip them"
  exit 0
} else {
  Remove-Item -Force (Join-Path $SkillDir ".ready") -ErrorAction SilentlyContinue
  Write-Host ""; Write-Host "NOT READY: fix the [MISSING] items above and re-run setup."
  exit 1
}
