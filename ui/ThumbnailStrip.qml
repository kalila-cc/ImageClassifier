import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: strip
    property var records: []
    property string currentId: ""
    property bool active: true
    readonly property int currentIndex: records.findIndex(item => item.id === currentId)
    readonly property bool needsScrolling: active && records.length * 104 - 8 > width - 16
    signal activated(string assetId)
    implicitHeight: 96
    color: "#202629"

    function revealCurrent() {
        if (active && currentIndex >= 0 && thumbnails.count > currentIndex)
            thumbnails.positionViewAtIndex(currentIndex, ListView.Center);
    }
    function scrollBy(distance) {
        thumbnails.cancelFlick();
        const left = thumbnails.originX;
        const right = Math.max(left, left + thumbnails.contentWidth - thumbnails.width);
        thumbnails.contentX = Math.max(left, Math.min(right, thumbnails.contentX + distance));
    }
    onCurrentIndexChanged: revealTimer.restart()
    onRecordsChanged: revealTimer.restart()
    onActiveChanged: if (active) revealTimer.restart()
    Timer { id: revealTimer; interval: 0; onTriggered: strip.revealCurrent() }
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
            border.color: arrow.activeFocus ? "#6dc4b4" : arrow.enabled ? "#52636c" : "#354147"
        }
    }

    RowLayout {
        anchors.fill: parent; anchors.margins: 8; spacing: 8
        ScrollButton {
            objectName: "thumbnailScrollBack"
            hint: "向左滚动缩略图"
            enabled: !thumbnails.atXBeginning
            onClicked: strip.scrollBy(-Math.max(104, thumbnails.width * .75))
        }
        ListView {
            id: thumbnails; objectName: "thumbnailList"
            Layout.fillWidth: true; Layout.fillHeight: true
            orientation: ListView.Horizontal; spacing: 8; clip: true
            model: strip.active ? strip.records : []
            reuseItems: true; cacheBuffer: 208
            boundsBehavior: Flickable.StopAtBounds
            onWidthChanged: revealTimer.restart()
            onCountChanged: revealTimer.restart()
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded; height: 5 }
            delegate: UiButton {
                id: tile
                required property var modelData
                required property int index
                objectName: "thumbnail_" + index
                readonly property bool current: modelData.id === strip.currentId
                width: 96; height: 72; padding: 0; focusPolicy: Qt.TabFocus
                hint: modelData.name || ""
                Accessible.name: (index + 1) + " · " + (modelData.name || "") + (modelData.isLive ? " · 实况照片" : "") + (current ? " · 当前文件" : "")
                onClicked: { strip.forceActiveFocus(); strip.activated(modelData.id) }
                background: Rectangle {
                    radius: 5
                    color: tile.down ? "#32584f" : tile.pointerHovered ? "#37444b" : tile.current ? "#274b45" : "#293237"
                    border.width: tile.current || tile.activeFocus ? 2 : 1
                    border.color: tile.current ? "#6dc4b4" : tile.pointerHovered || tile.activeFocus ? "#9fbbc0" : "#465259"
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
            MouseArea {
                anchors.fill: parent; acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    const pixels = wheel.pixelDelta.x || wheel.pixelDelta.y;
                    const angle = wheel.angleDelta.x || wheel.angleDelta.y;
                    if (thumbnails.contentWidth <= thumbnails.width || (!pixels && !angle)) { wheel.accepted = false; return; }
                    strip.scrollBy(pixels ? -pixels : -angle / 120 * 104);
                    wheel.accepted = true;
                }
            }
        }
        ScrollButton {
            objectName: "thumbnailScrollForward"
            forward: true; hint: "向右滚动缩略图"
            enabled: !thumbnails.atXEnd
            onClicked: strip.scrollBy(Math.max(104, thumbnails.width * .75))
        }
    }
}
