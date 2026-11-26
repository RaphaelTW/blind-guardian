use chrono::Utc;
use serde::Serialize;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;

#[derive(Serialize)]
struct AuditEvent<'a> {
    at: String,
    event: &'a str,
    result: &'a str,
}

pub fn append(path: &PathBuf, event: &str, result: &str) {
    let Some(parent) = path.parent() else { return };
    if fs::create_dir_all(parent).is_err() {
        return;
    }
    let entry = AuditEvent {
        at: Utc::now().to_rfc3339(),
        event,
        result,
    };
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        if let Ok(line) = serde_json::to_string(&entry) {
            let _ = writeln!(file, "{line}");
        }
    }
}
