import QtQuick
import ".."

Rectangle {
    id: card
    property url photo
    property string filename: ""
    property string kind: ""
    property bool selected: false
    property bool focused: false
    signal clicked()
    signal opened()
    radius: 8
    color: pointer.pressed ? "#c9ded9" : selected ? "#e0eeeb" : pointer.containsMouse ? "#f5f8f9" : "#ffffff"
    border.color: selected ? "#16756a" : pointer.containsMouse ? "#a9b8bd" : "#dce2e4"
    border.width: selected ? 2 : 1
    Image {
        objectName: "cardThumbnail"
        x: 5; y: 5; width: parent.width - 10; height: parent.height - 45
        source: card.photo; fillMode: Image.PreserveAspectCrop; asynchronous: true
        sourceSize.width: 600; clip: true
    }
    Rectangle {
        x: 12; y: 12; width: 19; height: 19; radius: 5
        color: card.selected ? "#16756a" : "#e6ffffff"
        border.color: card.selected ? "#16756a" : "#c5d0d4"
        Glyph { anchors.centerIn: parent; width: 13; height: 13; name: "check"; ink: "white"; visible: card.selected }
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 12; y: 12
        text: card.kind; color: "white"; font.pixelSize: 11
    }
    Text {
        x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 12
        width: parent.width - 34; text: card.filename; elide: Text.ElideMiddle
        color: "#3e4c53"; font.pixelSize: 11
    }
    Rectangle {
        visible: card.focused; width: 4; height: 4; radius: 2; color: "#16756a"
        anchors.right: parent.right; anchors.rightMargin: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 17
    }
    MouseArea {
        id: pointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: card.clicked()
        onDoubleClicked: card.opened()
    }
}
