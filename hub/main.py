import requests
import time
import os
import subprocess
from db import get_connection, get_last_seen_rowid
from dotenv import load_dotenv

MAC_ENDPOINT = "http://100.116.165.43:8000"
MESSAGE_POLL_INTERVAL = 2
CONTACTS_POLL_INTERVAL = 300
ERROR_SLEEP = 10

load_dotenv()

headers = {'X-API-Key': os.environ.get('BLUE_BUBBLES_API_KEY')}

def send_notification(con, cur, identifier, message):

    cur.execute("""
        SELECT contacts.first_name, contacts.last_name
        FROM contact_identifiers
        JOIN contacts
        ON contacts.id = contact_identifiers.contact_id
        WHERE contact_identifiers.value = ?
    """, (identifier,))

    row = cur.fetchone()

    if not row:
        name = identifier
    else:
        first = row['first_name'] or ''
        last = row['last_name'] or ''
        name = (first + ' ' + last).strip() or identifier

    subprocess.run(['notify-send', name, message], check=False)


def sync_messages():
    latest_id = get_last_seen_rowid()
    try:
        r = requests.get(MAC_ENDPOINT + '/messages/' + str(latest_id), headers=headers, timeout=10)
        r.raise_for_status()
        messages = r.json()
    except requests.RequestException as e:
        print(f"Request failed {e}")
        return

    if messages:
        con = get_connection()
        cur = con.cursor()

        for msg in messages:
            cur.execute("""
                INSERT OR IGNORE INTO messages (id, guid, identifier, service, text, date, is_from_me, is_system_message, group_title, has_attachments)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ? ,?)
            """, (msg['ROWID'], msg['guid'], msg['identifier'], msg['service'], msg['text'], msg['date'], msg['is_from_me'], msg['is_system_message'], msg['group_title'], msg['cache_has_attachments']))
            if not msg['is_from_me'] and latest_id != 0:
                send_notification(con, cur, msg['identifier'], msg['text'])
        print(f"{len(messages)} pushed successfully")
        con.commit()
        con.close()
    else:
        print("no messages!")

def sync_contacts():
    try:
        r = requests.get(MAC_ENDPOINT + '/contacts', headers=headers, timeout=5)
        r.raise_for_status()
        contacts = r.json()
    except requests.RequestException as e:
        print(f"Request failed {e}")
        return

    if contacts:
        con = get_connection()
        cur = con.cursor()

        for contact in contacts:
            cur.execute("""
                INSERT OR IGNORE INTO contacts (id, first_name, last_name, organization)
                VALUES (?, ?, ?, ?)
            """, (contact['id'], contact['first_name'], contact['last_name'], contact['organization']))
        print(f"{len(contacts)} pushed successfully")
        con.commit()
        con.close()
    else:
        print("no messages!")

def sync_contact_identifiers():
    try:
        r = requests.get(MAC_ENDPOINT + '/contacts/identifiers', headers=headers, timeout=5)
        r.raise_for_status()
        contact_identifiers = r.json()
    except requests.RequestException as e:
        print(f"Request failed {e}")
        return

    if contact_identifiers:
        con = get_connection()
        cur = con.cursor()

        for identifier in contact_identifiers:
            cur.execute("""
                INSERT OR IGNORE INTO contact_identifiers (contact_id, value, type)
                VALUES (?, ?, ?)
            """, (identifier['contact_id'], identifier['value'], identifier['type']))
        print(f"{len(contact_identifiers)} pushed successfully")
        con.commit()
        con.close()
    else:
        print("no messages!")

last_contacts_sync = 0

while True:
    sync_messages()

    if time.time() - last_contacts_sync > CONTACTS_POLL_INTERVAL:
        sync_contacts()
        sync_contact_identifiers()
        last_contacts_sync = time.time()

    time.sleep(MESSAGE_POLL_INTERVAL)


