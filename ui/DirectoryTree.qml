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
    signal directoryOpened(string path)
    signal newDirectoryRequested(string path)
    signal renameDirectoryRequested(string path,string name)
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
    component DirectoryMenuItem: MenuItem {
        id: entry
        implicitHeight: 36
        contentItem: Text {
            text: entry.text
            leftPadding: 10
            font.pixelSize: 12
            color: entry.enabled ? "#4d6542" : "#9ba493"
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 4
            color: entry.enabled && entry.down ? "#bed3c2" : entry.enabled && entry.highlighted ? "#d6e3d6" : "transparent"
        }
        MouseArea {anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor}
    }
    Menu {
        id: contextMenu
        objectName: "directoryContextMenu"
        parent: tree
        implicitWidth: 180
        padding: 4
        background: Rectangle {color: "#fcfdfb"; radius: 6; border.color: "#ced8c8"}
        DirectoryMenuItem {
            objectName: "openDirectoryMenuItem"
            text: "打开此目录"
            enabled: tree.enabled
            onTriggered: tree.directoryOpened(tree.contextPath)
        }
        DirectoryMenuItem {
            objectName: "createDirectoryMenuItem"
            text: "新建子目录"
            enabled: tree.enabled
            onTriggered: tree.newDirectoryRequested(tree.contextPath)
        }
        DirectoryMenuItem {
            objectName: "renameDirectoryMenuItem"
            text: "重命名"
            enabled: tree.enabled
            onTriggered: tree.renameDirectoryRequested(tree.contextPath, tree.contextName)
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
        color: enabled && dirMouse.pressed ? "#c6d9c2" : enabled && dirMouse.containsMouse ? "#d2e3cc" : tree.selectedPath === modelData.path ? "#dce9d9" : "transparent"
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
                } else tree.directorySelected(modelData.path)
            }
            onDoubleClicked: mouse => {if (mouse.button === Qt.LeftButton) tree.directoryOpened(modelData.path)}
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
                    text: tree.collapsedPaths[modelData.path] ? "▸" : "▾"
                    quiet: true
                    hint: (tree.collapsedPaths[modelData.path] ? "展开 " : "收起 ") + modelData.name
                    Accessible.name: hint
                    onClicked: tree.toggleDirectory(modelData.path)
                }
            }
            Glyph {name: "folder"; width: 16; height: 16; ink: "#768c69"}
            Text {Layout.fillWidth: true; Layout.minimumWidth: 0; text: modelData.name; elide: Text.ElideMiddle; font.pixelSize: 12; color: "#4d6542"}
            Text {visible: tree.workingPath === modelData.path; text: "工作"; font.pixelSize: 10; color: "#7b8b70"}
            Text {text: modelData.mediaCount >= 0 ? modelData.mediaCount : "…"; font.pixelSize: 11; color: modelData.mediaCount > 0 ? "#4d6542" : "#8a9782"; horizontalAlignment: Text.AlignRight}
        }
        ToolTip.visible: dirMouse.containsMouse
        ToolTip.text: modelData.path + "\n单击选择归类目标；双击查看直属图片和视频" + (tree.workingPath === modelData.path ? "\n当前工作目录" : "") + "\n" + (modelData.mediaCount >= 0 ? "含子目录合计 " + modelData.mediaCount + " 个（图片 " + modelData.imageCount + "，视频 " + modelData.videoCount + "）" : "总数暂不可用或统计不完整，可点击刷新") + (modelData.directCount >= 0 ? "\n当前目录直属 " + modelData.directCount + " 个（图片 " + modelData.directImageCount + "，视频 " + modelData.directVideoCount + "）" : "")
        ToolTip.delay: 700
    }
}
