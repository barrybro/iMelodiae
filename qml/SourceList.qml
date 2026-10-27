import QtQuick
import org.imelodiae

// Left-hand "Source" list: the Library and a few smart playlists
Rectangle {
    id: root

    property int current: 0
    signal picked(int source)

    color: "white"
    clip: true

    readonly property var sources: [
        { name: qsTr("Library"), icon: "library" },
        { name: qsTr("Recently Added"), icon: "smart" },
        { name: qsTr("Top 25 Most Played"), icon: "smart" },
        { name: qsTr("Recently Played"), icon: "smart" }
    ]

    ListHeader {
        id: header
        width: parent.width
        text: qsTr("Source")
    }

    Column {
        anchors.top: header.bottom
        anchors.topMargin: 2
        width: parent.width

        Repeater {
            model: root.sources

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool isSelected: root.current === index

                width: root.width
                height: 20
                color: isSelected ? Theme.selection : "transparent"

                // Source icon: a little blue "music" box for the library,
                // a purple gear box for smart playlists
                Rectangle {
                    id: badge
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 15
                    height: 15
                    radius: 3
                    border.color: row.modelData.icon === "library" ? "#2c5aa7" : "#5a3a9b"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: row.modelData.icon === "library" ? "#a9cbff" : "#d4b8ff" }
                        GradientStop { position: 1.0; color: row.modelData.icon === "library" ? "#3d7be0" : "#7a4fd0" }
                    }
                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 10
                        height: 11
                        kind: row.modelData.icon === "library" ? "note" : "gear"
                        color: "white"
                        engraved: false
                    }
                }

                Text {
                    anchors.left: badge.right
                    anchors.leftMargin: 6
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.name
                    font.family: Theme.font
                    font.pixelSize: Theme.listFontSize
                    color: row.isSelected ? Theme.selectionText : Theme.text
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.picked(row.index)
                }
            }
        }
    }
}
