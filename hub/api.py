from fastapi import APIRouter
from pydantic import BaseModel
from db import get_connection
from dotenv import load_dotenv
import os
import requests

MAC_ENDPOINT = "http://100.116.165.43:8000/send"

load_dotenv()

headers = {'X-API-Key': os.environ.get('BLUE_BUBBLES_API_KEY')}

router = APIRouter()

class SendMessageRequest(BaseModel):
    identifier: str
    message: str

@router.get("/messages")
async def get_all_messages():
    con = get_connection()

    cur = con.cursor()
    cur.execute("""
        SELECT
            messages.id,
            messages.guid,
            messages.identifier,
            messages.service,
            messages.text,
            messages.date,
            messages.is_from_me,
            messages.is_system_message,
            messages.group_title,
            messages.has_attachments,
            contacts.first_name,
            contacts.last_name,
            contacts.organization
        FROM messages
        LEFT JOIN contact_identifiers
        ON messages.identifier = contact_identifiers.value
        LEFT JOIN contacts
        ON contact_identifiers.contact_id = contacts.id
        ORDER BY messages.date DESC
        """)

    rows = cur.fetchall()
    con.close()

    return [dict(row) for row in rows]

@router.get("/messages/first")
async def get_all_latest_messages():
    con = get_connection()

    cur = con.cursor()
    cur.execute("""
        SELECT
            messages.id,
            messages.guid,
            messages.identifier,
            messages.service,
            messages.text,
            messages.date,
            messages.is_from_me,
            messages.is_system_message,
            messages.group_title,
            messages.has_attachments,
            contacts.first_name,
            contacts.last_name,
            contacts.organization
        FROM (
            SELECT *,
                ROW_NUMBER() OVER (PARTITION BY identifier ORDER BY date DESC) AS rn
            FROM messages
        ) AS messages
        LEFT JOIN contact_identifiers
            ON messages.identifier = contact_identifiers.value
        LEFT JOIN contacts
            ON contact_identifiers.contact_id = contacts.id
        WHERE messages.rn = 1
        ORDER BY messages.date DESC
    """)

    rows = cur.fetchall()
    con.close()

    return [dict(row) for row in rows]

@router.get("/messages/{identifier}")
async def get_message_by_phone(identifier: str):
    con = get_connection()

    cur = con.cursor()
    cur.execute("""
        SELECT
            messages.id,
            messages.guid,
            messages.identifier,
            messages.service,
            messages.text,
            messages.date,
            messages.is_from_me,
            messages.is_system_message,
            messages.group_title,
            messages.has_attachments,
            contacts.first_name,
            contacts.last_name,
            contacts.organization
        FROM messages
        LEFT JOIN contact_identifiers
            ON messages.identifier = contact_identifiers.value
        LEFT JOIN contacts
            ON contact_identifiers.contact_id = contacts.id
        WHERE messages.identifier = ?
        ORDER BY messages.date DESC
        LIMIT 40
        """, (identifier,))

    rows = cur.fetchall()
    con.close()

    return [dict(row) for row in rows]

@router.post("/send")
async def send_message(payload: SendMessageRequest):
    try:
        r = requests.post(MAC_ENDPOINT, headers=headers, json=payload.model_dump(), timeout=5)
        r.raise_for_status()
        return r.json()

    except requests.RequestException as e:
        return {"error": str(e)}
