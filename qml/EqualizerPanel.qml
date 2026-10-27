import QtQuick
import QtQuick.Controls.Basic
import org.imelodiae

// The iTunes 5 Equalizer window: On switch, preset menu, preamp and ten bands.
// Lives inside the main window as a floating panel you can drag by its title bar.
Popup {
    id: root

    property bool enabled_: false
    property real preamp: 0
    property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property string preset: "Flat"

    signal edited(bool enabled, real preamp, var bands, string preset)

    // Approximations of iTunes' built-in presets: band gains in dB, 32 Hz … 16 kHz
    readonly property var presets: ({
        "Acoustic": [5, 4.9, 3.95, 1.05, 2.15, 1.75, 3.5, 4.1, 3.55, 2.15],
        "Bass Booster": [5.5, 4.35, 3.5, 2.5, 1.25, 0, 0, 0, 0, 0],
        "Bass Reducer": [-5.5, -4.35, -3.5, -2.5, -1.25, 0, 0, 0, 0, 0],
        "Classical": [4.75, 3.75, 3, 2.5, -1.5, -1.5, 0, 2.25, 3.25, 3.75],
        "Dance": [3.57, 6.55, 4.99, 0, 1.92, 3.65, 5.15, 4.54, 3.59, 0],
        "Deep": [4.95, 3.55, 1.75, 1, 2.85, 2.5, 1.45, -2.15, -3.55, -4.6],
        "Electronic": [4.25, 3.8, 1.2, 0, -2.15, 2.25, 0.85, 1.25, 3.95, 4.8],
        "Flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Hip-Hop": [5, 4.25, 1.5, 3, -1, -1, 1.5, -0.5, 2, 3],
        "Jazz": [4, 3, 1.5, 2.25, -1.5, -1.5, 0, 1.5, 3, 3.75],
        "Latin": [4.5, 3, 0, 0, -1.5, -1.5, -1.5, 0, 3, 4.5],
        "Loudness": [6, 4, 0, 0, -2, 0, -1, -5, 5, 1],
        "Lounge": [-3, -1.5, -0.5, 1.5, 4, 2.5, 0, -1.5, 2, 1],
        "Piano": [3, 2, 0, 2.5, 3, 1.5, 3.5, 4.5, 3, 3.5],
        "Pop": [-1.5, -1, 0, 2, 4, 4, 2, 0, -1, -1.5],
        "R&B": [2.6, 6.92, 5.65, 1.33, -2.19, -1.5, 2.32, 2.65, 3, 3.75],
        "Rock": [5, 4, 3, 1.5, -0.5, -1, 0.5, 2.5, 3.5, 4.5],
        "Small Speakers": [5.5, 4.25, 3.5, 2.5, 1.25, 0, -1.25, -2.5, -3.5, -4.25],
        "Spoken Word": [-3.46, -0.47, 0, 0.69, 3.46, 4.61, 4.84, 4.28, 2.54, 0],
        "Treble Booster": [0, 0, 0, 0, 0, 1.25, 2.5, 3.5, 4.25, 5.5],
        "Treble Reducer": [0, 0, 0, 0, 0, -1.25, -2.5, -3.5, -4.25, -5.5],
        "Vocal Booster": [-1.5, -3, -3, 1.5, 3.75, 3.75, 3, 1.5, 0, -1.5]
    })
    readonly property var frequencies: ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]

    function setBand(i, db) {
        const next = bands.slice()
        next[i] = db
        edited(enabled_, preamp, next, qsTr("Manual"))
    }

    function choosePreset(name) {
        // Picking a preset switches the equalizer on, as in iTunes
        edited(true, preamp, presets[name].slice(), name)
    }

    width: 372
    height: 228
    padding: 0
    modal: false
    closePolicy: Popup.CloseOnEscape

    background: Item {
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            anchors.bottomMargin: -4
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.25)
        }
        Rectangle {
            anchors.fill: parent
            radius: 4
            border.color: "#4a4a4a"
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.toolbarTop }
                GradientStop { position: 0.12; color: Theme.toolbarUpper }
                GradientStop { position: 1.0; color: Theme.barBottom }
            }
        }
    }

    contentItem: Item {
        // Title bar: drag to move, round button to close
        Item {
            id: titleBar
            width: parent.width
            height: 20

            Rectangle {
                id: closeButton
                x: 7
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                border.color: "#8e2a22"
                gradient: Gradient {
                    GradientStop { position: 0.0; color: closeMouse.pressed ? "#b8332a" : "#ff8a7a" }
                    GradientStop { position: 1.0; color: closeMouse.pressed ? "#7d1d16" : "#d9352a" }
                }
                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    anchors.margins: -3
                    onClicked: root.close()
                }
            }

            Text {
                anchors.centerIn: parent
                text: qsTr("Equalizer")
                font.family: Theme.font
                font.pixelSize: 12
                color: "#1a1a1a"
                style: Text.Raised
                styleColor: "#e2e2e2"
            }

            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: 24
                cursorShape: Qt.SizeAllCursor
                property point grab
                onPressed: mouse => grab = Qt.point(mouse.x, mouse.y)
                onPositionChanged: mouse => {
                    const w = root.parent ? root.parent.width : 1000
                    const h = root.parent ? root.parent.height : 800
                    root.x = Math.max(0, Math.min(w - root.width, root.x + mouse.x - grab.x))
                    root.y = Math.max(0, Math.min(h - root.height, root.y + mouse.y - grab.y))
                }
            }
        }

        // On checkbox
        Row {
            id: onRow
            x: 16
            y: 30
            spacing: 5

            Rectangle {
                id: checkbox
                width: 14
                height: 14
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                border.color: root.enabled_ ? "#2457b0" : "#6b6b6b"
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.enabled_ ? Theme.gelTop : "#ffffff" }
                    GradientStop { position: 0.5; color: root.enabled_ ? Theme.gelMid : "#e9e9e9" }
                    GradientStop { position: 1.0; color: root.enabled_ ? "#8cc0ff" : "#f8f8f8" }
                }
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    visible: root.enabled_
                    text: "✓"
                    font.pixelSize: 12
                    font.bold: true
                    color: "#0d2a5c"
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("On")
                font.family: Theme.font
                font.pixelSize: Theme.listFontSize + 1
                color: Theme.engravedText
            }
        }
        MouseArea {
            anchors.fill: onRow
            anchors.margins: -3
            onClicked: root.edited(!root.enabled_, root.preamp, root.bands, root.preset)
        }

        // Preset pop-up button
        Rectangle {
            id: presetButton
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 27
            width: 168
            height: 20
            radius: 4
            border.color: "#555555"
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#ffffff" }
                GradientStop { position: 0.5; color: "#ededed" }
                GradientStop { position: 0.51; color: "#e0e0e0" }
                GradientStop { position: 1.0; color: "#f6f6f6" }
            }
            Text {
                x: 9
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 32
                text: root.preset
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.listFontSize + 1
            }
            // Aqua blue arrow cap
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 1
                width: 18
                radius: 3
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.gelTop }
                    GradientStop { position: 0.5; color: Theme.gelMid }
                    GradientStop { position: 1.0; color: "#8cc0ff" }
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    GlyphIcon { width: 7; height: 5; kind: "up"; color: "#0d2a5c"; engraved: false }
                    GlyphIcon { width: 7; height: 5; kind: "down"; color: "#0d2a5c"; engraved: false }
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: presetMenu.open()
            }

            Popup {
                id: presetMenu
                y: -Math.min(implicitHeight, 300) / 2
                width: presetButton.width
                height: Math.min(implicitHeight, 300)
                padding: 0
                topPadding: 4
                bottomPadding: 4
                background: Rectangle {
                    radius: 5
                    color: Qt.rgba(1, 1, 1, 0.97)
                    border.color: "#8e8e8e"
                }
                contentItem: ListView {
                    id: presetList
                    clip: true
                    implicitHeight: contentHeight
                    model: Object.keys(root.presets)
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: AquaScrollBar {}
                    delegate: Rectangle {
                        id: presetRow
                        required property string modelData
                        width: ListView.view.width
                        height: 19
                        color: rowMouse.containsMouse ? Theme.selection : "transparent"
                        Text {
                            x: 7
                            anchors.verticalCenter: parent.verticalCenter
                            visible: presetRow.modelData === root.preset
                            text: "✓"
                            font.pixelSize: Theme.listFontSize
                            color: rowMouse.containsMouse ? "white" : Theme.text
                        }
                        Text {
                            x: 22
                            anchors.verticalCenter: parent.verticalCenter
                            text: presetRow.modelData
                            font.family: Theme.font
                            font.pixelSize: Theme.listFontSize + 1
                            color: rowMouse.containsMouse ? "white" : Theme.text
                        }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.choosePreset(presetRow.modelData)
                                presetMenu.close()
                            }
                        }
                    }
                }
            }
        }

        // Slider area
        component EqSlider: Item {
            id: slider
            property real value: 0
            property string label: ""
            signal moved(real value)

            width: 24
            height: sliderArea.height

            readonly property real travel: groove.height - knob.height

            Rectangle {
                id: groove
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                width: 5
                height: 122
                radius: 2.5
                border.color: "#5a5a5a"
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#7b7b7b" }
                    GradientStop { position: 1.0; color: "#d4d4d4" }
                }
            }

            Rectangle {
                id: knob
                anchors.horizontalCenter: parent.horizontalCenter
                width: 15
                height: 11
                radius: 5.5
                y: (1 - (slider.value + 12) / 24) * slider.travel
                border.color: "#4f4f4f"
                gradient: Gradient {
                    GradientStop { position: 0.0; color: drag.pressed ? "#c0c0c0" : "#ffffff" }
                    GradientStop { position: 0.5; color: drag.pressed ? "#9a9a9a" : "#d0d0d0" }
                    GradientStop { position: 1.0; color: drag.pressed ? "#bcbcbc" : "#f4f4f4" }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 7
                    height: 1
                    color: "#7a7a7a"
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: groove.bottom
                anchors.topMargin: 5
                text: slider.label
                font.family: Theme.font
                font.pixelSize: Theme.smallFontSize
                color: Theme.engravedText
            }

            MouseArea {
                id: drag
                x: 0
                width: parent.width
                height: groove.height
                function update(my) {
                    const v = 12 - 24 * Math.max(0, Math.min(1, (my - knob.height / 2) / slider.travel))
                    // Snap gently to 0 dB
                    slider.moved(Math.abs(v) < 0.4 ? 0 : Math.round(v * 10) / 10)
                }
                onPressed: mouse => update(mouse.y)
                onPositionChanged: mouse => update(mouse.y)
                onDoubleClicked: slider.moved(0)
                onWheel: wheel => slider.moved(Math.max(-12, Math.min(12, slider.value + (wheel.angleDelta.y > 0 ? 0.5 : -0.5))))
            }
        }

        Item {
            id: sliderArea
            x: 14
            y: 64
            width: parent.width - 28
            height: 150

            // 0 dB guide line across the bands
            Rectangle {
                x: bandRow.x
                width: bandRow.width
                y: 61
                height: 1
                color: Qt.rgba(0, 0, 0, 0.25)
            }

            EqSlider {
                id: preampSlider
                x: 0
                label: qsTr("Preamp")
                value: root.preamp
                onMoved: v => root.edited(root.enabled_, v, root.bands, root.preset)
            }

            Column {
                x: preampSlider.width + 10
                width: 40
                Repeater {
                    model: ["+12 dB", "0 dB", "-12 dB"]
                    Text {
                        required property string modelData
                        required property int index
                        width: 40
                        height: index === 1 ? 52 : 35
                        verticalAlignment: index === 0 ? Text.AlignTop : index === 1 ? Text.AlignVCenter : Text.AlignBottom
                        horizontalAlignment: Text.AlignRight
                        text: modelData
                        font.family: Theme.font
                        font.pixelSize: Theme.smallFontSize - 1
                        color: Theme.engravedText
                    }
                }
            }

            Row {
                id: bandRow
                x: preampSlider.width + 56
                spacing: 2
                Repeater {
                    model: 10
                    EqSlider {
                        required property int index
                        label: root.frequencies[index]
                        value: root.bands[index] ?? 0
                        onMoved: v => root.setBand(index, v)
                    }
                }
            }
        }
    }
}
