import sqlite3

DB_PATH = "/home/brian/projects/blue-bubbles/hub/data/messages.db"

def get_connection():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")

    return con

def get_last_seen_rowid():
    con = get_connection()
    cur = con.cursor()

    cur.execute("""
        SELECT
        id
        FROM messages
        ORDER BY id DESC
        LIMIT 1
    """)

    row = cur.fetchone()

    con.close()

    return row['id'] if row else 0

def init_db():
    con = get_connection()
    cur = con.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY,
            guid TEXT UNIQUE,
            identifier TEXT NOT NULL,
            service TEXT,
            text TEXT,
            date INTEGER,
            is_from_me INTEGER DEFAULT 0,
            is_system_message INTEGER DEFAULT 0,
            group_title TEXT,
            has_attachments INTEGER DEFAULT 0
        )
    """)

    cur.execute("""
        CREATE TABLE IF NOT EXISTS attachments (
            id INTEGER PRIMARY KEY,
            guid TEXT UNIQUE,
            message_id INTEGER NOT NULL,
            filename TEXT,
            mime_type TEXT,
            total_bytes INTEGER,
            last_accessed_at INTEGER,
            FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE
        )
    """)

    cur.execute("""
        CREATE TABLE IF NOT EXISTS contacts (
            id INTEGER PRIMARY KEY,
            first_name TEXT,
            last_name TEXT,
            organization TEXT
        )
    """)

    cur.execute("""
        CREATE TABLE IF NOT EXISTS contact_identifiers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            contact_id INTEGER NOT NULL,
            value TEXT NOT NULL UNIQUE,
            type TEXT NOT NULL,
            FOREIGN KEY (contact_id) REFERENCES contacts (id) ON DELETE CASCADE
        )
    """)

    cur.execute("""
        CREATE INDEX IF NOT EXISTS idx_messages_identifier
        ON messages (identifier)
    """)

    con.commit()
    con.close()

if __name__ == "__main__":
    init_db()
    print("Database initialized.")
