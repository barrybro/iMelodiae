import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// Rounded Aqua search field with an engraved "Search" caption beneath
Item {
    id: root

    property alias text: field.text
    property alias field: field

    implicitWidth: 160
    implicitHeight: box.height + caption.implicitHeight + 2

    Rectangle {
        id: box
        width: parent.width
        height: 22
        radius: height / 2
        color: "white"
        border.color: field.activeFocus ? "#5b8fdd" : "#6b6b6b"
        border.width: field.activeFocus ? 2 : 1

        // Inner top shadow
        Rectangle {
            x: 4
            y: 1
            width: parent.width - 8
            height: 3
            radius: 1.5
            opacity: 0.18
            gradient: Gradient {
                GradientStop { position: 0.0; color: "black" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        GlyphIcon {
            id: loupe
            anchors.left: parent.left
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            width: 11
            height: 11
            kind: "magnifier"
            color: "#4d4d4d"
            engraved: false
        }

        TextField {
            id: field
            anchors.left: loupe.right
            anchors.right: clear.left
            anchors.leftMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height - 2
            padding: 0
            leftPadding: 2
            font.family: Theme.font
            font.pixelSize: Theme.listFontSize
            color: Theme.text
            selectionColor: "#b5d5ff"
            selectedTextColor: Theme.text
            verticalAlignment: TextInput.AlignVCenter
            background: null
            Keys.onEscapePressed: { text = ""; focus = false }
        }

        GlyphIcon {
            id: clear
            anchors.right: parent.right
            anchors.rightMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            width: 13
            height: 13
            kind: "clear"
            color: "#9a9a9a"
            engraved: false
            visible: field.text.length > 0
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.ArrowCursor
                onClicked: field.text = ""
            }
        }
    }

    Text {
        id: caption
        anchors.top: box.bottom
        anchors.topMargin: 2
        anchors.horizontalCenter: parent.horizontalCenter
        text: qsTr("Search")
        font.family: Theme.font
        font.pixelSize: Theme.smallFontSize
        color: Theme.engravedText
        style: Text.Raised
        styleColor: Theme.engravedHighlight
    }
}
