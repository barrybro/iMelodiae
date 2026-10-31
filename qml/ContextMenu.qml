import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// Right-click menu. Items are { label, action, checked, enabled } or { separator: true };
// picking one emits its action.
Popup {
    id: root

    property var items: []
    signal triggered(string action)

    // Open with the top-left corner at a point in `item`'s coordinates
    function popupAt(item, x, y) {
        const p = item.mapToItem(Overlay.overlay, x, y)
        root.x = p.x
        root.y = p.y
        open()
    }

    parent: Overlay.overlay
    // Keep the whole menu inside the window
    margins: 4
    padding: 0
    topPadding: 4
    bottomPadding: 4
    // Wide enough for the longest label, plus the check-mark gutter and right margin
    width: Math.max(160, 44 + Math.max(0, ...items.map(i => metrics.advanceWidth(i.label ?? ""))))
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    FontMetrics {
        id: metrics
        font.family: Theme.font
        font.pixelSize: Theme.listFontSize + 1
    }

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

    contentItem: Column {
        id: column

        Repeater {
            model: root.items
            delegate: Loader {
                required property var modelData
                sourceComponent: modelData.separator ? separator : menuRow
                property var entry: modelData
            }
        }
    }

    Component {
        id: separator
        Item {
            width: root.width
            height: 9
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 2
                height: 1
                color: "#dcdcdc"
            }
        }
    }

    Component {
        id: menuRow
        Rectangle {
            id: row
            readonly property var item: parent ? parent.entry : ({})
            readonly property bool active: item.enabled !== false
            readonly property bool highlighted: active && mouse.containsMouse

            width: root.width
            height: 20
            color: highlighted ? Theme.selection : "transparent"

            Text {
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: row.item.checked === true
                text: "✓"
                font.family: Theme.font
                font.pixelSize: Theme.listFontSize
                color: row.highlighted ? Theme.selectionText : row.active ? Theme.text : Theme.dimText
            }
            Text {
                id: label
                x: 24
                width: parent.width - x - 12
                anchors.verticalCenter: parent.verticalCenter
                text: row.item.label ?? ""
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.listFontSize + 1
                color: row.highlighted ? Theme.selectionText : row.active ? Theme.text : Theme.dimText
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (!row.active)
                        return
                    root.close()
                    root.triggered(row.item.action)
                }
            }
        }
    }
}
