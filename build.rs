use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(
        QmlModule::new("org.imelodiae")
            .qml_file(QmlFile::from("qml/Theme.qml").singleton(true))
            .qml_files([
                "qml/main.qml",
                "qml/BrushedMetal.qml",
                "qml/AquaRoundButton.qml",
                "qml/AquaSquareButton.qml",
                "qml/AquaScrollBar.qml",
                "qml/GlyphIcon.qml",
                "qml/LcdDisplay.qml",
                "qml/VolumeSlider.qml",
                "qml/SearchField.qml",
                "qml/SourceList.qml",
                "qml/BrowserColumn.qml",
                "qml/TrackList.qml",
                "qml/ListHeader.qml",
                "qml/ArtworkPane.qml",
                "qml/OutputMenu.qml",
                "qml/LyricsPane.qml",
            ]),
    )
    .qt_module("Quick")
    .files(["src/player.rs", "src/library.rs", "src/lyrics.rs"])
    .build();
}
