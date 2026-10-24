import QtQuick
import QtQuick.Controls

TextField {
    id: control
    implicitWidth: 180
    implicitHeight: 36
    leftPadding: 11
    rightPadding: 11
    topPadding: 7
    bottomPadding: 7
    font.pixelSize: 13
    color: "#263238"
    placeholderTextColor: "#89959a"
    selectionColor: "#d0e7e1"
    selectedTextColor: "#115f56"
    hoverEnabled: true
    selectByMouse: true
    background: Rectangle {
        radius: 6
        color: control.enabled ? "#ffffff" : "#f0f2f3"
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? "#16756a" : control.hovered ? "#a2b4b8" : "#dce2e4"
    }
}
