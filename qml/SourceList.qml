import QtQuick
import org.imelodiae

// Left-hand "Source" list: the Library and a few smart playlists, on iTunes 5's
// pale blue-grey background with a slate-blue selection bar
Rectangle {
    id: root

    property int current: 0
    signal picked(int source)

    color: Theme.sourceBackground
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
        alignment: Text.AlignHCenter
        sourceStyle: true
        grip: true
    }

    Column {
        anchors.top: header.bottom
        width: parent.width

        Repeater {
            model: root.sources

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool isSelected: root.current === index
                readonly property bool isLibrary: modelData.icon === "library"

                width: root.width
                height: 18
                gradient: Gradient {
                    GradientStop { position: 0.0; color: row.isSelected ? Theme.sourceSelectionTop : "transparent" }
                    GradientStop { position: 1.0; color: row.isSelected ? Theme.sourceSelectionBottom : "transparent" }
                }

                Rectangle {
                    visible: row.isSelected
                    width: parent.width
                    height: 1
                    color: Theme.sourceSelectionLine
                }

                // Library: golden music box. Smart playlist: lavender page with a purple gear.
                Rectangle {
                    id: badge
                    x: 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    radius: row.isLibrary ? 2 : 1
                    border.color: row.isLibrary ? "#6f5200" : "#6a5a96"
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: row.isLibrary ? "#ffe27a" : "#f1ebff" }
                        GradientStop { position: 1.0; color: row.isLibrary ? "#c8961b" : "#c9bdeb" }
                    }
                    GlyphIcon {
                        anchors.centerIn: parent
                        width: row.isLibrary ? 9 : 10
                        height: row.isLibrary ? 10 : 10
                        kind: row.isLibrary ? "note" : "gear"
                        color: row.isLibrary ? "#2a1e00" : "#3c2a78"
                        engraved: false
                    }
                }

                Text {
                    anchors.left: badge.right
                    anchors.leftMargin: 5
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.name
                    font.family: Theme.font
                    font.pixelSize: Theme.listFontSize + 1
                    font.bold: row.isSelected
                    color: row.isSelected ? Theme.selectionText : Theme.text
                    style: row.isSelected ? Text.Sunken : Text.Normal
                    styleColor: "#5b6b84"
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
