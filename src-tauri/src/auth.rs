use argon2::password_hash::{
    rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString,
};
use argon2::Argon2;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use uuid::Uuid;

const MAX_FAILURES: u32 = 5;
const LOCK_SECONDS: u64 = 300;
const SESSION_SECONDS: u64 = 1800;

#[derive(Serialize, Deserialize)]
struct CredentialFile {
    username: String,
    password_hash: String,
    failures: u32,
    locked_until: u64,
}

#[derive(Clone)]
struct Session {
    token: String,
    expires: u64,
}

pub struct AuthStore {
    path: PathBuf,
    session: Mutex<Option<Session>>,
    file_lock: Mutex<()>,
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO)
        .as_secs()
}

impl AuthStore {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            session: Mutex::new(None),
            file_lock: Mutex::new(()),
        }
    }

    pub fn initialized(&self) -> bool {
        self.path.exists()
    }

    pub fn initialize(&self, password: &str) -> Result<(), String> {
        if password.len() < 12 || password.len() > 256 {
            return Err("A senha deve ter entre 12 e 256 caracteres.".into());
        }
        let _guard = self.file_lock.lock();
        if self.path.exists() {
            return Err("Credenciais já configuradas.".into());
        }
        let salt = SaltString::generate(&mut OsRng);
        let hash = Argon2::default()
            .hash_password(password.as_bytes(), &salt)
            .map_err(|_| "Falha ao criar hash de senha.")?
            .to_string();
        let record = CredentialFile {
            username: "rakdos".into(),
            password_hash: hash,
            failures: 0,
            locked_until: 0,
        };
        let parent = self.path.parent().ok_or("Caminho de dados inválido.")?;
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&self.path)
            .map_err(|e| e.to_string())?;
        let bytes = serde_json::to_vec(&record).map_err(|e| e.to_string())?;
        file.write_all(&bytes)
            .and_then(|_| file.sync_all())
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    fn read(&self) -> Result<CredentialFile, String> {
        let mut bytes = Vec::new();
        OpenOptions::new()
            .read(true)
            .open(&self.path)
            .and_then(|mut f| f.read_to_end(&mut bytes))
            .map_err(|e| e.to_string())?;
        serde_json::from_slice(&bytes).map_err(|_| "Arquivo de credenciais inválido.".into())
    }

    fn write(&self, record: &CredentialFile) -> Result<(), String> {
        let temp = self.path.with_extension(format!("{}.tmp", Uuid::new_v4()));
        let bytes = serde_json::to_vec(record).map_err(|e| e.to_string())?;
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)
            .map_err(|e| e.to_string())?;
        file.write_all(&bytes)
            .and_then(|_| file.sync_all())
            .map_err(|e| e.to_string())?;
        fs::rename(&temp, &self.path).map_err(|e| e.to_string())
    }

    pub fn verify(&self, username: &str, password: &str) -> Result<(), String> {
        let _guard = self.file_lock.lock();
        let mut record = self.read()?;
        if now() < record.locked_until {
            return Err("Muitas tentativas. Aguarde cinco minutos.".into());
        }
        let parsed =
            PasswordHash::new(&record.password_hash).map_err(|_| "Hash de senha inválido.")?;
        let valid_password = Argon2::default()
            .verify_password(password.as_bytes(), &parsed)
            .is_ok();
        if !valid_password || username != record.username {
            record.failures = record.failures.saturating_add(1);
            if record.failures >= MAX_FAILURES {
                record.locked_until = now() + LOCK_SECONDS;
                record.failures = 0;
            }
            self.write(&record)?;
            return Err("Credenciais incorretas.".into());
        }
        record.failures = 0;
        record.locked_until = 0;
        self.write(&record)?;
        Ok(())
    }

    pub fn verify_password(&self, password: &str) -> Result<(), String> {
        let username = {
            let _guard = self.file_lock.lock();
            self.read()?.username
        };
        self.verify(&username, password)
    }

    pub fn login(&self, username: &str, password: &str) -> Result<String, String> {
        self.verify(username, password)?;
        let token = Uuid::new_v4().to_string();
        *self.session.lock() = Some(Session {
            token: token.clone(),
            expires: now() + SESSION_SECONDS,
        });
        Ok(token)
    }

    pub fn change_credentials(
        &self,
        current_username: &str,
        current_password: &str,
        new_username: &str,
        new_password: &str,
    ) -> Result<(), String> {
        self.verify(current_username, current_password)?;
        if new_username.len() < 3
            || new_username.len() > 64
            || !new_username
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        {
            return Err("Username inválido (3 a 64 letras, números, _ ou -).".into());
        }
        if new_password.len() < 12 || new_password.len() > 256 {
            return Err("A senha deve ter entre 12 e 256 caracteres.".into());
        }
        let salt = SaltString::generate(&mut OsRng);
        let hash = Argon2::default()
            .hash_password(new_password.as_bytes(), &salt)
            .map_err(|_| "Falha ao criar hash de senha.")?
            .to_string();
        let _guard = self.file_lock.lock();
        let mut record = self.read()?;
        record.username = new_username.to_owned();
        record.password_hash = hash;
        record.failures = 0;
        record.locked_until = 0;
        self.write(&record)?;
        self.logout();
        Ok(())
    }

    pub fn require_session(&self, token: &str) -> Result<(), String> {
        let mut session = self.session.lock();
        match session.as_mut() {
            Some(s) if s.token == token && s.expires > now() => {
                s.expires = now() + SESSION_SECONDS;
                Ok(())
            }
            _ => {
                *session = None;
                Err("Sessão expirada. Entre novamente.".into())
            }
        }
    }

    pub fn logout(&self) {
        *self.session.lock() = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn password_is_hashed_and_lockout_is_persisted() {
        let path = std::env::temp_dir().join(format!("bg-auth-test-{}.json", Uuid::new_v4()));
        let password = Uuid::new_v4().to_string();
        let store = AuthStore::new(path.clone());
        store.initialize(&password).unwrap();
        let file = fs::read_to_string(&path).unwrap();
        assert!(file.contains("$argon2id$"));
        assert!(!file.contains(&password));
        assert!(store.verify("rakdos", &password).is_ok());
        for _ in 0..5 {
            assert!(store.verify("rakdos", "wrong").is_err());
        }
        assert!(store.verify("rakdos", &password).is_err());
        let restarted = AuthStore::new(path.clone());
        assert!(restarted.verify("rakdos", &password).is_err());
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn changing_credentials_invalidates_existing_session() {
        let path = std::env::temp_dir().join(format!("bg-auth-change-{}.json", Uuid::new_v4()));
        let first = Uuid::new_v4().to_string();
        let second = Uuid::new_v4().to_string();
        let store = AuthStore::new(path.clone());
        store.initialize(&first).unwrap();
        let token = store.login("rakdos", &first).unwrap();
        store
            .change_credentials("rakdos", &first, "new_admin", &second)
            .unwrap();
        assert!(store.require_session(&token).is_err());
        assert!(store.login("rakdos", &first).is_err());
        assert!(store.login("new_admin", &second).is_ok());
        fs::remove_file(path).unwrap();
    }
}
