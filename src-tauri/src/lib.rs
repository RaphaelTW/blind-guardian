mod audit;
mod auth;
mod autostart;
mod icons;
mod inventory;
mod protection;
mod service_status;

use auth::AuthStore;
use inventory::InstalledApp;
use parking_lot::Mutex;
use protection::{ProtectionRecord, ProtectionState, ProtectionStore};
use std::fs;
use std::path::PathBuf;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{Emitter, Manager, State, WindowEvent};

struct AppState {
    auth: AuthStore,
    protection: ProtectionStore,
    manual_path: PathBuf,
    audit_path: PathBuf,
    manual_gate: Mutex<()>,
}

fn require(state: &State<'_, AppState>, token: &str) -> Result<(), String> {
    state.auth.require_session(token)
}

#[tauri::command]
fn is_initialized(state: State<'_, AppState>) -> bool {
    state.auth.initialized()
}

#[tauri::command]
fn initialize_admin(state: State<'_, AppState>, password: String) -> Result<(), String> {
    let result = state.auth.initialize(&password);
    audit::append(
        &state.audit_path,
        "initialize_admin",
        if result.is_ok() { "success" } else { "failure" },
    );
    result
}

#[tauri::command]
fn login(state: State<'_, AppState>, username: String, password: String) -> Result<String, String> {
    let result = state.auth.login(&username, &password);
    audit::append(
        &state.audit_path,
        "login",
        if result.is_ok() { "success" } else { "failure" },
    );
    result
}

#[tauri::command]
fn logout(state: State<'_, AppState>) {
    state.auth.logout();
}

#[tauri::command]
fn change_credentials(
    state: State<'_, AppState>,
    token: String,
    current_username: String,
    current_password: String,
    new_username: String,
    new_password: String,
) -> Result<(), String> {
    require(&state, &token)?;
    let result = state.auth.change_credentials(
        &current_username,
        &current_password,
        &new_username,
        &new_password,
    );
    audit::append(
        &state.audit_path,
        "change_credentials",
        if result.is_ok() { "success" } else { "failure" },
    );
    result
}

fn manual_apps(state: &AppState) -> Result<Vec<InstalledApp>, String> {
    if !state.manual_path.exists() {
        return Ok(Vec::new());
    }
    let bytes = fs::read(&state.manual_path).map_err(|e| e.to_string())?;
    serde_json::from_slice(&bytes).map_err(|_| "Inventário manual inválido.".into())
}

#[tauri::command]
fn list_installed(state: State<'_, AppState>, token: String) -> Result<Vec<InstalledApp>, String> {
    require(&state, &token)?;
    let mut apps = inventory::list();
    apps.extend(manual_apps(&state)?);
    Ok(apps)
}

#[tauri::command]
fn add_manual(
    state: State<'_, AppState>,
    token: String,
    path: String,
) -> Result<InstalledApp, String> {
    require(&state, &token)?;
    let path = inventory::validate_manual_path(&path)?;
    let _guard = state.manual_gate.lock();
    let mut apps = manual_apps(&state)?;
    let path_text = path.to_string_lossy().into_owned();
    if apps
        .iter()
        .any(|a| a.executable.as_deref() == Some(&path_text))
    {
        return Err("Executável já adicionado.".into());
    }
    let name = path
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "Aplicativo".into());
    let app = InstalledApp {
        id: format!("manual:{}", path_text.to_lowercase()),
        name,
        version: String::new(),
        publisher: String::new(),
        executable: Some(path_text),
        icon: icons::extract_icon(&path),
    };
    apps.push(app.clone());
    let parent = state.manual_path.parent().ok_or("Caminho inválido.")?;
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    fs::write(
        &state.manual_path,
        serde_json::to_vec(&apps).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    audit::append(&state.audit_path, "add_manual", "success");
    Ok(app)
}

#[tauri::command]
fn list_protection(
    state: State<'_, AppState>,
    token: String,
) -> Result<Vec<ProtectionRecord>, String> {
    require(&state, &token)?;
    state.protection.list()
}

#[tauri::command]
fn request_protection(
    state: State<'_, AppState>,
    token: String,
    username: String,
    password: String,
    app_id: String,
) -> Result<ProtectionRecord, String> {
    require(&state, &token)?;
    state.auth.verify(&username, &password)?;
    let mut apps = inventory::list();
    apps.extend(manual_apps(&state)?);
    let app = apps
        .iter()
        .find(|a| a.id == app_id)
        .ok_or("Aplicativo não encontrado no inventário.")?;
    let result = state.protection.request(app);
    audit::append(
        &state.audit_path,
        "request_protection",
        if result.is_ok() { "pending" } else { "failure" },
    );
    result
}

#[tauri::command]
fn remove_protection_request(
    state: State<'_, AppState>,
    token: String,
    username: String,
    password: String,
    app_id: String,
) -> Result<(), String> {
    require(&state, &token)?;
    state.auth.verify(&username, &password)?;
    let result = state.protection.remove(&app_id);
    audit::append(
        &state.audit_path,
        "remove_protection_request",
        if result.is_ok() { "success" } else { "failure" },
    );
    result
}

#[tauri::command]
fn authorize_execution(
    state: State<'_, AppState>,
    app_id: String,
    password: String,
) -> Result<(), String> {
    let records = state.protection.list()?;
    let record = records
        .iter()
        .find(|r| r.app_id == app_id)
        .ok_or("Aplicativo não cadastrado.")?;
    if record.state != ProtectionState::Active {
        return Err(
            "A proteção ainda não está ativa; a senha não pode liberar este aplicativo.".into(),
        );
    }
    state.auth.verify_password(&password)?;
    audit::append(&state.audit_path, "authorize_execution", "unsupported");
    Err(format!(
        "{}: execução autorizada ainda não validada; nenhum aplicativo foi iniciado.",
        record.name
    ))
}

#[tauri::command]
fn service_status() -> &'static str {
    service_status::status()
}

#[tauri::command]
fn quit_authenticated(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    username: String,
    password: String,
    confirmed: bool,
) -> Result<(), String> {
    if !confirmed {
        return Err("Confirmação necessária.".into());
    }
    state.auth.verify(&username, &password)?;
    audit::append(&state.audit_path, "quit", "success");
    app.exit(0);
    Ok(())
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let data = app.path().app_data_dir()?;
            app.manage(AppState {
                auth: AuthStore::new(data.join("credentials.json")),
                protection: ProtectionStore::new(data.join("protection.json")),
                manual_path: data.join("manual-apps.json"),
                audit_path: data.join("audit.jsonl"),
                manual_gate: Mutex::new(()),
            });
            if !cfg!(debug_assertions) {
                let _ = autostart::register_for_current_user();
            }
            let open = MenuItem::with_id(app, "open", "Abrir Blind Guardian", true, None::<&str>)?;
            let status =
                MenuItem::with_id(app, "status", "Proteção: experimental", false, None::<&str>)?;
            let quit =
                MenuItem::with_id(app, "quit", "Encerrar Blind Guardian", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&open, &status, &quit])?;
            TrayIconBuilder::new()
                .icon(app.default_window_icon().ok_or("Ícone ausente")?.clone())
                .menu(&menu)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "open" | "quit" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                        if event.id.as_ref() == "quit" {
                            let _ = app.emit("quit-requested", ());
                        }
                    }
                    _ => {}
                })
                .build(app)?;
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
                window.state::<AppState>().auth.logout();
                let _ = window.emit("session-closed", ());
            }
        })
        .invoke_handler(tauri::generate_handler![
            is_initialized,
            initialize_admin,
            login,
            logout,
            change_credentials,
            list_installed,
            add_manual,
            list_protection,
            request_protection,
            remove_protection_request,
            authorize_execution,
            service_status,
            quit_authenticated
        ])
        .run(tauri::generate_context!())
        .expect("Falha ao iniciar Blind Guardian");
}
