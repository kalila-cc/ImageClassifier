import QtQuick
import QtQuick.Layouts

Item {
    property string title: ""
    property string detail: ""
    property string actionText: ""
    property bool busy: false
    signal activated()
    id: empty
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(420, Math.max(0, parent.width-48))
        spacing: 16
        Rectangle {Layout.alignment:Qt.AlignHCenter;width:72;height:72;radius:20;color:"#e2ece9";Glyph {anchors.centerIn:parent;name:"image";width:32;height:32;ink:"#16756a"}}
        Text {Layout.fillWidth:true;text:empty.title;font.pixelSize:19;font.weight:Font.DemiBold;color:"#263238";horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap}
        Text {Layout.fillWidth:true;text:empty.detail;font.pixelSize:12;color:"#69777e";horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap;lineHeight:1.5}
        UiButton {objectName:"emptyStateAction";Layout.alignment:Qt.AlignHCenter;text:empty.actionText;primary:true;visible:!empty.busy;onClicked:empty.activated()}
    }
}
