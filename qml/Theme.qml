pragma Singleton
import QtQuick

// Colours and fonts sampled from iTunes 5 (2005): smooth "unified" grey metal,
// flush panes with dark hairline dividers and a pale blue-grey source list
QtObject {
    readonly property string font: "Lucida Grande"
    readonly property int listFontSize: 11
    readonly property int smallFontSize: 10

    // Unified toolbar / bottom bar metal
    readonly property color toolbarTop: "#d2d2d1"
    readonly property color toolbarUpper: "#c5c5c4"
    readonly property color toolbarBottom: "#969596"
    readonly property color barTop: "#c5c5c4"
    readonly property color barBottom: "#949393"
    readonly property color divider: "#404040"
    readonly property color engravedText: "#1e1e1e"
    readonly property color engravedHighlight: "#d9d9d9"

    // Source list
    readonly property color sourceBackground: "#e7edf6"
    readonly property color sourceSelectionTop: "#a8b7cd"
    readonly property color sourceSelectionBottom: "#96a6be"
    readonly property color sourceSelectionLine: "#8d9db5"

    // Lists
    readonly property color rowEven: "#ffffff"
    readonly property color rowOdd: "#edf3fe"
    readonly property color selection: "#3d80df"
    readonly property color selectionText: "#ffffff"
    readonly property color gridLine: "#d9d9d9"
    readonly property color frame: "#404040"
    readonly property color text: "#000000"
    readonly property color dimText: "#808080"

    // List column headers: a glossy white bar, aqua blue for the sorted column
    readonly property color headerTop: "#f9f9f9"
    readonly property color headerMid: "#e8e8e8"
    readonly property color headerBottom: "#ffffff"
    readonly property color headerLine: "#b9b9b9"
    readonly property color headerBottomLine: "#7a7a7a"
    readonly property color sortedTop: "#acceee"
    readonly property color sortedMid: "#6aaaeb"
    readonly property color sortedBottom: "#b8faff"

    // Darker grey header used above the source list and artwork
    readonly property color sourceHeaderTop: "#e9e9e9"
    readonly property color sourceHeaderBottom: "#9a9a9a"

    // LCD
    readonly property color lcdTop: "#eef0e4"
    readonly property color lcdUpper: "#dcdfd0"
    readonly property color lcdLower: "#d6dbbf"
    readonly property color lcdBottom: "#c3c7ae"
    readonly property color lcdBorder: "#56584c"
    readonly property color lcdText: "#1c1c18"

    // Aqua gel (scroll thumbs, toggled buttons)
    readonly property color gelTop: "#b9d6fb"
    readonly property color gelMid: "#4f8ef0"
    readonly property color gelBottom: "#2f6fd8"
    readonly property color activeGlyph: "#2a62d4"
}
