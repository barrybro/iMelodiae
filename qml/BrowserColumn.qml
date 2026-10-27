import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// One column of the Genre / Artist / Album browser
Rectangle {
    id: root

    property string title: ""
    property string pluralNoun: ""
    property var items: []
    property string selected: ""
    signal picked(string value)

    color: "white"
    clip: true

    ListHeader {
        id: header
        width: parent.width
        text: root.title
        alignment: Text.AlignHCenter
    }

    ListView {
        id: list
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: [""].concat(root.items)
        ScrollBar.vertical: AquaScrollBar {}

        delegate: Rectangle {
            id: row
            required property string modelData
            required property int index
            readonly property bool isSelected: modelData.toLowerCase() === root.selected.toLowerCase()

            width: ListView.view.width
            height: 17
            color: isSelected ? Theme.selection : "white"

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: row.index === 0
                      ? qsTr("All (%1 %2)").arg(root.items.length).arg(root.pluralNoun)
                      : row.modelData
                font.family: Theme.font
                font.pixelSize: Theme.listFontSize
                font.bold: row.index === 0
                color: row.isSelected ? Theme.selectionText : Theme.text
                elide: Text.ElideRight
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.picked(row.modelData)
            }
        }
    }
}
