import QtQuick
import QtQuick.Shapes

// Small vector glyphs (transport, speaker, shuffle, ...) as SVG paths on a 16×16 grid,
// scaled to the item's size. Rendered by the scene graph, so they stay crisp.
Item {
    id: root

    property string kind: "play"
    property color color: "#2e2e2e"
    // Aqua's engraved-metal look: a light one-pixel emboss under the glyph
    property bool engraved: true

    implicitWidth: 16
    implicitHeight: 16

    function gearPath() {
        let d = ""
        for (let i = 0; i < 16; ++i) {
            const a = i * Math.PI / 8
            const r = i % 2 === 0 ? 7.4 : 5.2
            for (const da of [-0.2, 0.2]) {
                const x = 8 + Math.cos(a + da) * r
                const y = 8 + Math.sin(a + da) * r
                d += (d === "" ? "M" : "L") + x.toFixed(2) + " " + y.toFixed(2) + " "
            }
        }
        // Centre hole (odd-even fill punches it out)
        return d + "Z M10.3 8 A2.3 2.3 0 1 1 10.29 7.99 Z"
    }

    // fill: filled path; stroke/strokeWidth: outlined path; stroke2/strokeWidth2: second
    // outline; knockout: drawn in white on top (e.g. the × of the clear button)
    readonly property var glyphs: ({
        play: { fill: "M4 2 L14.5 8 L4 14 Z" },
        pause: { fill: "M3 2.5 H6.5 V13.5 H3 Z M9.5 2.5 H13 V13.5 H9.5 Z" },
        next: { fill: "M1 3 L8 8 L1 13 Z M8 3 L15 8 L8 13 Z" },
        prev: { fill: "M15 3 L8 8 L15 13 Z M8 3 L1 8 L8 13 Z" },
        speakerLow: { fill: "M1 6 H4 L8 2 V14 L4 10 H1 Z" },
        speaker: {
            fill: "M1 6 H4 L8 2 V14 L4 10 H1 Z",
            stroke: "M10 5.5 A3.5 3.5 0 0 1 10 10.5 M11.5 3.2 A6 6 0 0 1 11.5 12.8",
            strokeWidth: 1.3
        },
        speakerHigh: {
            fill: "M1 6 H4 L8 2 V14 L4 10 H1 Z",
            stroke: "M10 5.8 A3 3 0 0 1 10 10.2 M11.5 3.8 A5.4 5.4 0 0 1 11.5 12.2 M13 1.8 A8 8 0 0 1 13 14.2",
            strokeWidth: 1.1
        },
        shuffle: {
            fill: "M11.5 1.5 L15.5 4.5 L11.5 7.5 Z M11.5 8.5 L15.5 11.5 L11.5 14.5 Z",
            stroke: "M0.5 4.5 C6 4.5 6.5 11.5 12 11.5 M0.5 11.5 C6 11.5 6.5 4.5 12 4.5",
            strokeWidth: 1.6
        },
        repeat: {
            fill: "M9 1 L12.5 3.5 L9 6 Z M7 10 L3.5 12.5 L7 15 Z",
            stroke: "M9.5 3.5 H4 A2.5 2.5 0 0 0 1.5 6 V10 A2.5 2.5 0 0 0 4 12.5 H6.5 M9.5 12.5 H12 A2.5 2.5 0 0 0 14.5 10 V6 A2.5 2.5 0 0 0 12 3.5 H10",
            strokeWidth: 1.6
        },
        repeatOne: {
            fill: "M9 1 L12.5 3.5 L9 6 Z M7 10 L3.5 12.5 L7 15 Z M7.2 6 L8.6 5.2 H9.4 V10.8 H8.2 V6.8 L7.2 7.3 Z",
            stroke: "M9.5 3.5 H4 A2.5 2.5 0 0 0 1.5 6 V10 A2.5 2.5 0 0 0 4 12.5 H6.5 M9.5 12.5 H12 A2.5 2.5 0 0 0 14.5 10 V6 A2.5 2.5 0 0 0 12 3.5 H10",
            strokeWidth: 1.6
        },
        plus: { fill: "M6.8 2 H9.2 V6.8 H14 V9.2 H9.2 V14 H6.8 V9.2 H2 V6.8 H6.8 Z" },
        eye: {
            fill: "M10.8 8 A2.8 2.8 0 1 1 10.79 7.99 Z",
            stroke: "M1 8 Q8 0.5 15 8 Q8 15.5 1 8 Z",
            strokeWidth: 1.4
        },
        artwork: {
            fill: "M3 12 L6.5 6.5 L10 12 Z M8 12 L11 8.5 L13.5 12 Z M12.2 4.6 A1.2 1.2 0 1 1 12.19 4.59 Z",
            stroke: "M1.5 2.5 H14.5 V13.5 H1.5 Z",
            strokeWidth: 1.4
        },
        magnifier: {
            stroke: "M10.5 6.5 A4 4 0 1 1 10.49 6.49 Z",
            strokeWidth: 1.7,
            stroke2: "M9.6 9.6 L14.6 14.6",
            strokeWidth2: 2.6
        },
        clear: {
            fill: "M16 8 A8 8 0 1 1 15.99 7.99 Z",
            knockout: "M5 5 L11 11 M11 5 L5 11"
        },
        note: {
            fill: "M1.6 12.4 A3 2.2 0 1 0 7.6 12.4 A3 2.2 0 1 0 1.6 12.4 Z M6.2 2 H7.8 V12.4 H6.2 Z M7.8 2 C8.5 5 13.5 5.5 12.2 10.5 C11.8 7.6 9.8 6.6 7.8 6.4 Z"
        },
        gear: { fill: gearPath(), oddEven: true },
        up: { fill: "M2 12 L8 4 L14 12 Z" },
        down: { fill: "M2 4 L8 12 L14 4 Z" },
        diamond: { fill: "M8 0 L16 8 L8 16 L0 8 Z" },
        snapback: {
            fill: "M0.8 2.5 L7.2 3.6 L2.6 8.4 Z",
            stroke: "M4.6 5.2 A5 5 0 1 1 5.8 13.6",
            strokeWidth: 1.7
        }
    })

    readonly property var glyph: glyphs[kind] ?? {}

    component Layer: Shape {
        id: layer
        property color tint
        property bool showKnockout: false
        width: 16
        height: 16
        preferredRendererType: Shape.CurveRenderer
        transform: Scale {
            xScale: root.width / 16
            yScale: root.height / 16
        }

        ShapePath {
            strokeColor: "transparent"
            fillColor: layer.tint
            fillRule: root.glyph.oddEven ? ShapePath.OddEvenFill : ShapePath.WindingFill
            PathSvg { path: root.glyph.fill ?? "" }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: layer.tint
            strokeWidth: root.glyph.strokeWidth ?? 1.5
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.glyph.stroke ?? "" }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: layer.tint
            strokeWidth: root.glyph.strokeWidth2 ?? 1.5
            capStyle: ShapePath.RoundCap
            PathSvg { path: root.glyph.stroke2 ?? "" }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: layer.showKnockout ? "white" : "transparent"
            strokeWidth: 1.8
            capStyle: ShapePath.RoundCap
            PathSvg { path: root.glyph.knockout ?? "" }
        }
    }

    Layer {
        visible: root.engraved
        y: 1
        tint: Qt.rgba(1, 1, 1, 0.6)
    }

    Layer {
        tint: root.color
        showKnockout: true
    }
}
