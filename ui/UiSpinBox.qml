import QtQuick
import QtQuick.Controls

SpinBox {
    id: control
    hoverEnabled: true
    up.indicator: Rectangle {
        x: control.mirrored ? 0 : control.width - width
        height: control.height
        implicitWidth: 36; implicitHeight: 36; radius: 5
        color: !enabled ? "#eef1eb" : control.up.pressed ? "#c9dacc" : control.up.hovered ? "#e2eae1" : "#ffffff"
        Text {anchors.centerIn: parent; text: "+"; font.pixelSize: 20; color: parent.enabled ? "#285c49" : "#a1aaa0"}
        HoverHandler {enabled: parent.enabled; cursorShape: Qt.PointingHandCursor}
    }
    down.indicator: Rectangle {
        x: control.mirrored ? control.width - width : 0
        height: control.height
        implicitWidth: 36; implicitHeight: 36; radius: 5
        color: !enabled ? "#eef1eb" : control.down.pressed ? "#c9dacc" : control.down.hovered ? "#e2eae1" : "#ffffff"
        Text {anchors.centerIn: parent; text: "−"; font.pixelSize: 20; color: parent.enabled ? "#285c49" : "#a1aaa0"}
        HoverHandler {enabled: parent.enabled; cursorShape: Qt.PointingHandCursor}
    }
}
