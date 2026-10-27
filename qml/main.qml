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
    color: Theme.toolbarBottom
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

    // ── Toolbar ──────────────────────────────────────────────────────────
    // iTunes 5's unified title bar + toolbar: one smooth grey gradient
    Rectangle {
        id: toolbar
        anchors.left: parent.left
        anchors.right: parent.right
        height: 84
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.toolbarTop }
            GradientStop { position: 0.1; color: Theme.toolbarUpper }
            GradientStop { position: 1.0; color: Theme.toolbarBottom }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(1, 1, 1, 0.6)
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.divider
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 4
            text: "iMelodiae"
            font.family: Theme.font
            font.pixelSize: 13
            color: "#1a1a1a"
            style: Text.Raised
            styleColor: "#dcdcdc"
        }

        Row {
            id: transport
            x: 26
            y: 31
            spacing: 2

            AquaRoundButton {
                anchors.verticalCenter: parent.verticalCenter
                diameter: 33
                glyph: "prev"
                glyphScale: 0.44
                onClicked: window.previous()
            }
            AquaRoundButton {
                anchors.verticalCenter: parent.verticalCenter
                diameter: 40
                glyph: player.playing ? "pause" : "play"
                glyphScale: 0.4
                onClicked: window.playPause()
            }
            AquaRoundButton {
                anchors.verticalCenter: parent.verticalCenter
                diameter: 33
                glyph: "next"
                glyphScale: 0.44
                onClicked: window.next()
            }
        }

        VolumeSlider {
            anchors.left: transport.right
            anchors.leftMargin: 18
            anchors.verticalCenter: transport.verticalCenter
            width: 108
            value: settings.volume
            onMoved: value => settings.volume = value
        }

        LcdDisplay {
            id: lcd
            width: Math.min(410, window.width - 2 * 290)
            height: 48
            x: (window.width - width) / 2
            y: 27
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

        SearchField {
            id: search
            anchors.right: browseButton.left
            anchors.rightMargin: 18
            y: 32
            width: Math.max(100, Math.min(140, window.width - lcd.x - lcd.width - 110))
            onTextChanged: library.search = text
        }

        AquaRoundButton {
            id: browseButton
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: 26
            diameter: 32
            glyph: "colorEye"
            glyphScale: 0.62
            label: qsTr("Browse")
            checked: settings.browserVisible
            onClicked: settings.browserVisible = !settings.browserVisible
        }
    }

    // A one-pixel dark divider with a wider invisible handle for dragging
    component Divider: Rectangle {
        id: divider
        property bool vertical: true
        property alias pressed: handle.pressed
        signal dragged(real delta)
        color: Theme.divider
        width: vertical ? 1 : parent.width
        height: vertical ? parent.height : 1
        z: 5
        MouseArea {
            id: handle
            anchors.centerIn: parent
            width: divider.vertical ? 7 : parent.width
            height: divider.vertical ? parent.height : 7
            cursorShape: divider.vertical ? Qt.SplitHCursor : Qt.SplitVCursor
            property real start
            onPressed: mouse => start = divider.vertical ? mouse.x : mouse.y
            onPositionChanged: mouse => divider.dragged((divider.vertical ? mouse.x : mouse.y) - start)
        }
    }

    // ── Panes ────────────────────────────────────────────────────────────
    Item {
        id: panes
        anchors.top: toolbar.bottom
        anchors.bottom: bottomBar.top
        anchors.left: parent.left
        anchors.right: parent.right

        // Left column: Source list + artwork
        Item {
            id: leftPane
            width: Math.max(130, Math.min(340, settings.sourceWidth))
            height: parent.height

            SourceList {
                anchors.fill: parent
                anchors.bottomMargin: artwork.visible ? artwork.height + 1 : 0
                current: library.source
                onPicked: source => library.source = source
            }

            Rectangle {
                visible: artwork.visible
                anchors.bottom: artwork.top
                width: parent.width
                height: 1
                color: Theme.divider
            }

            ArtworkPane {
                id: artwork
                visible: settings.artworkVisible
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
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

        Divider {
            id: splitter
            anchors.left: leftPane.right
            onDragged: delta => settings.sourceWidth = Math.max(130, Math.min(340, leftPane.width + delta))
        }

        Item {
            id: rightPane
            anchors.left: splitter.right
            anchors.right: lyricsPane.visible ? lyricsSplitter.left : parent.right
            height: parent.height

            Row {
                id: browser
                visible: settings.browserVisible
                width: parent.width
                height: Math.max(80, Math.min(rightPane.height - 120, settings.browserHeight))
                readonly property real columnWidth: (width - 2) / 3

                BrowserColumn {
                    width: browser.columnWidth
                    height: parent.height
                    title: qsTr("Genre")
                    pluralNoun: qsTr("Genres")
                    items: library.genres
                    selected: library.genre
                    onPicked: value => library.genre = value
                }
                Rectangle { width: 1; height: parent.height; color: Theme.headerLine }
                BrowserColumn {
                    width: browser.columnWidth
                    height: parent.height
                    title: qsTr("Artist")
                    pluralNoun: qsTr("Artists")
                    items: library.artists
                    selected: library.artist
                    onPicked: value => library.artist = value
                }
                Rectangle { width: 1; height: parent.height; color: Theme.headerLine }
                BrowserColumn {
                    width: browser.columnWidth
                    height: parent.height
                    title: qsTr("Album")
                    pluralNoun: qsTr("Albums")
                    items: library.albums
                    selected: library.album
                    onPicked: value => library.album = value
                }
            }

            Divider {
                id: browserSplitter
                vertical: false
                visible: browser.visible
                anchors.top: browser.bottom
                onDragged: delta => settings.browserHeight = Math.max(80, Math.min(rightPane.height - 120, browser.height + delta))
            }

            TrackList {
                id: trackList
                anchors.top: browser.visible ? browserSplitter.bottom : parent.top
                anchors.bottom: parent.bottom
                width: parent.width
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

        Divider {
            id: lyricsSplitter
            visible: lyricsPane.visible
            anchors.right: lyricsPane.left
            onDragged: delta => settings.lyricsWidth = Math.max(200, Math.min(480, lyricsPane.width - delta))
        }

        LyricsPane {
            id: lyricsPane
            visible: settings.lyricsVisible
            anchors.right: parent.right
            width: Math.max(200, Math.min(480, settings.lyricsWidth))
            height: parent.height
            lyrics: songLyrics
            active: window.playingId >= 0
            title: window.nowPlaying.title ?? ""
            artist: window.nowPlaying.artist ?? ""
            artworkSource: visible && window.playingId >= 0 ? library.artworkUrl(window.playingId) : ""
            position: player.position
            onSeekRequested: ms => player.seek(ms)
        }
    }

    // ── Bottom bar ───────────────────────────────────────────────────────
    Rectangle {
        id: bottomBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 42
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.barTop }
            GradientStop { position: 1.0; color: Theme.barBottom }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.divider
        }
        Rectangle {
            y: 1
            width: parent.width
            height: 1
            color: Qt.rgba(1, 1, 1, 0.35)
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 17
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

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
            anchors.rightMargin: 17
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

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
