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
    property real previewZoom: 1
    property int decodeEdge: 2000
    property bool shareDecodedImage: false
    property bool retainedImage: false
    property string displayedSource: ""
    property real gestureOffset: 0
    property string heldSwipeSource: ""
    property real heldSwipeOffset: 0
    property var heldSwipeGeometry: ({})
    property int heldDecodeEdge: 2000
    property real arrivalOffset: 0
    property real arrivalStart: 0
    readonly property bool slideRunning: arrival.running
    readonly property real presentationOffset: heldSwipeSource !== "" && heldSwipeSource === displayedSource ? heldSwipeOffset : arrival.running ? arrivalOffset : gestureOffset
    function holdSwipePosition() {
        heldSwipeOffset = gestureOffset; heldSwipeGeometry = textureGeometry;
        heldDecodeEdge = decodeEdge; heldSwipeSource = displayedSource;
    }
    function clearSwipePosition() { heldSwipeSource = ""; heldSwipeOffset = 0; }
    NumberAnimation {
        id: arrival; target: preview; property: "arrivalOffset"; to: 0; duration: 200; easing.type: Easing.OutCubic
        onFinished: preview.clearSwipePosition()
    }
    property var displayedGeometry: ({width:1,height:1,canvasWidth:1,canvasHeight:1,centerX:0,centerY:0,angle:0})
    readonly property bool currentTexture: displayedSource !== "" && displayedSource === source.toString()
    readonly property var textureGeometry: currentTexture ? ({width:sourceWidth,height:sourceHeight,canvasWidth:canvasWidth,canvasHeight:canvasHeight,centerX:imageCenterX,centerY:imageCenterY,angle:angle}) : displayedGeometry
    readonly property real textureScale: Math.min(width / Math.max(1, textureGeometry.canvasWidth), height / Math.max(1, textureGeometry.canvasHeight))
    readonly property real fitScale: Math.min(width / Math.max(1, canvasWidth), height / Math.max(1, canvasHeight))
    readonly property real paintedWidth: canvasWidth * fitScale
    readonly property real paintedHeight: canvasHeight * fitScale
    readonly property alias status: texture.status
    readonly property bool ready: currentTexture && (texture.status === Image.Ready || (texture.status === Image.Loading && retainedImage))
    // Capture only a settled frame's geometry. Incoming metadata can change
    // before source, so coalesce those changes until all bindings have updated.
    function rememberGeometry() {
        if (currentTexture && (texture.status === Image.Ready || texture.status === Image.Loading))
            displayedGeometry = textureGeometry;
    }
    onTextureGeometryChanged: Qt.callLater(rememberGeometry)
    onPreviewZoomChanged: detailTimer.restart()
    onSourceChanged: {
        if (arrival.running) { arrival.stop(); clearSwipePosition(); }
        arrivalOffset = 0; detailTimer.stop(); retainedImage = false; decodeEdge = 2000;
    }
    Timer {
        id: detailTimer; interval: 180
        onTriggered: {
            let edge = 2000;
            while (edge < 2000 * preview.previewZoom && edge < 8192) edge *= 2;
            // Retain the highest requested detail for this image while browsing.
            preview.decodeEdge = Math.max(preview.decodeEdge, Math.min(8192, edge));
        }
    }
    function reload() {
        texture.source = "";
        texture.source = Qt.binding(function() { return preview.source; });
    }

    // Reuse the decoded texture while rotating. The center comes from the same
    // integer canvas transform used by export, including its rounding offset.
    Image {
        id: texture
        objectName: "rotatedImage"
        source: preview.source
        sourceSize.width: preview.decodeEdge; sourceSize.height: preview.decodeEdge
        asynchronous: true; cache: preview.shareDecodedImage; smooth: true; mipmap: true; retainWhileLoading: true
        onStatusChanged: if (status === Image.Ready) {
            // The retained outgoing texture stays where it was released. Start the
            // incoming slide in the same update that installs the new texture.
            const swiped = preview.heldSwipeSource !== "" && preview.heldSwipeSource !== source.toString();
            if (swiped) {
                preview.arrivalOffset = preview.heldSwipeOffset < 0 ? preview.width : -preview.width;
                preview.arrivalStart = preview.arrivalOffset;
                arrival.restart();
            }
            preview.displayedSource = source.toString();
            if (!swiped) preview.clearSwipePosition();
            preview.retainedImage = true;
            Qt.callLater(preview.rememberGeometry);
        } else if (status === Image.Error || status === Image.Null) {
            arrival.stop();
            preview.clearSwipePosition();
        }
        visible: source.toString() !== "" && status !== Image.Error && status !== Image.Null
        // A retained texture belongs to the previous image until the new one
        // is ready. Keep its source geometry, rotation and canvas together.
        width: preview.textureGeometry.width * preview.textureScale
        height: preview.textureGeometry.height * preview.textureScale
        x: (preview.width-preview.textureGeometry.canvasWidth*preview.textureScale)/2 + preview.textureGeometry.centerX*preview.textureScale - width/2
        y: (preview.height-preview.textureGeometry.canvasHeight*preview.textureScale)/2 + preview.textureGeometry.centerY*preview.textureScale - height/2
        rotation: preview.textureGeometry.angle
        transformOrigin: Item.Center
    }
    // Reuse the outgoing decoded texture during the slide so the incoming image
    // and outgoing image move together, without a blank frame between them.
    Image {
        id: outgoing; objectName: "outgoingSwipeImage"
        source: preview.shareDecodedImage ? preview.heldSwipeSource : ""
        sourceSize.width: preview.heldDecodeEdge; sourceSize.height: preview.heldDecodeEdge
        asynchronous: true; cache: true; smooth: true; mipmap: true
        visible: arrival.running && status === Image.Ready
        readonly property var geometry: preview.heldSwipeGeometry
        readonly property real scaleToFit: Math.min(preview.width / Math.max(1, geometry.canvasWidth || 1), preview.height / Math.max(1, geometry.canvasHeight || 1))
        width: (geometry.width || 1) * scaleToFit
        height: (geometry.height || 1) * scaleToFit
        x: (preview.width - (geometry.canvasWidth || 1) * scaleToFit) / 2 + (geometry.centerX || 0) * scaleToFit - width / 2
           + preview.heldSwipeOffset + preview.arrivalOffset - preview.arrivalStart - preview.presentationOffset
        y: (preview.height - (geometry.canvasHeight || 1) * scaleToFit) / 2 + (geometry.centerY || 0) * scaleToFit - height / 2
        rotation: geometry.angle || 0
        transformOrigin: Item.Center
    }
}
