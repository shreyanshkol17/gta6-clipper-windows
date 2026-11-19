# GTA 6 Clipper for Windows: one-command install.
# Paste into PowerShell (Start menu -> type "PowerShell" -> open it):
#   irm https://raw.githubusercontent.com/vossashtonai/gta6-clipper-windows/main/install.ps1 | iex
# Downloads both skills into your Claude Code skills folder and runs setup. No git, no admin needed.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "Installing GTA 6 Clipper for Windows..."
$Skills = Join-Path $env:USERPROFILE ".claude\skills"
$Zip = Join-Path $env:TEMP "gta6-clipper-windows.zip"
$Tmp = Join-Path $env:TEMP "gta6-clipper-windows"
$Src = if ($env:GTA6_INSTALL_SRC) { $env:GTA6_INSTALL_SRC } else { $null }   # local copy (used by tests)

if (-not $Src) {
  Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/vossashtonai/gta6-clipper-windows/archive/refs/heads/main.zip" -OutFile $Zip
  Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
  Expand-Archive -Path $Zip -DestinationPath $Tmp -Force
  $Src = (Get-ChildItem $Tmp -Directory | Select-Object -First 1).FullName
}

New-Item -ItemType Directory -Force -Path $Skills | Out-Null
foreach ($name in @("gta6-clipper", "gta6-live-clipper")) {
  $dst = Join-Path $Skills $name
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  # copy the skill files over the top: keeps an existing .venv / models / .env, replaces old Mac files
  Copy-Item -Recurse -Force (Join-Path $Src "skills\$name\*") $dst
  $old = Join-Path $dst "scripts\setup.sh"
  if (Test-Path $old) { Remove-Item -Force $old }   # left over from the Mac version
  Write-Host "  [ok]      skill $name -> $dst"
}
Remove-Item -Force $Zip -ErrorAction SilentlyContinue

$ErrorActionPreference = "Continue"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Skills "gta6-clipper\scripts\setup.ps1")
if ($LASTEXITCODE -eq 0) {
  Write-Host ""
  Write-Host "Done. Close and reopen Claude Code, then say: clip this stream <link>"
} else {
  Write-Host ""
  Write-Host "Setup didn't finish. Copy everything above and send it to Claude Code (or post it in the Skool community)."
}
