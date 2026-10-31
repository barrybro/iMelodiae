//! The music library: every known track, plus the filtered/sorted view shown in the song list.
//!
//! Filtering mirrors iTunes: Source (Library or a smart playlist) -> search text ->
//! Genre -> Artist -> Album, where each browser column lists only what survives the
//! columns to its left.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!(< QtCore/QAbstractListModel >);
        type QAbstractListModel;

        include!("cxx-qt-lib/qhash.h");
        type QHash_i32_QByteArray = cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray>;

        include!("cxx-qt-lib/qmodelindex.h");
        type QModelIndex = cxx_qt_lib::QModelIndex;

        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;

        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;

        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[base = QAbstractListModel]
        #[qproperty(i32, count, READ, NOTIFY)]
        #[qproperty(i32, total_count, READ, NOTIFY)]
        #[qproperty(QString, summary, READ, NOTIFY)]
        #[qproperty(QString, status, READ, NOTIFY)]
        #[qproperty(bool, scanning, READ, NOTIFY)]
        /// Bumped whenever a cover is downloaded, so artwork bindings re-check
        #[qproperty(i32, artwork_revision, READ, NOTIFY)]
        /// True while the list is being reset because files changed on disk, so the
        /// view can keep its scroll position
        #[qproperty(bool, updating, READ)]
        #[qproperty(i32, source, READ, WRITE = set_source_index, NOTIFY)]
        #[qproperty(QString, search, READ, WRITE = set_search_text, NOTIFY)]
        #[qproperty(QString, genre, READ, WRITE = set_genre_filter, NOTIFY)]
        #[qproperty(QString, artist, READ, WRITE = set_artist_filter, NOTIFY)]
        #[qproperty(QString, album, READ, WRITE = set_album_filter, NOTIFY)]
        #[qproperty(QStringList, genres, READ, NOTIFY)]
        #[qproperty(QStringList, artists, READ, NOTIFY)]
        #[qproperty(QStringList, albums, READ, NOTIFY)]
        #[qproperty(QString, sort_column, READ, NOTIFY)]
        #[qproperty(bool, sort_ascending, READ, NOTIFY)]
        type LibraryModel = super::LibraryModelRust;
    }

    unsafe extern "RustQt" {
        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut LibraryModel>);

        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut LibraryModel>);
    }

    unsafe extern "RustQt" {
        #[qinvokable]
        #[cxx_override]
        fn data(self: &LibraryModel, index: &QModelIndex, role: i32) -> QVariant;

        #[qinvokable]
        #[cxx_override]
        #[cxx_name = "roleNames"]
        fn role_names(self: &LibraryModel) -> QHash_i32_QByteArray;

        #[qinvokable]
        #[cxx_override]
        #[cxx_name = "rowCount"]
        fn row_count(self: &LibraryModel, parent: &QModelIndex) -> i32;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        fn set_source_index(self: Pin<&mut LibraryModel>, source: i32);
        fn set_search_text(self: Pin<&mut LibraryModel>, search: QString);
        fn set_genre_filter(self: Pin<&mut LibraryModel>, genre: QString);
        fn set_artist_filter(self: Pin<&mut LibraryModel>, artist: QString);
        fn set_album_filter(self: Pin<&mut LibraryModel>, album: QString);

        /// Scan a folder (path or file:// URL) in the background and add its music
        #[qinvokable]
        fn add_folder(self: Pin<&mut LibraryModel>, folder: &QString);

        /// Import ~/Music the first time the app runs with an empty library
        #[qinvokable]
        fn import_default_folder(self: Pin<&mut LibraryModel>);

        /// Sort by a column role name; clicking the same column again flips direction
        #[qinvokable]
        fn sort_by(self: Pin<&mut LibraryModel>, column: &QString);

        #[qinvokable]
        fn id_at(self: &LibraryModel, row: i32) -> i32;

        #[qinvokable]
        fn row_of_id(self: &LibraryModel, id: i32) -> i32;

        #[qinvokable]
        fn uri_of(self: &LibraryModel, id: i32) -> QString;

        /// JSON object describing a track, for the LCD and artwork panes
        #[qinvokable]
        fn track_info(self: &LibraryModel, id: i32) -> QString;

        /// file:// URL of the track's album artwork, or empty. If the song has no art,
        /// an online lookup starts in the background and artworkRevision changes when it lands.
        #[qinvokable]
        fn artwork_url(self: &LibraryModel, id: i32) -> QString;

        /// Track id that follows `id` in the current view; -1 when the end is reached and `wrap` is false
        #[qinvokable]
        fn next_id(self: &LibraryModel, id: i32, shuffle: bool, wrap: bool) -> i32;

        #[qinvokable]
        fn previous_id(self: &LibraryModel, id: i32) -> i32;

        /// Bump play count / last played when a song finishes
        #[qinvokable]
        fn mark_played(self: Pin<&mut LibraryModel>, id: i32);
    }

    impl cxx_qt::Threading for LibraryModel {}
    impl cxx_qt::Initialize for LibraryModel {}
}

use crate::coverart;
use crate::scanner::{self, Track};
use crate::watcher::{self, Changes};
use core::pin::Pin;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QStringList, QVariant};
use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
use std::path::{Path, PathBuf};

/// Sources in the left-hand Source list (0 is the whole Library)
pub const SOURCE_RECENTLY_ADDED: i32 = 1;
pub const SOURCE_TOP_PLAYED: i32 = 2;
pub const SOURCE_RECENTLY_PLAYED: i32 = 3;

const ROLES: &[&str] = &[
    "trackId",
    "title",
    "artist",
    "album",
    "genre",
    "kind",
    "time",
    "trackNumber",
    "year",
    "playCount",
    "bitRate",
    "sampleRate",
    "dateAdded",
    "lastPlayed",
];
const USER_ROLE: i32 = 0x0100;

type TrackOrder<'a> = Box<dyn Fn(usize, usize) -> Ordering + 'a>;

#[derive(Default)]
pub struct LibraryModelRust {
    count: i32,
    total_count: i32,
    summary: QString,
    status: QString,
    scanning: bool,
    updating: bool,
    artwork_revision: i32,
    /// Albums whose cover is being looked up right now
    covers_in_flight: Arc<Mutex<HashSet<String>>>,
    source: i32,
    search: QString,
    genre: QString,
    artist: QString,
    album: QString,
    genres: QStringList,
    artists: QStringList,
    albums: QStringList,
    sort_column: QString,
    sort_ascending: bool,

    /// Every track; a track's id is its index here. Deleted tracks are flagged
    /// `removed` rather than taken out, so ids never shift while the app runs.
    tracks: Vec<Track>,
    /// Lowercased search text and sort keys; rebuilt when tracks change
    index: SearchIndex,
    index_stale: bool,
    /// Track data changed since the last refresh, so rows must be redrawn even if the
    /// same songs are showing
    rows_dirty: bool,
    /// Plain copies of the browser lists, to tell whether they changed
    browser_values: [Vec<String>; 3],
    /// Music folders being kept in sync (shared with the watcher thread)
    folders: Arc<Mutex<Vec<PathBuf>>>,
    watcher: Option<notify::RecommendedWatcher>,
    /// Track ids in the current view, in display order
    view: Vec<usize>,
    shuffle_state: std::cell::Cell<u64>,
}

impl cxx_qt::Initialize for qobject::LibraryModel {
    fn initialize(mut self: Pin<&mut Self>) {
        let tracks = scanner::load_library();
        let folders = watcher::load_folders(&tracks);
        let mut rust = self.as_mut().rust_mut();
        rust.tracks = tracks;
        rust.folders = Arc::new(Mutex::new(folders.clone()));
        rust.sort_ascending = true;
        rust.shuffle_state.set(scanner::now_secs() | 1);
        self.as_mut().refresh();

        // Watch first, then rescan, so nothing that changes mid-scan is missed
        let thread = self.qt_thread();
        let shared = self.folders.clone();
        let watcher = watcher::watch(
            &folders,
            move |changes| {
                let _ = thread.queue(move |model: Pin<&mut qobject::LibraryModel>| {
                    model.apply_changes(changes);
                });
            },
            move || shared.lock().map(|f| f.clone()).unwrap_or_default(),
        );
        self.as_mut().rust_mut().watcher = watcher;
        self.rescan();
    }
}

fn display_artist(t: &Track) -> &str {
    if !t.album_artist.is_empty() {
        &t.album_artist
    } else {
        &t.artist
    }
}

fn to_qstringlist(items: impl IntoIterator<Item = String>) -> QStringList {
    let mut list = QStringList::default();
    for item in items {
        list.append(QString::from(item));
    }
    list
}

fn folder_path(folder: &str) -> PathBuf {
    let path = folder.strip_prefix("file://").unwrap_or(folder);
    PathBuf::from(percent_decode(path))
}

fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let Some(byte) = std::str::from_utf8(&bytes[i + 1..i + 3])
                .ok()
                .and_then(|hex| u8::from_str_radix(hex, 16).ok())
        {
            out.push(byte);
            i += 3;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

pub struct Filters {
    pub search: String,
    pub genre: String,
    pub artist: String,
    pub album: String,
    pub source: i32,
    pub sort_column: String,
    pub ascending: bool,
}

pub struct ViewResult {
    /// Track ids in display order
    pub view: Vec<usize>,
    pub genres: Vec<String>,
    pub artists: Vec<String>,
    pub albums: Vec<String>,
}

/// Lowercased text and sort order for every track, computed once per library change so a
/// keystroke in the search field costs a substring scan rather than thousands of allocations
#[derive(Default)]
pub struct SearchIndex {
    /// "title␁artist␁album artist␁album␁genre", lowercased; separators stop words matching across fields
    haystack: Vec<String>,
    title: Vec<String>,
    /// Lowercased album artist, or artist when there's none
    display_artist: Vec<String>,
    artist: Vec<String>,
    album: Vec<String>,
    genre: Vec<String>,
    /// Live track ids in Library order: artist, album, disc, track
    library_order: Vec<usize>,
    /// Each id's position in `library_order`, used to break ties in column sorts
    rank: Vec<usize>,
}

impl SearchIndex {
    pub fn build(tracks: &[Track]) -> Self {
        let lower = |f: fn(&Track) -> &str| tracks.iter().map(|t| f(t).to_lowercase()).collect::<Vec<_>>();
        let mut index = SearchIndex {
            haystack: tracks
                .iter()
                .map(|t| {
                    [&t.title, &t.artist, &t.album_artist, &t.album, &t.genre]
                        .map(|s| s.to_lowercase())
                        .join("\u{1}")
                })
                .collect(),
            title: lower(|t| &t.title),
            display_artist: lower(display_artist),
            artist: lower(|t| &t.artist),
            album: lower(|t| &t.album),
            genre: lower(|t| &t.genre),
            ..Default::default()
        };

        // Empty values sort last, like iTunes
        let key = |s: &String| (s.is_empty(), s.clone());
        let mut order: Vec<usize> = (0..tracks.len()).filter(|&i| !tracks[i].removed).collect();
        order.sort_by_cached_key(|&i| {
            let t = &tracks[i];
            (
                key(&index.display_artist[i]),
                key(&index.album[i]),
                t.disc_number,
                t.track_number,
                index.title[i].clone(),
            )
        });
        index.rank = vec![usize::MAX; tracks.len()];
        for (position, &i) in order.iter().enumerate() {
            index.rank[i] = position;
        }
        index.library_order = order;
        index
    }

    pub fn len(&self) -> usize {
        self.rank.len()
    }
}

/// Distinct non-empty values, sorted case-insensitively, keeping the first spelling seen
fn distinct(ids: &[usize], lower: &[String], original: impl Fn(usize) -> String) -> Vec<String> {
    let mut seen: HashMap<&str, usize> = HashMap::new();
    for &i in ids {
        let l = lower[i].as_str();
        if !l.is_empty() {
            seen.entry(l).or_insert(i);
        }
    }
    let mut values: Vec<(&str, usize)> = seen.into_iter().collect();
    values.sort_unstable_by(|a, b| a.0.cmp(b.0));
    values.into_iter().map(|(_, i)| original(i)).collect()
}

/// Apply source, search, browser and sort to the library
pub fn compute_view(tracks: &[Track], index: &SearchIndex, f: &Filters) -> ViewResult {
    let words: Vec<String> = f.search.to_lowercase().split_whitespace().map(str::to_owned).collect();
    let live = || (0..tracks.len()).filter(|&i| !tracks[i].removed);

    // 1. Source (Library or smart playlist)
    let mut ids: Vec<usize> = match f.source {
        SOURCE_RECENTLY_ADDED => {
            let mut ids: Vec<usize> = live().collect();
            ids.sort_by(|&a, &b| tracks[b].date_added.cmp(&tracks[a].date_added));
            ids.truncate(25);
            ids
        }
        SOURCE_TOP_PLAYED => {
            let mut ids: Vec<usize> = live().filter(|&i| tracks[i].play_count > 0).collect();
            ids.sort_by(|&a, &b| tracks[b].play_count.cmp(&tracks[a].play_count));
            ids.truncate(25);
            ids
        }
        SOURCE_RECENTLY_PLAYED => {
            let mut ids: Vec<usize> = live().filter(|&i| tracks[i].last_played > 0).collect();
            ids.sort_by(|&a, &b| tracks[b].last_played.cmp(&tracks[a].last_played));
            ids.truncate(25);
            ids
        }
        _ => index.library_order.clone(),
    };

    // 2. Search: every word must appear in one of the fields
    if !words.is_empty() {
        ids.retain(|&i| words.iter().all(|w| index.haystack[i].contains(w.as_str())));
    }

    // 3. Browser columns, each narrowed by the ones to its left
    let (genre, artist, album) = (f.genre.to_lowercase(), f.artist.to_lowercase(), f.album.to_lowercase());
    let genres = distinct(&ids, &index.genre, |i| tracks[i].genre.clone());
    if !genre.is_empty() {
        ids.retain(|&i| index.genre[i] == genre);
    }
    let artists = distinct(&ids, &index.display_artist, |i| display_artist(&tracks[i]).to_owned());
    if !artist.is_empty() {
        ids.retain(|&i| index.display_artist[i] == artist || index.artist[i] == artist);
    }
    let albums = distinct(&ids, &index.album, |i| tracks[i].album.clone());
    if !album.is_empty() {
        ids.retain(|&i| index.album[i] == album);
    }
    let mut view = ids;

    // 4. Column sort, ties broken by Library order
    let text = |v: &Vec<String>, a: usize, b: usize| {
        (v[a].is_empty(), &v[a]).cmp(&(v[b].is_empty(), &v[b]))
    };
    let by: Option<TrackOrder> = match f.sort_column.as_str() {
        "" => None,
        "title" => Some(Box::new(|a, b| text(&index.title, a, b))),
        "artist" => Some(Box::new(|_, _| Ordering::Equal)),
        "album" => Some(Box::new(|a, b| text(&index.album, a, b))),
        "genre" => Some(Box::new(|a, b| text(&index.genre, a, b))),
        "time" => Some(Box::new(|a, b| tracks[a].duration_ms.cmp(&tracks[b].duration_ms))),
        "kind" => Some(Box::new(|a, b| tracks[a].kind.cmp(&tracks[b].kind))),
        "year" => Some(Box::new(|a, b| tracks[a].year.cmp(&tracks[b].year))),
        "playCount" => Some(Box::new(|a, b| tracks[a].play_count.cmp(&tracks[b].play_count))),
        "trackNumber" => Some(Box::new(|a, b| tracks[a].track_number.cmp(&tracks[b].track_number))),
        "bitRate" => Some(Box::new(|a, b| tracks[a].bitrate.cmp(&tracks[b].bitrate))),
        "sampleRate" => Some(Box::new(|a, b| tracks[a].sample_rate.cmp(&tracks[b].sample_rate))),
        "dateAdded" => Some(Box::new(|a, b| tracks[a].date_added.cmp(&tracks[b].date_added))),
        "lastPlayed" => Some(Box::new(|a, b| tracks[a].last_played.cmp(&tracks[b].last_played))),
        _ => None,
    };
    if let Some(by) = by {
        view.sort_by(|&a, &b| by(a, b).then(index.rank[a].cmp(&index.rank[b])));
    }
    if !f.ascending {
        view.reverse();
    }

    ViewResult { view, genres, artists, albums }
}

impl qobject::LibraryModel {
    fn track(&self, id: i32) -> Option<&Track> {
        usize::try_from(id).ok().and_then(|i| self.tracks.get(i))
    }

    /// Rebuild the browser columns and the visible song list from the current filters.
    fn refresh(mut self: Pin<&mut Self>) {
        let filters = Filters {
            search: self.search.to_string(),
            genre: self.genre.to_string(),
            artist: self.artist.to_string(),
            album: self.album.to_string(),
            source: self.source,
            sort_column: self.sort_column.to_string(),
            ascending: self.sort_ascending,
        };
        if self.index_stale || self.index.len() != self.tracks.len() {
            let index = SearchIndex::build(&self.tracks);
            let mut rust = self.as_mut().rust_mut();
            rust.index = index;
            rust.index_stale = false;
        }
        let tracks = &self.tracks;
        let ViewResult { view, genres, artists, albums } = compute_view(tracks, &self.index, &filters);
        let total_ms = view.iter().map(|&i| tracks[i].duration_ms).sum();
        let total_bytes = view.iter().map(|&i| tracks[i].size).sum();
        let summary = QString::from(scanner::summary(view.len(), total_ms, total_bytes));
        let total = tracks.iter().filter(|t| !t.removed).count() as i32;

        // Resetting the model rebuilds every visible row in QML, which is the slow part on
        // older machines, so skip it when the same songs are showing (e.g. typing more
        // letters of a search that already matches just these songs)
        if self.rows_dirty || self.view != view {
            self.as_mut().begin_reset_model();
            let mut rust = self.as_mut().rust_mut();
            rust.view = view;
            rust.rows_dirty = false;
            self.as_mut().end_reset_model();
        }

        let count = self.view.len() as i32;
        if self.count != count {
            self.as_mut().rust_mut().count = count;
            self.as_mut().count_changed();
        }
        if self.total_count != total {
            self.as_mut().rust_mut().total_count = total;
            self.as_mut().total_count_changed();
        }
        if self.summary != summary {
            self.as_mut().rust_mut().summary = summary;
            self.as_mut().summary_changed();
        }
        // Each browser list rebuilds its column in QML, so only send ones that changed
        if self.browser_values[0] != genres {
            self.as_mut().rust_mut().genres = to_qstringlist(genres.iter().cloned());
            self.as_mut().rust_mut().browser_values[0] = genres;
            self.as_mut().genres_changed();
        }
        if self.browser_values[1] != artists {
            self.as_mut().rust_mut().artists = to_qstringlist(artists.iter().cloned());
            self.as_mut().rust_mut().browser_values[1] = artists;
            self.as_mut().artists_changed();
        }
        if self.browser_values[2] != albums {
            self.as_mut().rust_mut().albums = to_qstringlist(albums.iter().cloned());
            self.as_mut().rust_mut().browser_values[2] = albums;
            self.as_mut().albums_changed();
        }
    }

    fn set_status_text(mut self: Pin<&mut Self>, status: String) {
        self.as_mut().rust_mut().status = QString::from(status);
        self.status_changed();
    }

    pub fn set_source_index(mut self: Pin<&mut Self>, source: i32) {
        if self.source == source {
            return;
        }
        let mut rust = self.as_mut().rust_mut();
        rust.source = source;
        rust.genre = QString::default();
        rust.artist = QString::default();
        rust.album = QString::default();
        // Smart playlists keep their own ordering
        rust.sort_column = QString::default();
        rust.sort_ascending = true;
        self.as_mut().source_changed();
        self.as_mut().genre_changed();
        self.as_mut().artist_changed();
        self.as_mut().album_changed();
        self.as_mut().sort_column_changed();
        self.as_mut().sort_ascending_changed();
        self.refresh();
    }

    pub fn set_search_text(mut self: Pin<&mut Self>, search: QString) {
        if self.search == search {
            return;
        }
        self.as_mut().rust_mut().search = search;
        self.as_mut().search_changed();
        self.refresh();
    }

    pub fn set_genre_filter(mut self: Pin<&mut Self>, genre: QString) {
        if self.genre == genre {
            return;
        }
        let mut rust = self.as_mut().rust_mut();
        rust.genre = genre;
        rust.artist = QString::default();
        rust.album = QString::default();
        self.as_mut().genre_changed();
        self.as_mut().artist_changed();
        self.as_mut().album_changed();
        self.refresh();
    }

    pub fn set_artist_filter(mut self: Pin<&mut Self>, artist: QString) {
        if self.artist == artist {
            return;
        }
        let mut rust = self.as_mut().rust_mut();
        rust.artist = artist;
        rust.album = QString::default();
        self.as_mut().artist_changed();
        self.as_mut().album_changed();
        self.refresh();
    }

    pub fn set_album_filter(mut self: Pin<&mut Self>, album: QString) {
        if self.album == album {
            return;
        }
        self.as_mut().rust_mut().album = album;
        self.as_mut().album_changed();
        self.refresh();
    }

    pub fn sort_by(mut self: Pin<&mut Self>, column: &QString) {
        let mut rust = self.as_mut().rust_mut();
        if rust.sort_column == *column {
            rust.sort_ascending = !rust.sort_ascending;
        } else {
            rust.sort_column = column.clone();
            rust.sort_ascending = true;
        }
        self.as_mut().sort_column_changed();
        self.as_mut().sort_ascending_changed();
        self.refresh();
    }

    /// Merge changes found on disk (by the startup rescan or the folder watcher)
    fn apply_changes(mut self: Pin<&mut Self>, changes: Changes) {
        if changes.is_empty() {
            return;
        }
        let (mut added, mut removed) = (0usize, 0usize);
        let mut rust = self.as_mut().rust_mut();
        let mut index: HashMap<String, usize> = rust
            .tracks
            .iter()
            .enumerate()
            .filter(|(_, t)| !t.removed)
            .map(|(i, t)| (t.path.clone(), i))
            .collect();

        for mut track in changes.upserts {
            match index.get(&track.path) {
                Some(&i) => {
                    // Re-read tags, but keep the listening history
                    let old = &rust.tracks[i];
                    track.play_count = old.play_count;
                    track.last_played = old.last_played;
                    track.date_added = old.date_added;
                    rust.tracks[i] = track;
                }
                None => {
                    index.insert(track.path.clone(), rust.tracks.len());
                    rust.tracks.push(track);
                    added += 1;
                }
            }
        }
        for (path, mtime) in changes.touched {
            if let Some(&i) = index.get(&path) {
                rust.tracks[i].mtime = mtime;
            }
        }
        for path in &changes.removed {
            if let Some(&i) = index.get(path) {
                rust.tracks[i].removed = true;
                removed += 1;
            }
        }
        for dir in &changes.removed_dirs {
            let prefix = format!("{}/", dir.trim_end_matches('/'));
            for track in rust.tracks.iter_mut().filter(|t| !t.removed && t.path.starts_with(&prefix)) {
                track.removed = true;
                removed += 1;
            }
        }

        scanner::save_library(&rust.tracks);
        rust.index_stale = true;
        rust.rows_dirty = true;
        rust.updating = true;
        self.as_mut().refresh();
        self.as_mut().rust_mut().updating = false;

        if !self.scanning && (added > 0 || removed > 0) {
            let songs = |n: usize| if n == 1 { "1 song".to_owned() } else { format!("{n} songs") };
            let msg = match (added, removed) {
                (a, 0) => format!("Added {}", songs(a)),
                (0, r) => format!("Removed {}", songs(r)),
                (a, r) => format!("Added {}, removed {}", songs(a), songs(r)),
            };
            self.set_status_text(msg);
        }
    }

    /// Check the music folders for anything that changed while the app was closed
    fn rescan(self: Pin<&mut Self>) {
        let folders = self.folders.lock().map(|f| f.clone()).unwrap_or_default();
        if folders.is_empty() {
            return;
        }
        let known: HashMap<String, u64> = self
            .tracks
            .iter()
            .filter(|t| !t.removed)
            .map(|t| (t.path.clone(), t.mtime))
            .collect();
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let changes = watcher::rescan(&folders, &known);
            let _ = thread.queue(move |model: Pin<&mut qobject::LibraryModel>| {
                model.apply_changes(changes);
            });
        });
    }

    pub fn import_default_folder(self: Pin<&mut Self>) {
        if self.tracks.iter().any(|t| !t.removed) || self.scanning {
            return;
        }
        if let Some(music) = dirs::audio_dir().or_else(|| dirs::home_dir().map(|h| h.join("Music")))
            && music.is_dir()
        {
            self.add_folder(&QString::from(music.to_string_lossy().as_ref()));
        }
    }

    pub fn add_folder(mut self: Pin<&mut Self>, folder: &QString) {
        if self.scanning {
            return;
        }
        let root = folder_path(&folder.to_string());
        if !root.is_dir() {
            self.set_status_text(format!("Can't open {}", root.display()));
            return;
        }

        // Keep this folder in sync from now on
        let is_new = self.folders.lock().map(|mut f| watcher::add_folder(&mut f, &root)).unwrap_or(false);
        if is_new && let Some(w) = self.as_mut().rust_mut().watcher.as_mut() {
            watcher::watch_folder(w, &root);
        }

        let known: HashSet<String> =
            self.tracks.iter().filter(|t| !t.removed).map(|t| t.path.clone()).collect();
        self.as_mut().rust_mut().scanning = true;
        self.as_mut().scanning_changed();
        self.as_mut().set_status_text("Importing…".to_owned());

        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let files: Vec<PathBuf> = walkdir::WalkDir::new(&root)
                .follow_links(true)
                .into_iter()
                .filter_map(Result::ok)
                .filter(|e| e.file_type().is_file() && scanner::is_audio_file(e.path()))
                .map(|e| e.into_path())
                .filter(|p| !known.contains(p.to_string_lossy().as_ref()))
                .collect();

            let total = files.len();
            let mut batch = Vec::new();
            let mut last_flush = std::time::Instant::now();
            for (n, path) in files.iter().enumerate() {
                if let Some(track) = scanner::read_track(path) {
                    batch.push(track);
                }
                // Hand results to the GUI thread about once a second so the list fills in as we go
                if last_flush.elapsed().as_millis() >= 1000 || n + 1 == total {
                    last_flush = std::time::Instant::now();
                    let chunk = std::mem::take(&mut batch);
                    let done = n + 1;
                    let _ = thread.queue(move |mut model: Pin<&mut qobject::LibraryModel>| {
                        model.as_mut().set_status_text(format!("Importing {done} of {total}…"));
                        // Merge by path, in case the folder watcher already picked some up
                        model.apply_changes(Changes { upserts: chunk, ..Default::default() });
                    });
                }
            }

            let _ = thread.queue(move |mut model: Pin<&mut qobject::LibraryModel>| {
                scanner::save_library(&model.tracks);
                model.as_mut().rust_mut().scanning = false;
                model.as_mut().scanning_changed();
                let msg = match total {
                    0 => "No new songs found".to_owned(),
                    1 => "Imported 1 song".to_owned(),
                    n => format!("Imported {n} songs"),
                };
                model.as_mut().set_status_text(msg);
                model.refresh();
            });
        });
    }

    pub fn id_at(&self, row: i32) -> i32 {
        usize::try_from(row)
            .ok()
            .and_then(|r| self.view.get(r))
            .map(|&id| id as i32)
            .unwrap_or(-1)
    }

    pub fn row_of_id(&self, id: i32) -> i32 {
        self.view
            .iter()
            .position(|&i| i as i32 == id)
            .map(|r| r as i32)
            .unwrap_or(-1)
    }

    pub fn uri_of(&self, id: i32) -> QString {
        self.track(id)
            .and_then(|t| gstreamer::glib::filename_to_uri(&t.path, None).ok())
            .map(|uri| QString::from(uri.as_str()))
            .unwrap_or_default()
    }

    pub fn track_info(&self, id: i32) -> QString {
        let Some(t) = self.track(id) else {
            return QString::from("{}");
        };
        let info = serde_json::json!({
            "id": id,
            "path": t.path,
            "title": t.title,
            "artist": t.artist,
            "albumArtist": t.album_artist,
            "album": t.album,
            "genre": t.genre,
            "kind": t.kind,
            "year": t.year,
            "trackNumber": t.track_number,
            "discNumber": t.disc_number,
            "durationMs": t.duration_ms,
            "bitRate": t.bitrate,
            "sampleRate": t.sample_rate,
            "size": t.size,
            "playCount": t.play_count,
            "lastPlayed": t.last_played,
            "dateAdded": t.date_added,
        });
        QString::from(info.to_string())
    }

    pub fn artwork_url(&self, id: i32) -> QString {
        let Some(track) = self.track(id) else {
            return QString::default();
        };
        let artist = display_artist(track);
        let found = scanner::artwork_path(Path::new(&track.path))
            .or_else(|| coverart::cached_cover(artist, &track.album));
        match found {
            Some(path) => gstreamer::glib::filename_to_uri(&path, None)
                .map(|uri| QString::from(uri.as_str()))
                .unwrap_or_default(),
            None => {
                self.look_up_cover(track);
                QString::default()
            }
        }
    }

    /// Start an online cover lookup for the track's album, unless one is running or
    /// recently came up empty
    fn look_up_cover(&self, track: &Track) {
        let Some(folder) = Path::new(&track.path).parent() else {
            return;
        };
        // Only write cover.jpg into a folder that holds this one album, so a folder of
        // assorted singles doesn't end up showing one album's cover for everything
        let album = track.album.to_lowercase();
        let write_to_folder = self
            .tracks
            .iter()
            .filter(|t| !t.removed && Path::new(&t.path).parent() == Some(folder))
            .all(|t| t.album.to_lowercase() == album);
        let query = coverart::AlbumQuery {
            artist: display_artist(track).to_owned(),
            album: track.album.clone(),
            year: track.year,
            folder: folder.to_path_buf(),
            write_to_folder,
        };
        if query.album.trim().is_empty() || coverart::recently_missing(&query) {
            return;
        }
        let key = query.key();
        let in_flight = self.covers_in_flight.clone();
        if !in_flight.lock().map(|mut f| f.insert(key.clone())).unwrap_or(false) {
            return;
        }

        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let saved = coverart::fetch_and_save(&query);
            if let Ok(mut f) = in_flight.lock() {
                f.remove(&key);
            }
            if saved {
                let _ = thread.queue(|mut model: Pin<&mut qobject::LibraryModel>| {
                    let next = model.artwork_revision + 1;
                    model.as_mut().rust_mut().artwork_revision = next;
                    model.artwork_revision_changed();
                });
            }
        });
    }

    fn random_row(&self, len: usize) -> usize {
        // xorshift64: plenty random for shuffle
        let mut x = self.shuffle_state.get();
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.shuffle_state.set(x);
        (x % len as u64) as usize
    }

    pub fn next_id(&self, id: i32, shuffle: bool, wrap: bool) -> i32 {
        let len = self.view.len();
        if len == 0 {
            return -1;
        }
        if shuffle {
            let mut row = self.random_row(len);
            if len > 1 && self.view[row] as i32 == id {
                row = (row + 1) % len;
            }
            return self.view[row] as i32;
        }
        let row = self.row_of_id(id);
        let next = (row + 1) as usize;
        if next < len {
            self.view[next] as i32
        } else if wrap {
            self.view[0] as i32
        } else {
            -1
        }
    }

    pub fn previous_id(&self, id: i32) -> i32 {
        let row = self.row_of_id(id);
        if row > 0 {
            self.view[(row - 1) as usize] as i32
        } else {
            id
        }
    }

    pub fn mark_played(mut self: Pin<&mut Self>, id: i32) {
        let Ok(index) = usize::try_from(id) else {
            return;
        };
        let mut rust = self.as_mut().rust_mut();
        let Some(track) = rust.tracks.get_mut(index) else {
            return;
        };
        track.play_count += 1;
        track.last_played = scanner::now_secs();
        rust.rows_dirty = true;
        scanner::save_library(&self.tracks);
        // Only smart playlists and the Play Count column depend on this
        self.refresh();
    }

    pub fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        let Some(&id) = usize::try_from(index.row()).ok().and_then(|r| self.view.get(r)) else {
            return QVariant::default();
        };
        let t = &self.tracks[id];
        let number = |n: u32| {
            if n == 0 {
                QVariant::from(&QString::default())
            } else {
                QVariant::from(&QString::from(n.to_string()))
            }
        };
        match ROLES.get((role - USER_ROLE) as usize).copied() {
            Some("trackId") => QVariant::from(&(id as i32)),
            Some("title") => QVariant::from(&QString::from(t.title.as_str())),
            Some("artist") => QVariant::from(&QString::from(t.artist.as_str())),
            Some("album") => QVariant::from(&QString::from(t.album.as_str())),
            Some("genre") => QVariant::from(&QString::from(t.genre.as_str())),
            Some("kind") => QVariant::from(&QString::from(t.kind.as_str())),
            Some("time") => QVariant::from(&QString::from(scanner::format_time(t.duration_ms))),
            Some("trackNumber") => number(t.track_number),
            Some("year") => number(t.year),
            Some("playCount") => number(t.play_count),
            Some("bitRate") => {
                if t.bitrate == 0 {
                    QVariant::from(&QString::default())
                } else {
                    let kbps = scanner::group_thousands(t.bitrate as usize);
                    QVariant::from(&QString::from(format!("{kbps} kbps")))
                }
            }
            Some("sampleRate") => {
                QVariant::from(&QString::from(format!("{:.1} kHz", t.sample_rate as f64 / 1000.0)))
            }
            // Seconds since the epoch (0 = never), formatted for the locale in QML
            Some("dateAdded") => QVariant::from(&(t.date_added as f64)),
            Some("lastPlayed") => QVariant::from(&(t.last_played as f64)),
            _ => QVariant::default(),
        }
    }

    pub fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut roles = QHash::<QHashPair_i32_QByteArray>::default();
        for (i, name) in ROLES.iter().enumerate() {
            roles.insert(USER_ROLE + i as i32, QByteArray::from(*name));
        }
        roles
    }

    pub fn row_count(&self, _parent: &QModelIndex) -> i32 {
        self.view.len() as i32
    }
}

#[cfg(test)]
mod bench {
    use super::*;

    /// Times every keystroke of a few searches against a real library.json:
    /// `IMELODIAE_BENCH_LIBRARY=path cargo test --release bench -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn search_keystrokes() {
        let Ok(path) = std::env::var("IMELODIAE_BENCH_LIBRARY") else {
            return;
        };
        let tracks: Vec<Track> = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
        let started = std::time::Instant::now();
        let index = SearchIndex::build(&tracks);
        println!("index built in {:.1} ms", started.elapsed().as_secs_f64() * 1000.0);
        let filters = |search: &str| Filters {
            search: search.to_owned(),
            genre: String::new(),
            artist: String::new(),
            album: String::new(),
            source: 0,
            sort_column: String::new(),
            ascending: true,
        };
        for q in ["weezer", "beatles abbey", "rock", "love", "the", "a", "bowie heroes", "zzzz"] {
            println!("count {q} {}", compute_view(&tracks, &index, &filters(q)).view.len());
        }
        let mut worst = std::time::Duration::ZERO;
        let mut total = std::time::Duration::ZERO;
        let mut keystrokes = 0;
        for phrase in ["weezer", "beatles abbey"] {
            for end in 0..=phrase.len() {
                let started = std::time::Instant::now();
                let result = compute_view(&tracks, &index, &filters(&phrase[..end]));
                let took = started.elapsed();
                std::hint::black_box(result.view.len());
                worst = worst.max(took);
                total += took;
                keystrokes += 1;
            }
        }
        println!(
            "{} tracks: average {:.1} ms per keystroke, worst {:.1} ms",
            tracks.len(),
            total.as_secs_f64() * 1000.0 / keystrokes as f64,
            worst.as_secs_f64() * 1000.0
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn track(title: &str, artist: &str, album: &str, genre: &str, number: u32) -> Track {
        Track {
            title: title.into(),
            artist: artist.into(),
            album: album.into(),
            genre: genre.into(),
            track_number: number,
            ..Default::default()
        }
    }

    fn filters(search: &str) -> Filters {
        Filters {
            search: search.into(),
            genre: String::new(),
            artist: String::new(),
            album: String::new(),
            source: 0,
            sort_column: String::new(),
            ascending: true,
        }
    }

    fn library() -> Vec<Track> {
        let mut removed = track("Gone", "Weezer", "Pinkerton", "Rock", 1);
        removed.removed = true;
        vec![
            track("Say It Ain't So", "Weezer", "Weezer (Blue Album)", "Rock", 7),
            track("Buddy Holly", "Weezer", "Weezer (Blue Album)", "Rock", 4),
            track("Heroes", "David Bowie", "Best of Bowie", "Rock", 10),
            track("Clair de Lune", "Debussy", "Suite bergamasque", "Classical", 3),
            track("Untitled", "", "", "", 0),
            removed,
        ]
    }

    #[test]
    fn library_order_and_search() {
        let tracks = library();
        let index = SearchIndex::build(&tracks);
        let titles = |r: &ViewResult| r.view.iter().map(|&i| tracks[i].title.as_str()).collect::<Vec<_>>();

        // Artist, album, track number; untagged last; removed tracks never shown
        let all = compute_view(&tracks, &index, &filters(""));
        assert_eq!(titles(&all), ["Heroes", "Clair de Lune", "Buddy Holly", "Say It Ain't So", "Untitled"]);
        assert_eq!(all.genres, ["Classical", "Rock"]);

        // Every word must match, case-insensitively, in any field
        assert_eq!(titles(&compute_view(&tracks, &index, &filters("WEEZER blue"))), ["Buddy Holly", "Say It Ain't So"]);
        assert_eq!(titles(&compute_view(&tracks, &index, &filters("rock heroes"))), ["Heroes"]);
        // ...but a word can't straddle two fields
        assert!(compute_view(&tracks, &index, &filters("holly weezer")).view.len() == 1);
        assert!(compute_view(&tracks, &index, &filters("hollyweezer")).view.is_empty());
    }

    #[test]
    fn browser_and_sorting() {
        let tracks = library();
        let index = SearchIndex::build(&tracks);
        let titles = |r: &ViewResult| r.view.iter().map(|&i| tracks[i].title.as_str()).collect::<Vec<_>>();

        let mut f = filters("");
        f.genre = "rock".into(); // case-insensitive
        let rock = compute_view(&tracks, &index, &f);
        assert_eq!(rock.artists, ["David Bowie", "Weezer"]);
        assert_eq!(titles(&rock), ["Heroes", "Buddy Holly", "Say It Ain't So"]);

        f.artist = "Weezer".into();
        let weezer = compute_view(&tracks, &index, &f);
        assert_eq!(weezer.albums, ["Weezer (Blue Album)"]);

        // Sort by title, then reverse
        let mut f = filters("");
        f.sort_column = "title".into();
        assert_eq!(
            titles(&compute_view(&tracks, &index, &f)),
            ["Buddy Holly", "Clair de Lune", "Heroes", "Say It Ain't So", "Untitled"]
        );
        f.ascending = false;
        assert_eq!(titles(&compute_view(&tracks, &index, &f))[0], "Untitled");
    }
}
