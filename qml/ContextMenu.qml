import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// Right-click (or menu bar) menu. Items are { label, action, checked, enabled, shortcut,
// submenu } or { separator: true }; picking one emits its action. `shortcut` is just
// shown, greyed, at the right. An item with `submenu: true` opens `childMenu` beside it
// instead, and picking from that closes this menu too.
Popup {
    id: root

    property var items: []
    property var childMenu: null
    signal triggered(string action)

    readonly property bool childOpen: childMenu !== null && childMenu.opened
    // Closing the submenu because the pointer moved to another item, not because
    // something was picked or the user clicked away
    property bool switchingAway: false

    function openChild(row) {
        if (!childMenu || childMenu.opened)
            return
        childMenu.popupAt(row, row.width - 3, -4)
    }
    function closeChild() {
        if (childOpen) {
            switchingAway = true
            childMenu.close()
        }
    }

    Connections {
        target: root.childMenu
        function onClosed() {
            if (root.switchingAway)
                root.switchingAway = false
            else
                root.close()
        }
    }
    onClosed: closeChild()

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
    // Wide enough for the longest label and shortcut, plus the check-mark gutter and right margin
    readonly property real shortcutWidth: Math.max(0, ...items.map(i => metrics.advanceWidth(i.submenu ? "▸" : (i.shortcut ?? ""))))
    width: Math.max(160, 44 + Math.max(0, ...items.map(i => metrics.advanceWidth(i.label ?? "")))
                    + (shortcutWidth > 0 ? shortcutWidth + 28 : 0))
    modal: false
    focus: true
    // While the submenu is open, a click in it would count as outside this menu
    closePolicy: childOpen ? Popup.CloseOnEscape : Popup.CloseOnEscape | Popup.CloseOnPressOutside

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
            readonly property bool highlighted: active && (mouse.containsMouse || (item.submenu === true && root.childOpen))

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
                rightPadding: root.shortcutWidth > 0 ? root.shortcutWidth + 16 : 0
                font.family: Theme.font
                font.pixelSize: Theme.listFontSize + 1
                color: row.highlighted ? Theme.selectionText : row.active ? Theme.text : Theme.dimText
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: !!row.item.shortcut || row.item.submenu === true
                text: row.item.submenu ? "▸" : (row.item.shortcut ?? "")
                font.family: Theme.font
                font.pixelSize: row.item.submenu ? Theme.listFontSize + 5 : Theme.listFontSize + 1
                color: row.highlighted ? Theme.selectionText : row.item.submenu ? Theme.text : Theme.dimText
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                onEntered: {
                    if (row.item.submenu && row.active)
                        root.openChild(row)
                    else
                        root.closeChild()
                }
                onClicked: {
                    if (!row.active)
                        return
                    if (row.item.submenu) {
                        root.openChild(row)
                        return
                    }
                    root.close()
                    root.triggered(row.item.action)
                }
            }
        }
    }
}
