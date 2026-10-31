//! Reading audio files from disk: tags, durations, cover art and the on-disk library database.

use lofty::config::{ParseOptions, WriteOptions};
use lofty::file::{AudioFile, TaggedFileExt};
use lofty::mp4::{Mp4Codec, Mp4File};
use lofty::picture::PictureType;
use lofty::tag::{Accessor, ItemKey, Tag};
use serde::{Deserialize, Serialize};
use std::fs;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub const AUDIO_EXTENSIONS: &[&str] = &["flac", "m4a", "mp4", "alac", "mp3"];

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Track {
    pub path: String,
    pub title: String,
    pub artist: String,
    pub album_artist: String,
    pub album: String,
    pub genre: String,
    pub kind: String,
    pub track_number: u32,
    pub disc_number: u32,
    pub year: u32,
    pub duration_ms: u64,
    pub bitrate: u32,
    pub sample_rate: u32,
    pub size: u64,
    pub play_count: u32,
    pub last_played: u64,
    pub date_added: u64,
    /// File modification time (seconds) when the tags were last read; 0 = unknown
    pub mtime: u64,
    /// Deleted from disk this session. Kept in memory so track ids stay stable,
    /// never written to library.json.
    #[serde(skip)]
    pub removed: bool,
}

pub fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub fn file_mtime(path: &Path) -> u64 {
    fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub fn is_audio_file(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| AUDIO_EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

/// iTunes-style "Kind" description for a file.
fn kind_for(path: &Path) -> Option<String> {
    let ext = path.extension()?.to_str()?.to_ascii_lowercase();
    let kind = match ext.as_str() {
        "flac" => "FLAC audio file",
        "mp3" => "MPEG audio file",
        "m4a" | "mp4" | "alac" => {
            let mut file = fs::File::open(path).ok()?;
            let mp4 = Mp4File::read_from(&mut file, ParseOptions::new().read_tags(false)).ok()?;
            match mp4.properties().codec() {
                Some(Mp4Codec::ALAC) => "Apple Lossless audio file",
                Some(Mp4Codec::AAC) => "AAC audio file",
                Some(Mp4Codec::FLAC) => "FLAC audio file",
                Some(Mp4Codec::MP3) => "MPEG audio file",
                _ => "MPEG-4 audio file",
            }
        }
        _ => return None,
    };
    Some(kind.to_owned())
}

/// Read a single audio file. Files without tags still get an entry named after the file.
pub fn read_track(path: &Path) -> Option<Track> {
    let kind = kind_for(path)?;
    let size = fs::metadata(path).map(|m| m.len()).unwrap_or(0);
    let fallback_title = path
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();

    let mut track = Track {
        path: path.to_string_lossy().into_owned(),
        title: fallback_title,
        kind,
        size,
        date_added: now_secs(),
        mtime: file_mtime(path),
        ..Default::default()
    };

    let Ok(tagged) = lofty::read_from_path(path) else {
        return Some(track);
    };

    let props = tagged.properties();
    track.duration_ms = props.duration().as_millis() as u64;
    track.bitrate = props.audio_bitrate().unwrap_or(0);
    track.sample_rate = props.sample_rate().unwrap_or(0);

    if let Some(tag) = tagged.primary_tag().or_else(|| tagged.first_tag()) {
        let text = |v: Option<std::borrow::Cow<'_, str>>| {
            v.map(|s| s.trim().to_owned()).filter(|s| !s.is_empty())
        };
        if let Some(title) = text(tag.title()) {
            track.title = title;
        }
        track.artist = text(tag.artist()).unwrap_or_default();
        track.album = text(tag.album()).unwrap_or_default();
        track.genre = text(tag.genre()).unwrap_or_default();
        track.album_artist = tag
            .get_string(ItemKey::AlbumArtist)
            .map(|s| s.trim().to_owned())
            .unwrap_or_default();
        track.track_number = tag.track().unwrap_or(0);
        track.disc_number = tag.disk().unwrap_or(0);
        track.year = tag.date().map(|d| d.year as u32).unwrap_or(0);
    }

    Some(track)
}

/// Tag changes to write to a file. `None` leaves a field alone; an empty string or 0
/// removes it.
#[derive(Clone, Debug, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct TagEdit {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album_artist: Option<String>,
    pub album: Option<String>,
    pub genre: Option<String>,
    pub year: Option<u32>,
    pub track_number: Option<u32>,
    pub disc_number: Option<u32>,
}

/// Write tag changes into an audio file, in the tag `read_track` reads from
pub fn write_tags(path: &Path, edit: &TagEdit) -> Result<(), String> {
    let mut tagged = lofty::read_from_path(path).map_err(|e| e.to_string())?;
    if tagged.primary_tag().is_none() {
        // Start the file's main tag from whatever older tag it has (an MP3's ID3v1, say),
        // so the fields we're not changing aren't lost when reading switches to it
        let mut tag = Tag::new(tagged.primary_tag_type());
        if let Some(old) = tagged.first_tag() {
            for key in [ItemKey::TrackTitle, ItemKey::TrackArtist, ItemKey::AlbumTitle, ItemKey::Genre, ItemKey::AlbumArtist] {
                if let Some(v) = old.get_string(key.clone()) {
                    tag.insert_text(key, v.to_owned());
                }
            }
            if let Some(n) = old.track() {
                tag.set_track(n);
            }
            if let Some(n) = old.disk() {
                tag.set_disk(n);
            }
            if let Some(d) = old.date() {
                tag.set_date(d);
            }
        }
        tagged.insert_tag(tag);
    }
    let Some(tag) = tagged.primary_tag_mut() else {
        return Err("this file can't hold tags".to_owned());
    };

    let text = |tag: &mut Tag, value: &Option<String>, set: fn(&mut Tag, String), remove: fn(&mut Tag)| {
        match value.as_deref().map(str::trim) {
            Some("") => remove(tag),
            Some(v) => set(tag, v.to_owned()),
            None => {}
        }
    };
    text(tag, &edit.title, Tag::set_title, Tag::remove_title);
    text(tag, &edit.artist, Tag::set_artist, Tag::remove_artist);
    text(tag, &edit.album, Tag::set_album, Tag::remove_album);
    text(tag, &edit.genre, Tag::set_genre, Tag::remove_genre);
    match edit.album_artist.as_deref().map(str::trim) {
        Some("") => tag.remove_key(ItemKey::AlbumArtist),
        Some(v) => {
            tag.insert_text(ItemKey::AlbumArtist, v.to_owned());
        }
        None => {}
    }
    match edit.year {
        Some(0) => tag.remove_date(),
        Some(year) => tag.set_date(lofty::tag::items::Timestamp { year: year as u16, ..Default::default() }),
        None => {}
    }
    match edit.track_number {
        Some(0) => tag.remove_track(),
        Some(n) => tag.set_track(n),
        None => {}
    }
    match edit.disc_number {
        Some(0) => tag.remove_disk(),
        Some(n) => tag.set_disk(n),
        None => {}
    }

    tagged.save_to_path(path, WriteOptions::default()).map_err(|e| e.to_string())
}

pub fn data_dir() -> PathBuf {
    let dir = dirs::data_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("iMelodiae");
    let _ = fs::create_dir_all(&dir);
    dir
}

fn cache_dir() -> PathBuf {
    let dir = dirs::cache_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join("iMelodiae")
        .join("artwork");
    let _ = fs::create_dir_all(&dir);
    dir
}

fn library_file() -> PathBuf {
    data_dir().join("library.json")
}

pub fn load_library() -> Vec<Track> {
    fs::read(library_file())
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

pub fn save_library(tracks: &[Track]) {
    let path = library_file();
    let tmp = path.with_extension("json.tmp");
    let live: Vec<&Track> = tracks.iter().filter(|t| !t.removed).collect();
    match serde_json::to_vec(&live) {
        Ok(bytes) => {
            if fs::write(&tmp, bytes).is_ok() {
                let _ = fs::rename(&tmp, &path);
            }
        }
        Err(err) => eprintln!("iMelodiae: could not save library: {err}"),
    }
}

/// Find album artwork for a track: embedded picture first, then cover/folder images
/// in the track's directory. Returns a local file path.
pub fn artwork_path(track_path: &Path) -> Option<PathBuf> {
    if let Some(embedded) = embedded_artwork(track_path) {
        return Some(embedded);
    }
    let dir = track_path.parent()?;
    const NAMES: &[&str] = &["cover", "folder", "front", "album", "albumart"];
    let entries = fs::read_dir(dir).ok()?;
    let mut images: Vec<PathBuf> = entries
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| {
            p.extension()
                .and_then(|e| e.to_str())
                .map(|e| matches!(e.to_ascii_lowercase().as_str(), "jpg" | "jpeg" | "png"))
                .unwrap_or(false)
        })
        .collect();
    images.sort();
    images
        .iter()
        .find(|p| {
            p.file_stem()
                .and_then(|s| s.to_str())
                .map(|s| NAMES.contains(&s.to_ascii_lowercase().as_str()))
                .unwrap_or(false)
        })
        .or_else(|| images.first())
        .cloned()
}

fn embedded_artwork(track_path: &Path) -> Option<PathBuf> {
    let mut hasher = DefaultHasher::new();
    track_path.hash(&mut hasher);
    let cached = cache_dir().join(format!("{:016x}", hasher.finish()));
    if cached.exists() {
        return Some(cached);
    }

    let tagged = lofty::read_from_path(track_path).ok()?;
    let pictures = tagged.tags().iter().flat_map(|t| t.pictures());
    let picture = pictures
        .clone()
        .find(|p| p.pic_type() == PictureType::CoverFront)
        .or_else(|| tagged.tags().iter().flat_map(|t| t.pictures()).next())?;
    fs::write(&cached, picture.data()).ok()?;
    Some(cached)
}

pub fn format_time(ms: u64) -> String {
    let secs = ms / 1000;
    let (h, m, s) = (secs / 3600, (secs / 60) % 60, secs % 60);
    if h > 0 {
        format!("{h}:{m:02}:{s:02}")
    } else {
        format!("{m}:{s:02}")
    }
}

/// "1,234 songs, 3.2 days, 25.41 GB" status-bar summary.
pub fn summary(count: usize, total_ms: u64, total_bytes: u64) -> String {
    if count == 0 {
        return String::new();
    }
    let songs = if count == 1 {
        "1 song".to_owned()
    } else {
        format!("{} songs", group_thousands(count))
    };
    let secs = total_ms as f64 / 1000.0;
    let duration = if secs >= 86_400.0 {
        format!("{:.1} days", secs / 86_400.0)
    } else if secs >= 3600.0 {
        format!("{:.1} hours", secs / 3600.0)
    } else {
        format!("{:.0} minutes", (secs / 60.0).ceil())
    };
    let mb = total_bytes as f64 / (1024.0 * 1024.0);
    let size = if mb >= 1024.0 {
        format!("{:.2} GB", mb / 1024.0)
    } else {
        format!("{mb:.1} MB")
    };
    format!("{songs}, {duration}, {size}")
}

pub fn group_thousands(n: usize) -> String {
    let digits = n.to_string();
    let mut out = String::new();
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i).is_multiple_of(3) {
            out.push(',');
        }
        out.push(c);
    }
    out
}
