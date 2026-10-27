//! Audio playback backed by a GStreamer `playbin`.
//!
//! `playbin` picks the right demuxer/decoder automatically, so FLAC (`flacdec`),
//! Apple Lossless in MP4/M4A (`qtdemux` + `avdec_alac`) and MP3 (`mpg123audiodec`)
//! all go through the same code path.
//!
//! The output device (USB DAC, Bluetooth speaker, ...) comes from a GStreamer
//! `DeviceMonitor` and can be switched mid-song.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;

        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
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
        /// Stable id (PipeWire/Pulse node name) of the chosen output; empty = system default
        #[qproperty(QString, output, READ, WRITE = set_output_device, NOTIFY)]
        #[qproperty(QStringList, output_ids, READ, NOTIFY)]
        #[qproperty(QStringList, output_names, READ, NOTIFY)]
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

        fn set_output_device(self: Pin<&mut Player>, output: QString);

        /// Re-scan the available audio outputs into outputIds / outputNames
        #[qinvokable]
        fn refresh_outputs(self: Pin<&mut Player>);

        /// The current track reached its end
        #[qsignal]
        fn finished(self: Pin<&mut Player>);

        #[qsignal]
        fn error_occurred(self: Pin<&mut Player>, message: QString);
    }
}

use core::pin::Pin;
use cxx_qt::CxxQtType;
use cxx_qt_lib::{QString, QStringList};
use gstreamer as gst;
use gstreamer::prelude::*;

pub struct PlayerRust {
    playing: bool,
    loaded: bool,
    position: i32,
    duration: i32,
    volume: f64,
    output: QString,
    output_ids: QStringList,
    output_names: QStringList,
    playbin: Option<gst::Element>,
    monitor: Option<gst::DeviceMonitor>,
    /// (id, display name, device) for every output found by the last scan
    devices: Vec<(String, String, gst::Device)>,
}

impl Default for PlayerRust {
    fn default() -> Self {
        Self {
            playing: false,
            loaded: false,
            position: 0,
            duration: 0,
            volume: 0.75,
            output: QString::default(),
            output_ids: QStringList::default(),
            output_names: QStringList::default(),
            playbin: None,
            monitor: None,
            devices: Vec::new(),
        }
    }
}

impl Drop for PlayerRust {
    fn drop(&mut self) {
        if let Some(playbin) = &self.playbin {
            let _ = playbin.set_state(gst::State::Null);
        }
        if let Some(monitor) = &self.monitor {
            monitor.stop();
        }
    }
}

/// Test override, e.g. IMELODIAE_AUDIO_SINK=fakesink for silent playback
fn sink_override() -> Option<gst::Element> {
    let name = std::env::var("IMELODIAE_AUDIO_SINK").ok()?;
    let sink = gst::ElementFactory::make(&name).build().ok()?;
    if sink.has_property("sync") {
        sink.set_property("sync", true);
    }
    Some(sink)
}

/// A stable identifier for a device that survives restarts and re-plugging
fn device_id(device: &gst::Device) -> String {
    device
        .properties()
        .and_then(|props| props.get::<String>("node.name").ok())
        .unwrap_or_else(|| device.display_name().to_string())
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
                    if let Some(sink) = sink_override().or_else(|| self.as_mut().output_sink()) {
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

    pub fn refresh_outputs(mut self: Pin<&mut Self>) {
        if self.monitor.is_none() {
            let monitor = gst::DeviceMonitor::new();
            monitor.add_filter(Some("Audio/Sink"), None);
            if let Err(err) = monitor.start() {
                eprintln!("iMelodiae: can't list audio outputs: {err}");
                return;
            }
            self.as_mut().rust_mut().monitor = Some(monitor);
        }
        let Some(monitor) = self.monitor.clone() else {
            return;
        };

        let mut devices: Vec<(String, String, gst::Device)> = Vec::new();
        for device in monitor.devices() {
            let id = device_id(&device);
            // Several providers (PipeWire, Pulse) can report the same node
            if !devices.iter().any(|(known, _, _)| *known == id) {
                devices.push((id, device.display_name().to_string(), device));
            }
        }
        devices.sort_by_key(|(_, name, _)| name.to_lowercase());

        let mut ids = QStringList::default();
        let mut names = QStringList::default();
        for (id, name, _) in &devices {
            ids.append(QString::from(id.as_str()));
            names.append(QString::from(name.as_str()));
        }
        let mut rust = self.as_mut().rust_mut();
        rust.devices = devices;
        rust.output_ids = ids;
        rust.output_names = names;
        self.as_mut().output_ids_changed();
        self.output_names_changed();
    }

    /// Sink element for the chosen output, or None to let playbin pick the system default
    fn output_sink(mut self: Pin<&mut Self>) -> Option<gst::Element> {
        let id = self.output.to_string();
        if id.is_empty() {
            return None;
        }
        if !self.devices.iter().any(|(known, _, _)| *known == id) {
            self.as_mut().refresh_outputs();
        }
        let device = self
            .devices
            .iter()
            .find(|(known, _, _)| *known == id)
            .map(|(_, _, device)| device.clone());

        // pulsesink is the most mature sink and addresses PipeWire nodes by name too
        if let Ok(sink) = gst::ElementFactory::make("pulsesink")
            .property("device", id.as_str())
            .build()
            && device.is_some()
        {
            return Some(sink);
        }
        match device.map(|d| d.create_element(None)) {
            Some(Ok(sink)) => Some(sink),
            _ => {
                self.error_occurred(QString::from(format!("Audio output \"{id}\" isn't available")));
                None
            }
        }
    }

    pub fn set_output_device(mut self: Pin<&mut Self>, output: QString) {
        if self.output == output {
            return;
        }
        self.as_mut().rust_mut().output = output;
        self.as_mut().output_changed();

        let Some(playbin) = self.playbin.clone() else {
            // The sink is chosen when the playbin is first created
            return;
        };
        if sink_override().is_some() {
            return;
        }

        // The sink can only be swapped while stopped: tear down, swap, and resume where we were
        let (loaded, was_playing, position) = (self.loaded, self.playing, self.position);
        let _ = playbin.set_state(gst::State::Null);
        let sink = self.as_mut().output_sink();
        playbin.set_property("audio-sink", sink.as_ref());
        if !loaded {
            return;
        }
        if playbin.set_state(gst::State::Paused).is_err() {
            self.error_occurred(QString::from("Couldn't switch audio output"));
            return;
        }
        // Wait for preroll so the seek lands
        let _ = playbin.state(gst::ClockTime::from_seconds(3));
        let _ = playbin.seek_simple(
            gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE,
            gst::ClockTime::from_mseconds(position.max(0) as u64),
        );
        if was_playing {
            let _ = playbin.set_state(gst::State::Playing);
        }
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
