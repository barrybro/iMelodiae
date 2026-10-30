import QtQuick
import org.imelodiae

// Mini player drawn as a white click-wheel iPod (2005). Browsing sets the library's
// source and Genre/Artist/Album filters, so the songs you pick here play in the same
// order they would from the browser. Scales to fit whatever space it's given.
Item {
    id: root

    property var library
    property var player
    property int playingId: -1
    property var nowPlaying: ({})
    property string artworkSource: ""
    property bool shuffle: false
    property int repeatMode: 0
    property real volume: 0.75

    signal playRequested(int id)
    signal playPauseRequested()
    signal nextRequested()
    signal previousRequested()
    signal shuffleEdited(bool shuffle)
    signal repeatEdited(int mode)
    signal volumeEdited(real volume)
    signal exitRequested()

    // Natural size of the device; everything inside is laid out in these units
    readonly property real bodyWidth: 250
    readonly property real bodyHeight: 418

    // Menu levels, root first. Browsing levels remember the filters that produce them.
    property var stack: [{ kind: "main", title: "iMelodiae" }]
    readonly property var level: stack[stack.length - 1]
    readonly property bool showingNowPlaying: level.kind === "nowPlaying"
    readonly property bool showingSongs: level.kind === "songs"

    // Now Playing: the wheel changes volume, or scrubs after a centre click
    property bool scrubbing: false
    property bool volumeShown: false

    // Highlighted menu row. Kept here rather than in the ListView, whose currentIndex
    // resets whenever its model does (e.g. when a play count changes)
    property int selected: 0
    onSelectedChanged: menu.reveal()

    function formatTime(ms) {
        const s = Math.max(0, Math.floor(ms / 1000))
        const h = Math.floor(s / 3600)
        const m = Math.floor(s / 60) % 60
        const sec = s % 60
        const pad = n => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec)
    }

    function menuItems(l) {
        const sub = (label, next) => ({ label: label, next: next })
        switch (l.kind) {
        case "main": {
            const items = [
                sub(qsTr("Music"), { kind: "music", title: qsTr("Music") }),
                sub(qsTr("Playlists"), { kind: "playlists", title: qsTr("Playlists") }),
                { label: qsTr("Shuffle Songs"), action: "shuffleSongs" },
                sub(qsTr("Settings"), { kind: "settings", title: qsTr("Settings") }),
                { label: qsTr("Full Player"), action: "exit" }
            ]
            if (root.playingId >= 0)
                items.push({ label: qsTr("Now Playing"), action: "nowPlaying", chevron: true })
            return items
        }
        case "music":
            return [
                sub(qsTr("Artists"), { kind: "artists", title: qsTr("Artists") }),
                sub(qsTr("Albums"), { kind: "albums", title: qsTr("Albums") }),
                sub(qsTr("Songs"), { kind: "songs", title: qsTr("Songs") }),
                sub(qsTr("Genres"), { kind: "genres", title: qsTr("Genres") })
            ]
        case "playlists":
            return [
                sub(qsTr("Recently Added"), { kind: "songs", title: qsTr("Recently Added"), source: 1 }),
                sub(qsTr("Top 25 Most Played"), { kind: "songs", title: qsTr("Top 25"), source: 2 }),
                sub(qsTr("Recently Played"), { kind: "songs", title: qsTr("Recently Played"), source: 3 })
            ]
        case "genres":
            return root.library.genres.map(g => sub(g, { kind: "artists", title: g, genre: g }))
        case "artists":
            return root.library.artists.map(a => sub(a, { kind: "albums", title: a, genre: l.genre, artist: a }))
        case "albums":
            return [sub(qsTr("All"), { kind: "songs", title: l.artist ?? qsTr("Songs"), genre: l.genre, artist: l.artist })]
                .concat(root.library.albums.map(a => sub(a, {
                    kind: "songs", title: a, genre: l.genre, artist: l.artist, album: a
                })))
        case "settings":
            return [
                { label: qsTr("Shuffle"), action: "shuffle", value: root.shuffle ? qsTr("Songs") : qsTr("Off") },
                {
                    label: qsTr("Repeat"), action: "repeat",
                    value: [qsTr("Off"), qsTr("All"), qsTr("One")][root.repeatMode]
                }
            ]
        }
        return []
    }

    // Narrow the library to what a level lists (no-op for plain menus)
    function applyFilters(l) {
        if (!["genres", "artists", "albums", "songs"].includes(l.kind))
            return
        root.library.source = l.source ?? 0
        root.library.genre = l.genre ?? ""
        root.library.artist = l.artist ?? ""
        root.library.album = l.album ?? ""
    }

    function push(l) {
        const s = stack.slice()
        s[s.length - 1] = Object.assign({}, level, { index: selected })
        s.push(l)
        applyFilters(l)
        stack = s
        selected = 0
        slide.from = screen.width
        slide.restart()
    }

    function pop() {
        if (stack.length < 2)
            return
        const s = stack.slice(0, -1)
        // Browsing levels below a Now Playing screen keep the filters that started the song
        if (!showingNowPlaying)
            applyFilters(s[s.length - 1])
        stack = s
        selected = level.index ?? 0
        menu.positionViewAtIndex(selected, ListView.Center)
        slide.from = -screen.width
        slide.restart()
    }

    function showNowPlaying() {
        if (!showingNowPlaying && playingId >= 0)
            push({ kind: "nowPlaying", title: qsTr("Now Playing") })
    }

    function select() {
        if (showingNowPlaying) {
            scrubbing = !scrubbing
            volumeShown = false
            idle.restart()
            return
        }
        if (showingSongs) {
            const id = library.idAt(selected)
            if (id >= 0) {
                playRequested(id)
                showNowPlaying()
            }
            return
        }
        const item = menuItems(level)[selected]
        if (!item)
            return
        if (item.next) {
            push(item.next)
        } else if (item.action === "shuffleSongs") {
            applyFilters({ kind: "songs" })
            shuffleEdited(true)
            playRequested(library.nextId(-1, true, false))
            showNowPlaying()
        } else if (item.action === "nowPlaying") {
            showNowPlaying()
        } else if (item.action === "shuffle") {
            shuffleEdited(!shuffle)
        } else if (item.action === "repeat") {
            repeatEdited((repeatMode + 1) % 3)
        } else if (item.action === "exit") {
            exitRequested()
        }
    }

    // One click of the wheel: +1 clockwise / down
    function tick(step) {
        if (showingNowPlaying) {
            if (scrubbing) {
                player.seek(Math.max(0, Math.min(player.duration - 1000, player.position + step * 5000)))
            } else {
                volumeShown = true
                volumeEdited(Math.max(0, Math.min(1, volume + step * 0.04)))
            }
            idle.restart()
        } else if (menu.count > 0) {
            selected = Math.max(0, Math.min(menu.count - 1, selected + step))
        }
    }

    // Leaving a song list for good returns from it like the Menu button would
    onPlayingIdChanged: if (playingId < 0 && showingNowPlaying) pop()

    Timer {
        id: idle
        interval: 2500
        onTriggered: {
            root.volumeShown = false
            root.scrubbing = false
        }
    }

    focus: true
    Keys.onUpPressed: tick(-1)
    Keys.onDownPressed: tick(1)
    Keys.onReturnPressed: select()
    Keys.onEnterPressed: select()
    Keys.onRightPressed: select()
    Keys.onLeftPressed: pop()
    Keys.onEscapePressed: pop()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Backspace) {
            pop()
            event.accepted = true
        }
    }

    WheelHandler {
        property real accumulated: 0
        onWheel: event => {
            accumulated += event.angleDelta.y
            while (accumulated >= 60) { root.tick(-1); accumulated -= 60 }
            while (accumulated <= -60) { root.tick(1); accumulated += 60 }
        }
    }

    // ── Device ───────────────────────────────────────────────────────────
    Item {
        id: device
        anchors.centerIn: parent
        width: root.bodyWidth
        height: root.bodyHeight
        scale: Math.min(root.width / width, root.height / height) * 0.92

        // Soft shadow on the desk
        Repeater {
            model: 4
            Rectangle {
                required property int index
                anchors.fill: parent
                anchors.margins: -index
                anchors.topMargin: 3 - index
                anchors.bottomMargin: -3 - index * 2
                radius: body.radius + index
                color: Qt.rgba(0, 0, 0, 0.09 - index * 0.02)
            }
        }

        Rectangle {
            id: body
            anchors.fill: parent
            radius: 26
            border.color: "#c4c4c6"
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#ffffff" }
                GradientStop { position: 0.5; color: "#f7f7f8" }
                GradientStop { position: 1.0; color: "#e6e6e8" }
            }

            // Polished-plastic sheen across the top
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                anchors.bottomMargin: parent.height * 0.45
                radius: body.radius - 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.9) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                }
            }
        }

        // Screen bezel
        Rectangle {
            id: bezel
            x: 18
            y: 20
            width: 214
            height: 162
            radius: 5
            color: "#1d1d1f"
            border.color: "#8e8e93"

            Rectangle {
                id: screen
                anchors.centerIn: parent
                width: 208
                height: 156
                color: "white"
                clip: true

                // ── Title bar ──
                Rectangle {
                    id: titleBar
                    width: parent.width
                    height: 19
                    z: 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#ffffff" }
                        GradientStop { position: 1.0; color: "#cfd3d8" }
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: "#8f949b"
                    }

                    GlyphIcon {
                        x: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        visible: root.playingId >= 0
                        kind: root.player.playing ? "play" : "pause"
                        color: "#2a62d4"
                        engraved: false
                    }

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 52
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.level.title
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.bold: true
                        color: "#000000"
                    }

                    // Battery, charging
                    Item {
                        anchors.right: parent.right
                        anchors.rightMargin: 5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 19
                        height: 9
                        Rectangle {
                            width: 17
                            height: 9
                            radius: 1.5
                            color: "#ffffff"
                            border.color: "#5b5f66"
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: 0.5
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#b6f08c" }
                                    GradientStop { position: 1.0; color: "#3eaa20" }
                                }
                            }
                        }
                        Rectangle {
                            x: 17
                            y: 2.5
                            width: 2
                            height: 4
                            color: "#5b5f66"
                        }
                    }
                }

                // ── Pages ──
                Item {
                    id: page
                    anchors.top: titleBar.bottom
                    width: parent.width
                    height: parent.height - titleBar.height

                    NumberAnimation on x {
                        id: slide
                        to: 0
                        duration: 180
                        easing.type: Easing.OutCubic
                    }

                    ListView {
                        id: menu
                        anchors.fill: parent
                        anchors.rightMargin: scrollTrack.visible ? scrollTrack.width : 0
                        visible: !root.showingNowPlaying
                        interactive: false
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.showingSongs ? root.library : root.menuItems(root.level)
                        onCountChanged: reveal()
                        onModelChanged: reveal()

                        function reveal() {
                            if (count > 0)
                                positionViewAtIndex(Math.min(root.selected, count - 1), ListView.Contain)
                        }

                        delegate: Item {
                            id: row
                            required property int index
                            required property var model
                            readonly property bool isCurrent: index === Math.min(root.selected, ListView.view.count - 1)
                            readonly property var item: root.showingSongs ? null : model.modelData
                            width: ListView.view.width
                            // Exactly seven rows to a screen, so none is ever cut in half
                            height: ListView.view.height / 7

                            Rectangle {
                                anchors.fill: parent
                                visible: row.isCurrent
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#8bbcf6" }
                                    GradientStop { position: 0.5; color: "#5a98ec" }
                                    GradientStop { position: 1.0; color: "#3a78db" }
                                }
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                anchors.right: value.left
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: (row.item ? row.item.label : row.model.title) || qsTr("Unknown")
                                font.family: Theme.font
                                font.pixelSize: 12
                                font.bold: true
                                color: row.isCurrent ? "#ffffff" : "#000000"
                            }

                            Text {
                                id: value
                                anchors.right: chevron.visible ? chevron.left : parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.item?.value ?? ""
                                font.family: Theme.font
                                font.pixelSize: 12
                                color: row.isCurrent ? "#ffffff" : "#5e6268"
                            }

                            GlyphIcon {
                                id: chevron
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: visible ? 7 : 0
                                height: 9
                                visible: !!(row.item?.next || row.item?.chevron)
                                kind: "chevron"
                                color: row.isCurrent ? "#ffffff" : "#5e6268"
                                engraved: false
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: menu.visible && menu.count === 0
                        text: qsTr("No Songs")
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.bold: true
                        color: "#8a8d92"
                    }

                    // iPod-style scroll bar, only when the list overflows
                    Rectangle {
                        id: scrollTrack
                        anchors.right: parent.right
                        width: 7
                        height: parent.height
                        visible: menu.visible && menu.contentHeight > menu.height
                        color: "#e9ebee"
                        border.color: "#a7abb1"

                        Rectangle {
                            x: 1
                            width: parent.width - 2
                            readonly property real fraction: menu.height / Math.max(1, menu.contentHeight)
                            height: Math.max(8, parent.height * fraction)
                            y: (parent.height - height) * (menu.contentY - menu.originY)
                               / Math.max(1, menu.contentHeight - menu.height)
                            radius: 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#8bbcf6" }
                                GradientStop { position: 1.0; color: "#3a78db" }
                            }
                        }
                    }

                    // ── Now Playing ──
                    Item {
                        id: nowPlayingPage
                        anchors.fill: parent
                        visible: root.showingNowPlaying

                        Text {
                            x: 6
                            y: 3
                            text: {
                                const row = root.library.rowOfId(root.playingId)
                                return row >= 0 ? qsTr("%1 of %2").arg(row + 1).arg(root.library.count) : ""
                            }
                            font.family: Theme.font
                            font.pixelSize: 10
                            color: "#3c3f44"
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            y: 4
                            spacing: 4
                            GlyphIcon {
                                visible: root.shuffle
                                width: 11
                                height: 10
                                kind: "shuffle"
                                color: "#3c3f44"
                                engraved: false
                            }
                            GlyphIcon {
                                visible: root.repeatMode !== 0
                                width: 11
                                height: 10
                                kind: root.repeatMode === 2 ? "repeatOne" : "repeat"
                                color: "#3c3f44"
                                engraved: false
                            }
                        }

                        Rectangle {
                            id: artFrame
                            x: 8
                            y: 19
                            width: 70
                            height: 70
                            color: "#e4e6ea"
                            border.color: "#b4b8be"

                            Image {
                                id: art
                                anchors.fill: parent
                                anchors.margins: 1
                                source: root.artworkSource
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                                mipmap: true
                                sourceSize.width: 256
                                sourceSize.height: 256
                            }
                            GlyphIcon {
                                anchors.centerIn: parent
                                visible: art.status !== Image.Ready
                                width: 30
                                height: 30
                                kind: "note"
                                color: "#a3a8b0"
                                engraved: false
                            }
                        }

                        Column {
                            anchors.left: artFrame.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: artFrame.verticalCenter
                            spacing: 3

                            Text {
                                width: parent.width
                                text: root.nowPlaying.title ?? ""
                                elide: Text.ElideRight
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                font.family: Theme.font
                                font.pixelSize: 12
                                font.bold: true
                                color: "#000000"
                            }
                            Text {
                                width: parent.width
                                text: root.nowPlaying.artist ?? ""
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: "#26292d"
                            }
                            Text {
                                width: parent.width
                                text: root.nowPlaying.album ?? ""
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: "#26292d"
                            }
                        }

                        // Progress (or scrub position, or volume)
                        Item {
                            id: meter
                            // Room either side for the speakers while showing volume
                            x: root.volumeShown ? 20 : 10
                            y: 102
                            width: parent.width - 2 * x
                            height: 8

                            readonly property real fraction: root.volumeShown
                                ? root.volume
                                : root.player.duration > 0 ? root.player.position / root.player.duration : 0

                            GlyphIcon {
                                anchors.right: parent.left
                                anchors.rightMargin: 3
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.volumeShown
                                width: 9
                                height: 9
                                kind: "speakerLow"
                                color: "#3c3f44"
                                engraved: false
                            }
                            GlyphIcon {
                                anchors.left: parent.right
                                anchors.leftMargin: 3
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.volumeShown
                                width: 9
                                height: 9
                                kind: "speakerHigh"
                                color: "#3c3f44"
                                engraved: false
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: "#e3e6ea"
                                border.color: "#9da2a9"

                                Rectangle {
                                    visible: !root.scrubbing
                                    x: 1
                                    y: 1
                                    height: parent.height - 2
                                    width: Math.max(height, (parent.width - 2) * meter.fraction)
                                    opacity: meter.fraction > 0 ? 1 : 0
                                    radius: height / 2
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "#b9d6fb" }
                                        GradientStop { position: 0.5; color: "#4f8ef0" }
                                        GradientStop { position: 1.0; color: "#2f6fd8" }
                                    }
                                }

                                GlyphIcon {
                                    visible: root.scrubbing
                                    x: (parent.width - width) * meter.fraction
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 10
                                    height: 10
                                    kind: "diamond"
                                    color: "#2f6fd8"
                                    engraved: false
                                }
                            }
                        }

                        Text {
                            anchors.left: meter.left
                            anchors.top: meter.bottom
                            anchors.topMargin: 3
                            visible: !root.volumeShown
                            text: root.formatTime(root.player.position)
                            font.family: Theme.font
                            font.pixelSize: 10
                            font.bold: true
                            color: "#3c3f44"
                        }
                        Text {
                            anchors.right: meter.right
                            anchors.top: meter.bottom
                            anchors.topMargin: 3
                            visible: !root.volumeShown
                            text: "-" + root.formatTime(root.player.duration - root.player.position)
                            font.family: Theme.font
                            font.pixelSize: 10
                            font.bold: true
                            color: "#3c3f44"
                        }
                    }
                }
            }
        }

        // ── Click wheel ──
        Rectangle {
            id: wheel
            readonly property real diameter: 172
            x: (parent.width - diameter) / 2
            y: bezel.y + bezel.height + 30
            width: diameter
            height: diameter
            radius: diameter / 2
            border.color: "#c9c9cc"
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#e4e4e6" }
                GradientStop { position: 1.0; color: "#f6f6f7" }
            }

            // Which quadrant button is held down, for a slight press shade
            property string pressedRegion: ""

            readonly property color labelColor: "#a9a9ae"

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 13
                text: "MENU"
                font.family: Theme.font
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 0.5
                color: wheel.pressedRegion === "menu" ? "#7c7c82" : wheel.labelColor
            }
            GlyphIcon {
                anchors.right: parent.right
                anchors.rightMargin: 15
                anchors.verticalCenter: parent.verticalCenter
                width: 15
                height: 11
                kind: "next"
                color: wheel.pressedRegion === "next" ? "#7c7c82" : wheel.labelColor
                engraved: false
            }
            GlyphIcon {
                anchors.left: parent.left
                anchors.leftMargin: 15
                anchors.verticalCenter: parent.verticalCenter
                width: 15
                height: 11
                kind: "prev"
                color: wheel.pressedRegion === "prev" ? "#7c7c82" : wheel.labelColor
                engraved: false
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                spacing: 1
                GlyphIcon {
                    width: 10
                    height: 11
                    kind: "play"
                    color: wheel.pressedRegion === "play" ? "#7c7c82" : wheel.labelColor
                    engraved: false
                }
                GlyphIcon {
                    width: 10
                    height: 11
                    kind: "pause"
                    color: wheel.pressedRegion === "play" ? "#7c7c82" : wheel.labelColor
                    engraved: false
                }
            }

            Rectangle {
                id: centerButton
                readonly property real diameter: 66
                anchors.centerIn: parent
                width: diameter
                height: diameter
                radius: diameter / 2
                border.color: "#cfcfd2"
                readonly property bool down: wheel.pressedRegion === "center"
                gradient: Gradient {
                    GradientStop { position: 0.0; color: centerButton.down ? "#e6e6e8" : "#ffffff" }
                    GradientStop { position: 1.0; color: centerButton.down ? "#dadadd" : "#ededef" }
                }
            }

            MouseArea {
                id: wheelMouse
                anchors.fill: parent

                // Clockwise degrees per menu step
                readonly property real step: 18
                property real lastAngle: 0
                property real accumulated: 0
                property real travelled: 0
                property string region: ""

                function angleAt(x, y) {
                    return Math.atan2(y - height / 2, x - width / 2) * 180 / Math.PI
                }
                function regionAt(x, y) {
                    const r = Math.hypot(x - width / 2, y - height / 2)
                    if (r > width / 2)
                        return ""
                    if (r <= centerButton.diameter / 2)
                        return "center"
                    const a = angleAt(x, y)
                    if (a >= -135 && a < -45) return "menu"
                    if (a >= -45 && a < 45) return "next"
                    if (a >= 45 && a < 135) return "play"
                    return "prev"
                }

                onPressed: mouse => {
                    region = regionAt(mouse.x, mouse.y)
                    if (region === "") {
                        mouse.accepted = false
                        return
                    }
                    root.forceActiveFocus()
                    lastAngle = angleAt(mouse.x, mouse.y)
                    accumulated = 0
                    travelled = 0
                    wheel.pressedRegion = region
                }
                onPositionChanged: mouse => {
                    if (region === "center")
                        return
                    const a = angleAt(mouse.x, mouse.y)
                    let d = a - lastAngle
                    if (d > 180) d -= 360
                    if (d < -180) d += 360
                    lastAngle = a
                    accumulated += d
                    travelled += Math.abs(d)
                    if (travelled > 8)
                        wheel.pressedRegion = ""
                    while (accumulated >= step) { root.tick(1); accumulated -= step }
                    while (accumulated <= -step) { root.tick(-1); accumulated += step }
                }
                onReleased: mouse => {
                    wheel.pressedRegion = ""
                    // A turn of the wheel isn't a button press
                    if (travelled > 8 || regionAt(mouse.x, mouse.y) !== region)
                        return
                    switch (region) {
                    case "center": root.select(); break
                    case "menu": root.pop(); break
                    case "next": root.nextRequested(); break
                    case "prev": root.previousRequested(); break
                    case "play": root.playPauseRequested(); break
                    }
                }
                onCanceled: wheel.pressedRegion = ""
            }
        }
    }
}
