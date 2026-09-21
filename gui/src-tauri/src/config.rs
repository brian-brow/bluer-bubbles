use std::fs;

use serde::Deserialize;
use tauri::{AppHandle, Manager};

#[derive(Debug, Deserialize)]
pub struct Config {
    pub mac_api_url: String,
    pub mac_api_key: String,
}

impl Config {
    pub fn load(app: &AppHandle) -> Result<Self, String> {
        let config_dir = app
            .path()
            .app_config_dir()
            .map_err(|error| error.to_string())?;

        let path = config_dir.join("config.json");
        let contents = fs::read_to_string(&path)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?;

        serde_json::from_str(&contents)
            .map_err(|error| format!("failed to parse {}: {error}", path.display()))
    }
}
