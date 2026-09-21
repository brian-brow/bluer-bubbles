use reqwest::{Client, RequestBuilder};
use serde::{de::DeserializeOwned, Deserialize, Serialize};

use crate::config::Config;

use tauri::State;

#[derive(Debug, Deserialize, Serialize)]
pub struct MacMessage {
    #[serde(rename = "ROWID")]
    pub row_id: i64,
    pub guid: Option<String>,
    pub identifier: String,
    pub service: Option<String>,
    pub text: Option<String>,
    pub date: Option<i64>,
    pub is_from_me: i64,
    pub is_system_message: i64,
    pub group_title: Option<String>,

    #[serde(rename = "cache_has_attachments")]
    pub has_attachments: i64,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct SendMessageResponse {
    pub success: bool,
    pub returncode: Option<i32>,
    pub stdout: Option<String>,
    pub error: Option<String>,
}

#[derive(Serialize)]
struct SendMessageRequest {
    identifier: String,
    message: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct MacContact {
    pub id: i64,
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub organization: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct MacContactIdentifier {
    pub contact_id: i64,
    pub value: String,
    #[serde(rename = "type")]
    pub identifier_type: String,
}

pub struct MacApi {
    client: Client,
    base_url: String,
    api_key: String,
}

impl MacApi {
    pub fn new(config: &Config) -> Result<Self, String> {
        let client = Client::builder()
            .timeout(std::time::Duration::from_secs(10))
            .build()
            .map_err(|error| error.to_string())?;

        Ok(Self {
            client,
            base_url: config.mac_api_url.trim_end_matches('/').to_string(),
            api_key: config.mac_api_key.clone(),
        })
    }

    async fn send_json<T>(&self, request: RequestBuilder) -> Result<T, String>
    where
        T: DeserializeOwned,
    {
        request
            .header("X-API-Key", &self.api_key)
            .send()
            .await
            .map_err(|error| error.to_string())?
            .error_for_status()
            .map_err(|error| error.to_string())?
            .json::<T>()
            .await
            .map_err(|error| error.to_string())
    }

    pub async fn messages_after(
        &self,
        row_id: i64,
    ) -> Result<Vec<MacMessage>, String> {
        let url = format!("{}/messages/{row_id}", self.base_url);

        self.send_json(self.client.get(url)).await
    }

    pub async fn send(
        &self,
        identifier: String,
        message: String,
    ) -> Result<SendMessageResponse, String> {
        let url = format!("{}/send", self.base_url);
        let body = SendMessageRequest { identifier, message };

        self.send_json( self
            .client
            .post(url)
            .json(&body),
        )
        .await
    }

    pub async fn contacts(&self) -> Result<Vec<MacContact>, String> {
        let url = format!("{}/contacts", self.base_url);

        self.send_json(self.client.get(url)).await
    }

    pub async fn contact_identifiers(
        &self,
    ) -> Result<Vec<MacContactIdentifier>, String> {
        let url = format!("{}/contacts/identifiers", self.base_url);

        self.send_json(self.client.get(url)).await
    }


}

#[tauri::command]
pub async fn fetch_mac_messages(
    mac_api: State<'_, MacApi>,
    row_id: i64,
) -> Result<Vec<MacMessage>, String> {
    mac_api.messages_after(row_id).await
}

#[tauri::command]
pub async fn send(
    mac_api: State<'_, MacApi>,
    identifier: String,
    message: String,
) -> Result<SendMessageResponse, String> {
    mac_api.send(identifier, message).await
}
