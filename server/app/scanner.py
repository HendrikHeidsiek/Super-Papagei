"""Scans the audiobook folder and extracts metadata, chapters and covers.

Layout: one top-level folder per book. Inside: one or more audio files,
optionally a cover image and a .cue file with chapter marks.
"""
from __future__ import annotations

import hashlib
import io
import json
import logging
import os
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import mutagen
from mutagen.id3 import ID3
from mutagen.mp4 import MP4
from PIL import Image

from . import db

log = logging.getLogger("scanner")

AUDIO_EXT = {".mp3": "audio/mpeg", ".m4b": "audio/mp4", ".m4a": "audio/mp4", ".aac": "audio/aac",
             ".ogg": "audio/ogg", ".opus": "audio/ogg", ".flac": "audio/flac"}
COVER_NAMES = ["cover", "folder", "front"]
IMG_EXT = {".jpg", ".jpeg", ".png", ".webp"}
THUMB_SIZE = 480


def book_id(folder: str) -> str:
    return hashlib.sha1(folder.encode("utf-8")).hexdigest()[:16]


def natural_key(s: str):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]


# ---------------------------------------------------------------- tags

def _first(v):
    if v is None:
        return None
    if isinstance(v, list):
        v = v[0] if v else None
    if v is None:
        return None
    if hasattr(v, "text"):
        v = v.text[0] if v.text else None
    if isinstance(v, bytes):
        v = v.decode("utf-8", "replace")
    s = str(v).strip() if v is not None else None
    return s or None


def read_tags(path: Path) -> dict:
    f = mutagen.File(path)
    if f is None:
        return {"duration": 0.0}
    out: dict = {"duration": float(getattr(f.info, "length", 0) or 0)}
    tags = f.tags or {}
    if isinstance(f, MP4):
        def free(name):
            for prefix in ("----:com.pilabor.tone:", "----:com.apple.iTunes:"):
                v = tags.get(prefix + name)
                if v:
                    return _first(v)
            return None
        out.update(
            title=_first(tags.get("©nam")), album=_first(tags.get("©alb")),
            author=_first(tags.get("aART")) or _first(tags.get("©ART")),
            narrator=_first(tags.get("©nrt")) or _first(tags.get("©wrt")),
            description=_first(tags.get("ldes")) or _first(tags.get("©des")) or _first(tags.get("desc")) or _first(tags.get("©cmt")),
            genre=_first(tags.get("©gen")), year=_first(tags.get("©day")),
            series=free("SERIES") or free("MOVEMENTNAME") or _first(tags.get("©mvn")),
            part=free("PART") or free("MOVEMENT") or _first(tags.get("©mvi")),
            language=free("LANGUAGE"), publisher=_first(tags.get("©pub")) or free("PUBLISHER"),
        )
        chapters = []
        try:
            for c in (f.chapters or []):
                chapters.append({"title": c.title or "", "start": float(c.start)})
        except Exception:
            pass
        out["chapters"] = chapters
        out["has_art"] = bool(tags.get("covr"))
    else:
        def t(key):
            return _first(tags.get(key)) if hasattr(tags, "get") else None

        def txxx(name):
            if not hasattr(tags, "getall"):
                return None
            for fr in tags.getall("TXXX"):
                if fr.desc.upper() == name:
                    return _first(fr)
            return None
        desc = txxx("LONG_COMMENT")
        if not desc and hasattr(tags, "getall"):
            for fr in tags.getall("COMM"):
                if fr.text:
                    desc = _first(fr)
                    break
        out.update(
            title=t("TIT2"), album=t("TALB"), author=t("TPE2") or t("TPE1"),
            narrator=txxx("NARRATOR") or t("TCOM"), description=desc, genre=t("TCON"),
            year=t("TDRC") or t("TYER"), series=txxx("SERIES") or t("MVNM"),
            part=txxx("PART") or txxx("SERIES-PART") or t("MVIN"), language=txxx("LANGUAGE"), publisher=t("TPUB"),
        )
        chapters = []
        cuesheet = txxx("CUESHEET")
        if hasattr(tags, "getall"):
            chaps = sorted(tags.getall("CHAP"), key=lambda c: c.start_time)
            for c in chaps:
                title = ""
                for sub in c.sub_frames.values():
                    if sub.FrameID == "TIT2":
                        title = _first(sub) or ""
                chapters.append({"title": title, "start": c.start_time / 1000.0})
            out["has_art"] = bool(tags.getall("APIC"))
        out["chapters"] = chapters
        out["cuesheet"] = cuesheet
    if out.get("description"):
        out["description"] = clean_html(out["description"])
    return out


def clean_html(s: str) -> str:
    s = s.replace("\\n", "\n")
    s = re.sub(r"<\s*br\s*/?>", "\n", s, flags=re.I)
    s = re.sub(r"</p>\s*", "\n\n", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "", s)
    s = re.sub(r"[ \t]+\n", "\n", s)
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s.strip()


def parse_cue(text: str) -> list[dict]:
    """Returns [{file, title, start}]; times are MM:SS:FF (75 frames/s)."""
    out, cur_file, cur_title = [], None, None
    for line in text.splitlines():
        line = line.strip()
        m = re.match(r'FILE\s+"(.*)"', line)
        if m:
            cur_file = m.group(1)
            continue
        m = re.match(r'TITLE\s+"(.*)"', line)
        if m:
            cur_title = m.group(1)
            continue
        m = re.match(r"INDEX\s+01\s+(\d+):(\d+):(\d+)", line)
        if m:
            mm, ss, ff = map(int, m.groups())
            out.append({"file": cur_file, "title": cur_title or "", "start": mm * 60 + ss + ff / 75.0})
            cur_title = None
    return out


# ---------------------------------------------------------------- book

def dedupe_names(s: str | None) -> str | None:
    if not s:
        return s
    parts, seen = [], set()
    for p in re.split(r"\s*[,;/]\s*", s):
        k = p.strip().lower()
        if k and k not in seen:
            seen.add(k)
            parts.append(p.strip())
    return ", ".join(parts)


def clean_title(s: str | None) -> str | None:
    if not s:
        return s
    s = re.sub(r"\s*\((un)?abridged\)\s*$", "", s, flags=re.I)
    s = re.sub(r"\s*\(ungekürzt\)\s*$", "", s, flags=re.I)
    return s.strip()


def pick_files(files: list[tuple[Path, dict]]) -> list[tuple[Path, dict]]:
    """Drop duplicate encodings of the same book (e.g. .mp3 + .m4b of equal length)."""
    if len(files) < 2:
        return files
    durs = [m["duration"] for _, m in files]
    longest = max(durs) or 1
    if all(abs(d - longest) / longest < 0.03 for d in durs):
        # same recording several times: prefer the one with chapters, then the smaller file
        return [sorted(files, key=lambda x: (not x[1].get("chapters"), x[0].stat().st_size))[0]]
    return sorted(files, key=lambda x: natural_key(x[0].name))


def folder_signature(folder: Path) -> str:
    parts = []
    for p in sorted(folder.iterdir(), key=lambda p: p.name):
        if p.name.startswith("."):
            continue
        try:
            st = p.stat()
        except OSError:
            continue
        parts.append(f"{p.name}:{st.st_size}:{int(st.st_mtime)}")
    return hashlib.sha1("|".join(parts).encode()).hexdigest()


def find_cover(folder: Path) -> Path | None:
    imgs = [p for p in folder.iterdir() if p.suffix.lower() in IMG_EXT and not p.name.startswith(".")]
    for name in COVER_NAMES:
        for p in imgs:
            if p.stem.lower() == name:
                return p
    return imgs[0] if imgs else None


def embedded_art(path: Path) -> bytes | None:
    try:
        f = mutagen.File(path)
        if isinstance(f, MP4):
            c = f.tags.get("covr") if f.tags else None
            return bytes(c[0]) if c else None
        tags = ID3(path)
        apics = tags.getall("APIC")
        return apics[0].data if apics else None
    except Exception:
        return None


def write_covers(bid: str, source: Path | None, audio: Path, cache: Path) -> bool:
    """Writes cover_full.jpg and cover_thumb.jpg into cache/<bid>/. Returns True if a cover exists."""
    data = None
    if source:
        try:
            data = source.read_bytes()
        except OSError:
            data = None
    if data is None:
        data = embedded_art(audio)
    if not data:
        return False
    try:
        img = Image.open(io.BytesIO(data))
        img = img.convert("RGB")
    except Exception:
        return False
    out = cache / bid
    out.mkdir(parents=True, exist_ok=True)
    full = img.copy()
    full.thumbnail((1400, 1400))
    full.save(out / "cover_full.jpg", "JPEG", quality=88)
    thumb = img.copy()
    thumb.thumbnail((THUMB_SIZE, THUMB_SIZE))
    thumb.save(out / "cover_thumb.jpg", "JPEG", quality=82)
    # dominant colour for a soft tinted background in the app
    small = img.resize((24, 24))
    px = list(small.getdata())
    r = sum(p[0] for p in px) // len(px)
    g = sum(p[1] for p in px) // len(px)
    b = sum(p[2] for p in px) // len(px)
    (out / "color.txt").write_text(f"#{r:02x}{g:02x}{b:02x}")
    return True


def scan_book(root: Path, folder_name: str, cache: Path) -> dict | None:
    folder = root / folder_name
    audio_paths = sorted(
        [p for p in folder.iterdir() if p.suffix.lower() in AUDIO_EXT and not p.name.startswith(".")],
        key=lambda p: natural_key(p.name),
    )
    if not audio_paths:
        return None
    metas = []
    for p in audio_paths:
        try:
            metas.append((p, read_tags(p)))
        except Exception as e:
            log.warning("cannot read %s: %s", p, e)
    if not metas:
        return None
    files = pick_files(metas)
    first = files[0][1]

    # chapters across all files, in global seconds
    chapters: list[dict] = []
    offset = 0.0
    file_list = []
    cue_files = [p for p in folder.iterdir() if p.suffix.lower() == ".cue" and not p.name.startswith(".")]
    for idx, (p, m) in enumerate(files):
        file_list.append({"index": idx, "name": p.name, "size": p.stat().st_size,
                          "duration": round(m["duration"], 3), "mime": AUDIO_EXT[p.suffix.lower()],
                          "ext": p.suffix.lower().lstrip(".")})
        chs = m.get("chapters") or []
        if len(chs) < 2:
            cue_text = None
            for c in cue_files:
                if c.stem == p.stem or len(files) == 1:
                    try:
                        cue_text = c.read_text("utf-8", "replace")
                    except OSError:
                        pass
                    break
            if not cue_text:
                cue_text = m.get("cuesheet")
            if cue_text:
                chs = parse_cue(cue_text)
        if len(chs) < 2:
            chs = [{"title": clean_title(m.get("title")) or p.stem, "start": 0.0}] if len(files) > 1 else chs
        for c in chs:
            chapters.append({"title": c.get("title") or "", "start": round(offset + c["start"], 3)})
        offset += m["duration"]
    total = round(offset, 3)
    if not chapters:
        chapters = [{"title": "Gesamtes Buch", "start": 0.0}]
    for i, c in enumerate(chapters):
        c["end"] = chapters[i + 1]["start"] if i + 1 < len(chapters) else total
        if not c["title"]:
            c["title"] = f"Kapitel {i + 1}"

    author = dedupe_names(first.get("author"))
    stem = files[0][0].stem
    if not author and " - " in stem:
        author = stem.split(" - ", 1)[0].strip()
    title = clean_title(first.get("title")) or clean_title(first.get("album")) or folder_name
    bid = book_id(folder_name)
    has_cover = write_covers(bid, find_cover(folder), files[0][0], cache)
    color = None
    cfile = cache / bid / "color.txt"
    if has_cover and cfile.exists():
        color = cfile.read_text().strip()
    added = min(p.stat().st_mtime for p, _ in files)
    year = first.get("year")
    if year:
        m = re.match(r"(\d{4})", year)
        year = m.group(1) if m else None
    pdfs = [p.name for p in folder.iterdir() if p.suffix.lower() == ".pdf"]
    return {
        "id": bid, "folder": folder_name, "title": title, "author": author or "Unbekannt",
        "narrator": dedupe_names(first.get("narrator")), "series": first.get("series"), "series_part": first.get("part"),
        "description": first.get("description"), "genre": first.get("genre"), "year": year,
        "language": first.get("language"), "publisher": first.get("publisher"),
        "duration": total, "files": file_list, "chapters": chapters, "has_cover": has_cover,
        "cover_color": color, "added_at": int(added), "pdfs": pdfs,
    }


# ---------------------------------------------------------------- scanner

class Scanner:
    def __init__(self, root: Path, cache: Path):
        self.root = root
        self.cache = cache
        self.lock = threading.Lock()
        self.state = {"running": False, "last_finished": None, "last_duration": None,
                      "books": 0, "changed": 0, "errors": 0, "progress": 0, "total": 0}

    def scan(self, force: bool = False):
        if not self.lock.acquire(blocking=False):
            return
        t0 = time.time()
        try:
            self.state.update(running=True, changed=0, errors=0, progress=0)
            if not self.root.is_dir():
                log.error("library root %s missing", self.root)
                return
            folders = [p.name for p in self.root.iterdir()
                       if p.is_dir() and not p.name.startswith((".", "_", "@", "#"))]
            self.state["total"] = len(folders)
            known = {r["folder"]: r["signature"] for r in db.query("SELECT folder, signature FROM books")}
            todo = []
            for name in folders:
                try:
                    sig = folder_signature(self.root / name)
                except OSError:
                    continue
                if force or known.get(name) != sig:
                    todo.append((name, sig))
                else:
                    self.state["progress"] += 1
            log.info("scan: %d folders, %d to (re)read", len(folders), len(todo))

            def work(item):
                name, sig = item
                try:
                    book = scan_book(self.root, name, self.cache)
                except Exception as e:
                    log.exception("scan failed for %s: %s", name, e)
                    self.state["errors"] += 1
                    book = None
                finally:
                    self.state["progress"] += 1
                return name, sig, book

            with ThreadPoolExecutor(max_workers=int(os.environ.get("SCAN_THREADS", "4"))) as ex:
                for name, sig, book in ex.map(work, todo):
                    if book is None:
                        continue
                    db.execute(
                        "INSERT INTO books(id, folder, signature, data, added_at, updated_at) VALUES(?,?,?,?,?,?) "
                        "ON CONFLICT(id) DO UPDATE SET signature=excluded.signature, data=excluded.data, "
                        "updated_at=excluded.updated_at, missing=0",
                        (book["id"], name, sig, json.dumps(book, ensure_ascii=False), book["added_at"], int(time.time())),
                    )
                    self.state["changed"] += 1
            present = set(folders)
            for f in known:
                if f not in present:
                    db.execute("UPDATE books SET missing=1 WHERE folder=?", (f,))
            for f in present:
                db.execute("UPDATE books SET missing=0 WHERE folder=? AND missing=1", (f,))
            self.state["books"] = db.query("SELECT COUNT(*) AS n FROM books WHERE missing=0")[0]["n"]
            db.bump_library_version()
        finally:
            self.state.update(running=False, last_finished=int(time.time()), last_duration=round(time.time() - t0, 1))
            self.lock.release()
            log.info("scan done in %.1fs", time.time() - t0)

    def start_background(self, force=False):
        threading.Thread(target=self.scan, kwargs={"force": force}, daemon=True).start()

    def schedule(self, interval_min: int):
        def loop():
            while True:
                time.sleep(max(60, interval_min * 60))
                self.scan()
        threading.Thread(target=loop, daemon=True).start()
