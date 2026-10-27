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

        /// file:// URL of the track's album artwork, or empty
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

use crate::scanner::{self, Track};
use core::pin::Pin;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QStringList, QVariant};
use std::cmp::Ordering;
use std::collections::{BTreeSet, HashSet};
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
];
const USER_ROLE: i32 = 0x0100;

type TrackOrder = Box<dyn Fn(&Track, &Track) -> Ordering>;

#[derive(Default)]
pub struct LibraryModelRust {
    count: i32,
    total_count: i32,
    summary: QString,
    status: QString,
    scanning: bool,
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

    /// Every track; a track's id is its index here
    tracks: Vec<Track>,
    /// Track ids in the current view, in display order
    view: Vec<usize>,
    shuffle_state: std::cell::Cell<u64>,
}

impl cxx_qt::Initialize for qobject::LibraryModel {
    fn initialize(mut self: Pin<&mut Self>) {
        let tracks = scanner::load_library();
        let mut rust = self.as_mut().rust_mut();
        rust.tracks = tracks;
        rust.sort_ascending = true;
        rust.shuffle_state.set(scanner::now_secs() | 1);
        self.as_mut().refresh();
    }
}

fn display_artist(t: &Track) -> &str {
    if !t.album_artist.is_empty() {
        &t.album_artist
    } else {
        &t.artist
    }
}

fn lower_cmp(a: &str, b: &str) -> Ordering {
    // Empty values sort last, like iTunes
    match (a.is_empty(), b.is_empty()) {
        (true, false) => Ordering::Greater,
        (false, true) => Ordering::Less,
        _ => a
            .chars()
            .flat_map(char::to_lowercase)
            .cmp(b.chars().flat_map(char::to_lowercase)),
    }
}

/// Default iTunes ordering: artist, album, disc, track number
fn album_order(a: &Track, b: &Track) -> Ordering {
    lower_cmp(display_artist(a), display_artist(b))
        .then_with(|| lower_cmp(&a.album, &b.album))
        .then(a.disc_number.cmp(&b.disc_number))
        .then(a.track_number.cmp(&b.track_number))
        .then_with(|| lower_cmp(&a.title, &b.title))
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

impl qobject::LibraryModel {
    fn track(&self, id: i32) -> Option<&Track> {
        usize::try_from(id).ok().and_then(|i| self.tracks.get(i))
    }

    /// Rebuild the browser columns and the visible song list from the current filters.
    fn refresh(mut self: Pin<&mut Self>) {
        let search: Vec<String> = self
            .search
            .to_string()
            .to_lowercase()
            .split_whitespace()
            .map(str::to_owned)
            .collect();
        let genre = self.genre.to_string();
        let artist = self.artist.to_string();
        let album = self.album.to_string();
        let source = self.source;
        let sort_column = self.sort_column.to_string();
        let ascending = self.sort_ascending;

        let tracks = &self.tracks;

        // 1. Source (Library or smart playlist)
        let mut source_ids: Vec<usize> = (0..tracks.len()).collect();
        match source {
            SOURCE_RECENTLY_ADDED => {
                source_ids.sort_by(|&a, &b| tracks[b].date_added.cmp(&tracks[a].date_added));
                source_ids.truncate(25);
            }
            SOURCE_TOP_PLAYED => {
                source_ids.retain(|&i| tracks[i].play_count > 0);
                source_ids.sort_by(|&a, &b| tracks[b].play_count.cmp(&tracks[a].play_count));
                source_ids.truncate(25);
            }
            SOURCE_RECENTLY_PLAYED => {
                source_ids.retain(|&i| tracks[i].last_played > 0);
                source_ids.sort_by(|&a, &b| tracks[b].last_played.cmp(&tracks[a].last_played));
                source_ids.truncate(25);
            }
            _ => source_ids.sort_by(|&a, &b| album_order(&tracks[a], &tracks[b])),
        }

        // 2. Search
        source_ids.retain(|&i| {
            let t = &tracks[i];
            search.iter().all(|word| {
                [&t.title, &t.artist, &t.album_artist, &t.album, &t.genre]
                    .iter()
                    .any(|field| field.to_lowercase().contains(word.as_str()))
            })
        });

        // 3. Browser columns
        let collect = |ids: &[usize], key: fn(&Track) -> &str| -> Vec<String> {
            let set: BTreeSet<(String, String)> = ids
                .iter()
                .map(|&i| key(&tracks[i]))
                .filter(|s| !s.is_empty())
                .map(|s| (s.to_lowercase(), s.to_owned()))
                .collect();
            let mut seen = HashSet::new();
            set.into_iter()
                .filter(|(lower, _)| seen.insert(lower.clone()))
                .map(|(_, s)| s)
                .collect()
        };
        let matches = |value: &str, filter: &str| filter.is_empty() || value.eq_ignore_ascii_case(filter);

        let genres = collect(&source_ids, |t| &t.genre);
        let genre_ids: Vec<usize> = source_ids
            .iter()
            .copied()
            .filter(|&i| matches(&tracks[i].genre, &genre))
            .collect();
        let artists = collect(&genre_ids, display_artist);
        let artist_ids: Vec<usize> = genre_ids
            .iter()
            .copied()
            .filter(|&i| {
                matches(display_artist(&tracks[i]), &artist) || matches(&tracks[i].artist, &artist)
            })
            .collect();
        let albums = collect(&artist_ids, |t| &t.album);
        let mut view: Vec<usize> = artist_ids
            .into_iter()
            .filter(|&i| matches(&tracks[i].album, &album))
            .collect();

        // 4. Column sort
        if !sort_column.is_empty() {
            let by: TrackOrder = match sort_column.as_str() {
                "title" => Box::new(|a, b| lower_cmp(&a.title, &b.title)),
                "time" => Box::new(|a, b| a.duration_ms.cmp(&b.duration_ms)),
                "artist" => Box::new(album_order),
                "album" => Box::new(|a, b| {
                    lower_cmp(&a.album, &b.album).then_with(|| album_order(a, b))
                }),
                "genre" => Box::new(|a, b| {
                    lower_cmp(&a.genre, &b.genre).then_with(|| album_order(a, b))
                }),
                "kind" => Box::new(|a, b| a.kind.cmp(&b.kind).then_with(|| album_order(a, b))),
                "year" => Box::new(|a, b| a.year.cmp(&b.year).then_with(|| album_order(a, b))),
                "playCount" => Box::new(|a, b| a.play_count.cmp(&b.play_count)),
                "trackNumber" => Box::new(|a, b| {
                    a.track_number.cmp(&b.track_number).then_with(|| album_order(a, b))
                }),
                "bitRate" => Box::new(|a, b| a.bitrate.cmp(&b.bitrate)),
                _ => Box::new(|_, _| Ordering::Equal),
            };
            view.sort_by(|&a, &b| by(&tracks[a], &tracks[b]));
        }
        if !ascending {
            view.reverse();
        }

        let total_ms = view.iter().map(|&i| tracks[i].duration_ms).sum();
        let total_bytes = view.iter().map(|&i| tracks[i].size).sum();
        let summary = QString::from(scanner::summary(view.len(), total_ms, total_bytes));
        let total = tracks.len() as i32;

        self.as_mut().begin_reset_model();
        self.as_mut().rust_mut().view = view;
        self.as_mut().end_reset_model();

        let count = self.view.len() as i32;
        if self.count != count {
            self.as_mut().rust_mut().count = count;
            self.as_mut().count_changed();
        }
        if self.total_count != total {
            self.as_mut().rust_mut().total_count = total;
            self.as_mut().total_count_changed();
        }
        self.as_mut().rust_mut().summary = summary;
        self.as_mut().summary_changed();
        self.as_mut().rust_mut().genres = to_qstringlist(genres);
        self.as_mut().genres_changed();
        self.as_mut().rust_mut().artists = to_qstringlist(artists);
        self.as_mut().artists_changed();
        self.as_mut().rust_mut().albums = to_qstringlist(albums);
        self.as_mut().albums_changed();
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

    pub fn import_default_folder(self: Pin<&mut Self>) {
        if !self.tracks.is_empty() || self.scanning {
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

        let known: HashSet<String> = self.tracks.iter().map(|t| t.path.clone()).collect();
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
                        model.as_mut().rust_mut().tracks.extend(chunk);
                        model.as_mut().set_status_text(format!("Importing {done} of {total}…"));
                        model.refresh();
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
            "album": t.album,
            "genre": t.genre,
            "kind": t.kind,
            "year": t.year,
            "durationMs": t.duration_ms,
        });
        QString::from(info.to_string())
    }

    pub fn artwork_url(&self, id: i32) -> QString {
        self.track(id)
            .and_then(|t| scanner::artwork_path(Path::new(&t.path)))
            .and_then(|p| gstreamer::glib::filename_to_uri(&p, None).ok())
            .map(|uri| QString::from(uri.as_str()))
            .unwrap_or_default()
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
                    QVariant::from(&QString::from(format!("{} kbps", t.bitrate)))
                }
            }
            Some("sampleRate") => {
                QVariant::from(&QString::from(format!("{:.1} kHz", t.sample_rate as f64 / 1000.0)))
            }
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
