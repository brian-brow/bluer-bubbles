// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/

mod config;
mod db;
mod mac_api;
mod sync;

use std::time::{Duration, Instant};
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let config = config::Config::load(app.handle())
                .map_err(std::io::Error::other)?;

            let database = db::Database::open(app.handle())
                .map_err(std::io::Error::other)?;

            let mac_api = mac_api::MacApi::new(&config)
                .map_err(std::io::Error::other)?;

            app.manage(database);
            app.manage(mac_api);

            let app_handle = app.handle().clone();

            tauri::async_runtime::spawn(async move {
                let mut last_contacts_sync =
                    Instant::now() - Duration::from_secs(300);

                loop {
                    let database = app_handle.state::<db::Database>();
                    let mac_api = app_handle.state::<mac_api::MacApi>();

                    match sync::sync_messages(&database, &mac_api).await {
                        Ok(inserted_ids) => {
                            if !inserted_ids.is_empty() {
                                println!(
                                    "Inserted {} new messages",
                                    inserted_ids.len()
                                );
                            }
                        }
                        Err(error) => {
                            eprintln!("message sync failed: {error}");
                        }
                    }

                    if last_contacts_sync.elapsed() >= Duration::from_secs(300) {
                        if let Err(error) =
                            sync::sync_contacts(&database, &mac_api).await
                        {
                            eprintln!("contact sync failed: {error}");
                        }

                        last_contacts_sync = Instant::now();
                    }

                    tokio::time::sleep(
                        std::time::Duration::from_secs(2)
                    ).await;
                }
            });

            Ok(())
        })
    .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![
            db::list_messages,
            db::list_latest_messages,
            mac_api::fetch_mac_messages,
            mac_api::send,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
    }
