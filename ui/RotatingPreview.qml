import QtQuick

Item {
    id: preview
    property url source
    property real angle: 0
    property real sourceWidth: 1
    property real sourceHeight: 1
    property real canvasWidth: 1
    property real canvasHeight: 1
    property real imageCenterX: 0
    property real imageCenterY: 0
    readonly property real fitScale: Math.min(width / Math.max(1, canvasWidth), height / Math.max(1, canvasHeight))
    readonly property real paintedWidth: canvasWidth * fitScale
    readonly property real paintedHeight: canvasHeight * fitScale
    readonly property alias status: texture.status

    // Reuse the decoded texture while rotating. The center comes from the same
    // integer canvas transform used by export, including its rounding offset.
    Image {
        id: texture
        objectName: "rotatedImage"
        source: preview.source
        sourceSize.width: 2000; sourceSize.height: 2000
        asynchronous: true; cache: false; smooth: true; mipmap: true
        width: preview.sourceWidth * preview.fitScale
        height: preview.sourceHeight * preview.fitScale
        x: (preview.width-preview.paintedWidth)/2 + preview.imageCenterX*preview.fitScale - width/2
        y: (preview.height-preview.paintedHeight)/2 + preview.imageCenterY*preview.fitScale - height/2
        rotation: preview.angle
        transformOrigin: Item.Center
    }
}
