import QtQuick

Flickable {
    id: viewport
    property real imageWidth: 1
    property real imageHeight: 1
    property real zoom: 1
    property bool gesturesEnabled: true
    readonly property real fitScale: Math.min(width / Math.max(1, imageWidth), height / Math.max(1, imageHeight))
    readonly property real fillZoom: Math.max(width / Math.max(1, imageWidth), height / Math.max(1, imageHeight)) / Math.max(.000001, fitScale)
    readonly property real maximumZoom: Math.max(16, fillZoom * 2)
    readonly property real paintedWidth: imageWidth * fitScale * zoom
    readonly property real paintedHeight: imageHeight * fitScale * zoom
    contentWidth: Math.max(width, paintedWidth)
    contentHeight: Math.max(height, paintedHeight)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: gesturesEnabled && zoom > 1

    function clampPosition() {
        contentX = Math.max(0, Math.min(contentX, contentWidth - width));
        contentY = Math.max(0, Math.min(contentY, contentHeight - height));
    }
    function resetZoom() {
        cancelFlick(); zoom = 1; contentX = 0; contentY = 0;
    }
    function zoomAt(value, x, y, centerPoint) {
        if (!gesturesEnabled || width <= 0 || height <= 0) return;
        const next = Math.max(1, Math.min(maximumZoom, value));
        if (Math.abs(next - zoom) < .000001) return;
        // Keep the image coordinate under the pointer; double-click instead
        // brings that coordinate to the viewport center, clamped at the edges.
        const u = (contentX + x - (contentWidth - paintedWidth) / 2) / Math.max(1, paintedWidth);
        const v = (contentY + y - (contentHeight - paintedHeight) / 2) / Math.max(1, paintedHeight);
        cancelFlick(); zoom = next;
        contentX = (contentWidth - paintedWidth) / 2 + u * paintedWidth - (centerPoint ? width / 2 : x);
        contentY = (contentHeight - paintedHeight) / 2 + v * paintedHeight - (centerPoint ? height / 2 : y);
        clampPosition();
    }
    function toggleZoomAt(x, y) {
        if (zoom > 1.000001) resetZoom();
        else zoomAt(fillZoom, x, y, true);
    }
    onContentWidthChanged: clampTimer.restart()
    onContentHeightChanged: clampTimer.restart()
    onWidthChanged: clampTimer.restart()
    onHeightChanged: clampTimer.restart()
    Timer { id: clampTimer; interval: 0; onTriggered: viewport.clampPosition() }
    WheelHandler {
        parent: viewport
        target: null
        enabled: viewport.gesturesEnabled
        acceptedModifiers: Qt.ControlModifier
        onWheel: event => {
            const delta = event.pixelDelta.y || event.angleDelta.y;
            if (!delta) return;
            const point = viewport.contentItem.mapToItem(viewport, event.x, event.y);
            viewport.zoomAt(viewport.zoom * Math.exp(delta * .0015), point.x, point.y, false);
            event.accepted = true;
        }
    }
    // Middle-button drag remains available over the crop box, whose left-button
    // drag edits the crop. No changes are made to the crop's image coordinates.
    DragHandler {
        parent: viewport
        target: null
        enabled: viewport.interactive
        acceptedButtons: Qt.MiddleButton
        property real startX: 0
        property real startY: 0
        onActiveChanged: if (active) { viewport.cancelFlick(); startX = viewport.contentX; startY = viewport.contentY; }
        onTranslationChanged: {
            if (!active) return;
            viewport.contentX = startX - translation.x;
            viewport.contentY = startY - translation.y;
            viewport.clampPosition();
        }
    }
}
