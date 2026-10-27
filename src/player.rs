//! Audio playback backed by a GStreamer `playbin`.
//!
//! `playbin` picks the right demuxer/decoder automatically, so FLAC (`flacdec`),
//! Apple Lossless in MP4/M4A (`qtdemux` + `avdec_alac`) and MP3 (`mpg123audiodec`)
//! all go through the same code path.

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
        #[qproperty(bool, playing)]
        #[qproperty(bool, loaded)]
        #[qproperty(i32, position)]
        #[qproperty(i32, duration)]
        #[qproperty(f64, volume, READ, WRITE = set_volume_level, NOTIFY)]
        type Player = super::PlayerRust;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        /// Load a file:// URI and start playing it
        #[qinvokable]
        fn play_uri(self: Pin<&mut Player>, uri: &QString);

        #[qinvokable]
        fn play(self: Pin<&mut Player>);

        #[qinvokable]
        fn pause(self: Pin<&mut Player>);

        #[qinvokable]
        fn toggle(self: Pin<&mut Player>);

        #[qinvokable]
        fn stop(self: Pin<&mut Player>);

        /// Seek to a position in milliseconds
        #[qinvokable]
        fn seek(self: Pin<&mut Player>, ms: i32);

        /// Refresh position/duration and drain the GStreamer bus. Called from a QML timer.
        #[qinvokable]
        fn poll(self: Pin<&mut Player>);

        fn set_volume_level(self: Pin<&mut Player>, volume: f64);

        /// The current track reached its end
        #[qsignal]
        fn finished(self: Pin<&mut Player>);

        #[qsignal]
        fn error_occurred(self: Pin<&mut Player>, message: QString);
    }
}

use core::pin::Pin;
use cxx_qt::CxxQtType;
use cxx_qt_lib::QString;
use gstreamer as gst;
use gstreamer::prelude::*;

pub struct PlayerRust {
    playing: bool,
    loaded: bool,
    position: i32,
    duration: i32,
    volume: f64,
    playbin: Option<gst::Element>,
}

impl Default for PlayerRust {
    fn default() -> Self {
        Self {
            playing: false,
            loaded: false,
            position: 0,
            duration: 0,
            volume: 0.75,
            playbin: None,
        }
    }
}

impl Drop for PlayerRust {
    fn drop(&mut self) {
        if let Some(playbin) = &self.playbin {
            let _ = playbin.set_state(gst::State::Null);
        }
    }
}

/// Perceptual (cubic) volume curve, like a real volume knob.
fn linear_volume(volume: f64) -> f64 {
    volume.clamp(0.0, 1.0).powi(3)
}

impl qobject::Player {
    fn playbin(mut self: Pin<&mut Self>) -> Option<gst::Element> {
        if self.playbin.is_none() {
            match gst::ElementFactory::make("playbin").build() {
                Ok(playbin) => {
                    // Audio only: no video sink for embedded cover art streams
                    playbin.set_property_from_str("flags", "audio+soft-volume");
                    playbin.set_property("volume", linear_volume(self.volume));
                    // e.g. IMELODIAE_AUDIO_SINK=fakesink for silent testing
                    if let Ok(name) = std::env::var("IMELODIAE_AUDIO_SINK")
                        && let Ok(sink) = gst::ElementFactory::make(&name).build()
                    {
                        if sink.has_property("sync") {
                            sink.set_property("sync", true);
                        }
                        playbin.set_property("audio-sink", &sink);
                    }
                    self.as_mut().rust_mut().playbin = Some(playbin);
                }
                Err(err) => {
                    self.as_mut()
                        .error_occurred(QString::from(format!("Cannot create playbin: {err}")));
                    return None;
                }
            }
        }
        self.playbin.clone()
    }

    fn set_state(mut self: Pin<&mut Self>, state: gst::State) -> bool {
        let Some(playbin) = self.as_mut().playbin() else {
            return false;
        };
        if let Err(err) = playbin.set_state(state) {
            self.error_occurred(QString::from(format!("Playback failed: {err}")));
            return false;
        }
        true
    }

    pub fn play_uri(mut self: Pin<&mut Self>, uri: &QString) {
        let Some(playbin) = self.as_mut().playbin() else {
            return;
        };
        let _ = playbin.set_state(gst::State::Null);
        playbin.set_property("uri", uri.to_string());
        self.as_mut().set_position(0);
        self.as_mut().set_duration(0);
        if self.as_mut().set_state(gst::State::Playing) {
            self.as_mut().set_loaded(true);
            self.as_mut().set_playing(true);
        }
    }

    pub fn play(mut self: Pin<&mut Self>) {
        if self.loaded && self.as_mut().set_state(gst::State::Playing) {
            self.set_playing(true);
        }
    }

    pub fn pause(mut self: Pin<&mut Self>) {
        if self.loaded && self.as_mut().set_state(gst::State::Paused) {
            self.set_playing(false);
        }
    }

    pub fn toggle(self: Pin<&mut Self>) {
        if self.playing {
            self.pause();
        } else {
            self.play();
        }
    }

    pub fn stop(mut self: Pin<&mut Self>) {
        if let Some(playbin) = &self.playbin {
            let _ = playbin.set_state(gst::State::Null);
        }
        self.as_mut().set_playing(false);
        self.as_mut().set_loaded(false);
        self.as_mut().set_position(0);
        self.set_duration(0);
    }

    pub fn seek(mut self: Pin<&mut Self>, ms: i32) {
        let Some(playbin) = &self.playbin else {
            return;
        };
        let target = gst::ClockTime::from_mseconds(ms.max(0) as u64);
        if playbin
            .seek_simple(gst::SeekFlags::FLUSH | gst::SeekFlags::KEY_UNIT, target)
            .is_ok()
        {
            self.as_mut().set_position(ms.max(0));
        }
    }

    pub fn set_volume_level(mut self: Pin<&mut Self>, volume: f64) {
        let volume = volume.clamp(0.0, 1.0);
        if (volume - self.volume).abs() < f64::EPSILON {
            return;
        }
        if let Some(playbin) = &self.playbin {
            playbin.set_property("volume", linear_volume(volume));
        }
        self.as_mut().rust_mut().volume = volume;
        self.volume_changed();
    }

    pub fn poll(mut self: Pin<&mut Self>) {
        let Some(playbin) = self.playbin.clone() else {
            return;
        };

        if self.loaded {
            if let Some(pos) = playbin.query_position::<gst::ClockTime>() {
                self.as_mut().set_position(pos.mseconds() as i32);
            }
            if let Some(dur) = playbin.query_duration::<gst::ClockTime>() {
                self.as_mut().set_duration(dur.mseconds() as i32);
            }
        }

        let Some(bus) = playbin.bus() else {
            return;
        };
        let mut finished = false;
        let mut error = None;
        while let Some(msg) =
            bus.pop_filtered(&[gst::MessageType::Eos, gst::MessageType::Error])
        {
            match msg.view() {
                gst::MessageView::Eos(_) => finished = true,
                gst::MessageView::Error(err) => {
                    error = Some(format!("{} ({:?})", err.error(), err.debug()));
                }
                _ => {}
            }
        }

        if finished || error.is_some() {
            let _ = playbin.set_state(gst::State::Null);
            self.as_mut().set_playing(false);
            self.as_mut().set_loaded(false);
        }
        if let Some(error) = error {
            self.as_mut().error_occurred(QString::from(error));
        }
        if finished {
            self.finished();
        }
    }
}
