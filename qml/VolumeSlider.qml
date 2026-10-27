import QtQuick
import org.imelodiae

// Volume control: speaker - groove with a metal knob - loud speaker
Item {
    id: root

    property real value: 0.75
    signal moved(real value)

    implicitWidth: 120
    implicitHeight: 14

    GlyphIcon {
        id: low
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 10
        height: 10
        kind: "speakerLow"
        MouseArea { anchors.fill: parent; onClicked: root.moved(0) }
    }

    Item {
        id: track
        anchors.left: low.right
        anchors.right: high.left
        anchors.leftMargin: 5
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height

        Rectangle {
            id: groove
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 5
            radius: 2.5
            border.color: "#5a5a5a"
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#7b7b7b" }
                GradientStop { position: 1.0; color: "#d4d4d4" }
            }
        }

        Rectangle {
            id: knob
            width: 13
            height: 13
            radius: 6.5
            anchors.verticalCenter: parent.verticalCenter
            x: root.value * (track.width - width)
            border.color: "#4f4f4f"
            gradient: Gradient {
                GradientStop { position: 0.0; color: dragArea.pressed ? "#c0c0c0" : "#ffffff" }
                GradientStop { position: 0.5; color: dragArea.pressed ? "#9a9a9a" : "#d0d0d0" }
                GradientStop { position: 1.0; color: dragArea.pressed ? "#bcbcbc" : "#f4f4f4" }
            }
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            anchors.leftMargin: -3
            anchors.rightMargin: -3
            function update(mx) {
                root.moved(Math.max(0, Math.min(1, (mx - knob.width / 2) / (track.width - knob.width))))
            }
            onPressed: mouse => update(mouse.x)
            onPositionChanged: mouse => update(mouse.x)
            onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.value + wheel.angleDelta.y / 1200)))
        }
    }

    GlyphIcon {
        id: high
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        height: 11
        kind: "speakerHigh"
        MouseArea { anchors.fill: parent; onClicked: root.moved(1) }
    }
}
