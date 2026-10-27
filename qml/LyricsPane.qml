import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// Right-hand lyrics pane: the playing song up top, then its lyrics. Synced lyrics
// follow the music, with the current line dark and the rest greyed out.
Rectangle {
    id: root

    required property var lyrics
    property string title: ""
    property string artist: ""
    property string artworkSource: ""
    property int position: 0
    property bool active: false
    signal seekRequested(int ms)

    color: "white"
    clip: true

    readonly property var lines: {
        try {
            return JSON.parse(lyrics.linesJson)
        } catch (e) {
            return []
        }
    }

    // Index of the line being sung: the last line whose time has passed
    readonly property int currentLine: {
        if (!lyrics.synced || lines.length === 0)
            return -1
        let lo = 0, hi = lines.length - 1, found = -1
        // Show each line a touch early so it lands with the vocals
        const t = position + 250
        while (lo <= hi) {
            const mid = (lo + hi) >> 1
            if (lines[mid].t <= t) {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return found
    }

    ListHeader {
        id: header
        width: parent.width
        text: qsTr("Lyrics")
        alignment: Text.AlignHCenter
    }

    // Now playing
    Item {
        id: songInfo
        anchors.top: header.bottom
        width: parent.width
        height: root.active ? 64 : 0
        visible: root.active

        Rectangle {
            id: thumb
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            color: "#e6e6e6"
            border.color: "#b5b5b5"
            Image {
                anchors.fill: parent
                anchors.margins: 1
                source: root.artworkSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 96
                sourceSize.height: 96
            }
        }

        Column {
            anchors.left: thumb.right
            anchors.leftMargin: 9
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                text: root.title
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 13
                font.bold: true
                color: Theme.text
            }
            Text {
                width: parent.width
                text: root.artist
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.listFontSize
                color: Theme.dimText
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.gridLine
        }
    }

    ListView {
        id: list
        anchors.top: songInfo.bottom
        anchors.bottom: credit.top
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        visible: root.active && root.lyrics.state === "found"
        model: root.lines
        spacing: root.lyrics.synced ? 12 : 3
        topMargin: 16
        bottomMargin: 16
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: AquaScrollBar {}

        // Follow the song, unless the listener has just scrolled to read ahead
        currentIndex: root.currentLine
        highlightFollowsCurrentItem: true
        highlightMoveDuration: 450
        highlightRangeMode: userScroll.running || !root.lyrics.synced ? ListView.NoHighlightRange : ListView.ApplyRange
        preferredHighlightBegin: height * 0.3
        preferredHighlightEnd: height * 0.3 + 40
        highlight: Item {}
        onMovementStarted: userScroll.restart()

        Timer {
            id: userScroll
            interval: 4000
        }

        delegate: Item {
            id: line
            required property var modelData
            required property int index
            readonly property bool isCurrent: index === root.currentLine

            width: ListView.view.width
            height: lineText.implicitHeight

            Text {
                id: lineText
                x: 14
                width: parent.width - 28
                text: line.modelData.text.length ? line.modelData.text : (root.lyrics.synced ? "♪" : " ")
                wrapMode: Text.WordWrap
                font.family: Theme.font
                font.pixelSize: root.lyrics.synced ? 16 : 13
                font.bold: root.lyrics.synced
                color: !root.lyrics.synced ? "#333333" : (line.isCurrent ? "#1a1a1a" : "#b9b9b9")
                Behavior on color { ColorAnimation { duration: 250 } }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.lyrics.synced && line.modelData.t >= 0
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    userScroll.stop()
                    root.seekRequested(line.modelData.t)
                }
            }
        }
    }

    Text {
        anchors.top: songInfo.bottom
        anchors.bottom: credit.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        visible: !list.visible
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        font.family: Theme.font
        font.pixelSize: 12
        color: Theme.dimText
        text: {
            if (!root.active)
                return qsTr("Lyrics appear here while a song plays.")
            switch (root.lyrics.state) {
            case "loading": return qsTr("Searching for lyrics…")
            case "instrumental": return qsTr("♪\n\nInstrumental")
            case "missing": return qsTr("No lyrics found for this song.\n\nTip: put a .lrc file with the same name next to the song.")
            default: return ""
            }
        }
    }

    Text {
        id: credit
        anchors.bottom: parent.bottom
        width: parent.width
        height: visible ? 24 : 0
        visible: root.active && root.lyrics.source.length > 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: qsTr("Lyrics from %1").arg(root.lyrics.source)
        font.family: Theme.font
        font.pixelSize: Theme.smallFontSize
        color: Theme.dimText
    }
}
