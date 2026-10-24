import QtQuick
import QtQuick.Controls
import QtQuick.Window
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
    function pulse() { browsePulse.restart(); }
    function resetPulse() { browsePulse.stop();scale=1; }
    onVisibleChanged:if(!visible)resetPulse()
    onAssetChanged:resetPulse()
    z: browsePulse.running ? 2 : selected ? 1 : 0
    SequentialAnimation {
        id:browsePulse
        NumberAnimation {target:card;property:"scale";from:1;to:1.10;duration:350;easing.type:Easing.OutCubic}
        NumberAnimation {target:card;property:"scale";to:1;duration:550;easing.type:Easing.InOutCubic}
    }
    property bool externalHovered: false
    property bool externalPressed: false
    readonly property bool isHovered: enabled && (externalHovered || hovered.containsMouse)
    readonly property bool isPressed: enabled && (externalPressed || hovered.pressed)
    signal clicked()
    signal opened()
    signal playRequested()
    color: "#eef2f4"
    Accessible.role:Accessible.CheckBox
    Accessible.name:filename
    Accessible.checked:selected
    Image {
        id: thumb; objectName:"cardThumbnail"; anchors.fill:parent
        source: card.photo.startsWith("image://media/") ? card.photo + "/cover" : card.photo
        // Two cache sizes keep enlarged tiles sharp without a cache entry per slider position.
        readonly property int resolution:card.width*Screen.devicePixelRatio>600?1024:600
        sourceSize: Qt.size(resolution,resolution)
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
        clip: true
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
        anchors.fill:thumb;z:3
        color:card.isPressed?"#25000000":card.selected?Theme.alpha(Theme.primary,.08):card.isHovered?"#14ffffff":"transparent"
    }
    Rectangle {
        objectName:"cardSelectionOutline";anchors.fill:parent;z:3
        // Center the stroke on the tile edge so adjacent selections share one line.
        anchors.margins:card.selected?-2.5:0
        color:"transparent"
        border.width:card.selected?5:card.isHovered?1:0
        border.color:card.selected?"#ffffff":"#b3ffffff"
    }
    Rectangle {
        objectName:"cardSelectionBadge";z:4
        x: 13; y: 13; width: 25; height: 25; radius: width / 2
        color: card.selected ? Theme.checkFill : "#e6ffffff"
        border.width: card.selected ? 1.5 : 1
        border.color: card.selected ? "#ffffff" : "#c5d0d4"
        Glyph { objectName:"cardSelectionCheck";anchors.centerIn: parent; width: 18; height: 18; name: "check"; strokeWidth:3.5;ink:"white";visible:card.selected }
    }
    Rectangle {
        visible: card.kind !== "" && !card.asset.isLive; anchors.right: parent.right; anchors.rightMargin: 12; y: 12
        width: badge.implicitWidth + 14; height: 22; radius: 4; color: "#ce202629"
        Text { id: badge; anchors.centerIn: parent; text: card.kind; font.pixelSize: 10; color: "white"; font.weight: Font.DemiBold }
    }
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
        id: livePreview; objectName: "cardLivePreview"; z: 2; anchors.fill: thumb; clip: true
        asset: card.asset; available: card.liveAvailable; compact: true; ownerKey: "batch:"+(card.asset.id||"")
    }
    ToolTip.visible: card.isHovered && !card.isPressed && card.filename.length > 0
    ToolTip.text: card.filename
    ToolTip.delay: 800
}
