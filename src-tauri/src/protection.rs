use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use uuid::Uuid;

#[derive(Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ProtectionState {
    Unprotected,
    PendingValidation,
    Active,
    TemporarilyAuthorized,
    Unsupported,
    Failed,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProtectionRecord {
    pub app_id: String,
    pub name: String,
    pub executable: String,
    pub state: ProtectionState,
    pub strategy: String,
    pub detail: String,
}

pub trait ProtectionAdapter: Send + Sync {
    fn id(&self) -> &'static str;
    fn supports(&self, executable: &str) -> bool;
    fn verify_active(&self, executable: &str) -> Result<bool, String>;
}

pub struct AnyDeskAdapter;
impl ProtectionAdapter for AnyDeskAdapter {
    fn id(&self) -> &'static str {
        "anydesk-experimental"
    }
    fn supports(&self, executable: &str) -> bool {
        executable
            .rsplit(['\\', '/'])
            .next()
            .is_some_and(|name| name.eq_ignore_ascii_case("AnyDesk.exe"))
    }
    fn verify_active(&self, _executable: &str) -> Result<bool, String> {
        // O adaptador ainda não dispõe de verificação de serviço, AppLocker e conexão remota.
        Ok(false)
    }
}

pub struct ProtectionStore {
    path: PathBuf,
    gate: Mutex<()>,
    adapters: Vec<Box<dyn ProtectionAdapter>>,
}

impl ProtectionStore {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            gate: Mutex::new(()),
            adapters: vec![Box::new(AnyDeskAdapter)],
        }
    }

    fn read(&self) -> Result<Vec<ProtectionRecord>, String> {
        if !self.path.exists() {
            return Ok(Vec::new());
        }
        let bytes = fs::read(&self.path).map_err(|e| e.to_string())?;
        serde_json::from_slice(&bytes).map_err(|_| "Arquivo de proteção inválido.".into())
    }

    fn write(&self, records: &[ProtectionRecord]) -> Result<(), String> {
        let parent = self.path.parent().ok_or("Caminho inválido.")?;
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        let temp = self.path.with_extension(format!("{}.tmp", Uuid::new_v4()));
        let bytes = serde_json::to_vec(records).map_err(|e| e.to_string())?;
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)
            .map_err(|e| e.to_string())?;
        file.write_all(&bytes)
            .and_then(|_| file.sync_all())
            .map_err(|e| e.to_string())?;
        fs::rename(temp, &self.path).map_err(|e| e.to_string())
    }

    pub fn list(&self) -> Result<Vec<ProtectionRecord>, String> {
        let _guard = self.gate.lock();
        let mut records = self.read()?;
        for record in &mut records {
            if record.state == ProtectionState::Active
                || record.state == ProtectionState::TemporarilyAuthorized
            {
                let verified = self
                    .adapters
                    .iter()
                    .find(|a| a.id() == record.strategy)
                    .and_then(|a| a.verify_active(&record.executable).ok())
                    .unwrap_or(false);
                if !verified {
                    record.state = ProtectionState::Failed;
                    record.detail = "A proteção não pôde ser verificada.".into();
                }
            }
        }
        self.write(&records)?;
        Ok(records)
    }

    pub fn request(
        &self,
        app: &crate::inventory::InstalledApp,
    ) -> Result<ProtectionRecord, String> {
        let executable = app
            .executable
            .as_ref()
            .ok_or("Executável não identificado; adicione o EXE manualmente.")?;
        let path = crate::inventory::validate_manual_path(executable)?;
        let normalized = path.to_string_lossy().to_lowercase();
        if normalized.contains("\\windows\\")
            || normalized.contains("\\blind guardian\\")
            || app.name.to_lowercase().contains("sophos")
            || app.name.to_lowercase().contains("defender")
        {
            return Err("Este aplicativo não pode ser selecionado para proteção.".into());
        }
        let _guard = self.gate.lock();
        let mut records = self.read()?;
        if records.iter().any(|r| r.app_id == app.id) {
            return Err("Aplicativo já solicitado.".into());
        }
        let adapter = self.adapters.iter().find(|a| a.supports(executable));
        let record = ProtectionRecord {
            app_id: app.id.clone(),
            name: app.name.clone(),
            executable: executable.clone(),
            state: ProtectionState::PendingValidation,
            strategy: adapter.map_or("generic-experimental", |a| a.id()).into(),
            detail: "Política ainda não aplicada. A execução permanece livre.".into(),
        };
        records.push(record.clone());
        self.write(&records)?;
        Ok(record)
    }

    pub fn remove(&self, app_id: &str) -> Result<(), String> {
        let _guard = self.gate.lock();
        let mut records = self.read()?;
        let original = records.len();
        records.retain(|r| {
            r.app_id != app_id
                || r.state == ProtectionState::Active
                || r.state == ProtectionState::TemporarilyAuthorized
        });
        if original == records.len() {
            return Err(
                "Registro não encontrado ou proteção ativa; remoção exige o serviço.".into(),
            );
        }
        self.write(&records)
    }
}
