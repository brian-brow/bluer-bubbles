from fastapi import APIRouter
from subprocess import Popen, PIPE
from pydantic import BaseModel
from attributed_body import extract_text_from_attributed_body

import sqlite3

router = APIRouter()

class SendMessageRequest(BaseModel):
    identifier: str
    message: str

MESSAGES_DB_PATH = "file:/Users/brian/Library/Messages/chat.db?mode=ro"
CONTACTS_DB_PATH = "file:/Users/brian/Library/Application Support/AddressBook/Sources/A00AB68E-95C9-440F-88D0-576D7C3B6242/AddressBook-v22.abcddb?mode=ro"
LINUX_ENDPOINT = "http://100.74.253.10:8000/message"
POLL_INTERVAL = 2

@router.get("/")
async def root():
    return {"message": "Hello World"}

@router.post("/send")
async def send_message(payload: SendMessageRequest):
    scpt = """
        on run {targetNumber, messageText}
            tell application "Messages"
                set targetService to first account whose service type = iMessage
                set targetBuddy to participant targetNumber of targetService
                send messageText to targetBuddy
            end tell
        end run
    """
    args = [payload.identifier, payload.message]
    p = Popen(['osascript', '-'] + args, stdin=PIPE, stdout=PIPE, stderr=PIPE, text=True)
    stdout, stderr = p.communicate(scpt)

    if p.returncode != 0:
        print(f"AppleScript failed: {stderr}")
        return {"success": False, "error": stderr}

    return {"success": True, "returncode": p.returncode, "stdout": stdout}

@router.get("/contacts")
async def get_contacts():
    con = sqlite3.connect(CONTACTS_DB_PATH, uri = True)
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute("""
        SELECT
            Z_PK AS id,
            ZFIRSTNAME AS first_name,
            ZLASTNAME AS last_name,
            ZORGANIZATION AS organization
        FROM ZABCDRECORD;
        """)

    rows = cur.fetchall()
    con.close()

    return [dict(row) for row in rows]

@router.get("/contacts/identifiers")
async def get_contact_identifiers():
    con = sqlite3.connect(CONTACTS_DB_PATH, uri = True)
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute("""
        SELECT
            ZOWNER AS contact_id,
            ZFULLNUMBER AS value,
            'phone' AS type
        FROM ZABCDPHONENUMBER

        UNION ALL

        SELECT
            ZOWNER AS contact_id,
            ZADDRESS AS value,
            'email' AS type
        FROM ZABCDEMAILADDRESS
        """)

    rows = cur.fetchall()
    con.close()

    return [dict(row) for row in rows]


@router.get("/messages/{rowid}", tags=["messages"])
async def read_messages(rowid: int):
    con = sqlite3.connect(MESSAGES_DB_PATH, uri = True)
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    cur.execute("""
        SELECT
            message.ROWID,
            message.guid,
            handle.id AS identifier,
            message.service,
            message.text,
            message.date,
            message.is_from_me,
            message.is_system_message,
            message.group_title,
            message.cache_has_attachments,
            message.attributedBody
        FROM message
        JOIN handle
        ON message.handle_id = handle.ROWID
        WHERE message.ROWID > ?
        ORDER BY message.date DESC
        """, (rowid,))

    rows = cur.fetchall()
    con.close()

    json_rows = []

    for row in rows:
        row_dict = dict(row)
        row_dict['text'] = row_dict['text'] or extract_text_from_attributed_body(row_dict['attributedBody'])
        del row_dict['attributedBody']
        json_rows.append(row_dict)

    return json_rows
