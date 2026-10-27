import QtQuick
import org.imelodiae

// Round brushed-metal button (transport controls, Browse)
Item {
    id: root

    property alias glyph: icon.kind
    property real glyphScale: 0.42
    property string label: ""
    property bool checked: false
    property real diameter: 32
    signal clicked()

    implicitWidth: Math.max(diameter, labelText.implicitWidth)
    implicitHeight: diameter + (label.length ? labelText.implicitHeight + 1 : 0)

    // Soft drop shadow
    Rectangle {
        x: face.x
        y: face.y + 1
        width: root.diameter
        height: root.diameter
        radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.6)
    }

    Rectangle {
        id: face
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.diameter
        height: root.diameter
        radius: width / 2
        border.color: "#5e5e5e"
        border.width: 1

        readonly property bool down: mouse.pressed && mouse.containsMouse
        gradient: Gradient {
            GradientStop { position: 0.0; color: face.down || root.checked ? "#a9a9a9" : "#fdfdfd" }
            GradientStop { position: 0.48; color: face.down || root.checked ? "#8f8f8f" : "#d9d9d9" }
            GradientStop { position: 0.52; color: face.down || root.checked ? "#858585" : "#c4c4c4" }
            GradientStop { position: 1.0; color: face.down || root.checked ? "#b4b4b4" : "#f0f0f0" }
        }

        // Specular highlight
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 2
            width: parent.width * 0.62
            height: parent.height * 0.34
            radius: height / 2
            opacity: face.down ? 0.15 : 0.7
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#ffffff" }
                GradientStop { position: 1.0; color: "#00ffffff" }
            }
        }

        GlyphIcon {
            id: icon
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: kind === "play" ? 1 : 0
            width: Math.round(root.diameter * root.glyphScale)
            height: width
            color: root.enabled ? (root.checked ? Theme.activeGlyph : "#272727") : "#8a8a8a"
        }
    }

    Text {
        id: labelText
        visible: root.label.length > 0
        anchors.top: face.bottom
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.label
        font.family: Theme.font
        font.pixelSize: Theme.smallFontSize
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
