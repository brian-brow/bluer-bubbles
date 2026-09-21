// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/

mod config;
mod db;

use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let config = config::Config::load(app.handle())
                .map_err(std::io::Error::other)?;

            let database = db::Database::open(app.handle())
                .map_err(std::io::Error::other)?;

            app.manage(config);
            app.manage(database);

            Ok(())
        })
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![
            db::list_messages,
            db::list_latest_messages,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}





