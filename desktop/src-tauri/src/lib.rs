// Accès aux fichiers pour l'interface (src/lib/platform.ts) : la logique de l'app est en TypeScript,
// Rust ne fait que lire, écrire (de façon atomique) et lister des fichiers.
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

/// Dossiers utiles à l'app.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AppPaths {
    /// Données de l'app (transactions.json, settings.json, sync-meta.json, Backups/).
    data_dir: String,
    /// Racine d'iCloud Drive si elle existe (Mac, ou iCloud pour Windows).
    icloud_dir: Option<String>,
    home_dir: String,
    /// "macos", "windows" ou "linux".
    os: &'static str,
    /// Mode mesure : dossier de données fictives (variable BUDGET_BENCH_DIR), qui remplace `data_dir`.
    bench_dir: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FileInfo {
    /// Date de modification, en millisecondes depuis 1970.
    modified_ms: f64,
    size: u64,
    is_dir: bool,
}

fn home() -> PathBuf {
    let var = if cfg!(windows) { "USERPROFILE" } else { "HOME" };
    std::env::var_os(var).map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."))
}

fn err(path: &Path, e: std::io::Error) -> String {
    format!("{} : {e}", path.display())
}

#[tauri::command]
fn app_paths() -> AppPaths {
    let home = home();
    let (data_dir, icloud) = if cfg!(target_os = "macos") {
        // Dossier distinct de l'app Mac : les deux apps ne doivent jamais écrire dans les mêmes fichiers.
        (
            home.join("Library/Application Support/Budget Proto"),
            vec![home.join("Library/Mobile Documents/com~apple~CloudDocs")],
        )
    } else if cfg!(windows) {
        let appdata = std::env::var_os("APPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join("AppData").join("Roaming"));
        (appdata.join("Budget"), vec![home.join("iCloudDrive"), home.join("iCloud Drive")])
    } else {
        (home.join(".local/share/Budget"), vec![])
    };
    let bench_dir = std::env::var("BUDGET_BENCH_DIR").ok().filter(|d| !d.is_empty());
    AppPaths {
        data_dir: bench_dir.clone().unwrap_or_else(|| data_dir.display().to_string()),
        bench_dir,
        icloud_dir: icloud.into_iter().find(|p| p.is_dir()).map(|p| p.display().to_string()),
        home_dir: home.display().to_string(),
        os: if cfg!(target_os = "macos") { "macos" } else if cfg!(windows) { "windows" } else { "linux" },
    }
}

/// Contenu texte d'un fichier, `None` s'il n'existe pas.
#[tauri::command]
fn read_text(path: String) -> Result<Option<String>, String> {
    let p = PathBuf::from(&path);
    match fs::read_to_string(&p) {
        Ok(s) => Ok(Some(s)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(err(&p, e)),
    }
}

/// Contenu binaire d'un fichier (relevés .xlsx…), renvoyé tel quel (ArrayBuffer côté JS).
#[tauri::command]
fn read_bytes(path: String) -> Result<tauri::ipc::Response, String> {
    let p = PathBuf::from(&path);
    fs::read(&p).map(tauri::ipc::Response::new).map_err(|e| err(&p, e))
}

/// Écriture atomique : fichier temporaire dans le même dossier, puis renommage.
#[tauri::command]
fn write_text(path: String, contents: String) -> Result<(), String> {
    let p = PathBuf::from(&path);
    if let Some(parent) = p.parent() {
        fs::create_dir_all(parent).map_err(|e| err(parent, e))?;
    }
    let name = p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    let tmp = p.with_file_name(format!(".{name}.tmp"));
    fs::write(&tmp, contents).map_err(|e| err(&tmp, e))?;
    fs::rename(&tmp, &p).map_err(|e| err(&p, e))
}

#[tauri::command]
fn file_info(path: String) -> Option<FileInfo> {
    let meta = fs::metadata(&path).ok()?;
    let modified_ms = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs_f64() * 1000.0)
        .unwrap_or(0.0);
    Some(FileInfo { modified_ms, size: meta.len(), is_dir: meta.is_dir() })
}

/// Noms des éléments d'un dossier (vide s'il n'existe pas).
#[tauri::command]
fn list_dir(path: String) -> Vec<String> {
    fs::read_dir(&path)
        .map(|entries| {
            entries.filter_map(|e| e.ok()).map(|e| e.file_name().to_string_lossy().to_string()).collect()
        })
        .unwrap_or_default()
}

#[tauri::command]
fn make_dir(path: String) -> Result<(), String> {
    let p = PathBuf::from(&path);
    fs::create_dir_all(&p).map_err(|e| err(&p, e))
}

/// Supprime un fichier ou un dossier (sans erreur s'il n'existe pas).
#[tauri::command]
fn remove_file(path: String) -> Result<(), String> {
    let p = PathBuf::from(&path);
    // Un dossier est supprimé avec son contenu seulement s'il s'agit d'une sauvegarde (parent « Backups »).
    let result = if p.is_dir() {
        let in_backups = p.parent().and_then(|d| d.file_name()).is_some_and(|n| n == "Backups");
        if !in_backups {
            return Err(format!("{} : seuls les dossiers de sauvegarde peuvent être supprimés", p.display()));
        }
        fs::remove_dir_all(&p)
    } else {
        fs::remove_file(&p)
    };
    match result {
        Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(err(&p, e)),
        _ => Ok(()),
    }
}

#[tauri::command]
fn rename_path(from: String, to: String) -> Result<(), String> {
    let p = PathBuf::from(&from);
    fs::rename(&p, &to).map_err(|e| err(&p, e))
}

#[tauri::command]
fn copy_file(from: String, to: String) -> Result<(), String> {
    let p = PathBuf::from(&from);
    if let Some(parent) = Path::new(&to).parent() {
        fs::create_dir_all(parent).map_err(|e| err(parent, e))?;
    }
    fs::copy(&p, &to).map(|_| ()).map_err(|e| err(&p, e))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            app_paths, read_text, read_bytes, write_text, file_info, list_dir, make_dir, remove_file,
            rename_path, copy_file
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
