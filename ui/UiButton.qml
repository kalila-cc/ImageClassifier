import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    property bool quiet: false
    property bool chosen: false
    property bool dark: false
    property string iconName: ""
    property string tone: "normal" // normal, warning, danger
    property string hint: ""
    Accessible.name: text.length > 0 ? text : hint
    Accessible.description: hint
    readonly property bool emphasized: tone === "warning" || tone === "danger"
    readonly property color toneInk: tone === "danger" ? "#a33636" : "#805019"
    readonly property color toneFill: tone === "danger" ? "#faece8" : "#fff3df"
    readonly property color toneHover: tone === "danger" ? "#f3d4cd" : "#f5dfb9"
    readonly property color tonePressed: tone === "danger" ? "#eabbb1" : "#eccb91"
    readonly property color toneBorder: tone === "danger" ? "#d9a29a" : "#d9b783"
    readonly property bool pointerHovered: enabled && pointerArea.containsMouse
    readonly property color textInk: primary ? "#ffffff" : emphasized ? toneInk : chosen ? (dark ? "#ffffff" : "#11695f") : dark ? "#bfc9cd" : "#45545b"
    implicitHeight: 36
    implicitWidth: Math.max(36, implicitContentWidth + (text.length > 0 ? 24 : 16))
    padding: 0
    hoverEnabled: true
    opacity: enabled ? 1 : .4
    contentItem: Item {
        id: buttonContent
        implicitWidth: contentRow.implicitWidth
        implicitHeight: 20
        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 7
            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16
                visible: control.iconName.length > 0
                name: control.iconName
                ink: control.textInk
            }
            Text {
                id: label
                visible: control.text.length > 0
                text: control.text
                height: 20
                font.pixelSize: 13
                font.weight: control.primary || control.chosen ? Font.DemiBold : Font.Medium
                color: control.textInk
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
    background: Rectangle {
        radius: 6
        color: control.emphasized
               ? (control.primary
                  ? (control.enabled && control.down ? Qt.darker(control.toneInk,1.35) : control.pointerHovered ? Qt.darker(control.toneInk,1.15) : control.toneInk)
                  : control.enabled && control.down ? control.tonePressed : control.pointerHovered ? control.toneHover : control.toneFill)
               : control.primary
               ? (control.enabled && control.down ? "#105c53" : control.pointerHovered ? "#1b897b" : "#16756a")
               : control.dark
               ? (control.enabled && control.down ? "#3b4a50" : control.chosen ? (control.pointerHovered ? "#1b897b" : "#16756a") : control.pointerHovered ? "#303b40" : control.quiet ? "transparent" : "#293338")
               : control.enabled && control.down ? "#c9ded9"
               : control.pointerHovered ? (control.chosen ? "#cfe5df" : "#e8edef")
               : control.chosen ? "#e0eeeb" : control.quiet ? "transparent" : "#ffffff"
        border.width: control.primary ? 0 : control.emphasized ? 1 : control.quiet || control.chosen ? 0 : 1
        border.color: control.emphasized ? control.toneBorder : control.dark ? "#3e4a50" : "#dce2e4"
    }
    ToolTip.visible: pointerHovered && hint.length > 0
    ToolTip.text: hint
    ToolTip.delay: 600
    // Keep keyboard focus legible even when a caller supplies its own background.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: 8
        color: "transparent"
        border.width: 2
        border.color: "#509b90"
        visible: control.enabled && control.visualFocus
        z: 2
    }
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
