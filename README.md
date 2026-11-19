# GTA 6 Clipper (Windows)

Two free Claude Code skills that turn GTA 6 streams into ready-to-post vertical clips.

- **gta6-clipper** clips a stream that has finished. Give it a YouTube, Twitch or Kick link, or nothing and it finds today's biggest GTA 6 streams.
- **gta6-live-clipper** clips a stream while it's still live. A clip is ready about 5 to 8 minutes after the moment happens.

Every clip comes out 1080x1920: facecam on top, gameplay below, a hook title, word-by-word captions, and a post caption with hashtags.

**Windows version** (Windows 10 or 11, 64-bit). On a Mac? Use the Mac version: https://github.com/vossashtonai/gta6-clipper

## Install

### Option A: one command (easiest)

1. Click Start, type **PowerShell**, open it.
2. Paste this and press Enter:

```powershell
irm https://raw.githubusercontent.com/vossashtonai/gta6-clipper-windows/main/install.ps1 | iex
```

3. Wait for **READY** (first time takes 5 to 10 minutes, it downloads about 800 MB).
4. Close and reopen Claude Code, then say **clip this stream** `<link>`.

PowerShell is already on every Windows 10 and 11 PC, nothing to install. If you see red text, copy everything
it printed and paste it into Claude Code: it will fix it for you.

### Option B: paste this into Claude Code

```text
Install the GTA 6 Clipper for Windows from https://github.com/vossashtonai/gta6-clipper-windows.
Clone the repo to a temporary folder, then copy BOTH folders inside its skills/ folder
(gta6-clipper and gta6-live-clipper) into my Claude skills folder (%USERPROFILE%\.claude\skills\)
so they sit side by side.
Then run: powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\skills\gta6-clipper\scripts\setup.ps1"
(use a 10 minute timeout, the first run downloads about 800 MB).
Tell me what it installed and whether it says READY. Then remind me to restart Claude Code.
```

### Option C: as a Claude Code plugin

In Claude Code:

```text
/plugin marketplace add vossashtonai/gta6-clipper-windows
/plugin install gta6-clipper-windows@ashtonvossai-windows
```

Then say **set up the GTA 6 clipper**.

### Option D: by hand (PowerShell)

```powershell
git clone https://github.com/vossashtonai/gta6-clipper-windows.git $env:TEMP\gta6-clipper-windows
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\skills" | Out-Null
Copy-Item -Recurse -Force "$env:TEMP\gta6-clipper-windows\skills\*" "$env:USERPROFILE\.claude\skills\"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\skills\gta6-clipper\scripts\setup.ps1"
```

Setup checks what your PC needs and installs what's missing, no admin rights needed: FFmpeg, Deno, uv,
a Python environment (yt-dlp, faster-whisper, OpenCV, Pillow) and the Whisper speech model (~480 MB).
Re-run it any time downloads start failing; it updates yt-dlp.

You need [Claude Code for Windows](https://docs.claude.com/en/docs/claude-code/setup) (it uses Git for Windows,
which also gives you `git` for the clone).

## Use it

Open Claude Code and say:

- **clip this stream** `<link>`
- **find me today's biggest GTA 6 streams and clip them**
- **live clip** `<link>` (for a stream that's live right now)

Clips land in `GTA6-Clips` in your user folder (`C:\Users\<you>\GTA6-Clips`). Each one has an `.mp4` and a `.txt` with the title, caption and hashtags.

## How it works

| Step | Finished stream | Live stream | Tools |
|---|---|---|---|
| 1. Get the stream | Downloads the audio only (4 h ≈ 220 MB) | Records 1-minute pieces, keeps the last 15 min | yt-dlp, FFmpeg |
| 2. Speech to text | Whole stream in one go | Each minute as it lands | FFmpeg, faster-whisper |
| 3. Find the hype | Loud seconds + YouTube replay chat speed | Loud seconds + live Twitch chat speed | FFmpeg, chat |
| 4. Pick the moments | Claude reads 12-min chunks, best 3 scoring 7+ | Claude reads each 5-min window, any 7.5+ | Claude Code |
| 5. Make the clip | Downloads only those minutes | Cuts from the pieces already on your PC | OpenCV, faster-whisper, Pillow, FFmpeg |

Chat is counted, never read: 10-second buckets, a spike is 8+ messages at 2.5x the normal rate. Loud means 9 dB above the streamer's own normal. The facecam is found by looking for a face, and box edges, that stay still while the gameplay moves.

## Run it free

Picking (step 4) is the only part that uses AI. Everything else runs on your PC. To run without a Claude subscription:

1. Install [Ollama](https://ollama.com).
2. Check your memory (Settings → System → About → Installed RAM). 16 GB: `ollama pull qwen3.5:9b`. 32 GB or more: `ollama pull qwen3.5:27b`.
3. In PowerShell: `ollama launch claude` and pick the model.
4. Same prompts as above.

The free model is slower and its picks are rougher than Claude's. Expect some back and forth.

## Good to know

- Installed the Mac version by mistake (it says "Mac only")? Just run the one command above: it replaces it.
- Use Claude Code for Windows itself (the desktop app or `claude` in PowerShell / Git Bash), not Claude Code inside WSL.

- Age-restricted YouTube streams and Kick need your browser login. Tell Claude to use `--cookies firefox`. Chrome and Edge lock their cookies on Windows, so use Firefox or an exported cookies.txt.
- YouTube streams that are still live can be clipped by the finished-stream skill once the replay is up. Twitch past broadcasts work while the stream is still going.
- Twitch in "find me streams" is optional: create a free app at [dev.twitch.tv/console](https://dev.twitch.tv/console) and put `TWITCH_CLIENT_ID` and `TWITCH_CLIENT_SECRET` in `skills\\gta6-clipper\\.env` (see `.env.example`).
- Live clipping needs the Claude Code session to stay open, and run at most 2 streams at once on a 16 GB PC.
- Clip streamers who are fine with clipping, and watch every clip before you post it.
- YouTube ad money needs the Partner Program, and YouTube can refuse it for reposted, mass-made content. Add something of your own.

## Made by

[Ashton Voss AI](https://www.youtube.com/@ashtonvossai). More free AI systems in the AI Alliance Community.

MIT licensed.
