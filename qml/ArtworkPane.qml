import QtQuick
import org.imelodiae

// Album artwork viewer under the Source list. Click the header to switch
// between the selected song and the song that's playing.
Rectangle {
    id: root

    property string source: ""
    property bool showingNowPlaying: true
    // Whether there's a song to show art for (playing, or selected)
    property bool hasSong: false
    signal toggleMode()

    color: Theme.sourceBackground
    clip: true
    implicitHeight: width + header.height

    ListHeader {
        id: header
        width: parent.width
        text: root.showingNowPlaying ? qsTr("Now Playing") : qsTr("Selected Song")
        alignment: Text.AlignHCenter
        sourceStyle: true
        onClicked: root.toggleMode()
    }

    Item {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        Image {
            id: art
            anchors.fill: parent
            anchors.margins: 1
            source: root.source
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
            sourceSize.width: 512
            sourceSize.height: 512
        }

        Text {
            anchors.fill: parent
            anchors.margins: 12
            visible: art.status !== Image.Ready
            text: root.hasSong ? qsTr("No artwork\navailable") : root.showingNowPlaying ? qsTr("Nothing\nPlaying") : qsTr("No Song\nSelected")
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            font.family: Theme.font
            font.pixelSize: Theme.listFontSize
            color: Theme.dimText
        }
    }
}
