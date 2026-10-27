import QtQuick
import org.imelodiae

// The status "LCD" in the middle of the toolbar: song title, a line that cycles
// between artist and album, and a progress bar flanked by elapsed/remaining time.
Item {
    id: root

    property string title: ""
    property string artist: ""
    property string album: ""
    property int position: 0
    property int duration: 0
    property bool loaded: false
    property string message: ""

    signal seekRequested(int ms)
    signal snapbackClicked()

    property bool showRemaining: true
    property int infoLine: 0

    implicitWidth: 420
    implicitHeight: 52

    function formatTime(ms) {
        const s = Math.max(0, Math.floor(ms / 1000))
        const h = Math.floor(s / 3600)
        const m = Math.floor(s / 60) % 60
        const sec = s % 60
        const pad = n => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec)
    }

    // Light bevel below the LCD, like it's pressed into the metal
    Rectangle {
        anchors.fill: lcd
        anchors.topMargin: 1
        anchors.bottomMargin: -1
        radius: lcd.radius
        color: Qt.rgba(1, 1, 1, 0.7)
    }

    Rectangle {
        id: lcd
        anchors.fill: parent
        radius: 5
        border.color: Theme.lcdBorder
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.lcdTop }
            GradientStop { position: 0.3; color: Theme.lcdUpper }
            GradientStop { position: 0.75; color: Theme.lcdLower }
            GradientStop { position: 1.0; color: Theme.lcdBottom }
        }
        clip: true

        // Inner shadow along the top edge
        Rectangle {
            x: 3
            y: 1
            width: parent.width - 6
            height: 5
            radius: 2
            opacity: 0.16
            gradient: Gradient {
                GradientStop { position: 0.0; color: "black" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Idle: app name and a note
        Column {
            anchors.centerIn: parent
            visible: !root.loaded
            spacing: 3

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                visible: root.message.length === 0
                GlyphIcon {
                    width: 18
                    height: 20
                    kind: "note"
                    color: "#3e4033"
                    engraved: false
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "iMelodiae"
                    font.family: Theme.font
                    font.pixelSize: 17
                    color: "#3e4033"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.message.length > 0
                text: root.message
                font.family: Theme.font
                font.pixelSize: 12
                color: Theme.lcdText
                elide: Text.ElideRight
                width: Math.min(implicitWidth, lcd.width - 24)
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // Playing
        Item {
            anchors.fill: parent
            anchors.leftMargin: 26
            anchors.rightMargin: 26
            visible: root.loaded

            Text {
                id: titleText
                y: 3
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.message.length ? root.message : root.title
                font.family: Theme.font
                font.pixelSize: 12
                color: Theme.lcdText
                elide: Text.ElideRight
            }

            Text {
                id: infoText
                anchors.top: titleText.bottom
                anchors.topMargin: 1
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: {
                    const lines = [root.artist, root.album].filter(s => s.length > 0)
                    return lines.length ? lines[root.infoLine % lines.length] : ""
                }
                font.family: Theme.font
                font.pixelSize: 12
                color: Theme.lcdText
                elide: Text.ElideRight
                Behavior on text {
                    SequentialAnimation {
                        NumberAnimation { target: infoText; property: "opacity"; to: 0; duration: 150 }
                        PropertyAction {}
                        NumberAnimation { target: infoText; property: "opacity"; to: 1; duration: 150 }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.infoLine++
                }
            }

            Text {
                id: elapsed
                anchors.left: parent.left
                anchors.verticalCenter: bar.verticalCenter
                width: 38
                text: root.formatTime(scrub.pressed ? scrub.previewMs : root.position)
                font.family: Theme.font
                font.pixelSize: 11
                color: Theme.lcdText
            }

            Text {
                id: remaining
                anchors.right: parent.right
                anchors.verticalCenter: bar.verticalCenter
                width: 42
                horizontalAlignment: Text.AlignRight
                text: root.showRemaining
                      ? "-" + root.formatTime(root.duration - (scrub.pressed ? scrub.previewMs : root.position))
                      : root.formatTime(root.duration)
                font.family: Theme.font
                font.pixelSize: 11
                color: Theme.lcdText
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.showRemaining = !root.showRemaining
                }
            }

            Rectangle {
                id: bar
                anchors.left: elapsed.right
                anchors.right: remaining.left
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                height: 9
                color: "transparent"
                border.color: "#3f4136"
                radius: 1

                Rectangle {
                    x: 2
                    y: 2
                    height: parent.height - 4
                    width: Math.max(0, (parent.width - 4) * diamond.fraction)
                    color: "#4c4e40"
                }

                GlyphIcon {
                    id: diamond
                    readonly property real fraction: root.duration > 0
                        ? Math.min(1, (scrub.pressed ? scrub.previewMs : root.position) / root.duration) : 0
                    width: 11
                    height: 11
                    kind: "diamond"
                    color: "#202018"
                    engraved: false
                    anchors.verticalCenter: parent.verticalCenter
                    x: 2 + (parent.width - 4) * fraction - width / 2
                }

                MouseArea {
                    id: scrub
                    property int previewMs: 0
                    anchors.fill: parent
                    anchors.topMargin: -4
                    anchors.bottomMargin: -4
                    enabled: root.duration > 0
                    function msAt(x) {
                        return Math.round(Math.max(0, Math.min(1, (x - 2) / (bar.width - 4))) * root.duration)
                    }
                    onPressed: mouse => previewMs = msAt(mouse.x)
                    onPositionChanged: mouse => previewMs = msAt(mouse.x)
                    onReleased: root.seekRequested(previewMs)
                }
            }
        }

        // iTunes 5's two little round LCD buttons: cycle the info line (left), and
        // snapback to the playing song (right)
        component LcdRoundButton: Rectangle {
            id: lcdButton
            property string glyph
            signal clicked()
            width: 13
            height: 13
            radius: 6.5
            visible: root.loaded
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -4
            color: lcdMouse.pressed ? "#4c4e44" : "#80826f"
            GlyphIcon {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: lcdButton.glyph === "play" ? 0.5 : 0
                width: 7
                height: 7
                kind: lcdButton.glyph
                color: Theme.lcdUpper
                engraved: false
            }
            MouseArea {
                id: lcdMouse
                anchors.fill: parent
                anchors.margins: -4
                onClicked: lcdButton.clicked()
            }
        }

        LcdRoundButton {
            anchors.left: parent.left
            anchors.leftMargin: 7
            glyph: "play"
            onClicked: root.infoLine++
        }

        LcdRoundButton {
            anchors.right: parent.right
            anchors.rightMargin: 7
            glyph: "snapback"
            onClicked: root.snapbackClicked()
        }
    }

    Timer {
        interval: 3500
        repeat: true
        running: root.loaded
        onTriggered: root.infoLine++
    }
}
