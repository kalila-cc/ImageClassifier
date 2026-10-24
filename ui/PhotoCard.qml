import QtQuick
import QtQuick.Controls
Rectangle {
    id: card
    property string photo: ""
    property string filename: ""
    property string kind: ""
    property var asset: ({})
    property bool liveAvailable: false
    function playbackControlAt(item,x,y) {
        if(livePreview.hitTest(item,x,y))return true;
        if(!videoPlay.visible)return false;
        const point=videoPlay.mapFromItem(item,x,y);
        return point.x>=0&&point.y>=0&&point.x<videoPlay.width&&point.y<videoPlay.height;
    }
    property bool selected: false
    property bool focused: false
    property bool externalHovered: false
    property bool externalPressed: false
    readonly property bool isHovered: enabled && (externalHovered || hovered.containsMouse)
    readonly property bool isPressed: enabled && (externalPressed || hovered.pressed)
    signal clicked()
    signal opened()
    signal playRequested()
    radius: 8; color: isPressed ? "#c9ded9" : isHovered ? (selected ? "#d5e9e3" : "#f5f8f9") : selected ? "#e0eeeb" : "#ffffff"
    border.color: selected ? "#16756a" : isHovered ? "#a9b8bd" : "#dce2e4"
    border.width: selected ? 2 : 1
    Image {
        id: thumb; objectName:"cardThumbnail"; x: 5; y: 5
        width: parent.width - 10; height: parent.height - 45
        source: card.photo.startsWith("image://media/") ? card.photo + "/cover" : card.photo
        sourceSize: Qt.size(600, Math.max(1, Math.round(600 * height / Math.max(1, width))))
        property string completedSource:""
        property bool loadingHint:false
        retainWhileLoading:completedSource!==""&&source.toString()===completedSource
        onStatusChanged:{
            loadingHint=false;
            if(status===Image.Ready)completedSource=source.toString();
            if(status===Image.Loading)loadingHintTimer.restart();else loadingHintTimer.stop();
        }
        Timer {id:loadingHintTimer;interval:150;onTriggered:thumb.loadingHint=thumb.status===Image.Loading}
        fillMode: Image.PreserveAspectCrop; asynchronous: true; cache:true; clip: true
    }
    Rectangle {
        anchors.fill: thumb
        visible: thumb.status !== Image.Ready && !(thumb.status===Image.Loading&&thumb.retainWhileLoading)
        color: "#eef2f4"
        Column {
            visible:thumb.status!==Image.Loading||thumb.loadingHint
            anchors.centerIn: parent
            anchors.verticalCenterOffset:card.asset.type==="视频"?42:0
            spacing: 8
            Glyph { visible:card.asset.type!=="视频"; anchors.horizontalCenter: parent.horizontalCenter; width: 28; height: 28; name: "image"; ink: "#87989f" }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: thumb.status === Image.Loading ? "正在载入…" : thumb.status === Image.Error ? (card.asset.type==="视频"?"封面暂不可用":"缩略图加载失败") : "暂无预览"
                font.pixelSize: 12; color: "#69767b"
            }
        }
    }
    Rectangle {
        x: 13; y: 13; width: 19; height: 19; radius: 5
        color: card.selected ? "#16756a" : "#e6ffffff"; border.color: card.selected ? "#16756a" : "#c5d0d4"
        Glyph { anchors.centerIn: parent; width: 14; height: 14; name: "check"; ink: "white"; visible: card.selected }
    }
    Rectangle {
        visible: card.kind !== "" && !card.asset.isLive; anchors.right: parent.right; anchors.rightMargin: 12; y: 12
        width: badge.implicitWidth + 14; height: 22; radius: 4; color: "#ce202629"
        Text { id: badge; anchors.centerIn: parent; text: card.kind; font.pixelSize: 10; color: "white"; font.weight: Font.DemiBold }
    }
    Text { x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 13; width: parent.width - 38; elide: Text.ElideRight; text: card.filename; font.pixelSize: 12; font.weight: card.selected ? Font.DemiBold : Font.Normal; color: card.selected ? "#11695f" : "#45545b" }
    Rectangle { visible: card.focused; width: 5; height: 5; radius: 3; color: "#16756a"; anchors.right: parent.right; anchors.rightMargin: 13; anchors.bottom: parent.bottom; anchors.bottomMargin: 18 }
    MouseArea { id: hovered; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.clicked(); onDoubleClicked: card.opened() }
    UiButton {
        id:videoPlay;objectName:"cardVideoPlayButton";z:2
        anchors.centerIn:thumb;width:44;height:44;padding:0
        visible:card.asset.type==="视频"
        hint:"播放视频";Accessible.name:hint
        contentItem:Item {Glyph {anchors.centerIn:parent;width:22;height:22;name:"play";ink:"white"}}
        background:Rectangle {radius:22;color:videoPlay.down?"#d920292d":videoPlay.pointerHovered?"#b320292d":"#8020292d";border.width:1;border.color:"#55ffffff"}
        onClicked:card.playRequested()
    }
    LivePhotoPreview {
        id: livePreview; objectName: "cardLivePreview"; z: 2; anchors.fill: thumb
        asset: card.asset; available: card.liveAvailable; compact: true; ownerKey: "batch:"+(card.asset.id||"")
    }
    ToolTip.visible: card.isHovered && !card.isPressed && card.filename.length > 0
    ToolTip.text: card.filename
    ToolTip.delay: 800
}
