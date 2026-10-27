pragma Singleton
import QtQuick

// Colours and fonts lifted from the 2004-era Aqua / brushed-metal look
QtObject {
    readonly property string font: "Lucida Grande"
    readonly property int listFontSize: 11
    readonly property int smallFontSize: 10

    // Brushed metal
    readonly property color metalTop: "#e3e3e3"
    readonly property color metalBottom: "#a9a9a9"
    readonly property color metalEdge: "#6f6f6f"
    readonly property color engravedText: "#2b2b2b"
    readonly property color engravedHighlight: "#f2f2f2"

    // Lists
    readonly property color rowEven: "#ffffff"
    readonly property color rowOdd: "#edf3fe"
    readonly property color selection: "#3875d7"
    readonly property color selectionText: "#ffffff"
    readonly property color gridLine: "#d9d9d9"
    readonly property color frame: "#6b6b6b"
    readonly property color text: "#000000"
    readonly property color dimText: "#808080"

    // List column headers
    readonly property color headerTop: "#ffffff"
    readonly property color headerMid: "#ebebeb"
    readonly property color headerBottom: "#d4d4d4"
    readonly property color headerLine: "#a3a3a3"
    readonly property color sortedTop: "#c5dbfc"
    readonly property color sortedMid: "#87b4f6"
    readonly property color sortedBottom: "#5d98ef"

    // LCD
    readonly property color lcdTop: "#f4f5e4"
    readonly property color lcdBottom: "#d6dcbd"
    readonly property color lcdBorder: "#5f6152"
    readonly property color lcdText: "#202018"

    // Aqua gel (scroll thumbs, toggled buttons)
    readonly property color gelTop: "#b9d6fb"
    readonly property color gelMid: "#4f8ef0"
    readonly property color gelBottom: "#2f6fd8"
    readonly property color activeGlyph: "#2a62d4"
}
