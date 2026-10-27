import QtQuick
import org.imelodiae

// One column header cell: the glossy white iTunes 5 header, aqua blue when it's the
// column the list is sorted by, or the darker grey "source" style above the source list.
Rectangle {
    id: root

    property string text: ""
    property bool sorted: false
    property bool ascending: true
    property int alignment: Text.AlignLeft
    property bool sourceStyle: false
    // Show the ||| resize grip at the right edge
    property bool grip: false
    signal clicked()

    implicitHeight: 17
    clip: true

    gradient: Gradient {
        GradientStop {
            position: 0.0
            color: root.sourceStyle ? Theme.sourceHeaderTop : root.sorted ? Theme.sortedTop : Theme.headerTop
        }
        GradientStop {
            position: 0.4
            color: root.sourceStyle ? "#d6d6d6" : root.sorted ? "#88b8e9" : "#f0f0f0"
        }
        GradientStop {
            position: 0.5
            color: root.sourceStyle ? "#c4c4c4" : root.sorted ? Theme.sortedMid : Theme.headerMid
        }
        GradientStop {
            position: 0.7
            color: root.sourceStyle ? "#b0b0b0" : root.sorted ? "#86c2f8" : "#f2f2f2"
        }
        GradientStop {
            position: 1.0
            color: root.sourceStyle ? Theme.sourceHeaderBottom : root.sorted ? Theme.sortedBottom : Theme.headerBottom
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.headerBottomLine
    }
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: 1
        visible: !root.sourceStyle
        color: Theme.headerLine
    }

    Text {
        anchors.left: parent.left
        anchors.right: arrow.visible ? arrow.left : parent.right
        anchors.leftMargin: 5
        anchors.rightMargin: root.grip ? 14 : 4
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        horizontalAlignment: root.alignment
        font.family: Theme.font
        font.pixelSize: Theme.listFontSize
        color: root.sourceStyle ? "#1e1e1e" : Theme.text
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
        color: "#10203a"
        engraved: false
    }

    // |||
    Row {
        visible: root.grip
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Repeater {
            model: 3
            Rectangle {
                width: 1
                height: 9
                color: "#6e6e6e"
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
