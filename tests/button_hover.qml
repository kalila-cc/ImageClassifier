import QtQuick
import QtQuick.Controls
import "../ui"

Rectangle {
    width: 260; height: 220; color: "white"
    property alias buttonEnabled: button.enabled
    property alias chosen: button.chosen
    property alias primary: button.primary
    property color buttonColor: button.background.color
    property bool buttonHovered: button.hovered
    property int clicks: 0
    UiButton {
        id: button
        x: 12; y: 100; width: 196; height: 36
        text: "打开此目录继续整理"
        quiet: true
        onClicked: parent.clicks++
    }
}
