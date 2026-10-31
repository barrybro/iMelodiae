import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// Get Info: artwork, tags and file details for one song. Read-only. A floating panel
// inside the main window, dragged by its title bar like the Equalizer.
Popup {
    id: root

    // Parsed LibraryModel.trackInfo()
    property var info: ({})
    property string artworkSource: ""

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

    // Label/value pairs, skipping anything the file doesn't have
    readonly property var details: {
        const i = info
        const rows = [
            [qsTr("Kind"), i.kind ?? ""],
            [qsTr("Time"), i.durationMs ? formatTime(i.durationMs) : ""],
            [qsTr("Bit Rate"), i.bitRate ? qsTr("%1 kbps").arg(i.bitRate) : ""],
            [qsTr("Sample Rate"), i.sampleRate ? qsTr("%1 kHz").arg((i.sampleRate / 1000).toFixed(1)) : ""],
            [qsTr("Size"), formatSize(i.size ?? 0)],
            [qsTr("Album Artist"), i.albumArtist ?? ""],
            [qsTr("Genre"), i.genre ?? ""],
            [qsTr("Year"), i.year ? String(i.year) : ""],
            [qsTr("Track"), i.trackNumber ? String(i.trackNumber) : ""],
            [qsTr("Disc"), i.discNumber ? String(i.discNumber) : ""],
            [qsTr("Play Count"), String(i.playCount ?? 0)],
            [qsTr("Last Played"), formatDate(i.lastPlayed ?? 0)],
            [qsTr("Date Added"), formatDate(i.dateAdded ?? 0)]
        ]
        return rows.filter(r => r[1] !== "")
    }

    width: 400
    height: contentItem.implicitHeight
    padding: 0
    modal: false
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

    contentItem: Item {
        implicitHeight: sheet.y + sheet.height + 12

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
                text: root.info.title || qsTr("Song Info")
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
                        width: 104
                        height: 104
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
                            width: 40
                            height: 40
                            kind: "note"
                            color: "#a9b3c2"
                            engraved: false
                        }
                    }

                    Column {
                        width: body.width - 116
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            width: parent.width
                            text: root.info.title ?? ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.bold: true
                            color: Theme.text
                        }
                        Text {
                            width: parent.width
                            text: root.info.artist ?? ""
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 12
                            color: Theme.text
                        }
                        Text {
                            width: parent.width
                            text: root.info.album ?? ""
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 12
                            color: Theme.text
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.gridLine
                }

                Column {
                    width: parent.width
                    spacing: 3

                    Repeater {
                        model: root.details
                        delegate: Row {
                            required property var modelData
                            spacing: 8

                            // Labels right-aligned in a fixed column, values beside them
                            Text {
                                width: 90
                                horizontalAlignment: Text.AlignRight
                                text: modelData[0] + ":"
                                font.family: Theme.font
                                font.pixelSize: Theme.listFontSize
                                font.bold: true
                                color: Theme.dimText
                            }
                            Text {
                                width: body.width - 98
                                text: modelData[1]
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: Theme.listFontSize
                                color: Theme.text
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: where.implicitHeight

                    Text {
                        id: whereLabel
                        width: 90
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
}
