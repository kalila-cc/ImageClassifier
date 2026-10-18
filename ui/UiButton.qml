import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    property bool quiet: false
    property bool chosen: false
    property string tone: "normal" // normal, warning, danger
    property string hint: ""
    readonly property bool emphasized: tone === "warning" || tone === "danger"
    readonly property color toneInk: tone === "danger" ? "#a33636" : "#805019"
    readonly property color toneFill: tone === "danger" ? "#faece8" : "#fff3df"
    readonly property color toneHover: tone === "danger" ? "#f3d4cd" : "#f5dfb9"
    readonly property color tonePressed: tone === "danger" ? "#eabbb1" : "#eccb91"
    readonly property color toneBorder: tone === "danger" ? "#d9a29a" : "#d9b783"
    readonly property bool pointerHovered: enabled && pointerArea.containsMouse
    implicitHeight: 36
    implicitWidth: Math.max(36, label.implicitWidth + 28)
    padding: 0
    hoverEnabled: true
    opacity: enabled ? 1 : .4
    contentItem: Text {
        id: label
        text: control.text
        font.pixelSize: 12
        font.weight: control.primary || control.chosen ? Font.DemiBold : Font.Normal
        color: control.primary ? "white" : control.emphasized ? control.toneInk : control.chosen ? "#285c49" : "#555d58"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 7
        color: control.emphasized
               ? (control.primary
                  ? (control.enabled && control.down ? Qt.darker(control.toneInk,1.35) : control.pointerHovered ? Qt.darker(control.toneInk,1.15) : control.toneInk)
                  : control.enabled && control.down ? control.tonePressed : control.pointerHovered ? control.toneHover : control.toneFill)
               : control.primary
               ? (control.enabled && control.down ? "#173e2f" : control.pointerHovered ? "#36715a" : "#285c49")
               : control.enabled && control.down ? "#bed3c2"
               : control.pointerHovered ? (control.chosen ? "#cbdcca" : "#d6e3d6")
               : control.chosen ? "#e4ede7" : control.quiet ? "transparent" : "#ffffff"
        border.width: control.primary ? 0 : control.emphasized ? 1 : control.quiet || control.chosen ? 0 : 1
        border.color: control.emphasized ? control.toneBorder : "#dce1db"
    }
    ToolTip.visible: pointerHovered && hint.length > 0
    ToolTip.text: hint
    ToolTip.delay: 600
    // One hit area owns both hover feedback and cursor. Leave presses to Button.
    MouseArea {
        id: pointerArea
        anchors.fill: parent
        z: 1
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor
        scrollGestureEnabled: false
        onWheel: wheel => { wheel.accepted = false }
    }
}
