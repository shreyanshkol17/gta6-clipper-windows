"""Real-stream test: the exact commands Claude runs for a user, on real Twitch / YouTube links.

  VOD skill:  prep <url> -> (a scripted pick stands in for Claude's pick) -> render
  LIVE skill: start <live channel> -> next -> pick -> clip -> stop
  discover:   finds GTA 6 streams

python tests/realworld.py --twitch-vod URL --youtube URL --live URL --out DIR
Clips and a frame of each are copied to --out so a person can look at them.
"""
import argparse, json, os, shutil, subprocess, sys, tempfile, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VOD = ROOT / "skills" / "gta6-clipper" / "scripts" / "gta6clip.py"
LIVE = ROOT / "skills" / "gta6-live-clipper" / "scripts" / "live.py"
TMP = Path(tempfile.mkdtemp(prefix="gta6-real-"))
os.environ["GTA6_CLIPS_DIR"] = str(TMP / "clips")
os.environ["GTA6_LIVE_DIR"] = str(TMP / "live")
PY = sys.executable
for _st in (sys.stdout, sys.stderr):
    _st.reconfigure(encoding="utf-8", errors="replace")
results = {}


def sh(args, timeout=3600):
    t = time.time()
    r = subprocess.run([PY] + [str(a) for a in args], capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=timeout)
    print(f"$ {' '.join(str(a) for a in args[1:])}  ({time.time() - t:.0f}s, exit {r.returncode})\n{r.stdout[-2500:]}"
          + (f"\nSTDERR: {r.stderr[-1500:]}" if r.stderr.strip() else ""), flush=True)
    return r


def save(name, ok, **info):
    results[name] = {"ok": bool(ok), **info}
    print(("PASS " if ok else "FAIL ") + name + " " + json.dumps(info), flush=True)


def keep_clip(mp4, out, tag):
    out.mkdir(parents=True, exist_ok=True)
    dst = out / f"{tag}.mp4"
    shutil.copy(mp4, dst)
    shutil.copy(Path(mp4).with_suffix(".txt"), out / f"{tag}.txt")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", "4", "-i", str(dst), "-frames:v", "1",
                    str(out / f"{tag}.jpg")])
    pr = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,width,height:format=duration",
                                    "-of", "json", str(dst)], capture_output=True, text=True).stdout)
    v = [s for s in pr["streams"] if s["codec_type"] == "video"][0]
    return {"size": f"{v['width']}x{v['height']}", "audio": any(s["codec_type"] == "audio" for s in pr["streams"]),
            "sec": round(float(pr["format"]["duration"]), 1)}


def vod_test(tag, url, out):
    r = sh([VOD, "prep", url], timeout=2400)
    runs = [p for p in (TMP / "clips").glob("*") if p.is_dir() and (p / "transcript.json").exists()
            and json.loads((p / "stream.json").read_text(encoding="utf-8"))["url"] == url]
    if not runs:
        return save(f"{tag}: prep", False, error=r.stdout.strip().splitlines()[-1:] or r.stderr[-300:])
    rd = runs[0]
    segs = json.loads((rd / "transcript.json").read_text(encoding="utf-8"))
    save(f"{tag}: prep", len(segs) > 5, segments=len(segs), chunks=len(list((rd / "chunks").glob("*.md"))))
    # stand-in for Claude's pick: 30 s from the middle of the stream
    mid = segs[len(segs) // 2]["start"]
    for c in (rd / "chunks").glob("chunk_*.md"):
        (rd / "picks" / (c.stem + ".json")).write_text("[]", encoding="utf-8")
    ci = int(mid // (12 * 60)) + 1
    (rd / "picks" / f"chunk_{ci:02d}.json").write_text(json.dumps([{
        "start": mid, "end": mid + 30, "score": 8, "category": "test", "title": f"{tag} test clip",
        "hook": "WINDOWS TEST CLIP", "caption": "test", "hashtags": ["#GTA6"]}]), encoding="utf-8")
    sh([VOD, "render", rd], timeout=1800)
    mp4s = sorted((rd / "clips").glob("*.mp4"))
    if not mp4s:
        return save(f"{tag}: render", False)
    info = keep_clip(mp4s[0], out, tag)
    save(f"{tag}: render", info["size"] == "1080x1920" and info["audio"], **info)


def live_test(url, out):
    r = sh([LIVE, "start", url, "--window-min", "2"], timeout=300)
    runs = [p for p in (TMP / "live").glob("*") if p.is_dir()] if (TMP / "live").exists() else []
    if not runs:
        return save("live: start", False, error=r.stdout[-300:])
    rd = runs[0]
    save("live: start", "RECORDING" in r.stdout)
    r = sh([LIVE, "next", rd, "--wait", "540"], timeout=700)
    if "WINDOW:" not in r.stdout:
        sh([LIVE, "stop", rd])
        for f in ("daemon.log", "ytdlp.log", "ffmpeg.log"):
            if (rd / f).exists():
                print(f"--- {f}\n" + (rd / f).read_text(encoding="utf-8", errors="replace")[-2000:])
        return save("live: first window", False)
    save("live: first window", True)
    st = json.loads(sh([LIVE, "status", rd]).stdout)
    save("live: status", st.get("recorder_running") is True, recorded=st.get("recorded"))
    tr = json.loads((rd / "transcript.json").read_text(encoding="utf-8"))
    a = tr[len(tr) // 3]["start"] if tr else 20
    (rd / "picks" / "window_001.json").write_text(json.dumps([{
        "start": a, "end": a + 25, "score": 8, "category": "test", "title": "live test clip",
        "hook": "WINDOWS LIVE TEST", "caption": "test", "hashtags": ["#GTA6"]}]), encoding="utf-8")
    sh([LIVE, "clip", rd], timeout=900)
    mp4s = sorted((rd / "clips").glob("*.mp4"))
    if mp4s:
        info = keep_clip(mp4s[0], out, "live")
        save("live: clip from buffer", info["size"] == "1080x1920" and info["audio"], **info)
    else:
        save("live: clip from buffer", False)
    sh([LIVE, "stop", rd])
    for _ in range(90):
        if json.loads(sh([LIVE, "status", rd]).stdout).get("recorder_running") is False:
            break
        time.sleep(2)
    st = json.loads(sh([LIVE, "status", rd]).stdout)
    save("live: stop", st.get("recorder_running") is False, windows=st.get("windows"))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--twitch-vod"); p.add_argument("--youtube"); p.add_argument("--live")
    p.add_argument("--out", default=str(ROOT / "realworld-out"))
    a = p.parse_args()
    out = Path(a.out)
    r = sh([VOD, "discover", "--limit", "5"], timeout=600)
    save("discover", r.returncode == 0 and "Nothing found" not in r.stdout,
         found=sum(1 for l in r.stdout.splitlines() if l[:1].isdigit()))
    if a.live:
        live_test(a.live, out)
    if a.twitch_vod:
        vod_test("twitch-vod", a.twitch_vod, out)
    if a.youtube:
        vod_test("youtube-vod", a.youtube, out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "results.json").write_text(json.dumps(results, indent=1), encoding="utf-8")
    print("\nRESULTS\n" + "\n".join(f"{'PASS' if v['ok'] else 'FAIL'}  {k}" for k, v in results.items()))
    sys.exit(0 if all(v["ok"] for v in results.values()) else 1)


if __name__ == "__main__":
    main()
