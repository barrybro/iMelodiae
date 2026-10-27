import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// Aqua scroll bar: pinstriped trough with a blue gel thumb
ScrollBar {
    id: root

    readonly property bool isVertical: orientation === Qt.Vertical
    policy: size < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
    implicitWidth: isVertical ? 15 : 100
    implicitHeight: isVertical ? 100 : 15
    padding: 1
    minimumSize: 0.06

    background: Rectangle {
        gradient: Gradient {
            orientation: root.isVertical ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: 0.0; color: "#c8c8c8" }
            GradientStop { position: 0.3; color: "#ededed" }
            GradientStop { position: 1.0; color: "#f7f7f7" }
        }
        Rectangle {
            width: root.isVertical ? 1 : parent.width
            height: root.isVertical ? parent.height : 1
            color: "#a8a8a8"
        }
    }

    contentItem: Rectangle {
        implicitWidth: 13
        implicitHeight: 13
        radius: 6.5
        border.color: "#2457b0"
        gradient: Gradient {
            orientation: root.isVertical ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: 0.0; color: root.pressed ? "#3a74d1" : Theme.gelMid }
            GradientStop { position: 0.35; color: root.pressed ? "#a3c5f6" : Theme.gelTop }
            GradientStop { position: 0.55; color: root.pressed ? "#5b92e6" : "#79a9f4" }
            GradientStop { position: 1.0; color: root.pressed ? "#1f58b8" : Theme.gelBottom }
        }
        // Glossy highlight streak
        Rectangle {
            x: root.isVertical ? 3 : 4
            y: root.isVertical ? 4 : 2
            width: root.isVertical ? 4 : parent.width - 8
            height: root.isVertical ? parent.height - 8 : 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.45)
        }
    }
}
