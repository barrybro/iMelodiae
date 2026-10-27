//! Finding album covers online for songs that have none.
//!
//! MusicBrainz finds the album and the Cover Art Archive supplies the image; Apple's
//! iTunes Search API is the fallback. Album titles in libraries often carry extra
//! qualifiers ("Weezer (Blue Album)", "Nevermind [Deluxe Edition]"), so matching
//! strips them for the search and then uses them to pick the right candidate. That
//! is how the Blue Album is told apart from Weezer's six other self-titled albums.

use std::fs;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime};

const USER_AGENT: &str = concat!("iMelodiae/", env!("CARGO_PKG_VERSION"), " (desktop music player)");
/// Albums nobody had a cover for are retried after this long
const RETRY_MISSING: Duration = Duration::from_secs(7 * 24 * 3600);
/// Minimum score for a candidate to count as the right album
const MIN_SCORE: f64 = 4.0;

/// Words in a qualifier that describe an edition rather than which album it is
const EDITION_WORDS: &[&str] = &[
    "deluxe", "remaster", "remastered", "edition", "expanded", "bonus", "anniversary", "disc", "cd",
    "explicit", "clean", "special", "version", "mono", "stereo", "reissue", "super", "limited",
    "import", "collector", "collectors", "legacy", "tracks", "digital",
];

#[derive(Clone, Debug)]
pub struct AlbumQuery {
    pub artist: String,
    pub album: String,
    pub year: u32,
    /// Folder holding the album's files
    pub folder: PathBuf,
    /// Save cover.jpg in the folder (only when the folder holds just this album)
    pub write_to_folder: bool,
}

impl AlbumQuery {
    pub fn key(&self) -> String {
        format!("{}|{}", normalise(&self.artist), normalise(&self.album))
    }
}

/// Lowercase, "&" → "and", punctuation dropped, a leading "the " removed
fn normalise(s: &str) -> String {
    let s = s.to_lowercase().replace('&', " and ");
    let cleaned: String = s
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { ' ' })
        .collect();
    let words: Vec<&str> = cleaned.split_whitespace().collect();
    let words = match words.first() {
        Some(&"the") if words.len() > 1 => &words[1..],
        _ => &words[..],
    };
    words.join(" ")
}

/// Split "Weezer (Blue Album) [Deluxe Edition]" into ("Weezer", ["Blue Album", "Deluxe Edition"]).
/// A trailing " - Deluxe Edition" style suffix counts as a qualifier too.
fn split_title(title: &str) -> (String, Vec<String>) {
    let mut base = String::new();
    let mut qualifiers = Vec::new();
    let mut depth = 0;
    let mut current = String::new();
    for c in title.chars() {
        match c {
            '(' | '[' => {
                if depth > 0 {
                    current.push(c);
                }
                depth += 1;
            }
            ')' | ']' if depth > 0 => {
                depth -= 1;
                if depth == 0 {
                    qualifiers.push(std::mem::take(&mut current).trim().to_owned());
                } else {
                    current.push(c);
                }
            }
            _ if depth > 0 => current.push(c),
            _ => base.push(c),
        }
    }
    let mut base = base.split_whitespace().collect::<Vec<_>>().join(" ");
    if let Some((left, right)) = base.rsplit_once(" - ")
        && is_edition(right)
    {
        qualifiers.push(right.trim().to_owned());
        base = left.trim().to_owned();
    }
    if base.is_empty() {
        base = title.trim().to_owned();
    }
    qualifiers.retain(|q| !q.is_empty());
    (base, qualifiers)
}

fn is_edition(qualifier: &str) -> bool {
    let n = normalise(qualifier);
    n.split_whitespace().any(|w| EDITION_WORDS.contains(&w))
        || n.chars().all(|c| c.is_ascii_digit() || c == ' ')
}

/// Qualifiers that say which album this is ("Blue Album"), not which edition
fn identifying(qualifiers: &[String]) -> Vec<String> {
    qualifiers.iter().filter(|q| !is_edition(q)).map(|q| normalise(q)).collect()
}

/// How well a candidate album matches what we're looking for
fn score(
    query: &AlbumQuery,
    candidate_title: &str,
    candidate_note: &str,
    candidate_artist: &str,
    candidate_year: Option<u32>,
) -> f64 {
    let (base, qualifiers) = split_title(&query.album);
    let wanted = identifying(&qualifiers);
    let (cand_base, cand_qualifiers) = split_title(candidate_title);
    // A candidate's distinguishing note can live in its title or (MusicBrainz) separately
    let mut cand_ids = identifying(&cand_qualifiers);
    if !candidate_note.trim().is_empty() {
        cand_ids.push(normalise(candidate_note));
    }

    let mut s = 0.0;
    let (q_full, q_base) = (normalise(&query.album), normalise(&base));
    let (c_full, c_base) = (normalise(candidate_title), normalise(&cand_base));
    if c_full == q_full || c_base == q_base {
        s += 3.0;
    } else if !q_base.is_empty() && (c_full.contains(&q_base) || q_full.contains(&c_base)) {
        s += 1.5;
    } else {
        s += 2.0 * word_overlap(&q_full, &c_full);
    }

    // The deciding factor for same-named albums: "Blue Album" vs "Green Album"
    let id_matches = |a: &String, b: &String| a == b || a.contains(b.as_str()) || b.contains(a.as_str());
    if !wanted.is_empty() {
        if wanted.iter().any(|w| cand_ids.iter().any(|c| id_matches(w, c))) {
            s += 3.0;
        } else if !cand_ids.is_empty() {
            s -= 2.0;
        }
    } else if !cand_ids.is_empty() {
        // We asked for plain "Weezer"; a "Teal Album" is probably a different record
        s -= 0.5;
    }

    if query.year > 0
        && let Some(year) = candidate_year
    {
        match query.year.abs_diff(year) {
            0 => s += 2.0,
            1 => s += 1.0,
            _ => s -= 1.0,
        }
    }

    if normalise(candidate_artist) == normalise(&query.artist) {
        s += 1.0;
    }
    s
}

fn word_overlap(a: &str, b: &str) -> f64 {
    let a: std::collections::HashSet<&str> = a.split_whitespace().collect();
    let b: std::collections::HashSet<&str> = b.split_whitespace().collect();
    if a.is_empty() || b.is_empty() {
        return 0.0;
    }
    a.intersection(&b).count() as f64 / a.union(&b).count() as f64
}

fn agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(15)))
        .http_status_as_error(false)
        .user_agent(USER_AGENT)
        .build()
        .into()
}

/// MusicBrainz asks clients to make at most one request per second
fn musicbrainz_wait() {
    static LAST: Mutex<Option<Instant>> = Mutex::new(None);
    let mut last = LAST.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(at) = *last {
        let gap = Duration::from_millis(1100);
        if at.elapsed() < gap {
            std::thread::sleep(gap - at.elapsed());
        }
    }
    *last = Some(Instant::now());
}

fn lucene_escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

fn year_of(date: &str) -> Option<u32> {
    date.get(..4).and_then(|y| y.parse().ok())
}

/// Image bytes only if they really are a JPEG or PNG
fn image_bytes(mut response: ureq::http::Response<ureq::Body>) -> Option<Vec<u8>> {
    if response.status() != 200 {
        return None;
    }
    let bytes = response
        .body_mut()
        .with_config()
        .limit(20 * 1024 * 1024)
        .read_to_vec()
        .ok()?;
    let is_image = bytes.starts_with(&[0xFF, 0xD8, 0xFF]) || bytes.starts_with(b"\x89PNG");
    is_image.then_some(bytes)
}

fn from_musicbrainz(agent: &ureq::Agent, query: &AlbumQuery) -> Option<Vec<u8>> {
    let (base, _) = split_title(&query.album);
    let mut titles = vec![base.clone()];
    if base != query.album {
        titles.push(query.album.clone());
    }

    let mut candidates: Vec<(f64, String)> = Vec::new();
    for title in titles {
        musicbrainz_wait();
        let lucene = format!(
            "releasegroup:\"{}\" AND artist:\"{}\"",
            lucene_escape(&title),
            lucene_escape(&query.artist)
        );
        let Ok(mut response) = agent
            .get("https://musicbrainz.org/ws/2/release-group/")
            .query("fmt", "json")
            .query("limit", "25")
            .query("query", &lucene)
            .call()
        else {
            continue;
        };
        if response.status() != 200 {
            continue;
        }
        let Ok(json) = response.body_mut().read_json::<serde_json::Value>() else {
            continue;
        };
        for group in json["release-groups"].as_array().into_iter().flatten() {
            let artist = group["artist-credit"][0]["name"].as_str().unwrap_or_default();
            let mut s = score(
                query,
                group["title"].as_str().unwrap_or_default(),
                group["disambiguation"].as_str().unwrap_or_default(),
                artist,
                group["first-release-date"].as_str().and_then(year_of),
            );
            if group["primary-type"].as_str() == Some("Album") {
                s += 0.5;
            }
            if let Some(id) = group["id"].as_str()
                && !candidates.iter().any(|(_, known)| known == id)
            {
                candidates.push((s, id.to_owned()));
            }
        }
        if candidates.iter().any(|(s, _)| *s >= MIN_SCORE + 3.0) {
            break; // Confident already; skip the second search
        }
    }

    candidates.sort_by(|a, b| b.0.total_cmp(&a.0));
    // Not every album has art in the archive; try the best few matches
    for (_, id) in candidates.iter().filter(|(s, _)| *s >= MIN_SCORE).take(3) {
        let url = format!("https://coverartarchive.org/release-group/{id}/front-500");
        if let Some(bytes) = agent.get(&url).call().ok().and_then(image_bytes) {
            return Some(bytes);
        }
    }
    None
}

fn from_itunes(agent: &ureq::Agent, query: &AlbumQuery) -> Option<Vec<u8>> {
    let (base, qualifiers) = split_title(&query.album);
    let mut term = format!("{} {}", query.artist, base);
    for q in qualifiers.iter().filter(|q| !is_edition(q)) {
        term.push(' ');
        term.push_str(q);
    }
    let mut response = agent
        .get("https://itunes.apple.com/search")
        .query("term", &term)
        .query("entity", "album")
        .query("limit", "25")
        .call()
        .ok()?;
    if response.status() != 200 {
        return None;
    }
    let json: serde_json::Value = response.body_mut().read_json().ok()?;
    let best = json["results"]
        .as_array()?
        .iter()
        .map(|r| {
            let s = score(
                query,
                r["collectionName"].as_str().unwrap_or_default(),
                "",
                r["artistName"].as_str().unwrap_or_default(),
                r["releaseDate"].as_str().and_then(year_of),
            );
            (s, r)
        })
        .filter(|(s, _)| *s >= MIN_SCORE)
        .max_by(|a, b| a.0.total_cmp(&b.0))?;
    // The search returns 100px thumbnails; the same URL serves larger sizes
    let url = best.1["artworkUrl100"].as_str()?.replace("100x100bb", "600x600bb");
    agent.get(&url).call().ok().and_then(image_bytes)
}

fn cache_dir() -> PathBuf {
    let dir = dirs::cache_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join("iMelodiae")
        .join("artwork");
    let _ = fs::create_dir_all(&dir);
    dir
}

fn hashed(key: &str) -> String {
    let mut hasher = DefaultHasher::new();
    key.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

/// Downloaded cover kept in the cache, for albums whose folder can't hold a cover.jpg
pub fn cached_cover(artist: &str, album: &str) -> Option<PathBuf> {
    let key = format!("{}|{}", normalise(artist), normalise(album));
    let path = cache_dir().join(format!("album-{}.jpg", hashed(&key)));
    path.exists().then_some(path)
}

fn missing_marker(query: &AlbumQuery) -> PathBuf {
    cache_dir().join(format!("missing-{}", hashed(&query.key())))
}

/// True if we looked recently and found nothing, so we shouldn't ask again yet
pub fn recently_missing(query: &AlbumQuery) -> bool {
    fs::metadata(missing_marker(query))
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| SystemTime::now().duration_since(t).ok())
        .is_some_and(|age| age < RETRY_MISSING)
}

fn write_atomically(path: &Path, bytes: &[u8]) -> bool {
    let tmp = path.with_extension("imelodiae-tmp");
    if fs::write(&tmp, bytes).is_err() {
        let _ = fs::remove_file(&tmp);
        return false;
    }
    fs::rename(&tmp, path).is_ok()
}

/// Look the album up online and save its cover. Returns true if a cover was saved.
pub fn fetch_and_save(query: &AlbumQuery) -> bool {
    if query.album.trim().is_empty() || query.artist.trim().is_empty() {
        return false;
    }
    let agent = agent();
    let Some(bytes) = from_musicbrainz(&agent, query).or_else(|| from_itunes(&agent, query)) else {
        let _ = fs::write(missing_marker(query), b"");
        return false;
    };

    let ext = if bytes.starts_with(b"\x89PNG") { "png" } else { "jpg" };
    if query.write_to_folder {
        let cover = query.folder.join(format!("cover.{ext}"));
        if !cover.exists() && write_atomically(&cover, &bytes) {
            return true;
        }
    }
    // Folder is read-only or shared by several albums: keep the cover in the cache
    let cached = cache_dir().join(format!("album-{}.jpg", hashed(&query.key())));
    write_atomically(&cached, &bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn query(artist: &str, album: &str, year: u32) -> AlbumQuery {
        AlbumQuery {
            artist: artist.into(),
            album: album.into(),
            year,
            folder: PathBuf::new(),
            write_to_folder: false,
        }
    }

    #[test]
    fn splits_qualifiers() {
        assert_eq!(split_title("Weezer (Blue Album)"), ("Weezer".into(), vec!["Blue Album".into()]));
        assert_eq!(
            split_title("Nevermind [Super Deluxe Edition] (Remastered)"),
            ("Nevermind".into(), vec!["Super Deluxe Edition".into(), "Remastered".into()])
        );
        assert_eq!(
            split_title("Abbey Road - 2019 Remaster"),
            ("Abbey Road".into(), vec!["2019 Remaster".into()])
        );
        assert_eq!(split_title("(What's the Story) Morning Glory?").0, "Morning Glory?");
        assert!(is_edition("Deluxe Edition") && !is_edition("Blue Album"));
    }

    #[test]
    fn picks_the_blue_album_among_weezers_self_titled_records() {
        let q = query("Weezer", "Weezer (Blue Album)", 1994);
        // What MusicBrainz returns for releasegroup:"Weezer" AND artist:"Weezer"
        let candidates = [
            ("Weezer", "Red Album", 2008),
            ("Weezer", "Green Album", 2001),
            ("Weezer", "White Album", 2016),
            ("Weezer", "Teal Album", 2019),
            ("Weezer", "Black Album", 2019),
            ("Weezer", "Blue Album", 1994),
            ("Weezer", "Gold Album", 2026),
            ("Van Weezer", "", 2021),
            ("My Name Is Weezer", "", 1997),
        ];
        let best = candidates
            .iter()
            .max_by(|a, b| {
                score(&q, a.0, a.1, "Weezer", Some(a.2)).total_cmp(&score(&q, b.0, b.1, "Weezer", Some(b.2)))
            })
            .unwrap();
        assert_eq!(best.1, "Blue Album");
        assert!(score(&q, best.0, best.1, "Weezer", Some(best.2)) >= MIN_SCORE);

        // Green Album by name, even if the year tag were missing
        let q = query("Weezer", "Weezer (Green Album)", 0);
        assert!(score(&q, "Weezer", "Green Album", "Weezer", Some(2001)) > score(&q, "Weezer", "Blue Album", "Weezer", Some(1994)));
    }

    #[test]
    fn edition_qualifiers_dont_block_a_match() {
        let q = query("Nirvana", "Nevermind (Deluxe Edition)", 1991);
        assert!(score(&q, "Nevermind", "", "Nirvana", Some(1991)) >= MIN_SCORE);
        // iTunes names: "Weezer (Deluxe Edition)" is the Blue Album, "Weezer (Teal Album)" is not
        let q = query("Weezer", "Weezer (Blue Album)", 1994);
        assert!(
            score(&q, "Weezer (Deluxe Edition)", "", "Weezer", Some(1994))
                > score(&q, "Weezer (Teal Album)", "", "Weezer", Some(2019))
        );
    }
}

#[cfg(test)]
mod online_tests {
    use super::*;

    /// Hits MusicBrainz / Cover Art Archive / iTunes for real: `cargo test -- --ignored`
    #[test]
    #[ignore]
    fn fetches_real_covers() {
        let out = std::env::temp_dir().join(format!("imelodiae-covers-{}", std::process::id()));
        for (artist, album, year) in [
            ("Weezer", "Weezer (Blue Album)", 1994),
            ("Weezer", "Weezer (Green Album)", 2001),
            ("David Bowie", "Best of Bowie", 2002),
        ] {
            let folder = out.join(album);
            fs::create_dir_all(&folder).unwrap();
            let q = AlbumQuery { artist: artist.into(), album: album.into(), year, folder: folder.clone(), write_to_folder: true };
            let _ = fs::remove_file(missing_marker(&q));
            assert!(fetch_and_save(&q), "no cover for {album}");
            println!("{album}: {}", folder.join("cover.jpg").display());
        }
    }
}
