import os
import sqlite3
import threading
import time
from pathlib import Path

_local = threading.local()
_path: Path | None = None
_write_lock = threading.Lock()

SCHEMA = """
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS users(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE COLLATE NOCASE,
  display_name TEXT,
  password_hash TEXT NOT NULL,
  is_admin INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS tokens(
  token_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device TEXT,
  created_at INTEGER NOT NULL,
  last_used INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS books(
  id TEXT PRIMARY KEY,
  folder TEXT NOT NULL,
  signature TEXT NOT NULL,
  data TEXT NOT NULL,
  added_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  missing INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS progress(
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id TEXT NOT NULL,
  position REAL NOT NULL DEFAULT 0,
  finished INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  device TEXT,
  PRIMARY KEY(user_id, book_id)
);
CREATE TABLE IF NOT EXISTS progress_log(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id TEXT NOT NULL,
  position REAL NOT NULL,
  device TEXT,
  at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS progress_log_idx ON progress_log(user_id, book_id, at);
CREATE TABLE IF NOT EXISTS bookmarks(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id TEXT NOT NULL,
  position REAL NOT NULL,
  note TEXT,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
"""


def init(path: Path):
    global _path
    _path = path
    path.parent.mkdir(parents=True, exist_ok=True)
    conn().executescript(SCHEMA)
    cols = {r["name"] for r in query("PRAGMA table_info(users)")}
    if "avatar_version" not in cols:
        conn().execute("ALTER TABLE users ADD COLUMN avatar_version INTEGER")


def conn() -> sqlite3.Connection:
    c = getattr(_local, "conn", None)
    if c is None:
        c = sqlite3.connect(_path, timeout=30, isolation_level=None)
        c.row_factory = sqlite3.Row
        c.execute("PRAGMA foreign_keys=ON")
        c.execute("PRAGMA busy_timeout=30000")
        _local.conn = c
    return c


def query(sql, args=()):
    return [dict(r) for r in conn().execute(sql, args).fetchall()]


def execute(sql, args=()):
    with _write_lock:
        cur = conn().execute(sql, args)
        return cur.lastrowid


def transaction(statements):
    with _write_lock:
        c = conn()
        c.execute("BEGIN")
        try:
            for sql, args in statements:
                c.execute(sql, args)
            c.execute("COMMIT")
        except Exception:
            c.execute("ROLLBACK")
            raise


def library_version() -> int:
    r = query("SELECT value FROM meta WHERE key='library_version'")
    return int(r[0]["value"]) if r else 0


def bump_library_version():
    execute("INSERT INTO meta(key, value) VALUES('library_version', ?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (str(int(time.time() * 1000)),))
