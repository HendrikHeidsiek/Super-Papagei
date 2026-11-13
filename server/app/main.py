import gzip
import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import threading
import time
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.responses import FileResponse, JSONResponse, PlainTextResponse, RedirectResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException as StarletteHTTPException
from pydantic import BaseModel, Field

from . import db
from .scanner import Scanner

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("hoerwerk")

LIBRARY = Path(os.environ.get("LIBRARY_PATH", "/audiobooks"))
DATA = Path(os.environ.get("DATA_PATH", "/data"))
CACHE = DATA / "cache"
SCAN_INTERVAL = int(os.environ.get("SCAN_INTERVAL_MINUTES", "30"))
SERVER_NAME = os.environ.get("SERVER_NAME", "Super-Papagei")
VERSION = "1.1.14"

app = FastAPI(title="Super-Papagei", version=VERSION)
scanner = Scanner(LIBRARY, CACHE)
STATIC = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=STATIC), name="static")


# Optional settings for the start page (environment variables):
#   PUBLIC_URL      https://audio.example.org   (link previews, QR code)
#   OPERATOR_NAME   example.org                 ("Betreiber dieser Seite: …")
#   OPERATOR_URL    https://example.org
def public_base(request: Request) -> str:
    url = os.environ.get("PUBLIC_URL", "").strip().rstrip("/")
    if url:
        return url
    proto = request.headers.get("x-forwarded-proto") or request.url.scheme
    host = request.headers.get("x-forwarded-host") or request.headers.get("host") or request.url.netloc
    return f"{proto}://{host}"


@app.get("/", include_in_schema=False)
def landing(request: Request):
    import html as _html
    page = (STATIC / "index.html").read_text(encoding="utf-8")
    base = public_base(request)
    name = os.environ.get("OPERATOR_NAME", "").strip()
    link = os.environ.get("OPERATOR_URL", "").strip()
    if name:
        who = f'<a href="{_html.escape(link)}" rel="noopener">{_html.escape(name)}</a>' if link else _html.escape(name)
        operator = f"<span>Betreiber dieser Seite: {who}</span>"
    else:
        operator = ""
    page = page.replace("{{BASE}}", _html.escape(base)).replace("{{OPERATOR}}", operator)
    return Response(page, media_type="text/html",
                    headers={"Cache-Control": "no-cache", "X-Robots-Tag": "noindex, nofollow"})


@app.get("/qr/app.svg", include_in_schema=False)
def app_qr(request: Request):
    """QR code with the download link of this server, for the start page."""
    import io
    import segno
    buf = io.BytesIO()
    segno.make(public_base(request) + "/super-papagei.apk", error="m").save(
        buf, kind="svg", scale=1, border=0, dark="#120E0C", light=None, xmldecl=False)
    svg = buf.getvalue().decode().replace('class="segno"', 'shape-rendering="crispEdges"', 1)
    svg = re.sub(r'width="(\d+)" height="(\d+)"', r'viewBox="0 0 \1 \2" width="\1" height="\2"', svg, count=1)
    return Response(svg, media_type="image/svg+xml", headers={"Cache-Control": "public, max-age=3600"})


# The Android app ships inside the image, so it always matches this server.
APK = Path(__file__).parent.parent / "download" / "super-papagei.apk"


def _app_info() -> dict | None:
    try:
        info = json.loads(APK.with_name("app-version.json").read_text())
        return {"version": str(info["version"]), "build": int(info["build"])}
    except (ValueError, KeyError, OSError):
        return None


def _apk_name() -> str:
    # Every release gets its own address, so no cache (Cloudflare, browser)
    # can hand out an older APK under the same name.
    info = _app_info()
    return f"super-papagei-{info['version']}.apk" if info else "super-papagei.apk"


@app.api_route("/super-papagei.apk", methods=["GET", "HEAD"], include_in_schema=False)
def android_app_latest():
    """Stable link: redirects to the current version's own address."""
    if not APK.is_file():
        raise HTTPException(404)
    return RedirectResponse("/" + _apk_name(), status_code=302, headers={"Cache-Control": "no-store"})


@app.api_route("/super-papagei-{version}.apk", methods=["GET", "HEAD"], include_in_schema=False)
def android_app(version: str):
    if not APK.is_file() or "/" + _apk_name() != f"/super-papagei-{version}.apk":
        # an old version link: send people to the current one
        if APK.is_file():
            return RedirectResponse("/" + _apk_name(), status_code=302, headers={"Cache-Control": "no-store"})
        raise HTTPException(404)
    return FileResponse(APK, media_type="application/vnd.android.package-archive",
                        filename=_apk_name(),
                        headers={"Cache-Control": "public, max-age=31536000, immutable",
                                 "X-Robots-Tag": "noindex, nofollow"})


# Written by release.sh next to the APK: {"version": "1.0.1", "build": 2}
APP_INFO = APK.with_name("app-version.json")


@app.get("/api/app")
def app_update_info(response: Response):
    response.headers["Cache-Control"] = "no-store"
    """Newest Android app this server offers. Public, the app asks before login too."""
    info = _app_info()
    if not APK.is_file() or not info:
        return {"android": None}
    return {"android": {**info, "url": "/" + _apk_name(), "size": APK.stat().st_size}}


@app.get("/robots.txt", include_in_schema=False)
def robots():
    return PlainTextResponse("User-agent: *\nDisallow: /\n")


@app.exception_handler(StarletteHTTPException)
async def not_found(request: Request, exc: StarletteHTTPException):
    # Browsers that wander off the API land on the parrot instead of raw JSON.
    if exc.status_code == 404 and not request.url.path.startswith("/api/") and request.method == "GET":
        return RedirectResponse("/", status_code=302)
    return JSONResponse({"detail": exc.detail}, status_code=exc.status_code, headers=getattr(exc, "headers", None))




# ---------------------------------------------------------------- passwords & tokens

def hash_password(pw: str) -> str:
    salt = secrets.token_bytes(16)
    h = hashlib.scrypt(pw.encode(), salt=salt, n=2 ** 14, r=8, p=1)
    return f"scrypt${salt.hex()}${h.hex()}"


def check_password(pw: str, stored: str) -> bool:
    try:
        _, salt, h = stored.split("$")
        calc = hashlib.scrypt(pw.encode(), salt=bytes.fromhex(salt), n=2 ** 14, r=8, p=1)
        return hmac.compare_digest(calc.hex(), h)
    except Exception:
        return False


def token_hash(t: str) -> str:
    return hashlib.sha256(t.encode()).hexdigest()


def public_user(u: dict) -> dict:
    return {"id": u["id"], "username": u["username"], "display_name": u.get("display_name") or u["username"],
            "is_admin": bool(u["is_admin"]), "avatar_version": u.get("avatar_version")}


def current_user(request: Request) -> dict:
    token = None
    auth = request.headers.get("authorization", "")
    if auth.lower().startswith("bearer "):
        token = auth[7:].strip()
    if not token:
        token = request.query_params.get("token")
    if not token:
        raise HTTPException(401, "Nicht angemeldet")
    th = token_hash(token)
    rows = db.query("SELECT u.* FROM tokens t JOIN users u ON u.id=t.user_id WHERE t.token_hash=?", (th,))
    if not rows:
        raise HTTPException(401, "Sitzung abgelaufen")
    now = int(time.time())
    db.execute("UPDATE tokens SET last_used=? WHERE token_hash=? AND last_used<?", (now, th, now - 300))
    u = rows[0]
    u["_token_hash"] = th
    return u


def admin_user(u: dict = Depends(current_user)) -> dict:
    if not u["is_admin"]:
        raise HTTPException(403, "Nur für Admins")
    return u


# ---------------------------------------------------------------- startup

@app.on_event("startup")
def startup():
    db.init(DATA / "hoerwerk.db")
    CACHE.mkdir(parents=True, exist_ok=True)
    if not db.query("SELECT id FROM users LIMIT 1"):
        name = os.environ.get("ADMIN_USERNAME", "admin")
        pw = os.environ.get("ADMIN_PASSWORD") or secrets.token_urlsafe(9)
        db.execute("INSERT INTO users(username, display_name, password_hash, is_admin, created_at) VALUES(?,?,?,?,?)",
                   (name, name, hash_password(pw), 1, int(time.time())))
        if os.environ.get("ADMIN_PASSWORD"):
            log.info("Admin-Konto '%s' angelegt (Passwort aus ADMIN_PASSWORD)", name)
        else:
            log.warning("Admin-Konto angelegt: Benutzer '%s', Passwort '%s'  (bitte in der App ändern)", name, pw)
    scanner.start_background()
    scanner.schedule(SCAN_INTERVAL)
    threading.Thread(target=_watch_password_reset, daemon=True).start()


# ---------------------------------------------------------------- password reset
# Forgot the admin password? Put a text file "passwort-zuruecksetzen.txt" with
# the new password into the data folder on the NAS. The server picks it up
# within half a minute, sets it for the admin account and deletes the file.

RESET_FILE = DATA / "passwort-zuruecksetzen.txt"


def _apply_password_reset():
    if not RESET_FILE.is_file():
        return
    try:
        pw = RESET_FILE.read_text(encoding="utf-8-sig").strip().splitlines()[0].strip() if RESET_FILE.stat().st_size else ""
    except (OSError, IndexError):
        pw = ""
    try:
        RESET_FILE.unlink()
    except OSError:
        log.error("Passwort-Datei konnte nicht gelöscht werden: %s", RESET_FILE)
    if len(pw) < 8:
        log.error("Passwort nicht geändert: in %s stand kein Passwort mit mindestens 8 Zeichen", RESET_FILE.name)
        return
    name = os.environ.get("ADMIN_USERNAME", "admin")
    rows = db.query("SELECT id, username FROM users WHERE username=?", (name,)) or \
        db.query("SELECT id, username FROM users WHERE is_admin=1 ORDER BY id LIMIT 1")
    if not rows:
        log.error("Passwort nicht geändert: kein Admin-Konto gefunden")
        return
    db.execute("UPDATE users SET password_hash=? WHERE id=?", (hash_password(pw), rows[0]["id"]))
    login_guard.succeeded("", rows[0]["username"].lower())
    log.warning("Neues Passwort für '%s' gesetzt (aus %s, Datei gelöscht)", rows[0]["username"], RESET_FILE.name)


def _watch_password_reset():
    while True:
        try:
            _apply_password_reset()
        except Exception as e:  # never let this kill the thread
            log.exception("Passwort-Reset fehlgeschlagen: %s", e)
        time.sleep(20)


# ---------------------------------------------------------------- models

class LoginIn(BaseModel):
    username: str
    password: str
    device: str | None = None


class PasswordIn(BaseModel):
    old_password: str | None = None
    new_password: str = Field(min_length=6)


class UserIn(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=6)
    display_name: str | None = None
    is_admin: bool = False


class ProgressIn(BaseModel):
    book_id: str
    position: float
    finished: bool = False
    updated_at: int  # ms since epoch, client clock
    device: str | None = None


class ProgressBatch(BaseModel):
    items: list[ProgressIn]


class BookmarkIn(BaseModel):
    position: float
    note: str | None = None


# ---------------------------------------------------------------- auth

@app.get("/api/health")
def health():
    return {"ok": True, "name": SERVER_NAME, "version": VERSION, "app": "hoerwerk"}


class LoginGuard:
    """Slows down password guessing. The server is reachable from the internet.

    - per address: 10 failures within 15 minutes block that address for 15 minutes
    - per account: 6 failures within 15 minutes block logins to it for 5 minutes,
      from anywhere (short, so a stranger cannot lock someone out for long)
    A successful login clears both counters.
    """

    WINDOW = 15 * 60
    IP_MAX, IP_BLOCK = 10, 15 * 60
    USER_MAX, USER_BLOCK = 6, 5 * 60

    def __init__(self):
        self.lock = threading.Lock()
        self.fails: dict[str, list[float]] = {}
        self.blocked: dict[str, float] = {}

    def _prune(self, key: str, now: float) -> list[float]:
        recent = [t for t in self.fails.get(key, []) if now - t < self.WINDOW]
        self.fails[key] = recent
        return recent

    def wait_seconds(self, ip: str, user: str) -> int:
        now = time.time()
        with self.lock:
            until = max(self.blocked.get("ip:" + ip, 0), self.blocked.get("user:" + user, 0))
        return max(0, int(until - now))

    def failed(self, ip: str, user: str):
        now = time.time()
        with self.lock:
            for key, limit, block in (("ip:" + ip, self.IP_MAX, self.IP_BLOCK), ("user:" + user, self.USER_MAX, self.USER_BLOCK)):
                recent = self._prune(key, now)
                recent.append(now)
                if len(recent) >= limit:
                    self.blocked[key] = now + block
                    self.fails[key] = []
                    log.warning("login blocked for %s after %d failures", key, limit)

    def succeeded(self, ip: str, user: str):
        with self.lock:
            for key in ("ip:" + ip, "user:" + user):
                self.fails.pop(key, None)
                self.blocked.pop(key, None)


login_guard = LoginGuard()


def client_ip(request: Request) -> str:
    # Behind Nginx Proxy Manager the real address comes in these headers.
    fwd = request.headers.get("x-forwarded-for", "")
    return request.headers.get("x-real-ip") or (fwd.split(",")[0].strip() if fwd else "") or \
        (request.client.host if request.client else "?")


@app.post("/api/auth/login")
def login(body: LoginIn, request: Request):
    name = body.username.strip()
    ip = client_ip(request)
    wait = login_guard.wait_seconds(ip, name.lower())
    if wait:
        minutes = max(1, (wait + 59) // 60)
        raise HTTPException(429, f"Zu viele Fehlversuche. Bitte in {minutes} {'Minute' if minutes == 1 else 'Minuten'} erneut versuchen.",
                            headers={"Retry-After": str(wait)})
    rows = db.query("SELECT * FROM users WHERE username=?", (name,))
    if not rows or not check_password(body.password, rows[0]["password_hash"]):
        login_guard.failed(ip, name.lower())
        time.sleep(0.5)
        raise HTTPException(401, "Benutzername oder Passwort falsch")
    login_guard.succeeded(ip, name.lower())
    u = rows[0]
    token = secrets.token_urlsafe(32)
    now = int(time.time())
    db.execute("INSERT INTO tokens(token_hash, user_id, device, created_at, last_used) VALUES(?,?,?,?,?)",
               (token_hash(token), u["id"], body.device, now, now))
    return {"token": token, "user": public_user(u), "server": {"name": SERVER_NAME, "version": VERSION}}


@app.post("/api/auth/logout")
def logout(u=Depends(current_user)):
    db.execute("DELETE FROM tokens WHERE token_hash=?", (u["_token_hash"],))
    return {"ok": True}


@app.get("/api/me")
def me(u=Depends(current_user)):
    return public_user(u)


@app.put("/api/me/password")
def change_password(body: PasswordIn, u=Depends(current_user)):
    if not body.old_password or not check_password(body.old_password, u["password_hash"]):
        raise HTTPException(400, "Altes Passwort stimmt nicht")
    db.execute("UPDATE users SET password_hash=? WHERE id=?", (hash_password(body.new_password), u["id"]))
    db.execute("DELETE FROM tokens WHERE user_id=? AND token_hash<>?", (u["id"], u["_token_hash"]))
    return {"ok": True}


# ---------------------------------------------------------------- avatars

AVATARS = DATA / "avatars"
MAX_AVATAR_BYTES = 15 * 1024 * 1024


@app.put("/api/me/avatar")
async def upload_avatar(request: Request, u=Depends(current_user)):
    """Body: raw image bytes (JPEG, PNG, HEIC-as-JPEG ...). Stored as a 512 px square JPEG."""
    from PIL import Image, ImageOps
    import io
    body = await request.body()
    if not body or len(body) > MAX_AVATAR_BYTES:
        raise HTTPException(400, "Bild fehlt oder ist größer als 15 MB")
    try:
        img = ImageOps.exif_transpose(Image.open(io.BytesIO(body))).convert("RGB")
    except Exception:
        raise HTTPException(400, "Das Bild konnte nicht gelesen werden")
    img = ImageOps.fit(img, (512, 512), method=Image.LANCZOS)
    AVATARS.mkdir(parents=True, exist_ok=True)
    tmp = AVATARS / f"{u['id']}.jpg.tmp"
    img.save(tmp, "JPEG", quality=88)
    tmp.replace(AVATARS / f"{u['id']}.jpg")
    version = int(time.time())
    db.execute("UPDATE users SET avatar_version=? WHERE id=?", (version, u["id"]))
    return public_user(db.query("SELECT * FROM users WHERE id=?", (u["id"],))[0])


@app.delete("/api/me/avatar")
def delete_avatar(u=Depends(current_user)):
    (AVATARS / f"{u['id']}.jpg").unlink(missing_ok=True)
    db.execute("UPDATE users SET avatar_version=NULL WHERE id=?", (u["id"],))
    return public_user(db.query("SELECT * FROM users WHERE id=?", (u["id"],))[0])


@app.get("/api/users/{uid}/avatar")
def get_avatar(uid: int, _=Depends(current_user)):
    p = AVATARS / f"{uid}.jpg"
    if not p.exists():
        raise HTTPException(404, "Kein Avatar")
    return FileResponse(p, media_type="image/jpeg", headers={"Cache-Control": "private, max-age=86400"})


# ---------------------------------------------------------------- users (admin)

@app.get("/api/users")
def list_users(_=Depends(admin_user)):
    rows = db.query("SELECT u.*, (SELECT MAX(last_used) FROM tokens t WHERE t.user_id=u.id) AS last_seen "
                    "FROM users u ORDER BY username")
    return [{**public_user(r), "last_seen": r["last_seen"], "created_at": r["created_at"]} for r in rows]


@app.post("/api/users")
def create_user(body: UserIn, _=Depends(admin_user)):
    if db.query("SELECT id FROM users WHERE username=?", (body.username.strip(),)):
        raise HTTPException(409, "Benutzername ist schon vergeben")
    uid = db.execute("INSERT INTO users(username, display_name, password_hash, is_admin, created_at) VALUES(?,?,?,?,?)",
                     (body.username.strip(), body.display_name or body.username.strip(), hash_password(body.password),
                      int(body.is_admin), int(time.time())))
    return public_user(db.query("SELECT * FROM users WHERE id=?", (uid,))[0])


@app.delete("/api/users/{uid}")
def delete_user(uid: int, a=Depends(admin_user)):
    if uid == a["id"]:
        raise HTTPException(400, "Du kannst dich nicht selbst löschen")
    db.execute("DELETE FROM users WHERE id=?", (uid,))
    (AVATARS / f"{uid}.jpg").unlink(missing_ok=True)
    return {"ok": True}


@app.put("/api/users/{uid}/password")
def reset_password(uid: int, body: PasswordIn, _=Depends(admin_user)):
    db.execute("UPDATE users SET password_hash=? WHERE id=?", (hash_password(body.new_password), uid))
    db.execute("DELETE FROM tokens WHERE user_id=?", (uid,))
    return {"ok": True}


# ---------------------------------------------------------------- library

def load_book(bid: str) -> dict:  # noqa: E302
    rows = db.query("SELECT data FROM books WHERE id=? AND missing=0", (bid,))
    if not rows:
        raise HTTPException(404, "Buch nicht gefunden")
    return json.loads(rows[0]["data"])


@app.get("/api/library")
def library(request: Request, _=Depends(current_user)):
    version = db.library_version()
    etag = f'"lib-{version}"'
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers={"ETag": etag})
    books = [json.loads(r["data"]) for r in db.query("SELECT data FROM books WHERE missing=0")]
    for b in books:
        b.pop("folder", None)
        for f in b["files"]:
            f.pop("name", None)
    body = json.dumps({"version": version, "books": books, "scan": scanner.state}, ensure_ascii=False).encode()
    headers = {"ETag": etag, "Cache-Control": "no-cache"}
    if "gzip" in request.headers.get("accept-encoding", ""):
        body = gzip.compress(body, 6)
        headers["Content-Encoding"] = "gzip"
    return Response(body, media_type="application/json", headers=headers)


@app.get("/api/books/{bid}")
def book(bid: str, _=Depends(current_user)):
    b = load_book(bid)
    b.pop("folder", None)
    return b


@app.get("/api/books/{bid}/cover")
def cover(bid: str, size: str = "thumb", _=Depends(current_user)):
    if not re.fullmatch(r"[0-9a-f]{16}", bid):
        raise HTTPException(404)
    p = CACHE / bid / ("cover_full.jpg" if size == "full" else "cover_thumb.jpg")
    if not p.exists():
        raise HTTPException(404, "Kein Cover")
    return FileResponse(p, media_type="image/jpeg", headers={"Cache-Control": "private, max-age=604800"})


CHUNK = 256 * 1024


@app.api_route("/api/books/{bid}/files/{name}", methods=["GET", "HEAD"])
def audio_file(bid: str, name: str, request: Request, _=Depends(current_user)):
    """name is the file index, optionally with extension: "0" or "0.mp3"."""
    try:
        index = int(name.split(".", 1)[0])
    except ValueError:
        raise HTTPException(404)
    b = load_book(bid)
    if index < 0 or index >= len(b["files"]):
        raise HTTPException(404)
    f = b["files"][index]
    path = LIBRARY / b["folder"] / f["name"]
    if not path.exists():
        raise HTTPException(404, "Datei fehlt auf dem NAS")
    size = path.stat().st_size
    headers = {"Accept-Ranges": "bytes", "Content-Type": f["mime"], "ETag": f'"{size}-{int(path.stat().st_mtime)}"'}
    start, end = 0, size - 1
    status = 200
    rng = request.headers.get("range")
    if rng:
        m = re.match(r"bytes=(\d*)-(\d*)", rng)
        if not m:
            raise HTTPException(416)
        s, e = m.groups()
        if s == "":
            start = max(0, size - int(e))
        else:
            start = int(s)
            end = min(int(e), size - 1) if e else size - 1
        if start > end or start >= size:
            return Response(status_code=416, headers={"Content-Range": f"bytes */{size}"})
        status = 206
        headers["Content-Range"] = f"bytes {start}-{end}/{size}"
    headers["Content-Length"] = str(end - start + 1)
    if request.method == "HEAD":
        return Response(status_code=status, headers=headers)

    def stream():
        with open(path, "rb") as fh:
            fh.seek(start)
            remaining = end - start + 1
            while remaining > 0:
                chunk = fh.read(min(CHUNK, remaining))
                if not chunk:
                    break
                remaining -= len(chunk)
                yield chunk

    return StreamingResponse(stream(), status_code=status, headers=headers)


@app.post("/api/library/scan")
def trigger_scan(force: bool = False, _=Depends(admin_user)):
    scanner.start_background(force=force)
    return scanner.state


@app.get("/api/library/scan")
def scan_state(_=Depends(current_user)):
    return scanner.state


# ---------------------------------------------------------------- progress

def progress_row(r: dict) -> dict:
    return {"book_id": r["book_id"], "position": r["position"], "finished": bool(r["finished"]),
            "updated_at": r["updated_at"], "device": r["device"]}


@app.get("/api/progress")
def get_progress(u=Depends(current_user)):
    return [progress_row(r) for r in db.query("SELECT * FROM progress WHERE user_id=?", (u["id"],))]


@app.put("/api/progress")
def put_progress(body: ProgressBatch, u=Depends(current_user)):
    """Last write wins, decided by the client timestamp. Returns the stored state for every book sent."""
    now_ms = int(time.time() * 1000)
    out = []
    for it in body.items:
        ts = min(it.updated_at, now_ms + 60_000)  # clamp clocks that run ahead
        cur = db.query("SELECT * FROM progress WHERE user_id=? AND book_id=?", (u["id"], it.book_id))
        if not cur or ts > cur[0]["updated_at"]:
            db.execute(
                "INSERT INTO progress(user_id, book_id, position, finished, updated_at, device) VALUES(?,?,?,?,?,?) "
                "ON CONFLICT(user_id, book_id) DO UPDATE SET position=excluded.position, finished=excluded.finished, "
                "updated_at=excluded.updated_at, device=excluded.device",
                (u["id"], it.book_id, max(0.0, it.position), int(it.finished), ts, it.device))
            last = db.query("SELECT position, at FROM progress_log WHERE user_id=? AND book_id=? ORDER BY at DESC LIMIT 1",
                            (u["id"], it.book_id))
            if not last or abs(last[0]["position"] - it.position) > 120 or ts - last[0]["at"] > 15 * 60_000:
                db.execute("INSERT INTO progress_log(user_id, book_id, position, device, at) VALUES(?,?,?,?,?)",
                           (u["id"], it.book_id, it.position, it.device, ts))
                db.execute("DELETE FROM progress_log WHERE user_id=? AND book_id=? AND id NOT IN "
                           "(SELECT id FROM progress_log WHERE user_id=? AND book_id=? ORDER BY at DESC LIMIT 100)",
                           (u["id"], it.book_id, u["id"], it.book_id))
        row = db.query("SELECT * FROM progress WHERE user_id=? AND book_id=?", (u["id"], it.book_id))[0]
        out.append(progress_row(row))
    return out


@app.delete("/api/progress/{bid}")
def reset_progress(bid: str, u=Depends(current_user)):
    db.execute("DELETE FROM progress WHERE user_id=? AND book_id=?", (u["id"], bid))
    return {"ok": True}


@app.get("/api/progress/{bid}/history")
def progress_history(bid: str, u=Depends(current_user)):
    return db.query("SELECT position, device, at FROM progress_log WHERE user_id=? AND book_id=? ORDER BY at DESC LIMIT 50",
                    (u["id"], bid))


# ---------------------------------------------------------------- bookmarks

@app.get("/api/books/{bid}/bookmarks")
def list_bookmarks(bid: str, u=Depends(current_user)):
    return db.query("SELECT id, position, note, created_at FROM bookmarks WHERE user_id=? AND book_id=? ORDER BY position",
                    (u["id"], bid))


@app.post("/api/books/{bid}/bookmarks")
def add_bookmark(bid: str, body: BookmarkIn, u=Depends(current_user)):
    i = db.execute("INSERT INTO bookmarks(user_id, book_id, position, note, created_at) VALUES(?,?,?,?,?)",
                   (u["id"], bid, body.position, body.note, int(time.time())))
    return {"id": i, "position": body.position, "note": body.note}


@app.delete("/api/bookmarks/{bmid}")
def delete_bookmark(bmid: int, u=Depends(current_user)):
    db.execute("DELETE FROM bookmarks WHERE id=? AND user_id=?", (bmid, u["id"]))
    return {"ok": True}
