use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use winreg::enums::{HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE};
use winreg::RegKey;

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InstalledApp {
    pub id: String,
    pub name: String,
    pub version: String,
    pub publisher: String,
    pub executable: Option<String>,
    pub icon: Option<String>,
}

fn icon_path(raw: &str) -> Option<PathBuf> {
    let value = raw.trim();
    let path = if let Some(stripped) = value.strip_prefix('"') {
        stripped.split('"').next().unwrap_or("")
    } else {
        value.rsplit_once(',').map(|(p, _)| p).unwrap_or(value)
    };
    let expanded = std::env::vars().fold(path.to_owned(), |acc, (key, val)| {
        acc.replace(&format!("%{key}%"), &val)
    });
    let p = PathBuf::from(expanded);
    if p.is_file() {
        Some(p)
    } else {
        None
    }
}

fn registry_entries(root: &RegKey, hive: &str, key_path: &str, apps: &mut Vec<InstalledApp>) {
    let Ok(uninstall) = root.open_subkey(key_path) else {
        return;
    };
    for sub_name in uninstall.enum_keys().flatten() {
        let Ok(sub) = uninstall.open_subkey(&sub_name) else {
            continue;
        };
        let name: String = sub.get_value("DisplayName").unwrap_or_default();
        let name = name.trim();
        if name.is_empty() || sub.get_value::<u32, _>("SystemComponent").unwrap_or(0) == 1 {
            continue;
        }
        let version: String = sub.get_value("DisplayVersion").unwrap_or_default();
        let publisher: String = sub.get_value("Publisher").unwrap_or_default();
        let raw_icon: String = sub.get_value("DisplayIcon").unwrap_or_default();
        let executable = icon_path(&raw_icon).filter(|p| {
            p.extension()
                .is_some_and(|e| e.to_string_lossy().eq_ignore_ascii_case("exe"))
        });
        let icon_source = icon_path(&raw_icon).or_else(|| executable.clone());
        let icon = icon_source.as_deref().and_then(crate::icons::extract_icon);
        apps.push(InstalledApp {
            id: format!("{}:{}:{}", hive, key_path, sub_name),
            name: name.to_owned(),
            version,
            publisher,
            executable: executable.map(|p| p.to_string_lossy().into_owned()),
            icon,
        });
    }
}

pub fn list() -> Vec<InstalledApp> {
    let mut apps = Vec::new();
    let locations = [
        r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    ];
    for location in locations {
        registry_entries(
            &RegKey::predef(HKEY_LOCAL_MACHINE),
            "HKLM",
            location,
            &mut apps,
        );
        registry_entries(
            &RegKey::predef(HKEY_CURRENT_USER),
            "HKCU",
            location,
            &mut apps,
        );
    }
    let mut seen = HashSet::new();
    apps.retain(|a| {
        seen.insert(format!(
            "{}|{}|{}",
            a.name.to_lowercase(),
            a.version.to_lowercase(),
            a.publisher.to_lowercase()
        ))
    });
    apps.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    apps
}

pub fn validate_manual_path(path: &str) -> Result<PathBuf, String> {
    let file = Path::new(path)
        .canonicalize()
        .map_err(|_| "Executável não encontrado.")?;
    if !file.is_file()
        || !file
            .extension()
            .is_some_and(|e| e.to_string_lossy().eq_ignore_ascii_case("exe"))
    {
        return Err("Selecione um arquivo EXE válido.".into());
    }
    Ok(file)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inventory_contains_real_registry_entries_without_duplicates() {
        let apps = list();
        assert!(!apps.is_empty(), "Inventário do Windows vazio");
        let mut seen = HashSet::new();
        for app in apps {
            assert!(!app.name.trim().is_empty());
            assert!(seen.insert(format!(
                "{}|{}|{}",
                app.name.to_lowercase(),
                app.version.to_lowercase(),
                app.publisher.to_lowercase()
            )));
        }
    }
}
