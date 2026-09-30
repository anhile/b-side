#!/usr/bin/env python3
"""Experiment 1: which public tracks have time-synced lyrics, and where.

For each search in TRACKS it asks YouTube Music (signed out) for the track,
then its lyrics page as the web client and as the Android client, and LRCLIB
by the track's metadata. Where both sources have timings it compares the
start times of lines with the same words.

Only counts, sizes, times and public track metadata are written. No lyrics
text is kept. Standard library only.

    python3 spikes/live-lyrics/coverage.py            # all tracks
    python3 spikes/live-lyrics/coverage.py 3          # the first 3, for a try
"""

import json
import re
import statistics
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
RESULTS = HERE / "results"

YTM = "https://music.youtube.com"
API = YTM + "/youtubei/v1/{}?prettyPrint=false"
LRCLIB = "https://lrclib.net/api/"
LRCLIB_AGENT = "B-Side research spike (live lyrics coverage; no key)"
WEB_AGENT = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
             "(KHTML, like Gecko) Version/26.0 Safari/605.1.15")
# ytmusicapi's version, and a newer one to see whether the version matters.
ANDROID_VERSIONS = ["7.21.50", "8.30.54"]
# YouTube Music search filters, from ytmusicapi.
SONGS = "EgWKAQIIAWoMEA4QChADEAQQCRAF"
VIDEOS = "EgWKAQIQAWoMEA4QChADEAQQCRAF"
PAUSE = 0.6  # seconds between requests to the same service

# (search, group, filter)
TRACKS = [
    ("Blinding Lights The Weeknd", "pop", SONGS),
    ("Shape of You Ed Sheeran", "pop", SONGS),
    ("bad guy Billie Eilish", "pop", SONGS),
    ("Levitating Dua Lipa", "pop", SONGS),
    ("As It Was Harry Styles", "pop", SONGS),
    ("Anti-Hero Taylor Swift", "pop", SONGS),
    ("Espresso Sabrina Carpenter", "pop", SONGS),
    ("Bohemian Rhapsody Queen", "rock-old", SONGS),
    ("Smells Like Teen Spirit Nirvana", "rock-old", SONGS),
    ("Hotel California Eagles", "rock-old", SONGS),
    ("Wonderwall Oasis", "rock-old", SONGS),
    ("Billie Jean Michael Jackson", "rock-old", SONGS),
    ("Hey Jude The Beatles", "rock-old", SONGS),
    ("Take On Me a-ha", "rock-old", SONGS),
    ("SICKO MODE Travis Scott", "hip-hop", SONGS),
    ("HUMBLE. Kendrick Lamar", "hip-hop", SONGS),
    ("Lose Yourself Eminem", "hip-hop", SONGS),
    ("God's Plan Drake", "hip-hop", SONGS),
    ("Plug Walk Rich The Kid", "hip-hop", SONGS),
    ("Каста Вокруг шум", "russian", SONGS),
    ("Кино Группа крови", "russian", SONGS),
    ("Земфира Хочешь", "russian", SONGS),
    ("Сплин Выхода нет", "russian", SONGS),
    ("Баста Сансара", "russian", SONGS),
    ("Мумий Тролль Владивосток 2000", "russian", SONGS),
    ("Макс Корж Малиновый закат", "russian", SONGS),
    ("Монеточка Каждый раз", "russian", SONGS),
    ("ЛСП Монетка", "russian", SONGS),
    ("Dynamite BTS", "k-pop", SONGS),
    ("How You Like That BLACKPINK", "k-pop", SONGS),
    ("Super Shy NewJeans", "k-pop", SONGS),
    ("Despacito Luis Fonsi", "latin", SONGS),
    ("Tití Me Preguntó Bad Bunny", "latin", SONGS),
    ("Alors on danse Stromae", "other", SONGS),
    ("Du hast Rammstein", "other", SONGS),
    ("Gangnam Style PSY official video", "video", VIDEOS),
    ("Rick Astley Never Gonna Give You Up official video", "video", VIDEOS),
    ("The Weeknd Blinding Lights official video", "video", VIDEOS),
    ("Queen Bohemian Rhapsody Live Aid 1985", "live", VIDEOS),
    ("Nirvana Where Did You Sleep Last Night MTV Unplugged", "live", VIDEOS),
]


def log(*parts):
    line = "\t".join(str(p) for p in parts)
    print(line, flush=True)
    with open(RESULTS / "coverage.log", "a") as f:
        f.write(time.strftime("%Y-%m-%dT%H:%M:%S") + "\t" + line + "\n")


def request(url, body=None, headers=None):
    """Returns (status, text, bytes, milliseconds)."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers or {})
    if data is not None:
        req.add_header("Content-Type", "application/json")
    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read()
            status = resp.status
    except urllib.error.HTTPError as e:
        raw, status = e.read(), e.code
    except Exception as e:  # network trouble is a result too
        return 0, str(e), 0, int((time.monotonic() - start) * 1000)
    ms = int((time.monotonic() - start) * 1000)
    return status, raw.decode("utf-8", "replace"), len(raw), ms


def walk(node, key):
    """Every value stored under `key`, anywhere in the tree."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == key:
                yield v
            yield from walk(v, key)
    elif isinstance(node, list):
        for v in node:
            yield from walk(v, key)


def first(node, key):
    return next(walk(node, key), None)


def runs(node):
    return "".join(r.get("text", "") for r in (node or {}).get("runs", []))


# --- YouTube Music ------------------------------------------------------------

def web_version():
    _, html, _, _ = request(YTM + "/", headers={"User-Agent": WEB_AGENT, "Cookie": "SOCS=CAI"})
    m = re.search(r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"', html)
    return m.group(1) if m else "1.20260928.01.00"


def web(endpoint, body, version):
    context = {"client": {"clientName": "WEB_REMIX", "clientVersion": version, "hl": "en", "gl": "US"}}
    return request(API.format(endpoint), dict(body, context=context),
                   {"User-Agent": WEB_AGENT, "Origin": YTM, "Cookie": "SOCS=CAI"})


def android(endpoint, body, version):
    context = {"client": {"clientName": "ANDROID_MUSIC", "clientVersion": version,
                          "androidSdkVersion": 34, "hl": "en", "gl": "US"}}
    return request(API.format(endpoint), dict(body, context=context), {
        "User-Agent": f"com.google.android.apps.youtube.music/{version} (Linux; U; Android 14) gzip",
        "X-YouTube-Client-Name": "21",
        "X-YouTube-Client-Version": version,
    })


def find_track(query, params, version):
    status, text, _, _ = web("search", {"query": query, "params": params}, version)
    if status != 200:
        return None
    tree = json.loads(text)
    for item in walk(tree, "musicResponsiveListItemRenderer"):
        video = first(item.get("playlistItemData", {}), "videoId") or first(item.get("overlay", {}), "videoId")
        if video:
            return video
    return None


def describe(video, version):
    """Title, artist, album, seconds, video type and lyrics page, from /next."""
    status, text, _, _ = web("next", {"videoId": video}, version)
    if status != 200:
        return None
    tree = json.loads(text)
    panel = first(tree, "playlistPanelVideoRenderer") or {}
    byline = [r.get("text", "") for r in panel.get("longBylineText", {}).get("runs", [])]
    parts = [p.strip() for p in "".join(byline).split("•")]
    length = runs(panel.get("lengthText"))
    seconds = 0
    for piece in length.split(":"):
        seconds = seconds * 60 + int(piece or 0)
    page = re.search(r'"browseId":"(MPLYt[^"]*)"', text)
    return {
        "title": runs(panel.get("title")),
        "artist": parts[0] if parts else "",
        "album": parts[1] if len(parts) > 2 else "",
        "seconds": seconds,
        "type": (first(panel, "musicVideoType") or "").replace("MUSIC_VIDEO_TYPE_", ""),
        "page": page.group(1) if page else "",
    }


def web_lyrics(page, version):
    status, text, size, ms = web("browse", {"browseId": page}, version)
    if status != 200:
        return {"status": status, "plain": False, "bytes": size, "ms": ms}
    shelf = first(json.loads(text), "musicDescriptionShelfRenderer")
    return {"status": status, "plain": bool(shelf and runs(shelf.get("description"))),
            "bytes": size, "ms": ms}


def android_lyrics(page, version):
    status, text, size, ms = android("browse", {"browseId": page}, version)
    result = {"status": status, "timed": False, "lines": 0, "plain": False, "bytes": size, "ms": ms,
              "source": "", "cues": []}
    if status != 200:
        return result
    tree = json.loads(text)
    model = first(tree, "timedLyricsModel")
    data = (model or {}).get("lyricsData", {})
    cues = data.get("timedLyricsData") or []
    if cues and all("cueRange" in c for c in cues):
        result.update(timed=True, lines=len(cues), source=data.get("sourceMessage", ""),
                      cues=[(int(c["cueRange"]["startTimeMilliseconds"]), c.get("lyricLine", "")) for c in cues])
    result["plain"] = bool(first(tree, "musicDescriptionShelfRenderer")) or bool(result["cues"])
    return result


# --- LRCLIB -------------------------------------------------------------------

def lrclib_get(title, artist, album, seconds):
    query = {"track_name": title, "artist_name": artist, "duration": seconds}
    if album:
        query["album_name"] = album
    status, text, size, ms = request(LRCLIB + "get?" + urllib.parse.urlencode(query),
                                     headers={"User-Agent": LRCLIB_AGENT})
    time.sleep(PAUSE)
    if status != 200:
        return {"status": status, "synced": False, "ms": ms, "bytes": size, "cues": [], "duration": 0}
    item = json.loads(text)
    return lrclib_item(item, status, ms, size)


def lrclib_search(title, artist, seconds):
    query = {"track_name": title, "artist_name": artist}
    status, text, size, ms = request(LRCLIB + "search?" + urllib.parse.urlencode(query),
                                     headers={"User-Agent": LRCLIB_AGENT})
    time.sleep(PAUSE)
    if status != 200:
        return {"status": status, "synced": False, "ms": ms, "bytes": size, "cues": [], "duration": 0}
    items = [i for i in json.loads(text) if i.get("syncedLyrics")]
    # The closest length wins; farther than 10 s is another edit.
    items.sort(key=lambda i: abs((i.get("duration") or 0) - seconds))
    if not items or abs((items[0].get("duration") or 0) - seconds) > 10:
        return {"status": status, "synced": False, "ms": ms, "bytes": size, "cues": [], "duration": 0}
    return lrclib_item(items[0], status, ms, size)


LRC_LINE = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\](.*)")


def lrclib_item(item, status, ms, size):
    cues = []
    for line in (item.get("syncedLyrics") or "").splitlines():
        m = LRC_LINE.match(line)
        if m:
            cues.append((int((int(m.group(1)) * 60 + float(m.group(2))) * 1000), m.group(3).strip()))
    return {"status": status, "synced": bool(cues), "ms": ms, "bytes": size, "cues": cues,
            "duration": item.get("duration") or 0}


def clean_title(title):
    title = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", "", title)           # (feat. X), [Official Video]
    title = re.sub(r"\s+-\s+.*(remaster|version|edit|live|mix).*$", "", title, flags=re.I)
    return title.strip()


def clean_artist(artist):
    return re.split(r"\s*(?:,|&| x | and | feat\.? )\s*", artist, maxsplit=1, flags=re.I)[0].strip()


# --- Comparison ---------------------------------------------------------------

def norm(text):
    text = unicodedata.normalize("NFKC", text).lower()
    return re.sub(r"[^\w]+", " ", text).strip()


def offset(yt, lrc):
    """Median of YouTube minus LRCLIB start times over lines with the same words."""
    remaining = list(lrc)
    diffs = []
    for start, line in yt:
        key = norm(line)
        if not key:
            continue
        for i, (other, text) in enumerate(remaining):
            if norm(text) == key:
                diffs.append(start - other)
                del remaining[: i + 1]
                break
    if len(diffs) < 3:
        return None, len(diffs), None
    median = statistics.median(diffs)
    spread = statistics.median([abs(d - median) for d in diffs])
    return int(median), len(diffs), int(spread)


# --- Run ----------------------------------------------------------------------

COLUMNS = ["group", "search", "type", "title", "artist", "seconds", "has_page",
           "web_plain", "web_ms", "web_kb"] + \
          [f"android_{v}_{c}" for v in ANDROID_VERSIONS for c in ("status", "timed", "lines", "ms", "kb")] + \
          ["lrclib_raw", "lrclib_clean", "lrclib_search", "lrclib_ms", "lrclib_len_diff",
           "offset_ms", "matched_lines", "offset_spread_ms", "yt_source"]


def main():
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else len(TRACKS)
    RESULTS.mkdir(exist_ok=True)
    version = web_version()
    log("start", f"web client {version}", f"android {', '.join(ANDROID_VERSIONS)}", f"{limit} tracks")
    rows = []
    for query, group, params in TRACKS[:limit]:
        row = dict.fromkeys(COLUMNS, "")
        row.update(group=group, search=query)
        video = find_track(query, params, version)
        time.sleep(PAUSE)
        info = describe(video, version) if video else None
        time.sleep(PAUSE)
        if not info:
            log(query, "not found")
            rows.append(row)
            continue
        row.update(type=info["type"], title=info["title"], artist=info["artist"],
                   seconds=info["seconds"], has_page="yes" if info["page"] else "no")

        yt_cues = []
        if info["page"]:
            w = web_lyrics(info["page"], version)
            row.update(web_plain="yes" if w["plain"] else "no", web_ms=w["ms"], web_kb=round(w["bytes"] / 1024, 1))
            time.sleep(PAUSE)
            for v in ANDROID_VERSIONS:
                a = android_lyrics(info["page"], v)
                row.update({f"android_{v}_status": a["status"], f"android_{v}_timed": "yes" if a["timed"] else "no",
                            f"android_{v}_lines": a["lines"], f"android_{v}_ms": a["ms"],
                            f"android_{v}_kb": round(a["bytes"] / 1024, 1)})
                if a["timed"] and not yt_cues:
                    yt_cues, row["yt_source"] = a["cues"], a["source"]
                time.sleep(PAUSE)

        lrc = lrclib_get(info["title"], info["artist"], info["album"], info["seconds"])
        row["lrclib_raw"] = "yes" if lrc["synced"] else f"no ({lrc['status']})"
        ms = lrc["ms"]
        if not lrc["synced"]:
            lrc = lrclib_get(clean_title(info["title"]), clean_artist(info["artist"]), "", info["seconds"])
            row["lrclib_clean"] = "yes" if lrc["synced"] else f"no ({lrc['status']})"
            ms += lrc["ms"]
        if not lrc["synced"]:
            lrc = lrclib_search(clean_title(info["title"]), clean_artist(info["artist"]), info["seconds"])
            row["lrclib_search"] = "yes" if lrc["synced"] else f"no ({lrc['status']})"
            ms += lrc["ms"]
        row["lrclib_ms"] = ms
        if lrc["synced"]:
            row["lrclib_len_diff"] = round(lrc["duration"] - info["seconds"], 1)
        if yt_cues and lrc["synced"]:
            median, matched, spread = offset(yt_cues, lrc["cues"])
            row.update(offset_ms=median if median is not None else "", matched_lines=matched,
                       offset_spread_ms=spread if spread is not None else "")

        timed = [v for v in ANDROID_VERSIONS if row[f"android_{v}_timed"] == "yes"]
        log(query, info["type"], f"page {row['has_page']}", f"web plain {row['web_plain']}",
            f"android timed {','.join(timed) or 'no'}",
            f"lrclib {row['lrclib_raw'] if row['lrclib_raw'] == 'yes' else row['lrclib_clean'] or row['lrclib_search']}"
            if row["lrclib_raw"] != "yes" else "lrclib yes",
            f"offset {row['offset_ms']} ms over {row['matched_lines']} lines" if row["offset_ms"] != "" else "")
        rows.append(row)

    with open(RESULTS / "coverage.tsv", "w") as f:
        f.write("\t".join(COLUMNS) + "\n")
        for row in rows:
            f.write("\t".join(str(row[c]) for c in COLUMNS) + "\n")
    summarize(rows)


def summarize(rows):
    found = [r for r in rows if r["title"]]
    def share(pred, among):
        n = sum(1 for r in among if pred(r))
        return f"{n}/{len(among)}"
    lines = [f"tracks found: {len(found)}/{len(rows)}",
             f"lyrics page: {share(lambda r: r['has_page'] == 'yes', found)}",
             f"web plain: {share(lambda r: r['web_plain'] == 'yes', found)}"]
    for v in ANDROID_VERSIONS:
        lines.append(f"android {v} timed: {share(lambda r, v=v: r[f'android_{v}_timed'] == 'yes', found)}")
    lrc = lambda r: "yes" in (r["lrclib_raw"], r["lrclib_clean"], r["lrclib_search"])
    yt = lambda r: any(r[f"android_{v}_timed"] == "yes" for v in ANDROID_VERSIONS)
    lines += [f"lrclib synced (any step): {share(lrc, found)}",
              f"  raw metadata: {share(lambda r: r['lrclib_raw'] == 'yes', found)}",
              f"  after cleanup: {share(lambda r: r['lrclib_clean'] == 'yes', found)}",
              f"  by search: {share(lambda r: r['lrclib_search'] == 'yes', found)}",
              f"timed from either: {share(lambda r: yt(r) or lrc(r), found)}"]
    groups = sorted({r["group"] for r in found})
    for g in groups:
        among = [r for r in found if r["group"] == g]
        lines.append(f"  {g}: youtube {share(yt, among)}, lrclib {share(lrc, among)}")
    offsets = [int(r["offset_ms"]) for r in found if r["offset_ms"] != ""]
    if offsets:
        lines.append(f"offset youtube - lrclib, ms: median {int(statistics.median(offsets))}, "
                     f"min {min(offsets)}, max {max(offsets)}, n {len(offsets)}")
    text = "\n".join(lines)
    print("\n" + text)
    (RESULTS / "coverage-summary.txt").write_text(text + "\n")


if __name__ == "__main__":
    main()
