//! Regular (hand-made) playlists: a name and an ordered list of songs, saved to
//! playlists.json. Songs are stored by file path rather than track id, because ids are
//! only stable while the app runs.

use crate::scanner;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fs;
use std::path::PathBuf;

pub const UNTITLED: &str = "untitled playlist";

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Playlist {
    /// Stable identity, so a playlist can be found again after renames re-sort the list
    pub id: u64,
    pub name: String,
    /// File paths, in playlist order, each at most once
    pub tracks: Vec<String>,
}

impl Playlist {
    /// Append songs that aren't already in the playlist; returns how many were added
    pub fn add(&mut self, paths: &[String]) -> usize {
        let mut have: HashSet<String> = self.tracks.iter().cloned().collect();
        let before = self.tracks.len();
        for path in paths {
            if have.insert(path.clone()) {
                self.tracks.push(path.clone());
            }
        }
        self.tracks.len() - before
    }

    /// Take songs out of the playlist; returns how many were removed
    pub fn remove(&mut self, paths: &[String]) -> usize {
        let gone: HashSet<&String> = paths.iter().collect();
        let before = self.tracks.len();
        self.tracks.retain(|p| !gone.contains(p));
        before - self.tracks.len()
    }

    /// Move songs, keeping their relative order, to just before `before`, or to the end
    /// when `before` is None (or is itself one of the songs being moved and nothing
    /// after it stays put)
    pub fn move_before(&mut self, paths: &[String], before: Option<&str>) {
        let moving: HashSet<&String> = paths.iter().collect();
        let moved: Vec<String> = self.tracks.iter().filter(|p| moving.contains(p)).cloned().collect();
        if moved.is_empty() {
            return;
        }
        // Dropping onto one of the moved songs means "just after whatever stays put above it"
        let position = self.tracks.iter().position(|p| Some(p.as_str()) == before);
        let anchor = position.and_then(|at| self.tracks[at..].iter().find(|p| !moving.contains(p)).cloned());
        self.tracks.retain(|p| !moving.contains(p));
        let at = anchor
            .and_then(|a| self.tracks.iter().position(|p| *p == a))
            .unwrap_or(self.tracks.len());
        self.tracks.splice(at..at, moved);
    }
}

/// Keep playlists in Source-list order: by name, ignoring case, then oldest first
pub fn sort(playlists: &mut [Playlist]) {
    playlists.sort_by_cached_key(|p| (p.name.to_lowercase(), p.id));
}

/// `base`, or `base 2`, `base 3`… whichever no playlist is called yet
pub fn unique_name(playlists: &[Playlist], base: &str) -> String {
    let taken: HashSet<String> = playlists.iter().map(|p| p.name.to_lowercase()).collect();
    if !taken.contains(&base.to_lowercase()) {
        return base.to_owned();
    }
    (2..)
        .map(|n| format!("{base} {n}"))
        .find(|name| !taken.contains(&name.to_lowercase()))
        .unwrap_or_else(|| base.to_owned())
}

pub fn next_id(playlists: &[Playlist]) -> u64 {
    playlists.iter().map(|p| p.id).max().unwrap_or(0) + 1
}

fn playlists_file() -> PathBuf {
    scanner::data_dir().join("playlists.json")
}

pub fn load() -> Vec<Playlist> {
    let mut playlists: Vec<Playlist> = fs::read(playlists_file())
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default();
    sort(&mut playlists);
    playlists
}

pub fn save(playlists: &[Playlist]) {
    let path = playlists_file();
    let tmp = path.with_extension("json.tmp");
    match serde_json::to_vec_pretty(playlists) {
        Ok(bytes) => {
            if fs::write(&tmp, bytes).is_ok() {
                let _ = fs::rename(&tmp, &path);
            }
        }
        Err(err) => eprintln!("iMelodiae: could not save playlists: {err}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn paths(names: &[&str]) -> Vec<String> {
        names.iter().map(|s| s.to_string()).collect()
    }

    fn playlist(names: &[&str]) -> Playlist {
        Playlist { id: 1, name: "p".into(), tracks: paths(names) }
    }

    #[test]
    fn add_skips_songs_already_there() {
        let mut p = playlist(&["a", "b"]);
        assert_eq!(p.add(&paths(&["b", "c", "c", "d"])), 2);
        assert_eq!(p.tracks, paths(&["a", "b", "c", "d"]));
    }

    #[test]
    fn remove_takes_out_only_those_songs() {
        let mut p = playlist(&["a", "b", "c"]);
        assert_eq!(p.remove(&paths(&["b", "x"])), 1);
        assert_eq!(p.tracks, paths(&["a", "c"]));
    }

    #[test]
    fn move_before_keeps_relative_order() {
        let mut p = playlist(&["a", "b", "c", "d", "e"]);
        p.move_before(&paths(&["d", "b"]), Some("a"));
        assert_eq!(p.tracks, paths(&["b", "d", "a", "c", "e"]));

        p.move_before(&paths(&["b"]), None);
        assert_eq!(p.tracks, paths(&["d", "a", "c", "e", "b"]));

        // Dropped onto itself: stays where it is
        p.move_before(&paths(&["c"]), Some("c"));
        assert_eq!(p.tracks, paths(&["d", "a", "c", "e", "b"]));

        // Dropped onto a moved song lands before the next one that stays
        p.move_before(&paths(&["a", "c"]), Some("a"));
        assert_eq!(p.tracks, paths(&["d", "a", "c", "e", "b"]));
        p.move_before(&paths(&["d", "e"]), Some("e"));
        assert_eq!(p.tracks, paths(&["a", "c", "d", "e", "b"]));
    }

    #[test]
    fn names_are_unique_ignoring_case() {
        let named = |n: &str| Playlist { name: n.into(), ..Default::default() };
        assert_eq!(unique_name(&[], UNTITLED), "untitled playlist");
        let existing = [named("Untitled Playlist"), named("untitled playlist 2")];
        assert_eq!(unique_name(&existing, UNTITLED), "untitled playlist 3");
    }

    #[test]
    fn sorts_by_name_then_age() {
        let mut list = vec![
            Playlist { id: 3, name: "beta".into(), ..Default::default() },
            Playlist { id: 2, name: "Alpha".into(), ..Default::default() },
            Playlist { id: 1, name: "beta".into(), ..Default::default() },
        ];
        sort(&mut list);
        assert_eq!(list.iter().map(|p| p.id).collect::<Vec<_>>(), [2, 1, 3]);
    }
}
