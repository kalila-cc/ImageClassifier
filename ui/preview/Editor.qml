import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: viewer
    spacing: 0
    property var photos: []
    property int photoId: 0
    property int position: 0
    property string filename: ""
    property string mediaType: "图片"
    property string targetFolder: ""
    property bool cropActive: false
    property bool activeView: false
    readonly property bool keyboardAdjusting: rotationSlider.activeFocus
    property bool filmstripVisible: true
    property string ratio: "4:3"
    property int crops: 2
    property real zoom: 1
    onActiveViewChanged: { if (activeView) { cropActive = photos.length > 0 && mediaType !== "视频"; zoom = 1 } }
    onPhotoIdChanged: { zoom = 1; rotationSlider.value = 0; cropActive = activeView && photos.length > 0 && mediaType !== "视频" }
    onMediaTypeChanged: cropActive = activeView && photos.length > 0 && mediaType !== "视频"
    onPhotosChanged: { if (!photos.length) cropActive = false }
    function photoPath(id) { return "assets/photo-" + (id < 10 ? "0" : "") + id + ".jpg" }
    signal previous()
    signal next()
    signal pickPhoto(int id)
    signal notice(string message)
    signal showDetails()
    Rectangle {
        Layout.fillWidth: true; Layout.preferredHeight: 52; color: "#f9faf7"
        RowLayout { anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 8
            UiButton { text: "‹"; implicitWidth: 34; quiet: true; enabled: viewer.position > 0; onClicked: viewer.previous() }
            Text { text: viewer.photos.length ? (viewer.position+1) + " / " + viewer.photos.length : "0 / 0"; font.pixelSize: 12; color: "#708360"; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignHCenter }
            UiButton { text: "›"; implicitWidth: 34; quiet: true; enabled: viewer.position < viewer.photos.length-1; onClicked: viewer.next() }
            Text { text: viewer.photos.length ? viewer.filename : "没有匹配图片"; font.pixelSize: 12; color: "#4a6040"; Layout.leftMargin: 10; elide: Text.ElideMiddle; Layout.fillWidth: true }
            UiButton { text: "−"; implicitWidth: 30; quiet: true; enabled: viewer.zoom > 1; onClicked: viewer.zoom = Math.max(1, viewer.zoom-.25) }
            UiButton { text: viewer.zoom === 1 ? "适应" : Math.round(viewer.zoom*100)+"%"; quiet: true; implicitWidth: 56; onClicked: viewer.zoom = 1 }
            UiButton { text: "+"; implicitWidth: 30; quiet: true; enabled: viewer.zoom < 3; onClicked: viewer.zoom = Math.min(3, viewer.zoom+.25) }
            Rectangle { width: 1; height: 20; color: "#dce3d5"; Layout.leftMargin: 4; Layout.rightMargin: 4 }
            UiButton { text: "信息"; quiet: true; onClicked: viewer.showDetails() }
            UiButton { text: "胶片条"; chosen: viewer.filmstripVisible; quiet: true; onClicked: viewer.filmstripVisible = !viewer.filmstripVisible }
            UiButton { text: viewer.mediaType === "视频" ? "播放预览" : "裁剪 / 旋转"; chosen: viewer.cropActive; enabled: viewer.photos.length > 0; onClicked: { if (viewer.mediaType === "视频") viewer.notice("视频播放尚未接入"); else { viewer.cropActive = !viewer.cropActive; viewer.zoom = 1 } } }
        }
    }
    RowLayout {
        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; color: "#242c27"; clip: true
            Flickable {
                id: canvas
                anchors.fill: parent; anchors.margins: 10
                contentWidth: width * viewer.zoom; contentHeight: height * viewer.zoom; clip: true
                boundsBehavior: Flickable.StopAtBounds; interactive: viewer.zoom > 1
                onContentWidthChanged: contentX = Math.max(0, (contentWidth-width)/2)
                onContentHeightChanged: contentY = Math.max(0, (contentHeight-height)/2)
                Image {
                    id: photo
                    visible: viewer.photos.length > 0
                    width: canvas.contentWidth; height: canvas.contentHeight
                    source: viewer.photoPath(viewer.photoId); fillMode: Image.PreserveAspectFit
                    rotation: viewer.cropActive ? rotationSlider.value : 0
                    asynchronous: true
                    Rectangle {
                        visible: viewer.cropActive
                        anchors.centerIn: parent; rotation: -photo.rotation
                        property real aspect: viewer.ratio === "1:1" ? 1 : viewer.ratio === "16:9" ? 16/9 : viewer.ratio === "3:4" ? .75 : 4/3
                        width: Math.min(photo.paintedWidth*.82, photo.paintedHeight*.85*aspect); height: width/aspect
                        color: "transparent"; border.color: "#eff8e9"; border.width: 1
                        Repeater { model: 2; Rectangle { required property int index; x: parent.width/3*(index+1); width: 1; height: parent.height; color: "#77ffffff" } }
                        Repeater { model: 2; Rectangle { required property int index; y: parent.height/3*(index+1); height: 1; width: parent.width; color: "#77ffffff" } }
                        Repeater { model: 4; Rectangle { required property int index; x: index%2 ? parent.width-4 : -4; y: index>1 ? parent.height-4 : -4; width: 8; height: 8; color: "white"; radius: 1 } }
                    }
                }
            }
            Text { visible: viewer.photos.length === 0; anchors.centerIn: parent; text: "请返回批量模式调整筛选"; color: "#b5c1af"; font.pixelSize: 14 }
        }
        Rectangle {
            visible: viewer.cropActive
            Layout.preferredWidth: 254; Layout.fillHeight: true; color: "#f8faf5"
            ScrollView {
                id: toolsPanel; anchors.fill: parent; anchors.margins: 16; clip: true; contentWidth: availableWidth
                ColumnLayout {
                    width: toolsPanel.availableWidth; spacing: 14
                    RowLayout { Layout.fillWidth: true
                        Text { text: "裁剪与旋转"; font.pixelSize: 13; font.weight: Font.DemiBold; color: "#49623e"; Layout.fillWidth: true }
                        UiButton { text: "×"; quiet: true; implicitWidth: 26; implicitHeight: 26; onClicked: viewer.cropActive = false }
                    }
                    RowLayout { spacing: 4
                        Repeater { model: ["1:1", "4:3", "3:4", "16:9"]
                            UiButton { required property string modelData; text: modelData; chosen: viewer.ratio === modelData; implicitWidth: 52; implicitHeight: 30; onClicked: viewer.ratio = modelData }
                        }
                    }
                    RowLayout { Layout.fillWidth: true
                        Text { text: "角度"; font.pixelSize: 12; color: "#819373"; Layout.fillWidth: true }
                        Text { text: rotationSlider.value.toFixed(1)+"°"; font.pixelSize: 12; color: "#49623e" }
                        UiButton { text: "重置"; quiet: true; implicitHeight: 26; onClicked: rotationSlider.value = 0 }
                    }
                    Slider {
                        id: rotationSlider; Layout.fillWidth: true; from: -45; to: 45; value: 0; stepSize: .1
                        background: Rectangle { x: rotationSlider.leftPadding; y: rotationSlider.height/2-1; width: rotationSlider.availableWidth; height: 2; color: "#c7d3bf" }
                        handle: Rectangle { x: rotationSlider.leftPadding+rotationSlider.visualPosition*(rotationSlider.availableWidth-width); y: rotationSlider.height/2-7; width: 14; height: 14; radius: 7; color: "#6a8759" }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#dce5d4" }
                    RowLayout { Layout.fillWidth: true
                        Text { text: "子图 " + viewer.crops; font.pixelSize: 12; color: "#49623e"; Layout.fillWidth: true }
                        UiButton { text: "+ 添加"; quiet: true; implicitHeight: 28; onClicked: { if(viewer.crops<3) viewer.crops++; else viewer.notice("预览最多展示 3 个子图") } }
                    }
                    Repeater { model: viewer.crops
                        Rectangle {
                            required property int index
                            Layout.fillWidth: true; Layout.preferredHeight: 64; radius: 5; color: index===0 ? "#eaf1e4" : "white"; border.color: "#d6e1cd"
                            RowLayout { anchors.fill: parent; anchors.margins: 8; spacing: 10
                                Image { Layout.preferredWidth: 54; Layout.preferredHeight: 46; source: viewer.photoPath(viewer.photoId); fillMode: Image.PreserveAspectCrop; clip: true }
                                Column { spacing: 6
                                    Text { text: "子图 0" + (index+1); color: "#49623e"; font.pixelSize: 11 }
                                    Text { text: "↳ " + (index===1 ? "高中" : viewer.targetFolder); color: "#819373"; font.pixelSize: 11 }
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: viewer.notice("子图目标选择尚未接入") }
                        }
                    }
                    Text { text: "裁剪后保留原图"; color: "#819373"; font.pixelSize: 11 }
                }
            }
        }
    }
    Rectangle {
        visible: viewer.filmstripVisible && viewer.photos.length > 0
        Layout.fillWidth: true; Layout.preferredHeight: 76; color: "#303a32"
        ListView {
            id: strip
            anchors.fill: parent; anchors.margins: 8; orientation: ListView.Horizontal; spacing: 7; clip: true
            model: viewer.photos; currentIndex: viewer.position
            onCurrentIndexChanged: { if(currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain) }
            delegate: Rectangle {
                required property var modelData
                width: 82; height: 60; radius: 4; color: modelData.id===viewer.photoId ? "#b9cba8" : "#4c594d"
                Image { anchors.fill: parent; anchors.margins: modelData.id===viewer.photoId ? 3 : 1; source: viewer.photoPath(modelData.id); fillMode: Image.PreserveAspectCrop; clip: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: viewer.pickPhoto(modelData.id) }
            }
        }
    }
}
