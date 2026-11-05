import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// Left-hand "Source" list: the Library, a few smart playlists and the hand-made
// playlists, on iTunes 5's pale blue-grey background with a slate-blue selection bar.
// Drop songs on a playlist to add them, or on the empty space below to make a new one.
Rectangle {
    id: root

    property int current: 0
    // Hand-made playlist names, in order; playlist i is source firstPlaylist + i
    property var playlists: []
    readonly property int firstPlaylist: fixedSources.length
    // The source whose name is being edited, or -1
    property int editing: -1
    readonly property bool renaming: editing >= 0

    signal picked(int source)
    signal newPlaylistRequested()
    signal renameRequested(int source, string name)
    signal deleteRequested(int source)
    // Songs dragged onto a playlist, or onto the empty space (source -1)
    signal songsDropped(int source, var trackIds)

    color: Theme.sourceBackground
    clip: true
    activeFocusOnTab: true

    readonly property var fixedSources: [
        { name: qsTr("Library"), icon: "library" },
        { name: qsTr("Recently Added"), icon: "smart" },
        { name: qsTr("Top 25 Most Played"), icon: "smart" },
        { name: qsTr("Recently Played"), icon: "smart" }
    ]
    readonly property var sources: fixedSources.concat(playlists.map(name => ({ name: name, icon: "playlist" })))

    function isPlaylist(source) {
        return source >= firstPlaylist && source < sources.length
    }

    // Start editing a playlist's name in place
    function rename(source) {
        if (isPlaylist(source))
            editing = source
    }

    function finishRename(text, keep) {
        const source = editing
        editing = -1
        if (keep && source >= 0)
            renameRequested(source, text)
        root.forceActiveFocus()
    }

    Keys.onUpPressed: if (current > 0) picked(current - 1)
    Keys.onDownPressed: if (current < sources.length - 1) picked(current + 1)
    Keys.onPressed: event => {
        if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && isPlaylist(current))
            deleteRequested(current)
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_F2)
                 && isPlaylist(current))
            rename(current)
        else
            return
        event.accepted = true
    }

    // A click on the already-selected playlist renames it, after a pause so a
    // double-click doesn't
    Timer {
        id: renameTimer
        property int source: -1
        interval: 500
        onTriggered: root.rename(source)
    }

    ContextMenu {
        id: menu
        // The playlist right-clicked, or -1
        property int source: -1
        items: [{ label: qsTr("New Playlist"), action: "new", shortcut: "Ctrl+N" }].concat(
            root.isPlaylist(source) ? [
                { separator: true },
                { label: qsTr("Rename Playlist"), action: "rename" },
                { label: qsTr("Delete Playlist"), action: "delete", shortcut: "Del" }
            ] : [])
        onTriggered: action => {
            if (action === "new")
                root.newPlaylistRequested()
            else if (action === "rename")
                root.rename(source)
            else if (action === "delete")
                root.deleteRequested(source)
        }
    }

    ListHeader {
        id: header
        width: parent.width
        text: qsTr("Source")
        alignment: Text.AlignHCenter
        sourceStyle: true
        grip: true
    }

    Flickable {
        id: flick
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        contentHeight: Math.max(height, column.height)
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        clip: true
        ScrollBar.vertical: AquaScrollBar {}

        // The empty space: right-click for New Playlist, drop songs to make one
        MouseArea {
            id: emptyMouse
            width: flick.width
            height: flick.contentHeight
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: mouse => {
                root.forceActiveFocus()
                if (mouse.button === Qt.RightButton) {
                    menu.source = -1
                    menu.popupAt(emptyMouse, mouse.x, mouse.y)
                }
            }
        }
        DropArea {
            id: emptyDrop
            y: column.height
            width: flick.width
            height: flick.contentHeight - column.height
            keys: ["songs"]
            onDropped: drop => {
                const ids = drop.source.trackIds
                Qt.callLater(() => root.songsDropped(-1, ids))
            }
        }
        // Where a new playlist would appear
        Rectangle {
            visible: emptyDrop.containsDrag
            x: 3
            y: column.height + 1
            width: flick.width - 6
            height: 18
            radius: 4
            color: "transparent"
            border.color: Theme.selection
            border.width: 2
        }

        Column {
            id: column
            width: flick.width

            Repeater {
                model: root.sources

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool isSelected: root.current === index
                    readonly property bool isPlaylist: modelData.icon === "playlist"
                    readonly property bool editing: root.editing === index

                    width: column.width
                    height: 18
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: row.isSelected ? Theme.sourceSelectionTop : "transparent" }
                        GradientStop { position: 1.0; color: row.isSelected ? Theme.sourceSelectionBottom : "transparent" }
                    }

                    function startEditing() {
                        field.text = modelData.name
                        field.selectAll()
                        field.forceActiveFocus()
                    }
                    onEditingChanged: if (editing) startEditing()
                    Component.onCompleted: if (editing) startEditing()

                    Rectangle {
                        visible: row.isSelected
                        width: parent.width
                        height: 1
                        color: Theme.sourceSelectionLine
                    }

                    // Library: golden music box. Smart playlist: lavender page with a purple
                    // gear. Playlist: pale blue page with a note.
                    Rectangle {
                        id: badge
                        x: 5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        radius: row.modelData.icon === "library" ? 2 : 1
                        border.color: ({ library: "#6f5200", smart: "#6a5a96", playlist: "#3f6496" })[row.modelData.icon]
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: ({ library: "#ffe27a", smart: "#f1ebff", playlist: "#eef5ff" })[row.modelData.icon]
                            }
                            GradientStop {
                                position: 1.0
                                color: ({ library: "#c8961b", smart: "#c9bdeb", playlist: "#a9c6ec" })[row.modelData.icon]
                            }
                        }
                        GlyphIcon {
                            anchors.centerIn: parent
                            width: row.modelData.icon === "smart" ? 10 : 9
                            height: 10
                            kind: row.modelData.icon === "smart" ? "gear" : "note"
                            color: ({ library: "#2a1e00", smart: "#3c2a78", playlist: "#183a6a" })[row.modelData.icon]
                            engraved: false
                        }
                    }

                    Text {
                        id: label
                        visible: !row.editing
                        anchors.left: badge.right
                        anchors.leftMargin: 5
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.name
                        font.family: Theme.font
                        font.pixelSize: Theme.listFontSize + 1
                        font.bold: row.isSelected
                        color: row.isSelected ? Theme.selectionText : Theme.text
                        style: row.isSelected ? Text.Sunken : Text.Normal
                        styleColor: "#5b6b84"
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !row.editing
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onPressed: mouse => {
                            root.forceActiveFocus()
                            if (mouse.button === Qt.RightButton) {
                                menu.source = row.index
                                menu.popupAt(row, mouse.x, mouse.y)
                            } else if (row.isSelected && row.isPlaylist) {
                                renameTimer.source = row.index
                                renameTimer.restart()
                            } else {
                                root.picked(row.index)
                            }
                        }
                        onDoubleClicked: renameTimer.stop()
                    }

                    // The name being edited: Return keeps it, Escape puts the old one back
                    Rectangle {
                        visible: row.editing
                        anchors.fill: label
                        anchors.leftMargin: -2
                        anchors.topMargin: -1
                        anchors.bottomMargin: -1
                        color: "white"
                        border.color: Theme.selection
                        TextInput {
                            id: field
                            anchors.fill: parent
                            anchors.leftMargin: 2
                            anchors.rightMargin: 2
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            font.family: Theme.font
                            font.pixelSize: Theme.listFontSize + 1
                            color: Theme.text
                            selectByMouse: true
                            selectionColor: Theme.selection
                            Keys.onReturnPressed: root.finishRename(text, true)
                            Keys.onEnterPressed: root.finishRename(text, true)
                            Keys.onEscapePressed: root.finishRename(text, false)
                            onActiveFocusChanged: if (!activeFocus && row.editing) root.finishRename(text, true)
                        }
                    }

                    // Drop songs here to add them to this playlist
                    DropArea {
                        id: rowDrop
                        anchors.fill: parent
                        enabled: row.isPlaylist
                        keys: ["songs"]
                        onDropped: drop => {
                            const ids = drop.source.trackIds
                            Qt.callLater(() => root.songsDropped(row.index, ids))
                        }
                    }
                    Rectangle {
                        visible: rowDrop.containsDrag
                        anchors.fill: parent
                        anchors.leftMargin: 2
                        anchors.rightMargin: 2
                        radius: 4
                        color: "transparent"
                        border.color: Theme.selection
                        border.width: 2
                    }
                }
            }
        }
    }
}
