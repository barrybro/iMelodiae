import QtQuick
import org.imelodiae

// Small rounded-rectangle metal button for the bottom bar (add, shuffle, repeat, artwork)
Item {
    id: root

    property alias glyph: icon.kind
    property bool checked: false
    property string tooltip: ""
    signal clicked()

    implicitWidth: 30
    implicitHeight: 23

    Rectangle {
        anchors.fill: face
        anchors.topMargin: 1
        anchors.bottomMargin: -1
        radius: face.radius
        color: Qt.rgba(1, 1, 1, 0.55)
    }

    Rectangle {
        id: face
        anchors.fill: parent
        radius: 5
        border.color: "#5f5f5f"

        readonly property bool down: (mouse.pressed && mouse.containsMouse) || root.checked
        gradient: Gradient {
            GradientStop { position: 0.0; color: face.down ? "#9c9c9c" : "#fbfbfb" }
            GradientStop { position: 0.5; color: face.down ? "#8a8a8a" : "#dcdcdc" }
            GradientStop { position: 0.51; color: face.down ? "#808080" : "#cbcbcb" }
            GradientStop { position: 1.0; color: face.down ? "#a5a5a5" : "#ececec" }
        }

        GlyphIcon {
            id: icon
            anchors.centerIn: parent
            width: 15
            height: 13
            color: root.checked ? Theme.activeGlyph : "#2a2a2a"
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: root.tooltip.length > 0
        onClicked: root.clicked()
    }

    Rectangle {
        // Lightweight tooltip, Mac-style pale yellow
        visible: mouse.containsMouse && hoverTimer.fired
        y: -height - 6
        x: (root.width - width) / 2
        width: tipText.implicitWidth + 10
        height: tipText.implicitHeight + 4
        color: "#ffffc7"
        border.color: "#8c8c6e"
        z: 100
        Text {
            id: tipText
            anchors.centerIn: parent
            text: root.tooltip
            font.family: Theme.font
            font.pixelSize: Theme.smallFontSize
        }
    }

    Timer {
        id: hoverTimer
        property bool fired: false
        interval: 700
        running: mouse.containsMouse
        onTriggered: fired = true
        onRunningChanged: if (!running) fired = false
    }
}
