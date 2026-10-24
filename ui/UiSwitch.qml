import QtQuick
import QtQuick.Controls

Switch {
    id: control
    implicitWidth: 46; implicitHeight: 30; padding: 0
    hoverEnabled: true
    opacity: enabled ? 1 : .4
    contentItem: Item {}
    indicator: Rectangle {
        anchors.centerIn: parent
        width: 42; height: 24; radius: 12
        color: control.checked ? (control.down ? "#105c53" : control.hovered ? "#1b897b" : "#16756a") : control.down ? "#9baaae" : control.hovered ? "#b9c5c9" : "#cdd5d8"
        border.width: control.activeFocus ? 2 : 0; border.color: "#83b7ac"
        Rectangle {x: control.checked ? 21 : 3; y: 3; width: 18; height: 18; radius: 9; color: "white"}
    }
    HoverHandler {enabled: control.enabled; cursorShape: Qt.PointingHandCursor}
}
