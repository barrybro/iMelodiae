import QtCore
import QtQuick
import QtQuick.Dialogs
import org.imelodiae

Window {
    id: window

    width: settings.windowWidth
    height: settings.windowHeight
    minimumWidth: 780
    minimumHeight: 460
    visible: true
    color: Theme.metalBottom
    title: player.loaded && nowPlaying.title ? nowPlaying.title + " — iMelodiae" : "iMelodiae"

    property int selectedId: -1
    property int playingId: -1
    property var nowPlaying: ({ title: "", artist: "", album: "" })
    property string lcdMessage: ""

    onWidthChanged: settings.windowWidth = width
    onHeightChanged: settings.windowHeight = height

    Settings {
        id: settings
        property int windowWidth: 1080
        property int windowHeight: 700
        property real volume: 0.75
        property bool browserVisible: true
        property bool artworkVisible: true
        property bool shuffle: false
        property int repeatMode: 0 // 0 off, 1 all, 2 one
        property int sourceWidth: 180
        property int browserHeight: 140
        property string columnWidths: "{}"
        property string audioOutput: "" // device node name; empty = system default
        property bool lyricsVisible: true
        property int lyricsWidth: 280
        onLyricsVisibleChanged: window.loadLyrics()
    }

    Player {
        id: player
        volume: settings.volume
        output: settings.audioOutput

        onFinished: {
            const finishedId = window.playingId
            trackList.preserveScroll = true
            library.markPlayed(finishedId)
            Qt.callLater(() => {
                if (settings.repeatMode === 2)
                    window.playId(finishedId)
                else
                    window.playId(library.nextId(finishedId, settings.shuffle, settings.repeatMode === 1))
            })
        }
        onErrorOccurred: message => window.flash(qsTr("Can't play this song: %1").arg(message))
    }

    Lyrics {
        id: songLyrics
    }

    LibraryModel {
        id: library
        onStatusChanged: window.flash(status)
        Component.onCompleted: Qt.callLater(() => library.importDefaultFolder())
    }

    Timer {
        // Fast enough for synced lyrics to land on the beat
        interval: 100
        repeat: true
        running: player.loaded
        onTriggered: player.poll()
    }

    Timer {
        id: messageTimer
        interval: 4000
        onTriggered: if (!library.scanning) window.lcdMessage = ""
    }

    function flash(message) {
        lcdMessage = message
        messageTimer.restart()
    }

    function playId(id) {
        if (id < 0) {
            player.stop()
            playingId = -1
            nowPlaying = { title: "", artist: "", album: "" }
            songLyrics.clear()
            return
        }
        playingId = id
        nowPlaying = JSON.parse(library.trackInfo(id))
        player.playUri(library.uriOf(id))
        loadLyrics()
    }

    // Only look lyrics up while the pane is showing, so hidden lyrics cost no network requests
    function loadLyrics() {
        if (playingId < 0)
            songLyrics.clear()
        else if (settings.lyricsVisible)
            songLyrics.load(nowPlaying.path ?? "", nowPlaying.title ?? "", nowPlaying.artist ?? "",
                        nowPlaying.album ?? "", nowPlaying.durationMs ?? 0)
    }

    function playPause() {
        if (player.loaded) {
            player.toggle()
        } else if (selectedId >= 0) {
            playId(selectedId)
        } else if (library.count > 0) {
            playId(library.nextId(-1, settings.shuffle, false))
        }
    }

    function next() {
        if (playingId >= 0)
            playId(library.nextId(playingId, settings.shuffle, settings.repeatMode !== 0))
    }

    function previous() {
        if (playingId < 0)
            return
        if (player.position > 3000)
            player.seek(0)
        else
            playId(library.previousId(playingId))
    }

    function snapback() {
        if (playingId < 0)
            return
        if (library.rowOfId(playingId) < 0) {
            library.search = ""
            library.source = 0
            library.genre = ""
        }
        selectedId = playingId
        trackList.reveal(playingId)
    }

    BrushedMetal {
        anchors.fill: parent
    }

    // ── Toolbar ──────────────────────────────────────────────────────────
    Item {
        id: toolbar
        anchors.left: parent.left
        anchors.right: parent.right
        height: 76

        Column {
            x: 14
            y: 8
            spacing: 6

            Row {
                id: transport
                spacing: 3
                AquaRoundButton {
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: 31
                    glyph: "prev"
                    glyphScale: 0.46
                    onClicked: window.previous()
                }
                AquaRoundButton {
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: 38
                    glyph: player.playing ? "pause" : "play"
                    onClicked: window.playPause()
                }
                AquaRoundButton {
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: 31
                    glyph: "next"
                    glyphScale: 0.46
                    onClicked: window.next()
                }
            }

            VolumeSlider {
                width: transport.width
                value: settings.volume
                onMoved: value => settings.volume = value
            }
        }

        LcdDisplay {
            id: lcd
            width: Math.min(480, window.width - 2 * 250)
            height: 56
            x: (window.width - width) / 2
            y: 9
            title: window.nowPlaying.title ?? ""
            artist: window.nowPlaying.artist ?? ""
            album: window.nowPlaying.album ?? ""
            position: player.position
            duration: player.duration
            loaded: player.loaded
            message: window.lcdMessage
            onSeekRequested: ms => player.seek(ms)
            onSnapbackClicked: window.snapback()
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 12
            spacing: 12

            SearchField {
                id: search
                width: Math.max(110, Math.min(170, window.width - lcd.x - lcd.width - 90))
                onTextChanged: library.search = text
            }

            AquaRoundButton {
                diameter: 25
                glyph: "eye"
                glyphScale: 0.56
                label: qsTr("Browse")
                checked: settings.browserVisible
                onClicked: settings.browserVisible = !settings.browserVisible
            }
        }
    }

    // ── Panes ────────────────────────────────────────────────────────────
    Item {
        id: panes
        anchors.top: toolbar.bottom
        anchors.bottom: bottomBar.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 9
        anchors.rightMargin: 9

        // Left column: Source list + artwork
        Rectangle {
            id: leftPane
            width: Math.max(130, Math.min(340, settings.sourceWidth))
            height: parent.height
            color: Theme.frame

            SourceList {
                anchors.fill: parent
                anchors.margins: 1
                anchors.bottomMargin: artwork.visible ? artwork.height + 2 : 1
                current: library.source
                onPicked: source => library.source = source
            }

            ArtworkPane {
                id: artwork
                visible: settings.artworkVisible
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 1
                height: width + 17
                property bool nowPlayingMode: true
                showingNowPlaying: nowPlayingMode || window.selectedId < 0
                source: {
                    const id = showingNowPlaying ? window.playingId : window.selectedId
                    return id >= 0 && visible ? library.artworkUrl(id) : ""
                }
                onToggleMode: nowPlayingMode = !nowPlayingMode
            }
        }

        // Splitter between the source list and the song list
        MouseArea {
            id: splitter
            anchors.left: leftPane.right
            width: 7
            height: parent.height
            cursorShape: Qt.SplitHCursor
            onPositionChanged: mouse => {
                if (pressed)
                    settings.sourceWidth = Math.max(130, Math.min(340, leftPane.width + mouse.x - 3))
            }
        }

        Item {
            id: rightPane
            anchors.left: splitter.right
            anchors.right: lyricsPane.visible ? lyricsSplitter.left : parent.right
            height: parent.height

            Rectangle {
                id: browser
                visible: settings.browserVisible
                width: parent.width
                height: Math.max(80, Math.min(rightPane.height - 120, settings.browserHeight))
                color: Theme.frame

                Row {
                    anchors.fill: parent
                    anchors.margins: 1
                    spacing: 1
                    readonly property real columnWidth: (width - 2) / 3

                    BrowserColumn {
                        width: parent.columnWidth
                        height: parent.height
                        title: qsTr("Genre")
                        pluralNoun: qsTr("Genres")
                        items: library.genres
                        selected: library.genre
                        onPicked: value => library.genre = value
                    }
                    BrowserColumn {
                        width: parent.columnWidth
                        height: parent.height
                        title: qsTr("Artist")
                        pluralNoun: qsTr("Artists")
                        items: library.artists
                        selected: library.artist
                        onPicked: value => library.artist = value
                    }
                    BrowserColumn {
                        width: parent.columnWidth
                        height: parent.height
                        title: qsTr("Album")
                        pluralNoun: qsTr("Albums")
                        items: library.albums
                        selected: library.album
                        onPicked: value => library.album = value
                    }
                }
            }

            MouseArea {
                id: browserSplitter
                visible: browser.visible
                anchors.top: browser.bottom
                width: parent.width
                height: 7
                cursorShape: Qt.SplitVCursor
                onPositionChanged: mouse => {
                    if (pressed)
                        settings.browserHeight = Math.max(80, Math.min(rightPane.height - 120, browser.height + mouse.y - 3))
                }
            }

            Rectangle {
                anchors.top: browser.visible ? browserSplitter.bottom : parent.top
                anchors.bottom: parent.bottom
                width: parent.width
                color: Theme.frame

                TrackList {
                    id: trackList
                    anchors.fill: parent
                    anchors.margins: 1
                    tracks: library
                    selectedId: window.selectedId
                    playingId: window.playingId
                    playing: player.playing
                    widths: JSON.parse(settings.columnWidths)
                    onSelected: id => window.selectedId = id
                    onActivated: id => window.playId(id)
                    onWidthsEdited: widths => settings.columnWidths = JSON.stringify(widths)
                }
            }
        }

        MouseArea {
            id: lyricsSplitter
            visible: lyricsPane.visible
            anchors.right: lyricsPane.left
            width: 7
            height: parent.height
            cursorShape: Qt.SplitHCursor
            onPositionChanged: mouse => {
                if (pressed)
                    settings.lyricsWidth = Math.max(200, Math.min(480, lyricsPane.width - mouse.x + 3))
            }
        }

        Rectangle {
            id: lyricsPane
            visible: settings.lyricsVisible
            anchors.right: parent.right
            width: Math.max(200, Math.min(480, settings.lyricsWidth))
            height: parent.height
            color: Theme.frame

            LyricsPane {
                anchors.fill: parent
                anchors.margins: 1
                lyrics: songLyrics
                active: window.playingId >= 0
                title: window.nowPlaying.title ?? ""
                artist: window.nowPlaying.artist ?? ""
                artworkSource: visible && window.playingId >= 0 ? library.artworkUrl(window.playingId) : ""
                position: player.position
                onSeekRequested: ms => player.seek(ms)
            }
        }
    }

    // ── Bottom bar ───────────────────────────────────────────────────────
    Item {
        id: bottomBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 40

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            AquaSquareButton {
                glyph: "plus"
                tooltip: qsTr("Add Folder to Library")
                onClicked: folderDialog.open()
            }
            AquaSquareButton {
                glyph: "shuffle"
                tooltip: qsTr("Shuffle")
                checked: settings.shuffle
                onClicked: settings.shuffle = !settings.shuffle
            }
            AquaSquareButton {
                glyph: settings.repeatMode === 2 ? "repeatOne" : "repeat"
                tooltip: [qsTr("Repeat Off"), qsTr("Repeat All"), qsTr("Repeat One")][settings.repeatMode]
                checked: settings.repeatMode !== 0
                onClicked: settings.repeatMode = (settings.repeatMode + 1) % 3
            }
            AquaSquareButton {
                glyph: "artwork"
                tooltip: qsTr("Show or Hide Song Artwork")
                checked: settings.artworkVisible
                onClicked: settings.artworkVisible = !settings.artworkVisible
            }
        }

        Text {
            anchors.centerIn: parent
            text: library.scanning ? library.status : library.summary
            font.family: Theme.font
            font.pixelSize: Theme.listFontSize
            color: Theme.engravedText
            style: Text.Raised
            styleColor: Theme.engravedHighlight
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            AquaSquareButton {
                id: outputButton
                glyph: "output"
                tooltip: qsTr("Audio Output: %1").arg(outputMenu.currentName)
                checked: outputMenu.opened
                onClicked: outputMenu.toggle()
            }
            AquaSquareButton {
                glyph: "lyrics"
                tooltip: qsTr("Show or Hide Lyrics")
                checked: settings.lyricsVisible
                onClicked: settings.lyricsVisible = !settings.lyricsVisible
            }
        }
    }

    OutputMenu {
        id: outputMenu
        player: player
        // Pop up above the button, right-aligned with it
        parent: outputButton
        x: outputButton.width - width
        y: -height - 6
        onPicked: (id, name) => {
            settings.audioOutput = id
            window.flash(qsTr("Playing through %1").arg(name))
        }
    }

    FolderDialog {
        id: folderDialog
        title: qsTr("Add Folder to Library")
        currentFolder: StandardPaths.writableLocation(StandardPaths.MusicLocation)
        onAccepted: library.addFolder(selectedFolder.toString())
    }

    DropArea {
        anchors.fill: parent
        onDropped: drop => {
            for (const url of drop.urls)
                library.addFolder(url.toString())
        }
    }

    // ── Keyboard ─────────────────────────────────────────────────────────
    Shortcut {
        sequence: "Space"
        enabled: !search.field.activeFocus
        onActivated: window.playPause()
    }
    Shortcut { sequence: "Ctrl+Right"; onActivated: window.next() }
    Shortcut { sequence: "Ctrl+Left"; onActivated: window.previous() }
    Shortcut { sequence: "Ctrl+Up"; onActivated: settings.volume = Math.min(1, settings.volume + 0.1) }
    Shortcut { sequence: "Ctrl+Down"; onActivated: settings.volume = Math.max(0, settings.volume - 0.1) }
    Shortcut { sequences: [StandardKey.Find]; onActivated: search.field.forceActiveFocus() }
    Shortcut { sequences: [StandardKey.Open]; onActivated: folderDialog.open() }
    Shortcut { sequence: "Ctrl+B"; onActivated: settings.browserVisible = !settings.browserVisible }
    Shortcut { sequence: "Ctrl+L"; onActivated: window.snapback() }
    Shortcut { sequences: [StandardKey.Quit]; onActivated: Qt.quit() }

    // Developer aid: `imelodiae --play --screenshot=out.png` renders the window and quits
    Timer {
        id: screenshotTimer
        property string path: ""
        interval: 3000
        // Grab the root item so pop-ups in the overlay layer are included
        onTriggered: (window.contentItem.parent ?? window.contentItem).grabToImage(result => {
            result.saveToFile(path)
            Qt.quit()
        })
    }

    Component.onCompleted: {
        trackList.focusList()
        for (const arg of Qt.application.arguments) {
            if (arg.startsWith("--screenshot=")) {
                screenshotTimer.path = arg.substring(13)
                screenshotTimer.start()
            } else if (arg === "--play") {
                Qt.callLater(() => Qt.callLater(() => {
                    window.selectedId = library.idAt(1)
                    window.playPause()
                }))
            }
        }
    }
}
