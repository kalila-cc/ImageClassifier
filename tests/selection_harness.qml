import QtQuick
import "../ui"

Rectangle {
    width:600;height:400;color:"white"
    property var records:Array.from({length:64},(_,i)=>({id:String(i+1)}))
    property var selectedIds:[]
    property string openedId:""
    property alias scrollY:grid.contentY
    property alias dragging:selector.dragging
    property alias columns:grid.columns
    GridView {
        id:grid;anchors.fill:parent;model:parent.records
        property int columns:3
        cellWidth:width/columns;cellHeight:150
        delegate:Rectangle {width:grid.cellWidth-10;height:140;color:"#cccccc"}
        GridSelection {
            id:selector;parent:grid;anchors.fill:parent
            gridView:grid;records:grid.parent.records;selectedIds:grid.parent.selectedIds
            onSelectionRequested:ids=>grid.parent.selectedIds=ids
            onActivated:id=>grid.parent.openedId=id
        }
    }
}
