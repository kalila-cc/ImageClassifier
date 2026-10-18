import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: app
    visible: true
    width: 1460; height: 920
    minimumWidth: 1120; minimumHeight: 720
    title: "归图 · ImageClassifier — 界面预览"
    color: "#f4f6f2"
    palette.highlight: "#285c49"
    palette.buttonText: "#4c6344"
    palette.text: "#4c6344"
    property bool largeMode: false
    property bool middleExpanded: true
    property string destination: "初二"
    property string filter: "全部"
    property var selection: [0, 1, 2]
    property int focusPhoto: 0
    property string toastText: ""
    property var photos: [
        {id:0, name:"IMG_2048.JPG", kind:"", type:"图片"},
        {id:1, name:"IMG_2049.HEIC", kind:"◎ LIVE", type:"Live"},
        {id:2, name:"IMG_2050.JPG", kind:"", type:"图片"},
        {id:3, name:"IMG_2051.JPG", kind:"", type:"图片"},
        {id:4, name:"IMG_2052.JPG", kind:"", type:"图片"},
        {id:5, name:"IMG_2053.MOV", kind:"▷ 00:18", type:"视频"},
        {id:6, name:"IMG_2054.JPG", kind:"", type:"图片"},
        {id:7, name:"IMG_2055.HEIC", kind:"◎ LIVE", type:"Live"},
        {id:8, name:"IMG_2056.JPG", kind:"", type:"图片"},
        {id:9, name:"IMG_2057.JPG", kind:"", type:"图片"},
        {id:10, name:"IMG_2058.JPG", kind:"", type:"图片"},
        {id:11, name:"IMG_2059.MOV", kind:"▷ 00:42", type:"视频"}
    ]
    property var visiblePhotos: photos.filter(p => (filter === "全部" || p.type === filter) && p.name.toLowerCase().includes(batch.query.toLowerCase()))
    property int currentIndex: visiblePhotos.findIndex(p => p.id === focusPhoto)
    property bool allVisibleSelected: visiblePhotos.length > 0 && visiblePhotos.every(p => selection.includes(p.id))
    property string targetPath: ["初一", "初二", "初三"].includes(destination) ? "初中 / " + destination : destination
    onVisiblePhotosChanged: { if (visiblePhotos.length && !visiblePhotos.some(p => p.id === focusPhoto)) focusPhoto = visiblePhotos[0].id }
    function asset(i) { return "assets/photo-" + (i < 10 ? "0" : "") + i + ".jpg" }
    function notify(message) { toastText = message; toastTimer.restart() }
    function toggle(i) {
        focusPhoto = i;
        let items = selection.slice(); let index = items.indexOf(i);
        if(index >= 0) items.splice(index, 1); else items.push(i);
        selection = items;
    }
    function toggleVisible() {
        if (allVisibleSelected) selection = selection.filter(i => !visiblePhotos.some(p => p.id === i));
        else selection = Array.from(new Set(selection.concat(visiblePhotos.map(p => p.id))));
    }
    function navigate(delta) {
        const next = currentIndex + delta;
        if (next >= 0 && next < visiblePhotos.length) focusPhoto = visiblePhotos[next].id;
    }
    function classify() {
        const count = largeMode ? (visiblePhotos.length ? 1 : 0) : selection.length;
        notify(count ? "预览：将" + (largeMode ? "当前图片" : count + " 项") + "归类到「" + targetPath + "」，未操作真实文件" : "请先选择图片");
    }
    Timer { id: toastTimer; interval: 3000; onTriggered: app.toastText = "" }
    Shortcut { sequence: "Left"; enabled: app.largeMode && !sources.visible && !details.visible && !folderDialog.visible && !boundary.visible && !viewer.keyboardAdjusting; onActivated: app.navigate(-1) }
    Shortcut { sequence: "Right"; enabled: app.largeMode && !sources.visible && !details.visible && !folderDialog.visible && !boundary.visible && !viewer.keyboardAdjusting; onActivated: app.navigate(1) }
    ColumnLayout {
        anchors.fill: parent; spacing: 0
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 58; color: "#ffffff"
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 18; spacing: 12
                Rectangle { width: 29; height: 29; radius: 7; color: "#285c49"; Glyph { anchors.centerIn: parent; name: "image"; ink: "white"; width: 21; height: 21 } }
                Text { text: "归图"; font.pixelSize: 17; font.weight: Font.DemiBold; color: "#2c4436" }
                Rectangle { width: 1; height: 22; color: "#e0e5dc"; Layout.leftMargin: 8; Layout.rightMargin: 4 }
                UiButton { text: "春日随拍  ▾"; quiet: true; onClicked: sources.open() }
                Text { text: "第 01 批 · 12 项"; color: "#8b9684"; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 190; height: 38; radius: 8; color: "#edf1e9"
                    Row { anchors.centerIn: parent; spacing: 3
                        UiButton { text: "▦  批量模式"; implicitWidth: 90; implicitHeight: 32; chosen: !app.largeMode; quiet: true; onClicked: app.largeMode = false }
                        UiButton { text: "▣  大图模式"; implicitWidth: 90; implicitHeight: 32; chosen: app.largeMode; quiet: true; onClicked: app.largeMode = true }
                    }
                }
                Item { Layout.fillWidth: true }
                Text { text: "UI 预览"; color: "#929b86"; font.pixelSize: 10 }
                UiButton { text: "···"; quiet: true; implicitWidth: 36; onClicked: moreMenu.open()
                    Menu { id: moreMenu; y: parent.height
                        MenuItem { text: "批次边界预览"; onTriggered: boundary.open() }
                        MenuItem { text: "添加来源目录"; onTriggered: sources.open() }
                        MenuItem { text: "操作记录"; onTriggered: app.notify("操作记录尚未接入") }
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#dfe5da" }
        }
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            Rectangle {
                Layout.preferredWidth: 210; Layout.fillHeight: true; color: "#f0f3ed"
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 4
                    RowLayout { Layout.fillWidth: true; Layout.bottomMargin: 8
                        Text { text: "目标目录"; font.pixelSize: 13; font.weight: Font.DemiBold; color: "#52624a"; Layout.fillWidth: true }
                        UiButton { text: "+"; quiet: true; implicitWidth: 28; onClicked: folderDialog.open() }
                    }
                    FolderRow { Layout.fillWidth: true; label: "小学"; selected: app.destination === label; onClicked: app.destination = label }
                    FolderRow { Layout.fillWidth: true; label: "初中"; expandable: true; expanded: app.middleExpanded; selected: app.destination === label; onClicked: app.destination = label; onToggled: app.middleExpanded = !app.middleExpanded }
                    Repeater { model: app.middleExpanded ? ["初一", "初二", "初三"] : []
                        FolderRow { required property string modelData; Layout.fillWidth: true; label: modelData; depth: 1; selected: app.destination === label; onClicked: app.destination = label }
                    }
                    FolderRow { Layout.fillWidth: true; label: "高中"; selected: app.destination === label; onClicked: app.destination = label }
                    Item { Layout.fillHeight: true }
                    UiButton { Layout.fillWidth: true; text: "目录管理  ···"; quiet: true; onClicked: app.notify("目录改名、移动等操作尚未接入") }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#dce3d5"; Layout.topMargin: 5; Layout.bottomMargin: 5 }
                    UiButton { Layout.fillWidth: true; text: "已处理原图"; quiet: true; onClicked: app.notify("已处理目录尚未接入") }
                }
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#dfe5da" }
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                BatchView {
                    id: batch
                    visible: !app.largeMode; Layout.fillWidth: true; Layout.fillHeight: true
                    photos: app.visiblePhotos; selection: app.selection; focusPhoto: app.focusPhoto
                    allSelected: app.allVisibleSelected; filter: app.filter
                    onFilterChosen: value => app.filter = value
                    onTogglePhoto: id => app.toggle(id)
                    onToggleAll: app.toggleVisible()
                    onOpenPhoto: id => { app.focusPhoto = id; app.largeMode = true }
                }
                Editor {
                    id: viewer
                    visible: app.largeMode; Layout.fillWidth: true; Layout.fillHeight: true
                    activeView: app.largeMode
                    photos: app.visiblePhotos; photoId: app.focusPhoto
                    filename: app.photos[app.focusPhoto].name
                    mediaType: app.photos[app.focusPhoto].type
                    position: app.currentIndex; targetFolder: app.targetPath
                    onPrevious: app.navigate(-1)
                    onNext: app.navigate(1)
                    onPickPhoto: id => app.focusPhoto = id
                    onNotice: message => app.notify(message)
                    onShowDetails: details.open()
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 62; color: "#ffffff"
                    Rectangle { width: parent.width; height: 1; color: "#dce3d6" }
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20; spacing: 12
                        Text { text: app.largeMode ? (app.visiblePhotos.length ? (viewer.cropActive ? "当前原图 · " + viewer.crops + " 张子图" : "仅归类当前 1 项") : "没有可归类图片") : "已选 " + app.selection.length + " 项"; color: "#4e6444"; font.pixelSize: 13; font.weight: Font.DemiBold }
                        UiButton { visible: !app.largeMode && app.selection.length > 0; text: "清空"; quiet: true; onClicked: app.selection = [] }
                        Item { Layout.fillWidth: true }
                        Glyph { name: "folder"; width: 18; height: 18; ink: "#6a805e" }
                        Text { text: app.largeMode && viewer.cropActive ? "子图分别归类" : app.targetPath; color: "#4e6444"; font.pixelSize: 13 }
                        UiButton { text: app.largeMode ? (viewer.cropActive ? "保存子图并归档原图  →" : "归类当前图片  →") : "归类所选 " + app.selection.length + " 项  →"; primary: true; implicitHeight: 40; Layout.leftMargin: 8; enabled: app.largeMode ? app.visiblePhotos.length > 0 : app.selection.length > 0; onClicked: { if(app.largeMode && viewer.cropActive) app.notify("预览：未导出子图，也未移动原图"); else app.classify() } }
                    }
                }
            }
        }
    }
    Rectangle {
        z: 100; visible: app.toastText !== ""; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 78
        width: Math.min(parent.width-60, toast.implicitWidth+36); height: 43; radius: 7; color: "#ed243b2d"
        Text { id: toast; anchors.centerIn: parent; text: app.toastText; font.pixelSize: 12; color: "white" }
    }
    Dialog {
        id: sources; anchors.centerIn: parent; width: 390; modal: true; title: "来源目录"; standardButtons: Dialog.Close
        ColumnLayout { width: parent.width; spacing: 10
            Repeater { model: ["春日随拍", "iPhone 导出", "相机存档"]
                UiButton { required property string modelData; text: modelData; Layout.fillWidth: true; chosen: modelData === "春日随拍"; onClicked: app.notify("来源目录为示例，未扫描本机文件") }
            }
            UiButton { text: "+ 添加多个目录"; Layout.fillWidth: true; onClicked: app.notify("添加目录尚未接入") }
        }
    }
    Dialog {
        id: details; anchors.centerIn: parent; width: 360; modal: true; title: "图片信息 · 示例"; standardButtons: Dialog.Close
        Column { spacing: 14
            Text { text: app.photos[app.focusPhoto].name; font.pixelSize: 14; color: "#3f5737" }
            Text { text: "4032 × 3024   ·   3.8 MB\n2025.04.06  14:28\n以上属性为演示数据"; lineHeight: 1.8; color: "#7c8b70"; font.pixelSize: 12 }
        }
    }
    Dialog {
        id: folderDialog; anchors.centerIn: parent; width: 390; modal: true; title: "新建目录 · 界面预览"; standardButtons: Dialog.Ok | Dialog.Cancel
        ColumnLayout { width: parent.width; spacing: 14
            Text { text: "父目录：" + app.targetPath; color: "#65735d"; font.pixelSize: 12 }
            TextField { Layout.fillWidth: true; placeholderText: "目录名称" }
        }
        onAccepted: app.notify("目录创建尚未接入，未修改文件系统")
    }
    Dialog {
        id: boundary; anchors.centerIn: parent; width: 570; modal: true; title: "批次边界预览"; standardButtons: Dialog.Close
        ColumnLayout { width: parent.width; spacing: 14
            RowLayout { Layout.fillWidth: true; spacing: 12
                Repeater { model: 2
                    ColumnLayout { required property int index; Layout.fillWidth: true
                        Image { Layout.fillWidth: true; Layout.preferredHeight: 160; source: app.asset(index); fillMode: Image.PreserveAspectCrop; clip: true }
                        Text { text: index ? "下一批 · 第一张" : "当前批 · 最后一张"; font.pixelSize: 12; color: "#7c8e70" }
                    }
                }
            }
            Text { text: "算法尚未接入，此处仅展示相邻图片。"; font.pixelSize: 12; color: "#89977d" }
        }
    }
}
