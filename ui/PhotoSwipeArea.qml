import QtQuick

// Left-button photo navigation at fit scale; the enclosing Flickable owns zoomed panning.
MouseArea {
    id: pointer
    property bool navigationEnabled: false
    property bool zoomed: false
    property bool canPrevious: false
    property bool canNext: false
    property string assetKey: ""
    property rect imageBounds: Qt.rect(0,0,width,height)
    readonly property real swipeThreshold: Math.max(64,Math.min(160,width*.12))
    property bool tracking: false
    property bool lastReleaseWasDrag: false
    property bool dragDetected: false
    property real startX: 0
    property real startY: 0
    property real deltaX: 0
    property real deltaY: 0
    property real visualOffset: 0
    NumberAnimation {id:rebound;target:pointer;property:"visualOffset";to:0;duration:180;easing.type:Easing.OutCubic}
    readonly property int readyDirection: tracking && Math.abs(deltaX)>=swipeThreshold && Math.abs(deltaX)>Math.abs(deltaY)*1.35
                                         ? (deltaX<0 ? (canNext?1:0) : (canPrevious?-1:0)) : 0
    signal navigate(int direction)
    signal zoomRequested(real x,real y)
    acceptedButtons: Qt.LeftButton
    preventStealing: tracking
    cursorShape: navigationEnabled||zoomed ? (pressed?Qt.ClosedHandCursor:Qt.OpenHandCursor) : Qt.ArrowCursor
    function cancelGesture() { rebound.stop();tracking=false;deltaX=0;deltaY=0;visualOffset=0 }
    function updateGesture(mouse) {
        if(!tracking)return
        if(!navigationEnabled||mouse.modifiers!==Qt.NoModifier){cancelGesture();return}
        const point=mapToItem(null,mouse.x,mouse.y)
        deltaX=point.x-startX;deltaY=point.y-startY
        if(Math.abs(deltaX)+Math.abs(deltaY)>12)dragDetected=true
        // Once a vertical gesture is clear, never reinterpret it as a page turn.
        if(Math.abs(deltaY)>12&&Math.abs(deltaY)>Math.abs(deltaX)*1.2){cancelGesture();return}
        visualOffset=deltaX
    }
    onNavigationEnabledChanged: if(!navigationEnabled)cancelGesture()
    onAssetKeyChanged: cancelGesture()
    onEnabledChanged: if(!enabled)cancelGesture()
    function beginGesture(mouse) {
        cancelGesture();dragDetected=false
        const point=mapToItem(null,mouse.x,mouse.y);startX=point.x;startY=point.y
        tracking=navigationEnabled&&mouse.modifiers===Qt.NoModifier
                 &&mouse.x>=imageBounds.x&&mouse.x<=imageBounds.x+imageBounds.width
                 &&mouse.y>=imageBounds.y&&mouse.y<=imageBounds.y+imageBounds.height
    }
    onPressed: mouse=>beginGesture(mouse)
    onPositionChanged: mouse=>updateGesture(mouse)
    onReleased: mouse=>{
        updateGesture(mouse)
        const direction=readyDirection
        lastReleaseWasDrag=dragDetected
        tracking=false;deltaX=0;deltaY=0
        // Let the renderer retain the outgoing texture's position before resetting the gesture.
        if(direction!==0){navigate(direction);visualOffset=0}
        else if(visualOffset!==0)rebound.restart()
    }
    onCanceled: cancelGesture()
    onDoubleClicked: mouse=>{if(lastReleaseWasDrag){beginGesture(mouse);return}cancelGesture();dragDetected=false;zoomRequested(mouse.x,mouse.y)}
    Rectangle {
        visible:pointer.readyDirection!==0
        width:40;height:40;radius:20;color:"#d920292d"
        x:pointer.readyDirection<0?18:parent.width-width-18
        anchors.verticalCenter:parent.verticalCenter
        Glyph {anchors.centerIn:parent;width:22;height:22;name:pointer.readyDirection<0?"chevronLeft":"chevronRight";ink:"white"}
    }
}
