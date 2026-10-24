import QtQuick
import QtQuick.Controls
Slider {
    id: control
    implicitHeight: 28
    hoverEnabled:true
    HoverHandler {enabled:control.enabled;cursorShape:Qt.PointingHandCursor}
    opacity: enabled ? 1 : .4
    background: Rectangle {x:control.leftPadding;y:control.height/2-1; width:control.availableWidth;height:3;radius:2;color:"#dce3e5"
        Rectangle {width:parent.width*control.visualPosition;height:3;radius:2;color:"#16756a"}
    }
    handle: Rectangle {x:control.leftPadding+control.visualPosition*(control.availableWidth-width);y:control.height/2-7;width:14;height:14;radius:7;color:control.enabled&&control.pressed?"#16756a":control.enabled&&control.hovered?"#e0eeeb":"#ffffff";border.width:2;border.color:"#16756a"}
}
