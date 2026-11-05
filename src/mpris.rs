//! MPRIS: the D-Bus interface Linux desktops use to find and control music players.
//! It's what makes the keyboard's play/pause, next and previous keys work (Hyprland
//! sends them to whichever MPRIS player is active), and what lets bar widgets show
//! the playing song.
//!
//! QML feeds the playing state in through properties; requests from the desktop come
//! back out as signals for QML to act on, the same way the toolbar buttons do.

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
        #[qproperty(bool, playing, READ, WRITE = set_playing_state, NOTIFY)]
        #[qproperty(bool, loaded, READ, WRITE = set_loaded_state, NOTIFY)]
        /// The playing song as JSON: id, title, artist, albumArtist, album, path,
        /// durationMs and artUrl
        #[qproperty(QString, metadata, READ, WRITE = set_metadata_json, NOTIFY)]
        /// Milliseconds into the song; read by the desktop when it wants it. A jump (a
        /// seek, from anywhere in the app) is announced so progress bars follow it.
        #[qproperty(i32, position, READ, WRITE = set_position_ms, NOTIFY)]
        #[qproperty(f64, volume, READ, WRITE = set_volume_level, NOTIFY)]
        type MediaControls = super::MediaControlsRust;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        fn set_playing_state(self: Pin<&mut MediaControls>, playing: bool);
        fn set_loaded_state(self: Pin<&mut MediaControls>, loaded: bool);
        fn set_metadata_json(self: Pin<&mut MediaControls>, metadata: QString);
        fn set_position_ms(self: Pin<&mut MediaControls>, position: i32);
        fn set_volume_level(self: Pin<&mut MediaControls>, volume: f64);

        #[qsignal]
        fn play_pause_requested(self: Pin<&mut MediaControls>);
        #[qsignal]
        fn play_requested(self: Pin<&mut MediaControls>);
        #[qsignal]
        fn pause_requested(self: Pin<&mut MediaControls>);
        #[qsignal]
        fn stop_requested(self: Pin<&mut MediaControls>);
        #[qsignal]
        fn next_requested(self: Pin<&mut MediaControls>);
        #[qsignal]
        fn previous_requested(self: Pin<&mut MediaControls>);
        /// Jump to a position in the song, in milliseconds
        #[qsignal]
        fn seek_requested(self: Pin<&mut MediaControls>, position: i32);
        #[qsignal]
        fn volume_requested(self: Pin<&mut MediaControls>, volume: f64);
        #[qsignal]
        fn raise_requested(self: Pin<&mut MediaControls>);
        #[qsignal]
        fn quit_requested(self: Pin<&mut MediaControls>);
    }

    impl cxx_qt::Threading for MediaControls {}
    impl cxx_qt::Initialize for MediaControls {}
}

use core::pin::Pin;
use cxx_qt::{CxxQtThread, CxxQtType, Threading};
use cxx_qt_lib::QString;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use zbus::object_server::SignalEmitter;
use zbus::{OwnedObjectPath, OwnedVariant, Variant, interface};

const BUS_NAME: &str = "org.mpris.MediaPlayer2.imelodiae";
const OBJECT_PATH: &str = "/org/mpris/MediaPlayer2";
const NO_TRACK: &str = "/org/mpris/MediaPlayer2/TrackList/NoTrack";

/// What the desktop can ask about, shared with the D-Bus interfaces
#[derive(Default)]
struct State {
    playing: bool,
    loaded: bool,
    track: Track,
    position_ms: i32,
    volume: f64,
}

#[derive(Default, Clone, PartialEq, serde::Deserialize)]
#[serde(default, rename_all = "camelCase")]
struct Track {
    id: i64,
    title: String,
    artist: String,
    album_artist: String,
    album: String,
    path: String,
    duration_ms: i64,
    art_url: String,
}

impl Track {
    fn object_path(&self) -> String {
        format!("/org/imelodiae/Track/{}", self.id.max(0))
    }
}

pub struct MediaControlsRust {
    playing: bool,
    loaded: bool,
    metadata: QString,
    position: i32,
    volume: f64,
    state: Arc<Mutex<State>>,
    /// None when there's no session bus, in which case nothing is published
    connection: Option<zbus::Connection>,
}

impl Default for MediaControlsRust {
    fn default() -> Self {
        Self {
            playing: false,
            loaded: false,
            metadata: QString::default(),
            position: 0,
            volume: 1.0,
            state: Arc::new(Mutex::new(State { volume: 1.0, ..Default::default() })),
            connection: None,
        }
    }
}

type Thread = CxxQtThread<qobject::MediaControls>;

/// org.mpris.MediaPlayer2: who we are
struct Root {
    thread: Thread,
}

#[interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    fn raise(&self) {
        let _ = self.thread.queue(|o| o.raise_requested());
    }
    fn quit(&self) {
        let _ = self.thread.queue(|o| o.quit_requested());
    }
    #[zbus(property)]
    fn can_quit(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_raise(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn has_track_list(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn identity(&self) -> String {
        "iMelodiae".into()
    }
    #[zbus(property)]
    fn desktop_entry(&self) -> String {
        "imelodiae".into()
    }
    #[zbus(property)]
    fn supported_uri_schemes(&self) -> Vec<String> {
        Vec::new()
    }
    #[zbus(property)]
    fn supported_mime_types(&self) -> Vec<String> {
        Vec::new()
    }
}

/// org.mpris.MediaPlayer2.Player: playback state and controls
struct PlayerIface {
    state: Arc<Mutex<State>>,
    thread: Thread,
}

impl PlayerIface {
    fn with<R>(&self, f: impl FnOnce(&State) -> R) -> R {
        f(&self.state.lock().unwrap_or_else(|e| e.into_inner()))
    }
}

fn variant(v: impl Into<Variant<'static>>) -> Option<OwnedVariant> {
    v.into().try_into_owned().ok()
}

#[interface(name = "org.mpris.MediaPlayer2.Player")]
impl PlayerIface {
    fn play_pause(&self) {
        let _ = self.thread.queue(|o| o.play_pause_requested());
    }
    fn play(&self) {
        let _ = self.thread.queue(|o| o.play_requested());
    }
    fn pause(&self) {
        let _ = self.thread.queue(|o| o.pause_requested());
    }
    fn stop(&self) {
        let _ = self.thread.queue(|o| o.stop_requested());
    }
    fn next(&self) {
        let _ = self.thread.queue(|o| o.next_requested());
    }
    fn previous(&self) {
        let _ = self.thread.queue(|o| o.previous_requested());
    }
    /// Move by an offset in microseconds
    fn seek(&self, offset: i64) {
        let (loaded, at, length) = self.with(|s| (s.loaded, s.position_ms as i64, s.track.duration_ms));
        if !loaded {
            return;
        }
        let target = (at + offset / 1000).max(0);
        if length > 0 && target >= length {
            let _ = self.thread.queue(|o| o.next_requested());
        } else {
            let _ = self.thread.queue(move |o| o.seek_requested(target as i32));
        }
    }
    /// Jump to a position in microseconds, if `track_id` is still the playing song
    fn set_position(&self, track_id: OwnedObjectPath, position: i64) {
        let (loaded, current, length) = self.with(|s| (s.loaded, s.track.object_path(), s.track.duration_ms));
        let ms = position / 1000;
        if loaded && track_id.as_str() == current && ms >= 0 && (length == 0 || ms <= length) {
            let _ = self.thread.queue(move |o| o.seek_requested(ms as i32));
        }
    }
    fn open_uri(&self, _uri: String) {}

    #[zbus(signal)]
    async fn seeked(emitter: &SignalEmitter<'_>, position: i64) -> zbus::Result<()>;

    #[zbus(property)]
    fn playback_status(&self) -> String {
        self.with(|s| match (s.loaded, s.playing) {
            (true, true) => "Playing",
            (true, false) => "Paused",
            _ => "Stopped",
        })
        .into()
    }
    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, OwnedVariant> {
        self.with(|s| {
            let mut map = HashMap::new();
            let mut put = |key: &str, value: Option<OwnedVariant>| {
                if let Some(value) = value {
                    map.insert(key.to_owned(), value);
                }
            };
            if !s.loaded {
                put("mpris:trackid", OwnedObjectPath::try_from(NO_TRACK).ok().and_then(variant));
                return map;
            }
            let t = &s.track;
            put("mpris:trackid", OwnedObjectPath::try_from(t.object_path()).ok().and_then(variant));
            if t.duration_ms > 0 {
                put("mpris:length", variant(t.duration_ms * 1000));
            }
            put("xesam:title", variant(t.title.clone()));
            if !t.artist.is_empty() {
                put("xesam:artist", variant(vec![t.artist.clone()]));
            }
            if !t.album_artist.is_empty() {
                put("xesam:albumArtist", variant(vec![t.album_artist.clone()]));
            }
            if !t.album.is_empty() {
                put("xesam:album", variant(t.album.clone()));
            }
            if !t.art_url.is_empty() {
                put("mpris:artUrl", variant(t.art_url.clone()));
            }
            if let Ok(url) = gstreamer::glib::filename_to_uri(&t.path, None) {
                put("xesam:url", variant(url.to_string()));
            }
            map
        })
    }
    /// Microseconds into the song. Not signalled as it changes; desktops ask for it.
    #[zbus(property(emits_changed_signal = "false"))]
    fn position(&self) -> i64 {
        self.with(|s| s.position_ms as i64 * 1000)
    }
    #[zbus(property)]
    fn volume(&self) -> f64 {
        self.with(|s| s.volume)
    }
    #[zbus(property)]
    fn set_volume(&mut self, volume: f64) {
        let volume = volume.clamp(0.0, 1.0);
        let _ = self.thread.queue(move |o| o.volume_requested(volume));
    }
    #[zbus(property)]
    fn rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn minimum_rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn maximum_rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_play(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_pause(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_seek(&self) -> bool {
        self.with(|s| s.loaded)
    }
    #[zbus(property(emits_changed_signal = "const"))]
    fn can_control(&self) -> bool {
        true
    }
}

/// Which Player properties to announce as changed
#[derive(Clone, Copy)]
enum Changed {
    Status,
    Metadata,
    Volume,
}

impl cxx_qt::Initialize for qobject::MediaControls {
    fn initialize(mut self: Pin<&mut Self>) {
        let thread = self.qt_thread();
        let state = self.state.clone();
        let connect = async {
            let root = Root { thread: thread.clone() };
            let player = PlayerIface { state, thread };
            let connection = zbus::connection::Builder::session()
                .serve_at(OBJECT_PATH, root)
                .serve_at(OBJECT_PATH, player)
                .build()
                .await?;
            // A second copy of the app takes a name of its own, as MPRIS allows
            if connection.request_name(BUS_NAME).await.is_err() {
                connection
                    .request_name(format!("{BUS_NAME}.instance{}", std::process::id()))
                    .await?;
            }
            Ok::<_, zbus::Error>(connection)
        };
        match zbus::block_on(connect) {
            Ok(connection) => self.as_mut().rust_mut().connection = Some(connection),
            Err(err) => eprintln!("iMelodiae: media keys unavailable (no D-Bus session): {err}"),
        }
    }
}

impl qobject::MediaControls {
    fn update(&self, f: impl FnOnce(&mut State)) {
        f(&mut self.state.lock().unwrap_or_else(|e| e.into_inner()));
    }

    /// Send PropertiesChanged for some Player properties
    fn announce(&self, changes: &[Changed]) {
        let Some(connection) = self.connection.clone() else {
            return;
        };
        let changes = changes.to_vec();
        let sent = zbus::block_on(async move {
            let iface = connection.object_server().interface::<_, PlayerIface>(OBJECT_PATH).await?;
            let emitter = iface.signal_emitter();
            let player = iface.get().await;
            for change in changes {
                match change {
                    Changed::Status => {
                        player.playback_status_changed(emitter).await?;
                        player.can_seek_changed(emitter).await?;
                    }
                    Changed::Metadata => player.metadata_changed(emitter).await?,
                    Changed::Volume => player.volume_changed(emitter).await?,
                }
            }
            Ok::<_, zbus::Error>(())
        });
        if let Err(err) = sent {
            eprintln!("iMelodiae: could not update media controls: {err}");
        }
    }

    pub fn set_playing_state(mut self: Pin<&mut Self>, playing: bool) {
        if self.playing == playing {
            return;
        }
        self.as_mut().rust_mut().playing = playing;
        self.update(|s| s.playing = playing);
        self.announce(&[Changed::Status]);
        self.playing_changed();
    }

    pub fn set_loaded_state(mut self: Pin<&mut Self>, loaded: bool) {
        if self.loaded == loaded {
            return;
        }
        self.as_mut().rust_mut().loaded = loaded;
        self.update(|s| s.loaded = loaded);
        self.announce(&[Changed::Status, Changed::Metadata]);
        self.loaded_changed();
    }

    pub fn set_metadata_json(mut self: Pin<&mut Self>, metadata: QString) {
        if self.metadata == metadata {
            return;
        }
        let track: Track = serde_json::from_str(&metadata.to_string()).unwrap_or_default();
        self.as_mut().rust_mut().metadata = metadata;
        let mut changed = false;
        self.update(|s| {
            changed = s.track != track;
            s.track = track;
        });
        if changed {
            self.announce(&[Changed::Metadata]);
        }
        self.metadata_changed();
    }

    pub fn set_position_ms(mut self: Pin<&mut Self>, position: i32) {
        if self.position == position {
            return;
        }
        // Playback moves it forward a tenth of a second at a time; anything else is a seek
        let jumped = position > self.position + 2000 || position < self.position - 500;
        self.as_mut().rust_mut().position = position;
        self.update(|s| s.position_ms = position);
        if jumped && self.loaded {
            self.announce_seek(position);
        }
        self.position_changed();
    }

    pub fn set_volume_level(mut self: Pin<&mut Self>, volume: f64) {
        if self.volume == volume {
            return;
        }
        self.as_mut().rust_mut().volume = volume;
        self.update(|s| s.volume = volume);
        self.announce(&[Changed::Volume]);
        self.volume_changed();
    }

    fn announce_seek(&self, position: i32) {
        let Some(connection) = self.connection.clone() else {
            return;
        };
        let _ = zbus::block_on(async move {
            let iface = connection.object_server().interface::<_, PlayerIface>(OBJECT_PATH).await?;
            PlayerIface::seeked(iface.signal_emitter(), position as i64 * 1000).await
        });
    }
}
