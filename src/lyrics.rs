//! Song lyrics, time-synced when possible.
//!
//! Sources, in order: a `.lrc` file next to the song, lyrics embedded in the file's
//! tags, a local cache, and finally the free LRCLIB service (https://lrclib.net).

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        /// "idle", "loading", "found", "instrumental" or "missing"
        #[qproperty(QString, state, READ, NOTIFY)]
        #[qproperty(bool, synced, READ, NOTIFY)]
        /// JSON array of {"t": milliseconds or -1 when unsynced, "text": line}
        #[qproperty(QString, lines_json, READ, NOTIFY)]
        /// Where the lyrics came from, for the credit line
        #[qproperty(QString, source, READ, NOTIFY)]
        type Lyrics = super::LyricsRust;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        /// Look up lyrics for a song; repeated calls for the same song are ignored
        #[qinvokable]
        fn load(
            self: Pin<&mut Lyrics>,
            path: &QString,
            title: &QString,
            artist: &QString,
            album: &QString,
            duration_ms: i32,
        );

        #[qinvokable]
        fn clear(self: Pin<&mut Lyrics>);
    }

    impl cxx_qt::Threading for Lyrics {}
}

use core::pin::Pin;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use lofty::file::TaggedFileExt;
use lofty::tag::ItemKey;
use serde::{Deserialize, Serialize};
use std::fs;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::{Path, PathBuf};
use std::time::Duration;

const LRCLIB: &str = "https://lrclib.net/api";
/// How long to wait before asking LRCLIB again about a song it didn't have
const RETRY_MISSING_SECS: u64 = 7 * 24 * 3600;

#[derive(Default)]
pub struct LyricsRust {
    state: QString,
    synced: bool,
    lines_json: QString,
    source: QString,
    /// Song currently shown or being fetched
    key: String,
    /// Bumped on every request so late answers for an old song are dropped
    generation: u64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct Found {
    synced: bool,
    instrumental: bool,
    /// (milliseconds, or -1 when unsynced; text)
    lines: Vec<(i64, String)>,
    source: String,
}

#[derive(Serialize, Deserialize)]
struct CacheEntry {
    found: Option<Found>,
    checked_at: u64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LrclibRecord {
    #[serde(default)]
    duration: f64,
    #[serde(default)]
    instrumental: bool,
    plain_lyrics: Option<String>,
    synced_lyrics: Option<String>,
}

struct Query {
    path: PathBuf,
    title: String,
    artist: String,
    album: String,
    duration_secs: u64,
}

/// Parse a timestamp like `01:23.45` or `01:23` into milliseconds
fn parse_timestamp(stamp: &str) -> Option<i64> {
    let (min, rest) = stamp.split_once(':')?;
    let min: i64 = min.trim().parse().ok()?;
    let (sec, frac) = rest.split_once(['.', ':']).unwrap_or((rest, "0"));
    let sec: i64 = sec.trim().parse().ok()?;
    let frac = frac.trim();
    let frac_ms = match frac.len() {
        0 => 0,
        1 => frac.parse::<i64>().ok()? * 100,
        2 => frac.parse::<i64>().ok()? * 10,
        _ => frac[..3].parse::<i64>().ok()?,
    };
    Some(min * 60_000 + sec * 1000 + frac_ms)
}

/// Parse LRC text. Returns None if it has no timestamps (i.e. plain lyrics).
fn parse_lrc(text: &str) -> Option<Vec<(i64, String)>> {
    let mut offset = 0i64;
    let mut lines = Vec::new();
    for raw in text.lines() {
        let mut rest = raw.trim();
        let mut stamps = Vec::new();
        while let Some(tag) = rest.strip_prefix('[') {
            let Some(end) = tag.find(']') else { break };
            let inner = &tag[..end];
            if let Some(ms) = parse_timestamp(inner) {
                stamps.push(ms);
            } else if let Some(value) = inner.strip_prefix("offset:") {
                offset = value.trim().parse().unwrap_or(0);
            }
            rest = tag[end + 1..].trim_start();
        }
        if stamps.is_empty() {
            continue;
        }
        // Drop enhanced-LRC word timings like <00:12.34>
        let mut text = String::new();
        let mut in_word_stamp = false;
        for c in rest.chars() {
            match c {
                '<' => in_word_stamp = true,
                '>' if in_word_stamp => in_word_stamp = false,
                _ if !in_word_stamp => text.push(c),
                _ => {}
            }
        }
        let text = text.split_whitespace().collect::<Vec<_>>().join(" ");
        for ms in stamps {
            // A positive offset means the lyrics should show earlier
            lines.push(((ms - offset).max(0), text.clone()));
        }
    }
    if lines.is_empty() {
        return None;
    }
    lines.sort_by_key(|(ms, _)| *ms);
    Some(lines)
}

/// Build a result from LRC or plain text
fn from_text(text: &str, source: &str) -> Option<Found> {
    if let Some(lines) = parse_lrc(text) {
        return Some(Found { synced: true, instrumental: false, lines, source: source.to_owned() });
    }
    let lines: Vec<(i64, String)> = text
        .trim()
        .lines()
        .map(|l| (-1, l.trim().to_owned()))
        .collect();
    if lines.iter().all(|(_, l)| l.is_empty()) {
        return None;
    }
    Some(Found { synced: false, instrumental: false, lines, source: source.to_owned() })
}

fn sidecar_lyrics(path: &Path) -> Option<Found> {
    let text = fs::read_to_string(path.with_extension("lrc")).ok()?;
    from_text(&text, "LRC file")
}

fn embedded_lyrics(path: &Path) -> Option<Found> {
    let tagged = lofty::read_from_path(path).ok()?;
    let text = tagged
        .tags()
        .iter()
        .find_map(|tag| tag.get_string(ItemKey::Lyrics).map(str::to_owned))?;
    from_text(&text, "song file")
}

fn cache_path(q: &Query) -> PathBuf {
    let mut hasher = DefaultHasher::new();
    (&q.artist, &q.title, &q.album, q.duration_secs).hash(&mut hasher);
    let dir = dirs::cache_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join("iMelodiae")
        .join("lyrics");
    let _ = fs::create_dir_all(&dir);
    dir.join(format!("{:016x}.json", hasher.finish()))
}

fn record_to_found(record: LrclibRecord) -> Option<Found> {
    if record.instrumental {
        return Some(Found { instrumental: true, source: "LRCLIB".into(), ..Default::default() });
    }
    record
        .synced_lyrics
        .as_deref()
        .and_then(|t| from_text(t, "LRCLIB"))
        .or_else(|| record.plain_lyrics.as_deref().and_then(|t| from_text(t, "LRCLIB")))
}

/// Ask LRCLIB. Ok(None) means it doesn't have the song; Err means we couldn't ask.
fn fetch_lrclib(q: &Query) -> Result<Option<Found>, ureq::Error> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(10)))
        .http_status_as_error(false)
        .user_agent(concat!("iMelodiae/", env!("CARGO_PKG_VERSION")))
        .build()
        .into();

    // Exact match on title/artist/album/duration first
    let mut response = agent
        .get(format!("{LRCLIB}/get"))
        .query("track_name", &q.title)
        .query("artist_name", &q.artist)
        .query("album_name", &q.album)
        .query("duration", q.duration_secs.to_string())
        .call()?;
    if response.status() == 200 {
        let record: LrclibRecord = response.body_mut().read_json()?;
        if let Some(found) = record_to_found(record) {
            return Ok(Some(found));
        }
    }

    // Then a looser search, preferring synced lyrics with the closest duration
    let mut response = agent
        .get(format!("{LRCLIB}/search"))
        .query("track_name", &q.title)
        .query("artist_name", &q.artist)
        .call()?;
    if response.status() != 200 {
        return Ok(None);
    }
    let mut records: Vec<LrclibRecord> = response.body_mut().read_json()?;
    records.retain(|r| q.duration_secs == 0 || (r.duration - q.duration_secs as f64).abs() <= 5.0);
    records.sort_by_key(|r| {
        (
            r.synced_lyrics.is_none(),
            ((r.duration - q.duration_secs as f64).abs() * 10.0) as i64,
        )
    });
    Ok(records.into_iter().find_map(record_to_found))
}

fn lookup(q: &Query) -> Option<Found> {
    if let Some(found) = sidecar_lyrics(&q.path).or_else(|| embedded_lyrics(&q.path)) {
        return Some(found);
    }
    if q.title.is_empty() || q.artist.is_empty() {
        return None;
    }

    let cache = cache_path(q);
    let now = crate::scanner::now_secs();
    if let Some(entry) = fs::read(&cache)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<CacheEntry>(&bytes).ok())
        && (entry.found.is_some() || now.saturating_sub(entry.checked_at) < RETRY_MISSING_SECS)
    {
        return entry.found;
    }

    match fetch_lrclib(q) {
        Ok(found) => {
            let entry = CacheEntry { found, checked_at: now };
            if let Ok(bytes) = serde_json::to_vec(&entry) {
                let _ = fs::write(&cache, bytes);
            }
            entry.found
        }
        Err(err) => {
            // Offline or LRCLIB is down: don't cache, try again next time
            eprintln!("iMelodiae: lyrics lookup failed: {err}");
            None
        }
    }
}

impl qobject::Lyrics {
    fn show(mut self: Pin<&mut Self>, state: &str, found: Option<Found>) {
        let found = found.unwrap_or_default();
        let lines: Vec<serde_json::Value> = found
            .lines
            .iter()
            .map(|(t, text)| serde_json::json!({ "t": t, "text": text }))
            .collect();
        let mut rust = self.as_mut().rust_mut();
        rust.state = QString::from(state);
        rust.synced = found.synced;
        rust.lines_json = QString::from(serde_json::Value::Array(lines).to_string());
        rust.source = QString::from(found.source.as_str());
        self.as_mut().lines_json_changed();
        self.as_mut().synced_changed();
        self.as_mut().source_changed();
        self.state_changed();
    }

    pub fn load(
        mut self: Pin<&mut Self>,
        path: &QString,
        title: &QString,
        artist: &QString,
        album: &QString,
        duration_ms: i32,
    ) {
        let query = Query {
            path: PathBuf::from(path.to_string()),
            title: title.to_string().trim().to_owned(),
            artist: artist.to_string().trim().to_owned(),
            album: album.to_string().trim().to_owned(),
            duration_secs: (duration_ms.max(0) as u64 + 500) / 1000,
        };
        let key = path.to_string();
        if key == self.key {
            return;
        }
        let mut rust = self.as_mut().rust_mut();
        rust.key = key;
        rust.generation += 1;
        let generation = rust.generation;
        self.as_mut().show("loading", None);

        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let found = lookup(&query);
            let _ = thread.queue(move |lyrics: Pin<&mut qobject::Lyrics>| {
                if lyrics.generation != generation {
                    return;
                }
                let state = match &found {
                    Some(f) if f.instrumental => "instrumental",
                    Some(_) => "found",
                    None => "missing",
                };
                lyrics.show(state, found);
            });
        });
    }

    pub fn clear(mut self: Pin<&mut Self>) {
        let mut rust = self.as_mut().rust_mut();
        rust.key.clear();
        rust.generation += 1;
        self.show("idle", None);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_synced_lrc() {
        let lrc = "[ar:Someone]\n[offset:+500]\n[00:12.00]First line\n[00:15.5][01:02.25]Chorus\n[00:20.123]<00:20.123>Word <00:21.000>sync\n[00:30.00]\n";
        let lines = parse_lrc(lrc).unwrap();
        assert_eq!(
            lines,
            vec![
                (11_500, "First line".to_owned()),
                (15_000, "Chorus".to_owned()),
                (19_623, "Word sync".to_owned()),
                (29_500, String::new()),
                (61_750, "Chorus".to_owned()),
            ]
        );
    }

    #[test]
    fn plain_text_is_unsynced() {
        assert!(parse_lrc("Just\nwords").is_none());
        let found = from_text("Just\nwords\n", "x").unwrap();
        assert!(!found.synced);
        assert_eq!(found.lines, vec![(-1, "Just".to_owned()), (-1, "words".to_owned())]);
    }
}
