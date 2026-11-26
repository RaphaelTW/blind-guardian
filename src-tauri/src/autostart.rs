use winreg::{enums::HKEY_CURRENT_USER, RegKey};

pub fn register_for_current_user() -> Result<(), String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let command = format!("\"{}\"", exe.display());
    let current = RegKey::predef(HKEY_CURRENT_USER);
    let (run, _) = current
        .create_subkey(r"Software\Microsoft\Windows\CurrentVersion\Run")
        .map_err(|e| e.to_string())?;
    run.set_value("BlindGuardian", &command)
        .map_err(|e| e.to_string())
}
