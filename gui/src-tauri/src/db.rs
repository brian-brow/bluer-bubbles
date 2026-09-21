use std::fs;
use std::path::PathBuf;

use rusqlite::{params, Connection};
use serde::Serialize;
use tauri::{AppHandle, Manager, State};

use crate::mac_api::{MacContact, MacContactIdentifier, MacMessage};

#[derive(Debug, Serialize)]
pub struct Message {
    pub id: i64,
    pub guid: Option<String>,
    pub identifier: String,
    pub service: Option<String>,
    pub text: Option<String>,
    pub date: Option<i64>,
    pub is_from_me: i64,
    pub is_system_message: i64,
    pub group_title: Option<String>,
    pub has_attachments: i64,
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub organization: Option<String>,
}

pub struct Database {
    path: PathBuf,
}

impl Database {
    pub fn open(app: &AppHandle) -> Result<Self, String> {
        let data_dir = app
            .path()
            .app_data_dir()
            .map_err(|error| error.to_string())?;

        fs::create_dir_all(&data_dir)
            .map_err(|error| error.to_string())?;

        let path = data_dir.join("messages.db");
        let database = Self { path };

        database.init_schema()?;

        Ok(database)
    }

    fn connection(&self) -> Result<Connection, String> {
        let connection =
            Connection::open(&self.path).map_err(|error| error.to_string())?;

        connection
            .execute("PRAGMA foreign_keys = ON", [])
            .map_err(|error| error.to_string())?;

        Ok(connection)
    }

    fn init_schema(&self) -> Result<(), String> {
        let connection = self.connection()?;

        connection
            .execute_batch(
                "
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
                );

                CREATE TABLE IF NOT EXISTS attachments (
                    id INTEGER PRIMARY KEY,
                    guid TEXT UNIQUE,
                    message_id INTEGER NOT NULL,
                    filename TEXT,
                    mime_type TEXT,
                    total_bytes INTEGER,
                    last_accessed_at INTEGER,
                    FOREIGN KEY (message_id)
                        REFERENCES messages (id)
                        ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS contacts (
                    id INTEGER PRIMARY KEY,
                    first_name TEXT,
                    last_name TEXT,
                    organization TEXT
                );

                CREATE TABLE IF NOT EXISTS contact_identifiers (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    contact_id INTEGER NOT NULL,
                    value TEXT NOT NULL UNIQUE,
                    type TEXT NOT NULL,
                    FOREIGN KEY (contact_id)
                        REFERENCES contacts (id)
                        ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS idx_messages_identifier
                    ON messages (identifier);
                ",
            )
            .map_err(|error| error.to_string())?;

        Ok(())
    }

    pub fn last_message_id(&self) -> Result<i64, String> {
        let connection = self.connection()?;

        connection
            .query_row(
                "SELECT COALESCE(MAX(id), 0) FROM messages",
                [],
                |row| row.get(0),
            )
            .map_err(|error| error.to_string())
    }

    pub fn insert_messages(
        &self,
        messages: &[MacMessage],
    ) -> Result<Vec<i64>, String> {
        let mut connection = self.connection()?;
        let transaction = connection.transaction().map_err(|error| error.to_string())?;
        let mut inserted_ids = Vec::new();

        for message in messages {
            let inserted = transaction
                .execute(
                    "
                    INSERT OR IGNORE INTO messages (
                        id,
                        guid,
                        identifier,
                        service,
                        text,
                        date,
                        is_from_me,
                        is_system_message,
                        group_title,
                        has_attachments
                    )
                    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
                    ",
                    params![
                        message.row_id,
                        message.guid,
                        message.identifier,
                        message.service,
                        message.text,
                        message.date,
                        message.is_from_me,
                        message.is_system_message,
                        message.group_title,
                        message.has_attachments,
                    ],
                )
                .map_err(|error| error.to_string())?;

            if inserted == 1 {
                inserted_ids.push(message.row_id);
            }
        }

        transaction.commit().map_err(|error| error.to_string())?;

        Ok(inserted_ids)
    }

    pub fn upsert_contacts(&self, contacts: &[MacContact]) -> Result<(), String> {
        let mut connection = self.connection()?;
        let transaction = connection.transaction().map_err(|error| error.to_string())?;

        for contact in contacts {
            transaction
                .execute(
                    "
                    INSERT INTO contacts (id, first_name, last_name, organization)
                    VALUES (?1, ?2, ?3, ?4)
                    ON CONFLICT(id) DO UPDATE SET
                        first_name = excluded.first_name,
                        last_name = excluded.last_name,
                        organization = excluded.organization
                    ",
                    params![
                        contact.id,
                        contact.first_name,
                        contact.last_name,
                        contact.organization,
                    ],
                )
                .map_err(|error| error.to_string())?;
        }

        transaction.commit().map_err(|error| error.to_string())
    }

    pub fn upsert_contact_identifiers(
        &self,
        identifiers: &[MacContactIdentifier],
    ) -> Result<(), String> {
        let mut connection = self.connection()?;
        let transaction = connection.transaction().map_err(|error| error.to_string())?;

        for identifier in identifiers {
            transaction
                .execute(
                    "
                    INSERT INTO contact_identifiers (contact_id, value, type)
                    VALUES (?1, ?2, ?3)
                    ON CONFLICT(value) DO UPDATE SET
                        contact_id = excluded.contact_id,
                        type = excluded.type
                    ",
                    params![
                        identifier.contact_id,
                        identifier.value,
                        identifier.identifier_type,
                    ],
                )
                .map_err(|error| error.to_string())?;
        }

        transaction.commit().map_err(|error| error.to_string())
    }
}

#[tauri::command]
pub fn list_latest_messages(
    database: State<'_, Database>,
    before_id: Option<i64>,
    limit: u32,
) -> Result<Vec<Message>, String> {
    let connection = database.connection()?;
    let limit = i64::from(limit.min(100));

    let mut statement = connection
        .prepare(
            "
            WITH latest AS (
                SELECT
                    messages.*,
                    ROW_NUMBER() OVER (
                        PARTITION BY identifier
                        ORDER BY id DESC
                    ) AS row_number
                FROM messages
            )
            SELECT
                latest.id,
                latest.guid,
                latest.identifier,
                latest.service,
                latest.text,
                latest.date,
                latest.is_from_me,
                latest.is_system_message,
                latest.group_title,
                latest.has_attachments,
                contacts.first_name,
                contacts.last_name,
                contacts.organization
            FROM latest
            LEFT JOIN contact_identifiers
                ON latest.identifier = contact_identifiers.value
            LEFT JOIN contacts
                ON contact_identifiers.contact_id = contacts.id
            WHERE latest.row_number = 1
                AND (?1 IS NULL OR latest.id < ?1)
            ORDER BY latest.id DESC
            LIMIT ?2
            ",
        )
        .map_err(|error| error.to_string())?;

    let messages = statement
        .query_map(params![before_id, limit], |row| {
            Ok(Message {
                id: row.get("id")?,
                guid: row.get("guid")?,
                identifier: row.get("identifier")?,
                service: row.get("service")?,
                text: row.get("text")?,
                date: row.get("date")?,
                is_from_me: row.get("is_from_me")?,
                is_system_message: row.get("is_system_message")?,
                group_title: row.get("group_title")?,
                has_attachments: row.get("has_attachments")?,
                first_name: row.get("first_name")?,
                last_name: row.get("last_name")?,
                organization: row.get("organization")?,
            })
        })
        .map_err(|error| error.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| error.to_string())?;

    Ok(messages)
}


#[tauri::command]
pub fn list_messages(
    identifier: String,
    database: State<'_, Database>,
    before_id: Option<i64>,
    limit: u32,
) -> Result<Vec<Message>, String> {
    let connection = database.connection()?;
    let limit = i64::from(limit.min(100));

    let mut statement = connection
        .prepare(
            "
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
            WHERE messages.identifier = ?1
                AND (?2 IS NULL OR messages.id < ?2)
            ORDER BY messages.id DESC
            LIMIT ?3
            ",
        )
        .map_err(|error| error.to_string())?;

    let messages = statement
        .query_map(params![identifier, before_id, limit], |row| {
            Ok(Message {
                id: row.get("id")?,
                guid: row.get("guid")?,
                identifier: row.get("identifier")?,
                service: row.get("service")?,
                text: row.get("text")?,
                date: row.get("date")?,
                is_from_me: row.get("is_from_me")?,
                is_system_message: row.get("is_system_message")?,
                group_title: row.get("group_title")?,
                has_attachments: row.get("has_attachments")?,
                first_name: row.get("first_name")?,
                last_name: row.get("last_name")?,
                organization: row.get("organization")?,
            })
        })
        .map_err(|error| error.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| error.to_string())?;

    Ok(messages)
}
