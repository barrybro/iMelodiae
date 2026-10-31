import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// Get Info for one song or many. Tags can be edited and are written into the files on
// OK. With several songs selected, fields they share show that value and the rest show
// "Mixed"; only fields you change (ticked) are written, to every selected song, and a
// ticked field left empty removes that tag. A floating panel inside the main window,
// dragged by its title bar like the Equalizer.
Popup {
    id: root

    // Parsed LibraryModel.trackInfo() for each song
    property var infos: []
    readonly property var info: infos.length > 0 ? infos[0] : ({})
    readonly property bool multiple: infos.length > 1
    property string artworkSource: ""
    // Suggestions for the Genre field
    property var genres: []

    // Tag changes to write: a TagEdit (see scanner.rs) with only the changed fields
    signal saveRequested(var trackIds, var edit)

    readonly property var fields: [
        { key: "title", label: qsTr("Name") },
        { key: "artist", label: qsTr("Artist") },
        { key: "albumArtist", label: qsTr("Album Artist") },
        { key: "album", label: qsTr("Album") },
        { key: "genre", label: qsTr("Genre"), suggest: true },
        { key: "year", label: qsTr("Year"), number: true },
        { key: "trackNumber", label: qsTr("Track #"), number: true },
        { key: "discNumber", label: qsTr("Disc #"), number: true }
    ]

    function load(list, genreList) {
        // Rebuild the fields so every edit and tick from last time is gone
        editor.model = []
        infos = list
        genres = genreList
        editor.model = fields
    }

    function shownValue(info, field) {
        const v = info[field.key]
        if (field.number)
            return v ? String(v) : ""
        return v ?? ""
    }

    // What the selected songs share for a field, or null when they differ
    function commonValue(field) {
        if (infos.length === 0)
            return ""
        const first = shownValue(infos[0], field)
        for (let i = 1; i < infos.length; ++i)
            if (shownValue(infos[i], field) !== first)
                return null
        return first
    }

    // Fields that are rarely meant to be the same on every song, so a bulk change asks first
    readonly property var riskyKeys: ["title", "trackNumber"]

    function save() {
        if (confirmation.edit) {
            // Enter again while the sheet is up means "Change Anyway"
            commit(confirmation.edit)
            return
        }
        const edit = {}
        let any = false
        for (let i = 0; i < editor.count; ++i) {
            const row = editor.itemAt(i)
            if (!row.apply)
                continue
            const text = row.text.trim()
            edit[row.field.key] = row.field.number ? (parseInt(text, 10) || 0) : text
            any = true
        }
        if (!any) {
            close()
        } else if (multiple && riskyKeys.some(k => k in edit)) {
            confirmation.edit = edit
        } else {
            commit(edit)
        }
    }

    function commit(edit) {
        confirmation.edit = null
        saveRequested(infos.map(i => i.id), edit)
        close()
    }

    onClosed: confirmation.edit = null

    function formatTime(ms) {
        const s = Math.max(0, Math.floor(ms / 1000))
        const h = Math.floor(s / 3600)
        const m = Math.floor(s / 60) % 60
        const sec = s % 60
        const pad = n => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec)
    }
    function formatDate(secs) {
        return secs > 0 ? new Date(secs * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat) : ""
    }
    function formatSize(bytes) {
        return bytes > 0 ? qsTr("%1 MB").arg((bytes / (1024 * 1024)).toFixed(1)) : ""
    }

    // Read-only file details for a single song, skipping anything the file doesn't have
    readonly property var details: {
        if (multiple)
            return []
        const i = info
        const rows = [
            [qsTr("Kind"), i.kind ?? ""],
            [qsTr("Time"), i.durationMs ? formatTime(i.durationMs) : ""],
            [qsTr("Bit Rate"), i.bitRate ? qsTr("%1 kbps").arg(i.bitRate) : ""],
            [qsTr("Sample Rate"), i.sampleRate ? qsTr("%1 kHz").arg((i.sampleRate / 1000).toFixed(1)) : ""],
            [qsTr("Size"), formatSize(i.size ?? 0)],
            [qsTr("Play Count"), String(i.playCount ?? 0)],
            [qsTr("Last Played"), formatDate(i.lastPlayed ?? 0)],
            [qsTr("Date Added"), formatDate(i.dateAdded ?? 0)]
        ]
        return rows.filter(r => r[1] !== "")
    }

    width: 420
    height: contentItem.implicitHeight
    padding: 0
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape

    background: Item {
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            anchors.bottomMargin: -4
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.25)
        }
        Rectangle {
            anchors.fill: parent
            radius: 4
            border.color: "#4a4a4a"
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.toolbarTop }
                GradientStop { position: 0.06; color: Theme.toolbarUpper }
                GradientStop { position: 1.0; color: Theme.barBottom }
            }
        }
    }

    // Aqua push button; the default one is blue gel
    component PanelButton: Rectangle {
        id: button
        property string text
        property bool isDefault: false
        signal clicked()
        width: Math.max(80, label.implicitWidth + 28)
        height: 21
        radius: height / 2
        border.color: isDefault ? "#2457b0" : "#6b6b6b"
        readonly property bool down: buttonMouse.pressed && buttonMouse.containsMouse
        gradient: Gradient {
            GradientStop { position: 0.0; color: button.isDefault ? (button.down ? Theme.gelMid : Theme.gelTop) : (button.down ? "#c8c8c8" : "#ffffff") }
            GradientStop { position: 0.5; color: button.isDefault ? (button.down ? Theme.gelBottom : Theme.gelMid) : (button.down ? "#b4b4b4" : "#e6e6e6") }
            GradientStop { position: 1.0; color: button.isDefault ? "#8cc0ff" : (button.down ? "#d0d0d0" : "#f6f6f6") }
        }
        Text {
            id: label
            anchors.centerIn: parent
            text: button.text
            font.family: Theme.font
            font.pixelSize: Theme.listFontSize + 1
            color: button.isDefault ? "#0d2a5c" : Theme.text
        }
        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            onClicked: button.clicked()
        }
    }

    contentItem: Item {
        implicitHeight: buttons.y + buttons.height + 12

        // Title bar: drag to move, round button to close
        Item {
            id: titleBar
            width: parent.width
            height: 20

            Rectangle {
                x: 7
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                border.color: "#8e2a22"
                gradient: Gradient {
                    GradientStop { position: 0.0; color: closeMouse.pressed ? "#b8332a" : "#ff8a7a" }
                    GradientStop { position: 1.0; color: closeMouse.pressed ? "#7d1d16" : "#d9352a" }
                }
                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    anchors.margins: -3
                    onClicked: root.close()
                }
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 60
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.multiple ? qsTr("Multiple Song Information") : (root.info.title || qsTr("Song Info"))
                font.family: Theme.font
                font.pixelSize: 12
                color: "#1a1a1a"
                style: Text.Raised
                styleColor: "#e2e2e2"
            }

            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: 24
                cursorShape: Qt.SizeAllCursor
                property point grab
                onPressed: mouse => grab = Qt.point(mouse.x, mouse.y)
                onPositionChanged: mouse => {
                    const w = root.parent ? root.parent.width : 1000
                    const h = root.parent ? root.parent.height : 800
                    root.x = Math.max(0, Math.min(w - root.width, root.x + mouse.x - grab.x))
                    root.y = Math.max(0, Math.min(h - root.height, root.y + mouse.y - grab.y))
                }
            }
        }

        // White inset sheet holding the details
        Rectangle {
            id: sheet
            x: 12
            y: titleBar.height + 6
            width: parent.width - 24
            height: body.implicitHeight + 24
            color: "white"
            border.color: "#7a7a7a"

            Column {
                id: body
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 12

                Row {
                    spacing: 12

                    Rectangle {
                        width: 84
                        height: 84
                        color: Theme.sourceBackground
                        border.color: "#b9b9b9"

                        Image {
                            id: art
                            anchors.fill: parent
                            anchors.margins: 1
                            source: root.artworkSource
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            mipmap: true
                            sourceSize.width: 256
                            sourceSize.height: 256
                        }
                        GlyphIcon {
                            anchors.centerIn: parent
                            visible: art.status !== Image.Ready
                            width: 34
                            height: 34
                            kind: "note"
                            color: "#a9b3c2"
                            engraved: false
                        }
                    }

                    Column {
                        width: body.width - 96
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            width: parent.width
                            text: root.multiple ? qsTr("%1 songs").arg(root.infos.length) : (root.info.title ?? "")
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.bold: true
                            color: Theme.text
                        }
                        Text {
                            width: parent.width
                            readonly property var artist: root.commonValue(root.fields[1])
                            text: artist === null ? qsTr("Mixed artists") : artist
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 12
                            color: artist === null ? Theme.dimText : Theme.text
                        }
                        Text {
                            width: parent.width
                            readonly property var album: root.commonValue(root.fields[3])
                            text: album === null ? qsTr("Mixed albums") : album
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 12
                            color: album === null ? Theme.dimText : Theme.text
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.gridLine
                }

                // Editable tags
                Column {
                    width: parent.width
                    spacing: 4

                    Repeater {
                        id: editor
                        delegate: Item {
                            id: fieldRow
                            required property var modelData
                            required property int index
                            readonly property var field: modelData
                            readonly property var original: root.commonValue(field)
                            property alias text: input.text
                            // Write this field on OK. Several songs: ticked by hand or by
                            // typing. One song: whenever it differs from the file.
                            property bool ticked: false
                            readonly property bool apply: root.multiple ? ticked : input.text !== (original ?? "")

                            width: parent.width
                            height: 22

                            Text {
                                id: fieldLabel
                                width: 84
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: fieldRow.field.label + ":"
                                font.family: Theme.font
                                font.pixelSize: Theme.listFontSize
                                font.bold: true
                                color: Theme.dimText
                            }

                            // Apply checkbox, only when editing several songs
                            Rectangle {
                                id: tick
                                visible: root.multiple
                                anchors.left: fieldLabel.right
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: visible ? 14 : 0
                                height: 14
                                radius: 3
                                border.color: fieldRow.ticked ? "#2457b0" : "#6b6b6b"
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: fieldRow.ticked ? Theme.gelTop : "#ffffff" }
                                    GradientStop { position: 0.5; color: fieldRow.ticked ? Theme.gelMid : "#e9e9e9" }
                                    GradientStop { position: 1.0; color: fieldRow.ticked ? "#8cc0ff" : "#f8f8f8" }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: fieldRow.ticked
                                    text: "✓"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: "#0d2a5c"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -3
                                    onClicked: fieldRow.ticked = !fieldRow.ticked
                                }
                            }

                            Rectangle {
                                id: box
                                anchors.left: tick.right
                                anchors.leftMargin: root.multiple ? 6 : 8
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 20
                                color: "white"
                                border.color: input.activeFocus ? "#5b8fdd" : "#8e8e8e"
                                border.width: input.activeFocus ? 2 : 1

                                TextField {
                                    id: input
                                    anchors.fill: parent
                                    anchors.rightMargin: suggestButton.visible ? suggestButton.width : 0
                                    padding: 0
                                    leftPadding: 5
                                    rightPadding: 4
                                    background: null
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.family: Theme.font
                                    font.pixelSize: Theme.listFontSize + 1
                                    color: Theme.text
                                    selectionColor: "#b5d5ff"
                                    selectedTextColor: Theme.text
                                    selectByMouse: true
                                    placeholderText: fieldRow.original === null ? qsTr("Mixed") : ""
                                    placeholderTextColor: Theme.dimText
                                    inputMethodHints: fieldRow.field.number ? Qt.ImhDigitsOnly : Qt.ImhNone
                                    validator: fieldRow.field.number ? digits : null
                                    text: fieldRow.original ?? ""
                                    onTextEdited: {
                                        fieldRow.ticked = true
                                        if (fieldRow.field.suggest && activeFocus)
                                            suggestions.show(false)
                                    }
                                    onAccepted: {
                                        if (suggestions.opened && suggestions.pick())
                                            return
                                        root.save()
                                    }
                                    Keys.onDownPressed: if (suggestions.opened) suggestions.move(1)
                                    Keys.onUpPressed: if (suggestions.opened) suggestions.move(-1)
                                    Keys.onEscapePressed: event => {
                                        if (suggestions.opened)
                                            suggestions.close()
                                        else if (confirmation.edit)
                                            confirmation.edit = null
                                        else
                                            root.close()
                                    }
                                }

                                IntValidator {
                                    id: digits
                                    bottom: 0
                                    top: 9999
                                }

                                // Genre drop-down: every genre in the library
                                Rectangle {
                                    id: suggestButton
                                    visible: fieldRow.field.suggest === true
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 1
                                    width: 18
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: Theme.gelTop }
                                        GradientStop { position: 0.5; color: Theme.gelMid }
                                        GradientStop { position: 1.0; color: "#8cc0ff" }
                                    }
                                    GlyphIcon {
                                        anchors.centerIn: parent
                                        width: 8
                                        height: 6
                                        kind: "down"
                                        color: "#0d2a5c"
                                        engraved: false
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: suggestions.opened ? suggestions.close() : suggestions.show(true)
                                    }
                                }
                            }

                            Popup {
                                id: suggestions
                                y: box.y + box.height + 1
                                x: box.x
                                width: box.width
                                height: Math.min(180, list.contentHeight + 2)
                                padding: 1
                                closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape
                                visible: false

                                property bool showAll: false
                                readonly property var matches: {
                                    if (!fieldRow.field.suggest)
                                        return []
                                    const q = input.text.trim().toLowerCase()
                                    return showAll || q === "" ? root.genres
                                                               : root.genres.filter(g => g.toLowerCase().includes(q))
                                }

                                function show(all) {
                                    showAll = all
                                    list.currentIndex = all ? root.genres.indexOf(input.text) : -1
                                    if (matches.length > 0)
                                        open()
                                    else
                                        close()
                                    if (all && list.currentIndex >= 0)
                                        list.positionViewAtIndex(list.currentIndex, ListView.Center)
                                }
                                function move(step) {
                                    list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + step))
                                }
                                function pick() {
                                    if (list.currentIndex < 0)
                                        return false
                                    choose(matches[list.currentIndex])
                                    return true
                                }
                                function choose(genre) {
                                    input.text = genre
                                    fieldRow.ticked = true
                                    close()
                                    input.forceActiveFocus()
                                }

                                background: Rectangle {
                                    color: "white"
                                    border.color: "#8e8e8e"
                                }
                                contentItem: ListView {
                                    id: list
                                    clip: true
                                    model: suggestions.matches
                                    boundsBehavior: Flickable.StopAtBounds
                                    highlightMoveDuration: 0
                                    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                                    ScrollBar.vertical: AquaScrollBar {}
                                    delegate: Rectangle {
                                        id: option
                                        required property string modelData
                                        required property int index
                                        readonly property bool lit: ListView.isCurrentItem || optionMouse.containsMouse
                                        width: ListView.view.width
                                        height: 18
                                        color: lit ? Theme.selection : "transparent"
                                        Text {
                                            x: 6
                                            width: parent.width - 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: option.modelData
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.listFontSize + 1
                                            color: option.lit ? Theme.selectionText : Theme.text
                                        }
                                        MouseArea {
                                            id: optionMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: suggestions.choose(option.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: !root.multiple
                    width: parent.width
                    height: 1
                    color: Theme.gridLine
                }

                // Read-only file details (one song)
                Column {
                    visible: !root.multiple
                    width: parent.width
                    spacing: 3

                    Repeater {
                        model: root.details
                        delegate: Row {
                            required property var modelData
                            spacing: 8

                            // Labels right-aligned in a fixed column, values beside them
                            Text {
                                width: 84
                                horizontalAlignment: Text.AlignRight
                                text: modelData[0] + ":"
                                font.family: Theme.font
                                font.pixelSize: Theme.listFontSize
                                font.bold: true
                                color: Theme.dimText
                            }
                            Text {
                                width: body.width - 92
                                text: modelData[1]
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: Theme.listFontSize
                                color: Theme.text
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: where.implicitHeight

                        Text {
                            id: whereLabel
                            width: 84
                            horizontalAlignment: Text.AlignRight
                            text: qsTr("Where:")
                            font.family: Theme.font
                            font.pixelSize: Theme.listFontSize
                            font.bold: true
                            color: Theme.dimText
                        }
                        TextEdit {
                            id: where
                            anchors.left: whereLabel.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            text: root.info.path ?? ""
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.WrapAnywhere
                            font.family: Theme.font
                            font.pixelSize: Theme.listFontSize
                            color: Theme.text
                            selectionColor: "#b5d5ff"
                            selectedTextColor: Theme.text
                        }
                    }
                }
            }
        }

        Row {
            id: buttons
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: sheet.y + sheet.height + 10
            spacing: 10

            PanelButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }
            PanelButton {
                text: qsTr("OK")
                isDefault: true
                onClicked: root.save()
            }
        }

        // Confirmation sheet for bulk changes to Name or Track #, dropping from the title
        // bar like a Mac OS X sheet. Dims and blocks the panel underneath while it's up.
        Item {
            id: confirmation
            // The edit waiting for confirmation, or null
            property var edit: null
            readonly property var risky: edit
                ? root.fields.filter(f => root.riskyKeys.includes(f.key) && f.key in edit) : []

            anchors.fill: parent
            anchors.topMargin: titleBar.height
            visible: edit !== null
            z: 10
            clip: true

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.18)
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onWheel: wheel => wheel.accepted = true
            }

            Rectangle {
                id: sheetBox
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 40
                height: message.y + message.height + 16 + sheetButtons.height + 14
                y: confirmation.visible ? -1 : -height
                Behavior on y {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                border.color: "#6b6b6b"
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#e9e9e9" }
                    GradientStop { position: 1.0; color: "#f6f6f6" }
                }

                // Soft shadow under the sheet
                Rectangle {
                    anchors.top: parent.bottom
                    width: parent.width
                    height: 4
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.22) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Text {
                    id: heading
                    x: 18
                    y: 16
                    width: parent.width - 36
                    wrapMode: Text.Wrap
                    text: qsTr("Give all %1 songs the same %2?")
                          .arg(root.infos.length)
                          .arg(confirmation.risky.map(f => f.label).join(qsTr(" and ")))
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.bold: true
                    color: Theme.text
                }
                Text {
                    id: message
                    anchors.left: heading.left
                    anchors.right: heading.right
                    anchors.top: heading.bottom
                    anchors.topMargin: 8
                    wrapMode: Text.Wrap
                    text: {
                        const lines = confirmation.risky.map(f => {
                            const v = confirmation.edit[f.key]
                            return v === "" || v === 0
                                ? qsTr("• %1 will be removed from every selected song.").arg(f.label)
                                : qsTr("• Every selected song's %1 will become “%2”.").arg(f.label).arg(v)
                        })
                        return lines.join("\n") + "\n\n" + qsTr("This is written into the files and can't be undone.")
                    }
                    font.family: Theme.font
                    font.pixelSize: Theme.listFontSize
                    color: Theme.text
                }

                Row {
                    id: sheetButtons
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    spacing: 10

                    PanelButton {
                        text: qsTr("Cancel")
                        onClicked: confirmation.edit = null
                    }
                    PanelButton {
                        text: qsTr("Change Anyway")
                        isDefault: true
                        onClicked: root.commit(confirmation.edit)
                    }
                }
            }
        }
    }
}
