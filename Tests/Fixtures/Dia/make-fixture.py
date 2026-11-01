#!/usr/bin/env python3 -I
"""Rebuilds User Data/Profile 1/tabs.db(-wal): a made-up Dia 1.55 sidebar encrypted the way Dia
does it (SQLCipher 4, raw key from the Safe Storage secret "cra-test-secret"). The Work space's
folder is only in the -wal, as Dia's recent edits often are. Needs the sqlite3 and openssl CLIs."""
import base64, hashlib, hmac, os, shutil, sqlite3, subprocess, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "User Data", "Profile 1")
SECRET, LABEL = b"cra-test-secret", b"profile/Profile 1/tabs"
SALT_KEY = base64.b64decode("iOe1Ue/XtonbieE/5m1nAgewvWQlePHRcKnoU10EyOM=")
PAGE, RESERVE = 4096, 80

SCHEMA = """
CREATE TABLE spaces (id TEXT PRIMARY KEY, title TEXT NOT NULL, creation_date DATE NOT NULL, last_updated_at DATE NOT NULL, theme TEXT NOT NULL DEFAULT 'neutral');
CREATE TABLE nodes (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, entity_id TEXT NOT NULL, parent_id INTEGER, "order" INTEGER NOT NULL, deleted_at DATETIME, space_id TEXT NOT NULL DEFAULT '');
CREATE TABLE tabs (id TEXT PRIMARY KEY, node_id INTEGER NOT NULL, creation_date DATE NOT NULL);
CREATE TABLE tab_groups (id TEXT PRIMARY KEY, node_id INTEGER NOT NULL, creation_date DATE NOT NULL, title TEXT, theme TEXT NOT NULL DEFAULT 'neutral');
CREATE TABLE content_panes (id TEXT PRIMARY KEY, node_id INTEGER NOT NULL, creation_date DATE NOT NULL, custom_title TEXT, variant TEXT);
CREATE TABLE web_contents (id INTEGER PRIMARY KEY AUTOINCREMENT, content_pane_id TEXT NOT NULL, url TEXT NOT NULL, title TEXT);
"""

class Tree:
    def __init__(self, db): self.db, self.n = db, 0
    def node(self, kind, parent, order, space, deleted=None):
        self.n += 1
        ent = "%s-%d" % (kind, self.n)
        self.db.execute('INSERT INTO nodes (id, kind, entity_id, parent_id, "order", deleted_at, space_id) VALUES (?,?,?,?,?,?,?)',
                        (self.n, kind, ent, parent, order, deleted, space))
        return self.n, ent
    def tab(self, parent, order, space, *pages, deleted=None):
        nid, ent = self.node("tab", parent, order, space, deleted)
        self.db.execute("INSERT INTO tabs VALUES (?,?,?)", (ent, nid, "2026-10-14 07:32:25.072"))
        for i, (url, title, custom) in enumerate(pages):
            pid, pent = self.node("content_pane", nid, i, space)
            self.db.execute("INSERT INTO content_panes VALUES (?,?,?,?,?)", (pent, pid, "2026-10-14 07:32:25.072", custom,
                                                                             "web_content" if url else "new_tab_page"))
            if url: self.db.execute("INSERT INTO web_contents (content_pane_id, url, title) VALUES (?,?,?)", (pent, url, title))
    def group(self, parent, order, space, title):
        nid, ent = self.node("group", parent, order, space)
        self.db.execute("INSERT INTO tab_groups VALUES (?,?,?,?,?)", (ent, nid, "2026-10-14 07:32:25.072", title, "neutral"))
        return nid

def build(path, wal_path):
    subprocess.run(["sqlite3", path, ".filectrl reserve_bytes %d" % RESERVE, SCHEMA], check=True)
    db = sqlite3.connect(path)
    db.execute("INSERT INTO spaces VALUES ('home','Home','2026-10-01 08:00:00.000','2026-10-01 08:00:00.000','yellow')")
    db.execute("INSERT INTO spaces VALUES ('work','Work','2026-10-02 08:00:00.000','2026-10-02 08:00:00.000','neutral')")
    t = Tree(db)
    for space, offset in (("home", 0), ("work", 10)):
        t.node("pinned_container", None, offset, space)
    t.n = 2
    fav, _ = t.node("favorites", None, 20, "home")
    t.tab(fav, 0, "home", ("https://example.com/mail", "Mail", None))
    t.tab(fav, 1, "home", ("https://example.com/calendar", "Calendar", None))
    t.tab(1, 0, "home", ("https://example.com/docs", "Docs page", "Docs"))
    reading = t.group(1, 1, "home", "Reading")
    t.tab(reading, 0, "home", ("https://example.com/read/1", "Read one", None))
    deep = t.group(reading, 1, "home", "Deep")
    t.tab(deep, 0, "home", ("https://example.com/read/deep", "Deep read", None))
    t.tab(1, 2, "home", ("https://example.com/gone", "Deleted", None), deleted="2026-10-20 10:00:00.000")
    win, _ = t.node("window", None, 30, "home")
    t.tab(win, 0, "home", ("https://example.com/open", "Open", None))
    t.tab(win, 1, "home", ("https://example.com/left", "Left", None), ("https://example.com/right", "Right", None))
    t.tab(win, 2, "home", (None, None, None))
    wfav, _ = t.node("favorites", None, 40, "work")
    t.tab(wfav, 0, "work", ("https://example.com/jira", "Jira", None))
    db.commit(); db.close()

    db = sqlite3.connect(path)
    db.execute("PRAGMA journal_mode=WAL"); db.execute("PRAGMA wal_autocheckpoint=0")
    t = Tree(db); t.n = db.execute("SELECT max(id) FROM nodes").fetchone()[0]
    tools = t.group(2, 0, "work", "Tools")
    t.tab(tools, 0, "work", ("https://example.com/ci", "CI", None))
    db.commit()
    shutil.copy(path, path + ".snap"); shutil.copy(path + "-wal", wal_path)
    db.close()
    shutil.move(path + ".snap", path)

def key():
    root = hashlib.pbkdf2_hmac("sha1", SECRET, b"saltysalt", 1003, 16)
    prk = hmac.new(hmac.new(SALT_KEY, LABEL, hashlib.sha256).digest(), root, hashlib.sha256).digest()
    return hmac.new(prk, LABEL + b"\x01", hashlib.sha256).digest()

def encrypt_page(page, first, k):
    iv = os.urandom(16)
    start = 16 if first else 0
    ct = subprocess.run(["openssl", "enc", "-e", "-aes-256-cbc", "-nopad", "-K", k.hex(), "-iv", iv.hex()],
                        input=page[start:PAGE - RESERVE], capture_output=True, check=True).stdout
    return (os.urandom(16) if first else b"") + ct + iv + os.urandom(RESERVE - 16)

def main():
    k = key()
    with tempfile.TemporaryDirectory() as tmp:
        plain, wal = os.path.join(tmp, "tabs.db"), os.path.join(tmp, "wal")
        build(plain, wal)
        raw = open(plain, "rb").read()
        with open(os.path.join(OUT, "tabs.db"), "wb") as f:
            for i in range(len(raw) // PAGE): f.write(encrypt_page(raw[i * PAGE:(i + 1) * PAGE], i == 0, k))
        w = open(wal, "rb").read()
        with open(os.path.join(OUT, "tabs.db-wal"), "wb") as f:
            f.write(w[:32])
            off = 32
            while off + 24 + PAGE <= len(w):
                pno = int.from_bytes(w[off:off + 4], "big")
                f.write(w[off:off + 24] + encrypt_page(w[off + 24:off + 24 + PAGE], pno == 1, k))
                off += 24 + PAGE

if __name__ == "__main__":
    main()
