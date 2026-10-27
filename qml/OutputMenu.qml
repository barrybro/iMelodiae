import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// Pop-up menu for choosing where audio plays: the system default or a specific device
Popup {
    id: root

    required property var player
    signal picked(string id, string name)

    readonly property string currentName: {
        const i = player.outputIds.indexOf(player.output)
        return player.output === "" || i < 0 ? qsTr("System Default") : player.outputNames[i]
    }

    padding: 0
    topPadding: 4
    bottomPadding: 4
    width: Math.max(220, column.implicitWidth)
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // A press on the menu's own button closes it before the click arrives;
    // remember when, so that click doesn't immediately reopen it
    property double closedAt: 0
    onClosed: closedAt = Date.now()
    function toggle() {
        if (Date.now() - closedAt > 250)
            open()
    }

    onAboutToShow: player.refreshOutputs()

    background: Item {
        // Soft shadow
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            anchors.topMargin: 1
            anchors.bottomMargin: -3
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.18)
        }
        Rectangle {
            anchors.fill: parent
            radius: 5
            color: Qt.rgba(1, 1, 1, 0.97)
            border.color: "#8e8e8e"
        }
    }

    component MenuRow: Rectangle {
        id: row
        property string deviceId
        property string name
        readonly property bool current: root.player.output === deviceId

        width: root.width
        height: 20
        color: mouse.containsMouse ? Theme.selection : "transparent"

        Text {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            visible: row.current
            text: "✓"
            font.family: Theme.font
            font.pixelSize: Theme.listFontSize
            color: mouse.containsMouse ? Theme.selectionText : Theme.text
        }
        Text {
            x: 24
            width: parent.width - x - 12
            anchors.verticalCenter: parent.verticalCenter
            text: row.name
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.listFontSize + 1
            color: mouse.containsMouse ? Theme.selectionText : Theme.text
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                root.picked(row.deviceId, row.name)
                root.close()
            }
        }
    }

    contentItem: Column {
        id: column

        Text {
            x: 10
            height: 18
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Audio Output")
            font.family: Theme.font
            font.pixelSize: Theme.smallFontSize
            font.bold: true
            color: Theme.dimText
        }

        MenuRow {
            deviceId: ""
            name: qsTr("System Default")
        }

        Rectangle {
            x: 1
            width: root.width - 2
            height: 9
            color: "transparent"
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: 1
                color: "#dcdcdc"
            }
        }

        Repeater {
            model: root.player.outputIds
            delegate: MenuRow {
                required property string modelData
                required property int index
                deviceId: modelData
                name: root.player.outputNames[index] ?? modelData
            }
        }

        Text {
            x: 24
            height: 20
            visible: root.player.outputIds.length === 0
            verticalAlignment: Text.AlignVCenter
            text: qsTr("No other outputs found")
            font.family: Theme.font
            font.pixelSize: Theme.listFontSize
            color: Theme.dimText
        }
    }
}
