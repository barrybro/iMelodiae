//! What the window manager is doing with our window.
//!
//! A tiling compositor decides the window's size, so resizing it from the app only makes
//! it flash at the wrong size until the compositor sizes it back. Qt doesn't say whether
//! a Wayland window is tiled, so ask Hyprland directly when that's what we're running on.

#[cxx_qt::bridge]
pub mod qobject {
    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        type Compositor = super::CompositorRust;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        /// True when the compositor sets our window's size (tiled or fullscreen), so the
        /// app shouldn't resize it. False when floating, or when it can't tell.
        #[qinvokable]
        fn manages_size(self: &Compositor) -> bool;
    }
}

use serde::Deserialize;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::time::Duration;

#[derive(Default)]
pub struct CompositorRust;

#[derive(Deserialize)]
struct HyprClient {
    pid: i64,
    floating: bool,
    #[serde(default)]
    fullscreen: i64,
}

impl qobject::Compositor {
    pub fn manages_size(&self) -> bool {
        hyprland_manages_size().unwrap_or(false)
    }
}

fn hyprland_manages_size() -> Option<bool> {
    let signature = std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE")?;
    let socket = PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR")?)
        .join("hypr")
        .join(signature)
        .join(".socket.sock");
    let mut stream = UnixStream::connect(socket).ok()?;
    stream.set_read_timeout(Some(Duration::from_millis(300))).ok()?;
    stream.write_all(b"j/clients").ok()?;
    let mut reply = String::new();
    stream.read_to_string(&mut reply).ok()?;

    let clients: Vec<HyprClient> = serde_json::from_str(&reply).ok()?;
    let pid = i64::from(std::process::id());
    let ours = clients.iter().find(|c| c.pid == pid)?;
    Some(!ours.floating || ours.fullscreen != 0)
}
