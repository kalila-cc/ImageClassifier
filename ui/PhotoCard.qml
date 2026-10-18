import QtQuick
Rectangle {
    id: card
    property string photo: ""
    property string filename: ""
    property string kind: ""
    property bool selected: false
    property bool focused: false
    property bool externalHovered: false
    property bool externalPressed: false
    readonly property bool isHovered: enabled && (externalHovered || hovered.containsMouse)
    readonly property bool isPressed: enabled && (externalPressed || hovered.pressed)
    signal clicked()
    signal opened()
    radius: 9; color: isPressed ? "#d3e3d7" : isHovered ? (selected ? "#dcebdd" : "#eef4ec") : selected ? "#eaf1eb" : "#ffffff"
    border.color: selected ? "#46775e" : isHovered ? "#90ad91" : "#e0e5de"
    border.width: selected ? 2 : 1
    Image { id: thumb; x: 5; y: 5; width: parent.width - 10; height: parent.height - 45; source: card.photo; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 600; clip: true }
    Rectangle {
        x: 13; y: 13; width: 19; height: 19; radius: 5
        color: card.selected ? "#285c49" : "#aaffffff"; border.color: card.selected ? "#285c49" : "#d5dbd4"
        Glyph { anchors.centerIn: parent; width: 14; height: 14; name: "check"; ink: "white"; visible: card.selected }
    }
    Rectangle {
        visible: card.kind !== ""; anchors.right: parent.right; anchors.rightMargin: 12; y: 12
        width: badge.implicitWidth + 14; height: 22; radius: 4; color: "#b32b342e"
        Text { id: badge; anchors.centerIn: parent; text: card.kind; font.pixelSize: 10; color: "white"; font.weight: Font.DemiBold }
    }
    Text { x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 13; width: parent.width - 38; elide: Text.ElideRight; text: card.filename; font.pixelSize: 11; color: "#4c574d" }
    Rectangle { visible: card.focused; width: 5; height: 5; radius: 3; color: "#285c49"; anchors.right: parent.right; anchors.rightMargin: 13; anchors.bottom: parent.bottom; anchors.bottomMargin: 18 }
    MouseArea { id: hovered; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.clicked(); onDoubleClicked: card.opened() }
}
