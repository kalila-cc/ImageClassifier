import QtQuick
import QtQuick.Controls
Slider {
    id: control
    implicitHeight: 28
    hoverEnabled:true
    HoverHandler {enabled:control.enabled;cursorShape:Qt.PointingHandCursor}
    background: Rectangle {x:control.leftPadding;y:control.height/2-1; width:control.availableWidth;height:3;radius:2;color:"#cbd7c2"
        Rectangle {width:parent.width*control.visualPosition;height:3;radius:2;color:"#6a8759"}
    }
    handle: Rectangle {x:control.leftPadding+control.visualPosition*(control.availableWidth-width);y:control.height/2-7;width:14;height:14;radius:7;color:control.enabled&&control.pressed?"#6a8759":control.enabled&&control.hovered?"#dce8d4":"#ffffff";border.width:2;border.color:"#6a8759"}
}
