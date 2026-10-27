//! Keeping the library in sync with the music folders on disk.
//!
//! On startup `rescan` compares the folders with the library (new files, deleted files,
//! files whose modification time changed); while the app runs, `watch` reacts to
//! filesystem events. Both produce a `Changes` set that the library model merges.

use crate::scanner::{self, Track};
use notify::event::{AccessKind, AccessMode, ModifyKind};
use notify::{EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use std::collections::{BTreeSet, HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::time::Duration;

/// Wait for the filesystem to go quiet this long before acting, so a folder being
/// copied in is handled once, after the copy finishes
const SETTLE: Duration = Duration::from_millis(1500);

#[derive(Default, Debug)]
pub struct Changes {
    /// New or modified files, freshly read
    pub upserts: Vec<Track>,
    /// Known files whose modification time we hadn't recorded yet (path, mtime)
    pub touched: Vec<(String, u64)>,
    /// Files that are gone
    pub removed: Vec<String>,
    /// Folders that are gone, along with everything in them
    pub removed_dirs: Vec<String>,
}

impl Changes {
    pub fn is_empty(&self) -> bool {
        self.upserts.is_empty()
            && self.touched.is_empty()
            && self.removed.is_empty()
            && self.removed_dirs.is_empty()
    }
}

fn folders_file() -> PathBuf {
    scanner::data_dir().join("folders.json")
}

/// Drop folders that sit inside another folder in the list
fn minimise(mut roots: Vec<PathBuf>) -> Vec<PathBuf> {
    roots.sort();
    roots.dedup();
    let mut out: Vec<PathBuf> = Vec::new();
    for root in roots {
        if !out.iter().any(|kept| root.starts_with(kept)) {
            out.push(root);
        }
    }
    out
}

/// The folders whose music is in the library. Libraries from before folders were
/// recorded get a list worked out from where their tracks live.
pub fn load_folders(tracks: &[Track]) -> Vec<PathBuf> {
    if let Some(roots) = fs::read(folders_file())
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Vec<PathBuf>>(&bytes).ok())
    {
        return roots;
    }
    let music = dirs::audio_dir().or_else(|| dirs::home_dir().map(|h| h.join("Music")));
    let mut roots = Vec::new();
    if let Some(music) = music.filter(|m| tracks.iter().any(|t| Path::new(&t.path).starts_with(m))) {
        roots.push(music);
    }
    for track in tracks {
        let path = Path::new(&track.path);
        if !roots.iter().any(|r| path.starts_with(r))
            && let Some(parent) = path.parent()
        {
            roots.push(parent.to_path_buf());
        }
    }
    let roots = minimise(roots);
    if !roots.is_empty() {
        save_folders(&roots);
    }
    roots
}

pub fn save_folders(roots: &[PathBuf]) {
    if let Ok(bytes) = serde_json::to_vec_pretty(roots) {
        let _ = fs::write(folders_file(), bytes);
    }
}

/// Add a folder to the list. Returns false if it was already covered.
pub fn add_folder(roots: &mut Vec<PathBuf>, folder: &Path) -> bool {
    if roots.iter().any(|r| folder.starts_with(r)) {
        return false;
    }
    roots.push(folder.to_path_buf());
    *roots = minimise(std::mem::take(roots));
    save_folders(roots);
    true
}

fn audio_files(dir: &Path) -> impl Iterator<Item = PathBuf> {
    walkdir::WalkDir::new(dir)
        .follow_links(true)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|e| e.file_type().is_file() && scanner::is_audio_file(e.path()))
        .map(|e| e.into_path())
}

/// A missing track counts as deleted only if its surroundings still exist. If a whole
/// drive is unplugged its songs stay in the library until it comes back.
fn really_gone(path: &Path, roots: &[PathBuf]) -> bool {
    if path.exists() {
        return false;
    }
    let root_present = roots.iter().any(|r| path.starts_with(r) && r.is_dir());
    let grandparent_present = path.parent().and_then(Path::parent).is_some_and(Path::is_dir);
    root_present || grandparent_present
}

/// Compare the folders on disk with the library. `known` maps each track path to the
/// modification time recorded for it (0 = not recorded yet).
pub fn rescan(roots: &[PathBuf], known: &HashMap<String, u64>) -> Changes {
    let mut changes = Changes::default();
    let mut seen = HashSet::new();

    for root in roots.iter().filter(|r| r.is_dir()) {
        for path in audio_files(root) {
            let key = path.to_string_lossy().into_owned();
            let mtime = scanner::file_mtime(&path);
            match known.get(&key) {
                None => changes.upserts.extend(scanner::read_track(&path)),
                Some(0) => changes.touched.push((key.clone(), mtime)),
                Some(&recorded) if recorded != mtime => {
                    changes.upserts.extend(scanner::read_track(&path))
                }
                Some(_) => {}
            }
            seen.insert(key);
        }
    }

    for path in known.keys() {
        if !seen.contains(path) && really_gone(Path::new(path), roots) {
            changes.removed.push(path.clone());
        }
    }
    changes
}

/// Work out what a burst of filesystem events means for the library
fn changes_for(paths: BTreeSet<PathBuf>, roots: &[PathBuf]) -> Changes {
    let mut changes = Changes::default();
    for path in paths {
        if path.is_dir() {
            // A folder appeared (copied or moved in): import everything inside it
            changes.upserts.extend(audio_files(&path).filter_map(|p| scanner::read_track(&p)));
        } else if path.is_file() {
            if scanner::is_audio_file(&path) {
                changes.upserts.extend(scanner::read_track(&path));
            }
        } else if really_gone(&path, roots) || roots.iter().any(|r| path.starts_with(r)) {
            let key = path.to_string_lossy().into_owned();
            if scanner::is_audio_file(&path) {
                changes.removed.push(key);
            } else {
                // Could have been a folder; anything that lived under it is gone too
                changes.removed_dirs.push(key);
            }
        }
    }
    changes
}

/// Does this event mean something may have been added, changed or removed?
fn is_content_change(kind: &EventKind) -> bool {
    match kind {
        EventKind::Create(_) | EventKind::Remove(_) => true,
        // Ignore metadata-only changes such as access times, which reading tags or
        // playing a song can cause
        EventKind::Modify(ModifyKind::Metadata(_)) => false,
        EventKind::Modify(_) => true,
        // A file that was open for writing has been closed: it's finished being written
        EventKind::Access(AccessKind::Close(AccessMode::Write)) => true,
        _ => false,
    }
}

/// Watch the folders and call `on_changes` (on a background thread) whenever the
/// music in them changes. Dropping the returned watcher stops it.
pub fn watch(
    roots: &[PathBuf],
    on_changes: impl Fn(Changes) + Send + 'static,
    current_roots: impl Fn() -> Vec<PathBuf> + Send + 'static,
) -> Option<RecommendedWatcher> {
    let (tx, rx) = mpsc::channel::<PathBuf>();
    let mut watcher = notify::recommended_watcher(move |result: notify::Result<notify::Event>| {
        if let Ok(event) = result
            && is_content_change(&event.kind)
        {
            for path in event.paths {
                let _ = tx.send(path);
            }
        }
    })
    .map_err(|err| eprintln!("iMelodiae: can't watch music folders: {err}"))
    .ok()?;

    for root in roots.iter().filter(|r| r.is_dir()) {
        if let Err(err) = watcher.watch(root, RecursiveMode::Recursive) {
            eprintln!("iMelodiae: can't watch {}: {err}", root.display());
        }
    }

    std::thread::spawn(move || {
        // Each burst of events is collected until things settle, then handled at once
        while let Ok(first) = rx.recv() {
            let mut paths = BTreeSet::from([first]);
            loop {
                match rx.recv_timeout(SETTLE) {
                    Ok(path) => {
                        paths.insert(path);
                    }
                    Err(mpsc::RecvTimeoutError::Timeout) => break,
                    Err(mpsc::RecvTimeoutError::Disconnected) => return,
                }
            }
            let changes = changes_for(paths, &current_roots());
            if !changes.is_empty() {
                on_changes(changes);
            }
        }
    });

    Some(watcher)
}

pub fn watch_folder(watcher: &mut RecommendedWatcher, folder: &Path) {
    if let Err(err) = watcher.watch(folder, RecursiveMode::Recursive) {
        eprintln!("iMelodiae: can't watch {}: {err}", folder.display());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn minimise_drops_nested_folders() {
        let roots = minimise(vec![
            PathBuf::from("/music/rock"),
            PathBuf::from("/music"),
            PathBuf::from("/other"),
            PathBuf::from("/music"),
        ]);
        assert_eq!(roots, vec![PathBuf::from("/music"), PathBuf::from("/other")]);
    }

    #[test]
    fn rescan_finds_new_changed_and_removed() {
        let dir = std::env::temp_dir().join(format!("imelodiae-rescan-{}", std::process::id()));
        let album = dir.join("Artist").join("Album");
        fs::create_dir_all(&album).unwrap();
        // Unreadable "audio" still imports, titled after the file
        fs::write(album.join("new.mp3"), b"not really audio").unwrap();
        fs::write(album.join("same.flac"), b"x").unwrap();
        fs::write(album.join("edited.flac"), b"x").unwrap();
        fs::write(album.join("cover.jpg"), b"x").unwrap();

        let path = |name: &str| album.join(name).to_string_lossy().into_owned();
        let known = HashMap::from([
            (path("same.flac"), scanner::file_mtime(&album.join("same.flac"))),
            (path("edited.flac"), 1),
            (path("deleted.flac"), 5),
        ]);
        let changes = rescan(std::slice::from_ref(&dir), &known);

        let mut upserted: Vec<_> = changes.upserts.iter().map(|t| t.path.clone()).collect();
        upserted.sort();
        assert_eq!(upserted, vec![path("edited.flac"), path("new.mp3")]);
        assert_eq!(changes.removed, vec![path("deleted.flac")]);
        assert!(changes.touched.is_empty());

        // An unplugged drive: neither the root nor the album's parent exists
        let gone_root = PathBuf::from("/nonexistent-imelodiae-drive");
        let known = HashMap::from([("/nonexistent-imelodiae-drive/A/B/x.flac".to_owned(), 5)]);
        assert!(rescan(&[gone_root], &known).removed.is_empty());

        fs::remove_dir_all(&dir).unwrap();
    }
}
