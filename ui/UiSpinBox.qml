import QtQuick
import QtQuick.Controls

SpinBox {
    id: control
    hoverEnabled: true
    implicitWidth: 140; implicitHeight: 36
    palette.text: "#263238"
    palette.highlight: "#16756a"
    background: Rectangle {
        radius: 6; color: control.enabled ? "#ffffff" : "#edf1f2"
        border.color: control.activeFocus ? "#16756a" : "#dce2e4"
    }
    up.indicator: Rectangle {
        x: control.mirrored ? 0 : control.width - width
        height: control.height
        implicitWidth: 36; implicitHeight: 36; radius: 5
        color: !enabled ? "#edf1f2" : control.up.pressed ? "#c9ded9" : control.up.hovered ? "#e8edef" : "transparent"
        Text {anchors.centerIn: parent; text: "+"; font.pixelSize: 20; color: parent.enabled ? "#16756a" : "#9aa6ab"}
        HoverHandler {enabled: parent.enabled; cursorShape: Qt.PointingHandCursor}
    }
    down.indicator: Rectangle {
        x: control.mirrored ? control.width - width : 0
        height: control.height
        implicitWidth: 36; implicitHeight: 36; radius: 5
        color: !enabled ? "#edf1f2" : control.down.pressed ? "#c9ded9" : control.down.hovered ? "#e8edef" : "transparent"
        Text {anchors.centerIn: parent; text: "−"; font.pixelSize: 20; color: parent.enabled ? "#16756a" : "#9aa6ab"}
        HoverHandler {enabled: parent.enabled; cursorShape: Qt.PointingHandCursor}
    }
}
