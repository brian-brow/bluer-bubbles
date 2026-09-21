use crate::db::Database;
use crate::mac_api::MacApi;

pub async fn sync_contacts(
    database: &Database,
    mac_api: &MacApi,
) -> Result<(), String> {
    let contacts = mac_api.contacts().await?;
    database.upsert_contacts(&contacts)?;

    let identifiers = mac_api.contact_identifiers().await?;
    database.upsert_contact_identifiers(&identifiers)?;

    Ok(())
}

pub async fn sync_messages(
    database: &Database,
    mac_api: &MacApi,
) -> Result<Vec<i64>, String> {
    let last_id = database.last_message_id()?;
    let messages = mac_api.messages_after(last_id).await?;

    database.insert_messages(&messages)
}
