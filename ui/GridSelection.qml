import QtQuick

Item {
    id: selectionArea
    required property var gridView
    required property var records
    required property var selectedIds
    property real cardGap: 0
    property var priorSelection: []
    property bool dragging: false
    property bool gestureCancelled: false
    property bool wasDragging: false
    property int pressedIndex: -1
    property string pressedId: ""
    readonly property bool rangeGesture: pressedIndex >= 0
    property real anchorX: 0
    property real anchorY: 0
    property real endX: 0
    property real endY: 0
    property real pointerX: 0
    property real pointerY: 0
    property real pressX: 0
    property real pressY: 0
    readonly property int hoveredIndex: enabled && selectionMouse.containsMouse ? indexAt(selectionMouse.mouseX,selectionMouse.mouseY) : -1
    readonly property int downIndex: enabled && selectionMouse.pressed && !dragging && !gestureCancelled ? pressedIndex : -1
    signal selectionRequested(var ids)
    signal focusRequested(string id)
    signal activated(string id)
    clip: true
    z: 10

    function indexAt(x, y) {
        // GridView can move its origin after resizing, filtering or removing rows.
        // Hit-test the rendered delegate instead of assuming row zero starts at y=0.
        const point=gridView.contentItem.mapFromItem(selectionArea,x,y);
        const index=gridView.indexAt(point.x,point.y);
        if(index<0||index>=records.length)return -1;
        const card=gridView.itemAtIndex(index);
        if(!card)return -1;
        const local=card.mapFromItem(selectionArea,x,y);
        if(local.x<0||local.y<0||local.x>=card.width||local.y>=card.height)return -1;
        return index;
    }
    function updateSelection() {
        if(!dragging||gestureCancelled)return;
        endX=Math.max(0,Math.min(selectionMouse.width,pointerX))+gridView.contentX;
        endY=Math.max(0,Math.min(height,pointerY))+gridView.contentY;
        const ids=new Set(priorSelection);
        if(rangeGesture) {
            // A drag starting on a photo follows display order, like selecting
            // text across lines. Gaps and the incomplete last row clamp to a card.
            const column=Math.max(0,Math.min(gridView.columns-1,Math.floor(endX/gridView.cellWidth)));
            const row=Math.max(0,Math.floor((endY-gridView.originY)/gridView.cellHeight));
            const last=Math.min(records.length-1,row*gridView.columns+column);
            for(let i=Math.min(pressedIndex,last);i<=Math.max(pressedIndex,last);++i)ids.add(records[i].id);
            selectionRequested(Array.from(ids));
            return;
        }
        const left=Math.min(anchorX,endX),right=Math.max(anchorX,endX);
        const top=Math.min(anchorY,endY),bottom=Math.max(anchorY,endY);
        for(let i=0;i<records.length;++i) {
            const x=(i%gridView.columns)*gridView.cellWidth;
            const y=gridView.originY+Math.floor(i/gridView.columns)*gridView.cellHeight;
            if(x<=right&&x+gridView.cellWidth-cardGap>=left&&y<=bottom&&y+gridView.cellHeight-cardGap>=top)ids.add(records[i].id);
        }
        selectionRequested(Array.from(ids));
    }
    function cancelGesture() {
        if(dragging)selectionRequested(priorSelection.slice());
        dragging=false;gestureCancelled=true;
    }
    onEnabledChanged: if(!enabled)cancelGesture()
    onVisibleChanged: if(!visible)cancelGesture()
    onRecordsChanged: cancelGesture()
    onWidthChanged: cancelGesture()
    onHeightChanged: cancelGesture()
    Connections {
        target: selectionArea.gridView
        function onCellWidthChanged(){selectionArea.cancelGesture()}
        function onCellHeightChanged(){selectionArea.cancelGesture()}
    }
    Rectangle {
        visible: selectionArea.dragging && !selectionArea.rangeGesture
        x: Math.min(selectionArea.anchorX,selectionArea.endX)-selectionArea.gridView.contentX
        y: Math.min(selectionArea.anchorY,selectionArea.endY)-selectionArea.gridView.contentY
        width: Math.abs(selectionArea.endX-selectionArea.anchorX)
        height: Math.abs(selectionArea.endY-selectionArea.anchorY)
        color: Theme.alpha(Theme.primary,.15);border.color:Theme.primary;border.width:1;radius:2
    }
    MouseArea {
        id: selectionMouse
        objectName: "batchSelectionMouse"
        anchors.fill: parent;anchors.rightMargin:14
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        hoverEnabled: true
        cursorShape: selectionArea.dragging ? (selectionArea.rangeGesture ? Qt.PointingHandCursor : Qt.CrossCursor) : selectionArea.hoveredIndex>=0 ? Qt.PointingHandCursor : Qt.ArrowCursor
        scrollGestureEnabled: false
        onWheel: wheel=>{wheel.accepted=false}
        onPressed: mouse=>{
            const index=selectionArea.indexAt(mouse.x,mouse.y);
            const card=index>=0?selectionArea.gridView.itemAtIndex(index):null;
            if(card&&typeof card.playbackControlAt==="function"&&card.playbackControlAt(selectionMouse,mouse.x,mouse.y)) {
                mouse.accepted=false;return;
            }
            selectionArea.priorSelection=selectionArea.selectedIds.slice();
            selectionArea.dragging=false;selectionArea.wasDragging=false;selectionArea.gestureCancelled=false;
            selectionArea.pressedIndex=selectionArea.indexAt(mouse.x,mouse.y);
            selectionArea.pressedId=selectionArea.pressedIndex>=0?selectionArea.records[selectionArea.pressedIndex].id:"";
            selectionArea.pressX=mouse.x;selectionArea.pressY=mouse.y;
            selectionArea.pointerX=mouse.x;selectionArea.pointerY=mouse.y;
            selectionArea.anchorX=mouse.x+selectionArea.gridView.contentX;
            selectionArea.anchorY=mouse.y+selectionArea.gridView.contentY;
            if(selectionArea.pressedId)selectionArea.focusRequested(selectionArea.pressedId);
        }
        onPositionChanged: mouse=>{
            if(!pressed||selectionArea.gestureCancelled)return;
            selectionArea.pointerX=mouse.x;selectionArea.pointerY=mouse.y;
            if(!selectionArea.dragging&&Math.hypot(mouse.x-selectionArea.pressX,mouse.y-selectionArea.pressY)>=Qt.styleHints.startDragDistance){
                selectionArea.dragging=true;selectionArea.wasDragging=true;
            }
            selectionArea.updateSelection();
        }
        onReleased: mouse=>{
            selectionArea.pointerX=mouse.x;selectionArea.pointerY=mouse.y;
            if(selectionArea.dragging)selectionArea.updateSelection();
            selectionArea.dragging=false;
        }
        onClicked: mouse=>{
            if(selectionArea.wasDragging||selectionArea.gestureCancelled||selectionArea.pressedIndex<0)return;
            const id=selectionArea.pressedId;
            const ids=selectionArea.selectedIds.slice(),index=ids.indexOf(id);
            if(index>=0)ids.splice(index,1);else ids.push(id);
            selectionArea.selectionRequested(ids);
        }
        onDoubleClicked: mouse=>{
            const index=selectionArea.indexAt(mouse.x,mouse.y);
            if(index>=0&&!selectionArea.wasDragging&&!selectionArea.gestureCancelled&&selectionArea.records[index].id===selectionArea.pressedId){
                selectionArea.gestureCancelled=true;
                selectionArea.activated(selectionArea.pressedId);
            }
        }
        onCanceled: selectionArea.cancelGesture()
    }
    Timer {
        interval: 30;repeat:true;running:selectionArea.dragging&&selectionMouse.pressed
        onTriggered: {
            const edge=40,y=selectionArea.pointerY;
            let speed=y<edge?-Math.min(20,(edge-y)/2):y>selectionArea.height-edge?Math.min(20,(y-selectionArea.height+edge)/2):0;
            if(speed===0)return;
            const grid=selectionArea.gridView;
            const next=Math.max(grid.originY,Math.min(grid.originY+Math.max(0,grid.contentHeight-grid.height),grid.contentY+speed));
            if(next!==grid.contentY){grid.contentY=next;selectionArea.updateSelection()}
        }
    }
    Shortcut {sequence:"Escape";enabled:selectionArea.dragging;onActivated:selectionArea.cancelGesture()}
}
