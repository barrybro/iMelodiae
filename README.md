# iMelodiae

A music player for Linux that looks like a 2004-era jukebox: brushed metal, a
pale-green LCD, glossy Aqua buttons, a Genre/Artist/Album browser and blue-striped
song lists.

Built with **Rust**, **QML** (Qt 6 via [cxx-qt](https://github.com/KDAB/cxx-qt)) and **GStreamer**.

## Formats

Playback goes through a GStreamer `playbin`, so anything your GStreamer install can
decode will play. iMelodiae imports:

| Format | Extension | GStreamer plugin |
|---|---|---|
| FLAC | `.flac` | `flacdec` (gst-plugins-good) |
| Apple Lossless | `.m4a` | `qtdemux` + `avdec_alac` (gst-libav) |
| MP3 | `.mp3` | `mpg123audiodec` (gst-plugins-good) |

AAC `.m4a` files also import and play. The **Kind** column shows which codec a file uses.

## Building

Dependencies on Arch: `rust qt6-base qt6-declarative qt6-svg gstreamer gst-plugins-base gst-plugins-good gst-libav`

```sh
cargo run --release
```

On first launch with an empty library, iMelodiae imports your XDG Music folder (`~/Music`).
To add more music, click **+** in the bottom-left corner, press **Ctrl+O**, or drag a folder onto the window.

## Features

- **Source list:** Library, plus Recently Added, Top 25 Most Played and Recently Played smart playlists
- **Browser** (Browse button / Ctrl+B): Genre → Artist → Album columns
- **Search:** filters on title, artist, album and genre as you type (Ctrl+F)
- **Sorting:** click a column header; click again to reverse it. Drag a header's edge to resize the column.
- **LCD:** click the time to switch between remaining and total time, drag the diamond to seek, click the
  artist line to cycle through artist and album, and click the curved arrow (Ctrl+L) to jump to the playing song.
- **Shuffle and Repeat** (Off, All or One), plus a toggle for the artwork pane. Artwork comes from tags embedded in the file, or
  from `cover.jpg` / `folder.jpg` next to the file.
- **Play counts** are tracked and feed the smart playlists.

### Keyboard

| Key | Action |
|---|---|
| Space | Play / Pause |
| Ctrl+→ / Ctrl+← | Next / Previous |
| Ctrl+↑ / Ctrl+↓ | Volume |
| Enter, double-click | Play selected song |

## Files

- Library database: `~/.local/share/iMelodiae/library.json`
- Artwork cache: `~/.cache/iMelodiae/artwork/`
- Settings (window layout, volume, column widths): `~/.config/iMelodiae/iMelodiae.conf`

## Developer aids

- `IMELODIAE_AUDIO_SINK=fakesink` plays to a silent sink.
- `imelodiae --play --screenshot=out.png` starts playing the second song, saves a screenshot after 3 s, then quits.
  This also works headless with `QT_QPA_PLATFORM=offscreen`.

## Layout

```
src/main.rs      app startup
src/player.rs    Player QObject: GStreamer playbin wrapper
src/library.rs   LibraryModel: QAbstractListModel with browser/search/sort/smart playlists
src/scanner.rs   tag reading (lofty), Kind detection, artwork, library.json persistence
qml/             the UI; main.qml wires it together
```
