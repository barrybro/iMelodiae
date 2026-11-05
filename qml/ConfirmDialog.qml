import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// A small modal question, like a Mac OS X alert sheet: a bold heading, a line of
// explanation, Cancel and a default button. Return confirms, Escape cancels.
Popup {
    id: root

    property string heading: ""
    property string message: ""
    property string confirmText: qsTr("OK")
    signal confirmed()

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round(Math.max(0, (parent.height - height) / 3))
    width: 380
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape

    function confirm() {
        close()
        confirmed()
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.18)
    }

    background: Rectangle {
        border.color: "#6b6b6b"
        radius: 4
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#e9e9e9" }
            GradientStop { position: 1.0; color: "#f6f6f6" }
        }
    }

    // Aqua push button; the default one is blue gel
    component AlertButton: Rectangle {
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
        implicitHeight: buttons.y + buttons.height + 14
        focus: true
        Keys.onReturnPressed: root.confirm()
        Keys.onEnterPressed: root.confirm()

        Text {
            id: title
            x: 18
            y: 16
            width: parent.width - 36
            wrapMode: Text.Wrap
            text: root.heading
            font.family: Theme.font
            font.pixelSize: 13
            font.bold: true
            color: Theme.text
        }
        Text {
            id: body
            anchors.left: title.left
            anchors.right: title.right
            anchors.top: title.bottom
            anchors.topMargin: 8
            wrapMode: Text.Wrap
            text: root.message
            font.family: Theme.font
            font.pixelSize: Theme.listFontSize
            color: Theme.text
        }
        Row {
            id: buttons
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: body.y + body.height + 16
            spacing: 10

            AlertButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }
            AlertButton {
                text: root.confirmText
                isDefault: true
                onClicked: root.confirm()
            }
        }
    }
}
