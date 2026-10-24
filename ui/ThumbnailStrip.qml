import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: strip
    property var records: []
    property string currentId: ""
    property bool active: true
    readonly property int currentIndex: records.findIndex(item => item.id === currentId)
    readonly property bool needsScrolling: active && records.length * 80 > width - 16
    property bool positioned: false
    signal activated(string assetId)
    implicitHeight: 96
    color: "#202629"

    function revealCurrent() {
        if (!active || currentIndex < 0 || thumbnails.count <= currentIndex) return;
        const destination = thumbnails.originX + currentIndex * 80 + 40 - thumbnails.width / 2;
        scrollTo(destination, positioned);
        positioned = true;
    }
    function scrollTo(destination, animate) {
        scrollMotion.stop();
        thumbnails.cancelFlick();
        const left = thumbnails.originX;
        const right = Math.max(left, left + thumbnails.contentWidth - thumbnails.width);
        const target = Math.max(left, Math.min(right, destination));
        if (animate && Math.abs(target - thumbnails.contentX) > .5) {
            scrollMotion.from = thumbnails.contentX;
            scrollMotion.to = target;
            scrollMotion.start();
        } else thumbnails.contentX = target;
    }
    function scrollBy(distance, animate) {
        scrollTo((scrollMotion.running ? scrollMotion.to : thumbnails.contentX) + distance, animate);
    }
    onCurrentIndexChanged: revealTimer.restart()
    onRecordsChanged: { scrollMotion.stop(); revealTimer.restart(); }
    onActiveChanged: {
        scrollMotion.stop(); positioned = false;
        if (active) revealTimer.restart(); else revealTimer.stop();
    }
    Timer { id: revealTimer; interval: 0; onTriggered: strip.revealCurrent() }
    NumberAnimation {
        id: scrollMotion; objectName: "thumbnailScrollMotion"
        target: thumbnails; property: "contentX"; duration: 200; easing.type: Easing.OutCubic
    }
    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#343e43" }

    component ScrollButton: UiButton {
        id: arrow
        property bool forward: false
        implicitWidth: 32; implicitHeight: 52
        visible: strip.needsScrolling
        opacity: 1
        Accessible.name: hint
        contentItem: Item {
            Glyph {
                anchors.centerIn: parent
                width: 24; height: 24
                name: "back"; rotation: arrow.forward ? 180 : 0
                ink: arrow.enabled ? "#e8eeef" : "#718086"
            }
        }
        background: Rectangle {
            radius: 6
            color: !arrow.enabled ? "#242d31" : arrow.down ? "#40545c" : arrow.pointerHovered ? "#35464e" : "#2a363c"
            border.width: 1
            border.color: arrow.activeFocus ? Theme.onDark : arrow.enabled ? "#52636c" : "#354147"
        }
    }

    RowLayout {
        anchors.fill: parent; anchors.margins: 8; spacing: 8
        ScrollButton {
            objectName: "thumbnailScrollBack"
            hint: "向左滚动缩略图"
            enabled: !thumbnails.atXBeginning
            onClicked: strip.scrollBy(-Math.max(80, thumbnails.width * .75), true)
        }
        ListView {
            id: thumbnails; objectName: "thumbnailList"
            Layout.fillWidth: true; Layout.fillHeight: true
            orientation: ListView.Horizontal; spacing: 0; clip: true
            model: strip.active ? strip.records : []
            reuseItems: true; cacheBuffer: 208
            boundsBehavior: Flickable.StopAtBounds
            onWidthChanged: revealTimer.restart()
            onCountChanged: revealTimer.restart()
            onDraggingChanged: if (dragging) scrollMotion.stop()
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded; height: 5; onPressedChanged: if (pressed) scrollMotion.stop() }
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                width: 80; height: thumbnails.height
                property bool pooled: false
                ListView.onPooled: pooled = true
                ListView.onReused: pooled = false
                UiButton {
                    id: tile
                    readonly property var modelData: cell.modelData
                    readonly property int index: cell.index
                    anchors.centerIn: parent
                    objectName: "thumbnail_" + index
                    readonly property bool current: modelData.id === strip.currentId
                    width: 72; height: 72; padding: 0; focusPolicy: Qt.TabFocus
                    scale: current ? 78 / 72 : 1
                    Behavior on scale { enabled: strip.active && !cell.pooled; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    leftPadding:0;rightPadding:0;topPadding:0;bottomPadding:0
                    hint: modelData.name || ""
                    Accessible.name: (index + 1) + " · " + (modelData.name || "") + (modelData.isLive ? " · 实况照片" : "") + (current ? " · 当前文件" : "")
                    onClicked: { strip.forceActiveFocus(); strip.activated(modelData.id) }
                    background: Rectangle {
                        radius: 5
                        color: tile.down ? Theme.mix(Theme.primary,Qt.rgba(.12,.15,.16,1),.55) : tile.pointerHovered ? "#37444b" : tile.current ? Theme.mix(Theme.primary,Qt.rgba(.12,.15,.16,1),.7) : "#293237"
                        border.width: tile.current || tile.activeFocus ? 2 : 1
                        border.color: tile.current ? Theme.onDark : tile.pointerHovered || tile.activeFocus ? "#9fbbc0" : "#465259"
                    }
                    contentItem: Item {
                        Image {
                            id: preview;objectName:"filmstripPreview"
                            anchors { fill: parent; margins: 4 }
                            source: (tile.modelData.thumb||"").startsWith("image://media/") ? tile.modelData.thumb + "/cover" : tile.modelData.thumb||""
                            sourceSize: Qt.size(192, Math.max(1, Math.round(192 * height / Math.max(1, width)))); asynchronous: true
                            fillMode: Image.PreserveAspectCrop; clip: true
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            visible: tile.modelData.type !== "视频" && preview.status !== Image.Ready
                            Glyph { anchors.horizontalCenter: parent.horizontalCenter; width: 22; height: 22; name: "image"; ink: "#92a5ad" }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: preview.status === Image.Loading ? "载入中" : preview.status === Image.Error ? "加载失败" : "暂无预览"
                                font.pixelSize: 10; color: "#c4cfd4"
                            }
                        }
                        Rectangle {
                            anchors.centerIn:parent;width:28;height:28;radius:14;color:"#9920292d"
                            visible: tile.modelData.type === "视频"
                            Glyph { anchors.centerIn:parent;width:16;height:16;name:"play";ink:"white" }
                        }
                        Rectangle {
                            objectName: "filmstripLiveBadge"
                            anchors.top: parent.top; anchors.right: parent.right
                            anchors.topMargin: 7; anchors.rightMargin: 7
                            width: 22; height: 22; radius: 6
                            visible: !!tile.modelData.isLive
                            color: "#99f5f7f6"; border.color: "#33ffffff"
                            Image {
                                anchors.centerIn: parent; width: 18; height: 18
                                source: "icons/live-photo.svg"; sourceSize: Qt.size(36, 36)
                            }
                        }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent; acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    const pixels = wheel.pixelDelta.x || wheel.pixelDelta.y;
                    const angle = wheel.angleDelta.x || wheel.angleDelta.y;
                    if (thumbnails.contentWidth <= thumbnails.width || (!pixels && !angle)) { wheel.accepted = false; return; }
                    strip.scrollBy(pixels ? -pixels : -angle / 120 * 80, false);
                    wheel.accepted = true;
                }
            }
        }
        ScrollButton {
            objectName: "thumbnailScrollForward"
            forward: true; hint: "向右滚动缩略图"
            enabled: !thumbnails.atXEnd
            onClicked: strip.scrollBy(Math.max(80, thumbnails.width * .75), true)
        }
    }
}
