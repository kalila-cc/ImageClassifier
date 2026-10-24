import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ListView {
    id: tree
    property var directories: []
    property string rootPath: ""
    property string selectedPath: ""
    property string workingPath: ""
    property var collapsedPaths: ({})
    property string contextPath: ""
    property string contextName: ""
    property string retainedRootPath: ""
    signal directorySelected(string path)
    signal selectionGestureStarted()
    signal selectionGestureReverted()
    signal directoryOpened(string path)
    signal newDirectoryRequested(string path)
    signal renameDirectoryRequested(string path,string name)
    signal directoryRevealRequested(string path)
    onRootPathChanged: {
        if (rootPath !== retainedRootPath) collapsedPaths = ({})
        retainedRootPath = ""
    }
    function toggleDirectory(path) {
        const next = Object.assign({}, collapsedPaths)
        if (next[path]) delete next[path]
        else next[path] = true
        collapsedPaths = next
    }
    function expandDirectory(path) {
        const next = Object.assign({}, collapsedPaths)
        delete next[path]
        collapsedPaths = next
    }
    function relocateDirectories(from, to) {
        if (rootPath.toLowerCase() === from.toLowerCase()) retainedRootPath = to
        const next = {}
        for (const path of Object.keys(collapsedPaths)) next[backend.relocatedPath(path, from, to)] = true
        collapsedPaths = next
    }
    UiMenu {
        id: contextMenu
        objectName: "directoryContextMenu"
        parent: tree
        UiMenuItem {
            objectName: "openDirectoryMenuItem"
            text: "浏览此目录"; iconName: "grid"
            enabled: tree.enabled
            onTriggered: tree.directoryOpened(tree.contextPath)
        }
        UiMenuItem {
            objectName: "createDirectoryMenuItem"
            text: "新建子目录"; iconName: "plus"
            enabled: tree.enabled
            onTriggered: tree.newDirectoryRequested(tree.contextPath)
        }
        UiMenuItem {
            objectName: "renameDirectoryMenuItem"
            text: "重命名"; iconName: "rename"
            enabled: tree.enabled
            onTriggered: tree.renameDirectoryRequested(tree.contextPath, tree.contextName)
        }
        UiMenuItem {
            objectName: "revealDirectoryMenuItem"
            text: "在资源管理器中打开"; iconName: "folderOpen"
            enabled: tree.enabled
            onTriggered: tree.directoryRevealRequested(tree.contextPath)
        }
    }
    model: {
        const result = []
        let hiddenBelow = -1
        for (let i = 0; i < directories.length; ++i) {
            const row = directories[i]
            if (hiddenBelow >= 0 && row.depth > hiddenBelow) continue
            hiddenBelow = -1
            const hasChildren = i + 1 < directories.length && directories[i + 1].depth > row.depth
            result.push(Object.assign({}, row, {hasChildren: hasChildren}))
            if (hasChildren && collapsedPaths[row.path]) hiddenBelow = row.depth
        }
        return result
    }
    clip: true
    spacing: 2
    ScrollBar.vertical: ScrollBar {}
    delegate: Rectangle {
        required property var modelData
        width: ListView.view.width
        height: 37
        radius: 5
        color: enabled && dirMouse.pressed ? "#c6ddd8" : enabled && dirMouse.containsMouse ? "#e1e7e9" : tree.selectedPath === modelData.path ? "#dcece8" : "transparent"
        Rectangle {anchors.left:parent.left;anchors.verticalCenter:parent.verticalCenter;width:3;height:19;radius:2;color:"#16756a";visible:tree.selectedPath===modelData.path}
        MouseArea {
            id: dirMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    tree.contextPath = modelData.path
                    tree.contextName = modelData.path.replace(/\\/g, "/").split("/").pop()
                    const point = mapToItem(tree, mouse.x, mouse.y)
                    contextMenu.popup(point.x, point.y)
                } else {
                    tree.selectionGestureStarted()
                    tree.directorySelected(modelData.path)
                }
            }
            onDoubleClicked: mouse => {
                if (mouse.button === Qt.LeftButton) {
                    // The first click selects immediately; a double-click is only a browse action.
                    tree.selectionGestureReverted()
                    tree.directoryOpened(modelData.path)
                }
            }
        }
        RowLayout {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 2 + Math.min(modelData.depth, 5) * 12
            anchors.right: parent.right
            anchors.rightMargin: 8
            spacing: 4
            Item {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 28
                UiButton {
                    anchors.fill: parent
                    visible: modelData.hasChildren
                    iconName: tree.collapsedPaths[modelData.path] ? "chevronRight" : "chevronDown"
                    quiet: true
                    hint: (tree.collapsedPaths[modelData.path] ? "展开 " : "收起 ") + modelData.name
                    Accessible.name: hint
                    onClicked: tree.toggleDirectory(modelData.path)
                }
            }
            Glyph {name: "folder"; width: 16; height: 16; ink: "#74868d"}
            Column {
                Layout.fillWidth:true;Layout.minimumWidth:0;spacing:0
                Text {width:parent.width;text:modelData.depth===0?(modelData.path.replace(/\\/g,"/").split("/").filter(p=>p).pop()||modelData.name):modelData.name;elide:Text.ElideMiddle;font.pixelSize:13;font.weight:tree.selectedPath===modelData.path?Font.DemiBold:Font.Normal;color:tree.selectedPath===modelData.path?"#126257":"#3a4c54"}
                Text {visible:tree.workingPath===modelData.path;text:"浏览中";font.pixelSize:10;color:"#71828a"}
            }
            Rectangle {Layout.preferredWidth:Math.max(25,countLabel.implicitWidth+12);Layout.preferredHeight:21;radius:5;color:tree.selectedPath===modelData.path?"#c5ded6":"#e3e8eb"
                Text {id:countLabel;anchors.centerIn:parent;text:modelData.mediaCount>=0?modelData.mediaCount:"…";font.pixelSize:11;color:tree.selectedPath===modelData.path?"#126257":"#677780"}
            }
        }
        ToolTip.visible: dirMouse.containsMouse
        ToolTip.text: modelData.path + "\n单击选择归类目标；双击查看直属图片和视频" + (tree.workingPath === modelData.path ? "\n当前浏览目录" : "") + "\n" + (modelData.mediaCount >= 0 ? "含子目录合计 " + modelData.mediaCount + " 个（图片 " + modelData.imageCount + "，视频 " + modelData.videoCount + "）" : "总数暂不可用或统计不完整，可点击刷新") + (modelData.directCount >= 0 ? "\n当前目录直属 " + modelData.directCount + " 个（图片 " + modelData.directImageCount + "，视频 " + modelData.directVideoCount + "）" : "")
        ToolTip.delay: 700
    }
}
