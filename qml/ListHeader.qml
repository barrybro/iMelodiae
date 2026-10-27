import QtQuick
import org.imelodiae

// One column header cell: the glossy light-grey Aqua header,
// or blue when it's the column the list is sorted by.
Rectangle {
    id: root

    property string text: ""
    property bool sorted: false
    property bool ascending: true
    property int alignment: Text.AlignLeft
    signal clicked()

    implicitHeight: 17
    clip: true

    gradient: Gradient {
        GradientStop { position: 0.0; color: root.sorted ? Theme.sortedTop : Theme.headerTop }
        GradientStop { position: 0.5; color: root.sorted ? Theme.sortedMid : Theme.headerMid }
        GradientStop { position: 0.51; color: root.sorted ? Theme.sortedBottom : Theme.headerBottom }
        GradientStop { position: 1.0; color: root.sorted ? "#a8c8f8" : "#f0f0f0" }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.headerLine
    }
    Rectangle {
        anchors.right: parent.right
        height: parent.height
        width: 1
        color: Theme.headerLine
    }

    Text {
        anchors.left: parent.left
        anchors.right: arrow.visible ? arrow.left : parent.right
        anchors.leftMargin: 5
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        horizontalAlignment: root.alignment
        font.family: Theme.font
        font.pixelSize: Theme.listFontSize
        color: Theme.text
        elide: Text.ElideRight
    }

    GlyphIcon {
        id: arrow
        visible: root.sorted
        anchors.right: parent.right
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        width: 8
        height: 7
        kind: root.ascending ? "up" : "down"
        color: "#1f3f7a"
        engraved: false
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
