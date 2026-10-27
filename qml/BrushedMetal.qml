import QtQuick
import org.imelodiae

// Brushed-aluminium window background: a soft vertical gradient overlaid
// with a procedurally drawn, horizontally tiling grain texture.
Rectangle {
    id: root

    gradient: Gradient {
        GradientStop { position: 0.0; color: Theme.metalTop }
        GradientStop { position: 0.55; color: "#c4c4c4" }
        GradientStop { position: 1.0; color: Theme.metalBottom }
    }

    Image {
        id: grain
        anchors.fill: parent
        fillMode: Image.Tile
        opacity: 0.35
        smooth: false
    }

    Canvas {
        id: grainCanvas
        width: 512
        height: 256
        visible: false

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            let seed = 1979
            const rand = () => {
                seed = (seed * 16807) % 2147483647
                return seed / 2147483647
            }
            for (let i = 0; i < 2600; ++i) {
                const y = Math.floor(rand() * height) + 0.5
                const x = rand() * width
                const len = 40 + rand() * 260
                const light = rand() > 0.5
                ctx.strokeStyle = light ? Qt.rgba(1, 1, 1, 0.05 + rand() * 0.12)
                                        : Qt.rgba(0, 0, 0, 0.03 + rand() * 0.07)
                ctx.beginPath()
                ctx.moveTo(x, y)
                ctx.lineTo(x + len, y)
                // Wrap around so the tile repeats seamlessly
                if (x + len > width) {
                    ctx.moveTo(x - width, y)
                    ctx.lineTo(x + len - width, y)
                }
                ctx.stroke()
            }
        }
        // toDataURL() itself emits painted(), so only export the texture once
        property bool exported: false
        onPainted: {
            if (exported)
                return
            exported = true
            grain.source = toDataURL("image/png")
        }
        Component.onCompleted: requestPaint()
    }
}
