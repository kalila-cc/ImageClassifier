import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: batch
    spacing: 0
    property var photos: []
    property var selection: []
    property int focusPhoto: 0
    property bool allSelected: false
    property string filter: "全部"
    property alias query: search.text
    signal togglePhoto(int id)
    signal openPhoto(int id)
    signal toggleAll()
    signal filterChosen(string value)
    Rectangle {
        Layout.fillWidth: true; Layout.preferredHeight: 52; color: "#f9faf7"
        RowLayout { anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 5
            UiButton { text: batch.allSelected ? "取消全选" : "全选"; quiet: true; onClicked: batch.toggleAll() }
            Rectangle { height: 20; width: 1; color: "#dce3d5"; Layout.leftMargin: 5; Layout.rightMargin: 5 }
            Repeater { model: ["全部", "图片", "Live", "视频"]
                UiButton { required property string modelData; text: modelData; quiet: true; chosen: batch.filter === modelData; implicitWidth: 50; implicitHeight: 30; onClicked: batch.filterChosen(modelData) }
            }
            Text { text: batch.photos.length + " 项"; font.pixelSize: 11; color: "#8e9b81"; Layout.leftMargin: 8 }
            Item { Layout.fillWidth: true }
            Text { text: "缩略图"; font.pixelSize: 11; color: "#819174" }
            Slider {
                id: sizeSlider; Layout.preferredWidth: 100; from: 170; to: 310; value: 240; stepSize: 35
                background: Rectangle { x: sizeSlider.leftPadding; y: sizeSlider.height/2-1; width: sizeSlider.availableWidth; height: 2; color: "#c7d3bf" }
                handle: Rectangle { x: sizeSlider.leftPadding+sizeSlider.visualPosition*(sizeSlider.availableWidth-width); y: sizeSlider.height/2-6; width: 12; height: 12; radius: 6; color: "#6a8759" }
            }
            TextField { id: search; Layout.preferredWidth: 146; implicitHeight: 31; placeholderText: "搜索文件名"; font.pixelSize: 11; leftPadding: 10; selectByMouse: true
                background: Rectangle { color: "white"; radius: 5; border.color: "#dfe5d9" }
            }
        }
    }
    GridView {
        id: grid
        Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 12; clip: true
        property int columns: Math.max(2, Math.floor(width / sizeSlider.value))
        cellWidth: width / columns; cellHeight: cellWidth * .73 + 36
        model: batch.photos
        ScrollBar.vertical: ScrollBar { width: 6; policy: ScrollBar.AsNeeded }
        delegate: PreviewPhotoCard {
            required property var modelData
            width: grid.cellWidth - 10; height: grid.cellHeight - 10
            photo: Qt.resolvedUrl("assets/photo-" + (modelData.id < 10 ? "0" : "") + modelData.id + ".jpg")
            filename: modelData.name; kind: modelData.kind
            selected: batch.selection.includes(modelData.id); focused: batch.focusPhoto === modelData.id
            onClicked: batch.togglePhoto(modelData.id)
            onOpened: batch.openPhoto(modelData.id)
        }
        Column { anchors.centerIn: parent; spacing: 14; visible: grid.count === 0
            Text { text: "没有匹配的图片"; font.pixelSize: 15; color: "#728467" }
            UiButton { text: "清除筛选"; onClicked: { search.clear(); batch.filterChosen("全部") } }
        }
    }
}
