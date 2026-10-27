import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// The song list: sortable, resizable columns over pale-blue striped rows
Rectangle {
    id: root

    required property var tracks
    property int selectedId: -1
    property int playingId: -1
    property bool playing: false
    // Column widths by role, persisted by the window
    property var widths: ({})
    // Set before an update that shouldn't move the list (play counts, imports)
    property bool preserveScroll: false

    signal activated(int trackId)
    signal selected(int trackId)
    signal widthsEdited(var widths)

    color: "white"
    clip: true

    readonly property var columns: [
        { role: "status", title: "", width: 20, fixed: true },
        { role: "title", title: qsTr("Song Name"), width: 0 },
        { role: "time", title: qsTr("Time"), width: 52, align: Text.AlignRight },
        { role: "artist", title: qsTr("Artist"), width: 140 },
        { role: "album", title: qsTr("Album"), width: 150 },
        { role: "genre", title: qsTr("Genre"), width: 90 },
        { role: "kind", title: qsTr("Kind"), width: 140 },
        { role: "playCount", title: qsTr("Play Count"), width: 72, align: Text.AlignRight }
    ]

    function widthOf(col) {
        if (col.role === "title") {
            let others = 0
            for (const c of columns)
                if (c.role !== "title")
                    others += widthOf(c)
            const fitted = list.width - others
            return Math.max(widths.title ?? 140, fitted)
        }
        return col.fixed ? col.width : (widths[col.role] ?? col.width)
    }

    readonly property real totalWidth: {
        // Depend on widths and list width so this re-evaluates on resize
        void widths; void list.width
        let sum = 0
        for (const c of columns)
            sum += widthOf(c)
        return sum
    }

    function select(row) {
        const count = list.count
        if (count === 0)
            return
        row = Math.max(0, Math.min(count - 1, row))
        root.selected(root.tracks.idAt(row))
        list.positionViewAtIndex(row, ListView.Contain)
    }

    function reveal(trackId) {
        const row = root.tracks.rowOfId(trackId)
        if (row >= 0)
            list.positionViewAtIndex(row, ListView.Center)
    }

    function focusList() {
        list.forceActiveFocus()
    }

    // Header
    Item {
        id: headerRow
        width: parent.width
        height: 17
        clip: true
        z: 2

        Row {
            x: -list.contentX
            Repeater {
                model: root.columns
                delegate: ListHeader {
                    id: cell
                    required property var modelData
                    width: root.widthOf(modelData)
                    height: 17
                    text: modelData.title
                    alignment: modelData.align ?? Text.AlignLeft
                    sorted: modelData.role !== "status" && root.tracks.sortColumn === modelData.role
                    ascending: root.tracks.sortAscending
                    onClicked: {
                        if (modelData.role !== "status")
                            root.tracks.sortBy(modelData.role)
                    }

                    // Drag the right edge to resize
                    MouseArea {
                        visible: !cell.modelData.fixed
                        anchors.right: parent.right
                        width: 6
                        height: parent.height
                        cursorShape: Qt.SplitHCursor
                        property real startX
                        property real startWidth
                        onPressed: mouse => {
                            startX = mapToItem(root, mouse.x, 0).x
                            startWidth = cell.width
                        }
                        onPositionChanged: mouse => {
                            const dx = mapToItem(root, mouse.x, 0).x - startX
                            const next = Object.assign({}, root.widths)
                            next[cell.modelData.role] = Math.max(36, Math.round(startWidth + dx))
                            root.widthsEdited(next)
                        }
                    }
                }
            }
        }
        // Filler to the right of the last column
        ListHeader {
            x: root.totalWidth - list.contentX
            width: Math.max(0, parent.width - x)
            height: 17
        }
    }

    ListView {
        id: list
        anchors.top: headerRow.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        model: root.tracks
        reuseItems: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.AutoFlickIfNeeded
        contentWidth: root.totalWidth
        keyNavigationEnabled: false
        activeFocusOnTab: true
        ScrollBar.vertical: AquaScrollBar {}
        ScrollBar.horizontal: AquaScrollBar {}

        // Stripes continue below the last song, like a real Aqua table
        Rectangle {
            parent: list
            z: -1
            y: list.contentHeight - list.contentY
            width: list.width
            height: Math.max(0, list.height - y)
            color: "white"
            clip: true
            Column {
                y: 0
                Repeater {
                    model: Math.max(0, Math.ceil(list.height / 17) + 1)
                    Rectangle {
                        required property int index
                        width: list.width
                        height: 17
                        color: (list.count + index) % 2 ? Theme.rowOdd : Theme.rowEven
                    }
                }
            }
        }

        delegate: Rectangle {
            id: row
            required property var model
            required property int index
            readonly property bool isSelected: model.trackId === root.selectedId
            readonly property bool isPlaying: model.trackId === root.playingId

            width: Math.max(root.totalWidth, ListView.view.width)
            height: 17
            color: isSelected ? Theme.selection : (index % 2 ? Theme.rowOdd : Theme.rowEven)

            Row {
                height: parent.height
                Repeater {
                    model: root.columns
                    delegate: Item {
                        id: cellItem
                        required property var modelData
                        width: root.widthOf(modelData)
                        height: row.height

                        GlyphIcon {
                            visible: cellItem.modelData.role === "status" && row.isPlaying
                            anchors.centerIn: parent
                            width: 13
                            height: 11
                            kind: root.playing ? "speaker" : "speakerLow"
                            color: row.isSelected ? "white" : "#1a1a1a"
                            engraved: false
                        }

                        Text {
                            visible: cellItem.modelData.role !== "status"
                            anchors.fill: parent
                            anchors.leftMargin: 5
                            anchors.rightMargin: 6
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: cellItem.modelData.align ?? Text.AlignLeft
                            text: visible ? (row.model[cellItem.modelData.role] ?? "") : ""
                            font.family: Theme.font
                            font.pixelSize: Theme.listFontSize
                            color: row.isSelected ? Theme.selectionText : Theme.text
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            anchors.right: parent.right
                            width: 1
                            height: parent.height
                            color: row.isSelected ? "#5a8fe0" : Theme.gridLine
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onPressed: {
                    list.forceActiveFocus()
                    root.selected(row.model.trackId)
                }
                onDoubleClicked: root.activated(row.model.trackId)
            }
        }

        Keys.onUpPressed: root.select(root.tracks.rowOfId(root.selectedId) - 1)
        Keys.onDownPressed: root.select(root.tracks.rowOfId(root.selectedId) + 1)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Home) {
                root.select(0)
            } else if (event.key === Qt.Key_End) {
                root.select(count - 1)
            } else if (event.key === Qt.Key_PageDown) {
                root.select(root.tracks.rowOfId(root.selectedId) + Math.floor(height / 17))
            } else if (event.key === Qt.Key_PageUp) {
                root.select(root.tracks.rowOfId(root.selectedId) - Math.floor(height / 17))
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.selectedId >= 0)
                    root.activated(root.selectedId)
            } else {
                return
            }
            event.accepted = true
        }

        property real savedY: 0
        Connections {
            target: root.tracks
            function onModelAboutToBeReset() {
                list.savedY = list.contentY
            }
            function onModelReset() {
                const keep = root.preserveScroll || root.tracks.scanning
                root.preserveScroll = false
                Qt.callLater(() => {
                    if (keep) {
                        list.contentY = Math.min(list.savedY, Math.max(list.originY, list.contentHeight - list.height + list.originY))
                    } else {
                        const row = root.tracks.rowOfId(root.selectedId)
                        if (row >= 0)
                            list.positionViewAtIndex(row, ListView.Contain)
                        else
                            list.positionViewAtBeginning()
                    }
                })
            }
        }
    }

    Text {
        anchors.centerIn: list
        width: Math.min(360, list.width - 40)
        visible: root.tracks.totalCount === 0
        text: root.tracks.scanning
              ? qsTr("Importing your music…")
              : qsTr("Your library is empty.\n\nClick the + button below to add a music folder, or drag a folder onto this window.")
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.family: Theme.font
        font.pixelSize: 12
        color: Theme.dimText
    }
}
