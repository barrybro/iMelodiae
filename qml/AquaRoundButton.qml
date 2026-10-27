import QtQuick
import org.imelodiae

// Round iTunes 5 toolbar button: white face, grey ring, darker when pressed
Item {
    id: root

    property alias glyph: icon.kind
    property real glyphScale: 0.42
    property string label: ""
    property bool checked: false
    property real diameter: 32
    signal clicked()

    implicitWidth: Math.max(diameter, labelText.implicitWidth)
    implicitHeight: diameter + (label.length ? labelText.implicitHeight + 2 : 0)

    // Light bevel under the ring
    Rectangle {
        x: face.x
        y: face.y + 1
        width: root.diameter
        height: root.diameter
        radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.45)
    }

    Rectangle {
        id: face
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.diameter
        height: root.diameter
        radius: width / 2
        border.color: "#6c6c6c"
        border.width: 1

        readonly property bool down: (mouse.pressed && mouse.containsMouse) || root.checked
        // Lit from below, like the real thing: grey at the top, nearly white at the bottom
        gradient: Gradient {
            GradientStop { position: 0.0; color: face.down ? "#a6a6a6" : "#dedede" }
            GradientStop { position: 0.45; color: face.down ? "#b8b8b8" : "#ececec" }
            GradientStop { position: 0.8; color: face.down ? "#cdcdcd" : "#f8f8f8" }
            GradientStop { position: 1.0; color: face.down ? "#d8d8d8" : "#ffffff" }
        }

        // Inner ring highlight
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, face.down ? 0.2 : 0.8)
        }

        GlyphIcon {
            id: icon
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: kind === "play" ? 1 : 0
            width: Math.round(root.diameter * root.glyphScale)
            height: width
            color: root.enabled ? "#2b2b2b" : "#8a8a8a"
        }
    }

    Text {
        id: labelText
        visible: root.label.length > 0
        anchors.top: face.bottom
        anchors.topMargin: 2
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.label
        font.family: Theme.font
        font.pixelSize: Theme.listFontSize
        color: Theme.engravedText
        style: Text.Raised
        styleColor: Theme.engravedHighlight
    }

    MouseArea {
        id: mouse
        anchors.fill: face
        enabled: root.enabled
        onClicked: root.clicked()
    }
}
