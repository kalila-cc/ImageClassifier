import QtQuick
import QtQuick.Controls

MenuItem {
    id: entry
    property string iconName: ""
    leftPadding: 10; rightPadding: 10
    topPadding: 0; bottomPadding: 0
    implicitWidth: leftPadding + contentItem.implicitWidth + rightPadding
    implicitHeight: 36
    contentItem: Item {
        implicitWidth: menuLabel.implicitWidth + (entry.iconName.length > 0 ? 24 : 0)
        implicitHeight: 20
        Glyph {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16
            name: entry.iconName; visible: entry.iconName.length > 0
            ink: entry.enabled ? "#687a82" : "#9ba6ab"
        }
        Text {
            id: menuLabel
            anchors.fill: parent
            anchors.leftMargin: entry.iconName.length > 0 ? 24 : 0
            text: entry.text
            font.pixelSize: 12; color: entry.enabled ? "#35464e" : "#9ba6ab"
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }
    background: Rectangle {
        radius: 5
        color: entry.enabled && entry.down ? "#c9ded9" : entry.enabled && entry.highlighted ? "#e0eeeb" : "transparent"
    }
    MouseArea {anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: entry.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor}
}
