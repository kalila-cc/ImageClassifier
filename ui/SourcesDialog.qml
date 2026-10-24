import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

UiDialog {
    id: dialog
    objectName: "sourcesDialog"
    title: "来源目录"
    width: Math.min(600, parent.width - 48)
    height: Math.min(implicitHeight, parent.height - 48)
    padding: 24
    modal: true
    closePolicy: submitting ? Popup.NoAutoClose : Popup.CloseOnEscape

    property var draftPaths: []
    property bool recursive: true
    property bool submitting: false
    property bool pasteExpanded: false
    property string feedback: ""
    property bool feedbackError: false
    property bool submittedScopeChanged: false
    readonly property bool changedScope: recursive !== backend.recursive
        || draftPaths.length !== backend.sources.length
        || draftPaths.some(path => !backend.sources.some(source => samePath(path, source)))
    readonly property bool rebuildsBatch: backend.sources.length > 0
        && (recursive !== backend.recursive
            || backend.sources.some(source => !draftPaths.some(path => samePath(path, source))))
    readonly property int addedCount: draftPaths.filter(path => !backend.sources.some(source => samePath(path, source))).length
    signal chooseRequested()
    signal beforeApply()
    signal scopeApplied(bool scopeChanged)

    function samePath(a, b) { return a.replace(/\\/g, "/").toLowerCase() === b.replace(/\\/g, "/").toLowerCase() }
    function directoryName(path) { const parts = path.replace(/\\/g, "/").split("/").filter(Boolean); return parts.length ? parts[parts.length - 1] : path }
    function isExisting(path) { return backend.sources.some(source => samePath(path, source)) }
    function report(message, error) { feedback = message; feedbackError = error }
    function addPaths(values) {
        if (submitting || backend.busy) return false;
        const result = backend.validateSources(values);
        if (result.error) { report(result.error, true); return false; }
        const next = draftPaths.slice();
        let duplicates = 0;
        for (const path of result.paths) {
            if (next.some(existing => samePath(path, existing))) duplicates++;
            else next.push(path);
        }
        const added = next.length - draftPaths.length;
        draftPaths = next;
        report(duplicates ? (added ? "已加入 " + added + " 个目录，重复目录已跳过。" : "这些目录已在列表中，无需重复添加。") : "", false);
        return true;
    }
    function addPastedPaths() {
        const values = sourcePaths.text.split(/\r?\n/).map(path => path.trim()).filter(Boolean);
        if (!values.length) return;
        if (addPaths(values)) { sourcePaths.clear(); sourcePaths.forceActiveFocus(); }
    }
    function removePath(index) {
        if (submitting || backend.busy) return;
        const next = draftPaths.slice(); next.splice(index, 1); draftPaths = next;
        report("", false);
    }
    function submit() {
        if (submitting || backend.busy || sourcePaths.text.trim().length || (!draftPaths.length && !backend.sources.length)) return;
        submittedScopeChanged = rebuildsBatch;
        beforeApply();
        report("", false);
        submitting = true;
        backend.applySources(draftPaths, recursive);
    }
    onOpened: {
        draftPaths = backend.sources.slice();
        recursive = backend.sources.length ? backend.recursive : backend.defaultRecursive;
        submitting = false; pasteExpanded = false; sourcePaths.clear(); report("", false);
        chooseButton.forceActiveFocus(Qt.TabFocusReason);
    }
    Connections {
        target: backend
        function onSourcesApplied(success, error) {
            if (!dialog.submitting) return;
            dialog.submitting = false;
            if (success) { dialog.scopeApplied(dialog.submittedScopeChanged); dialog.close(); }
            else dialog.report(error || "未完成扫描，请重试。", true);
        }
    }
    Shortcut {
        sequence: "Ctrl+Return"; enabled: dialog.visible && !dialog.submitting && !backend.busy
        onActivated: { if (sourcePaths.activeFocus) dialog.addPastedPaths(); else dialog.submit(); }
    }
    Shortcut {
        sequence: "Ctrl+Enter"; enabled: dialog.visible && !dialog.submitting && !backend.busy
        onActivated: { if (sourcePaths.activeFocus) dialog.addPastedPaths(); else dialog.submit(); }
    }

    header: Column {
        leftPadding: 24; rightPadding: 24; topPadding: 24; bottomPadding: 0; spacing: 7
        Text { text: "来源目录"; font.pixelSize: 19; font.weight: Font.DemiBold; color: "#263238" }
        Text { text: "选择要整理的图片和视频所在的目录"; font.pixelSize: 12; color: "#6c7b83" }
    }
    contentItem: ScrollView {
        id: bodyScroll
        implicitHeight: body.implicitHeight
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            id: body
            width: bodyScroll.availableWidth
            spacing: 16
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: 3; Layout.rightMargin: 3; spacing: 8
                Text { text: "浏览范围"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#45545b" }
                Text { text: dialog.draftPaths.length + " 个目录"; font.pixelSize: 12; color: "#7b8990" }
                Text { text: "未保存"; visible: dialog.changedScope && (dialog.draftPaths.length > 0 || backend.sources.length > 0); font.pixelSize: 11; color: "#805019" }
                Item { Layout.fillWidth: true }
                UiButton {
                    id: chooseButton; objectName: "sourceChooseButton"
                    text: "添加目录…"; iconName: "plus"; implicitHeight: 32
                    enabled: !dialog.submitting && !backend.busy
                    onClicked: dialog.chooseRequested()
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: dialog.draftPaths.length ? Math.min(210, directoryList.contentHeight + 2) : 130
                color: "#ffffff"; radius: 8; border.color: "#dce2e4"
                ListView {
                    id: directoryList; objectName: "sourceDirectoryList"
                    anchors.fill: parent; anchors.margins: 1
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    model: dialog.draftPaths
                    ScrollBar.vertical: ScrollBar { policy: directoryList.contentHeight > directoryList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                    delegate: Item {
                        required property string modelData
                        required property int index
                        width: directoryList.width; height: 68
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 10; spacing: 12
                            Glyph { name: "folder"; Layout.preferredWidth: 22; Layout.preferredHeight: 22; ink: "#687e82" }
                            ColumnLayout {
                                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 4
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Text { text: dialog.directoryName(modelData); Layout.fillWidth: true; elide: Text.ElideRight; color: "#34444c"; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Text { text: dialog.isExisting(modelData) ? "已添加" : "待添加"; font.pixelSize: 11; color: dialog.isExisting(modelData) ? "#829097" : "#16756a" }
                                }
                                Text {
                                    text: modelData.replace(/\//g, "\\"); Layout.fillWidth: true; elide: Text.ElideMiddle
                                    font.pixelSize: 11; color: "#74838b"
                                    ToolTip.visible: pathHover.hovered; ToolTip.text: text; ToolTip.delay: 500
                                    HoverHandler { id: pathHover }
                                }
                            }
                            UiButton {
                                objectName: "sourceRemove" + index; iconName: "close"; quiet: true; implicitWidth: 30; implicitHeight: 30
                                hint: "移出浏览范围：" + dialog.directoryName(modelData) + "（不删除文件）"
                                enabled: !dialog.submitting && !backend.busy
                                onClicked: dialog.removePath(index)
                            }
                        }
                        Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.leftMargin: 14; anchors.right: parent.right; anchors.rightMargin: 14; height: 1; color: "#edf0f2"; visible: index < dialog.draftPaths.length - 1 }
                    }
                }
                Column {
                    anchors.centerIn: parent; spacing: 9; visible: dialog.draftPaths.length === 0
                    Glyph { anchors.horizontalCenter: parent.horizontalCenter; name: "folderOpen"; width: 28; height: 28; ink: "#8a9b9f" }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: backend.sources.length ? "已移出全部来源目录" : "添加一个目录，开始整理"; font.pixelSize: 13; color: "#55686f" }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: backend.sources.length ? "保存后不再浏览任何来源目录，磁盘文件保留" : "可加入多个目录，文件仍保存在原位置"; font.pixelSize: 11; color: "#829097" }
                }
            }
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: -8; spacing: 8
                Text { text: "移出列表不会删除磁盘中的文件"; Layout.fillWidth: true; font.pixelSize: 11; color: "#829097" }
                UiButton {
                    objectName: "sourcePasteToggle"; text: dialog.pasteExpanded ? "收起路径输入" : "粘贴路径"
                    quiet: true; implicitHeight: 28; enabled: !dialog.submitting && !backend.busy
                    onClicked: { dialog.pasteExpanded = !dialog.pasteExpanded; if (dialog.pasteExpanded) sourcePaths.forceActiveFocus(); }
                }
            }
            ColumnLayout {
                visible: dialog.pasteExpanded; Layout.fillWidth: true; spacing: 8
                Text { text: "目录路径 · 每行一个"; color: "#45545b"; font.pixelSize: 12 }
                ScrollView {
                    Layout.fillWidth: true; Layout.preferredHeight: 88; clip: true
                    TextArea {
                        id: sourcePaths; objectName: "sourcePaths"
                        Accessible.name: "待加入的目录路径，每行一个"
                        placeholderText: "例如 D:\\照片\\相机\n或粘贴资源管理器中复制的目录路径"
                        selectByMouse: true; wrapMode: TextEdit.Wrap; font.pixelSize: 12; padding: 10
                        color: "#34444c"; placeholderTextColor: "#89959a"
                        selectionColor: "#d0e7e1"; selectedTextColor: "#115f56"
                        enabled: !dialog.submitting && !backend.busy
                        background: Rectangle { color: "white"; radius: 6; border.width: sourcePaths.activeFocus ? 2 : 1; border.color: sourcePaths.activeFocus ? "#16756a" : "#dce2e4" }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text { text: "Ctrl + Enter 加入列表"; Layout.fillWidth: true; font.pixelSize: 11; color: "#829097" }
                    UiButton { objectName: "sourcePasteAddButton"; text: "加入列表"; implicitHeight: 30; enabled: sourcePaths.text.trim().length > 0 && !dialog.submitting && !backend.busy; onClicked: dialog.addPastedPaths() }
                }
            }
            Text {
                objectName: "sourceFeedback"
                visible: dialog.feedback.length > 0; Layout.fillWidth: true
                text: dialog.feedback; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                font.pixelSize: 12; lineHeight: 1.3; color: dialog.feedbackError ? "#a33636" : "#16756a"
                Accessible.role: Accessible.AlertMessage; Accessible.name: text
                ToolTip.visible: feedbackHover.hovered; ToolTip.text: text; ToolTip.delay: 500
                HoverHandler { id: feedbackHover }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#e5eaec" }
            RowLayout {
                Layout.fillWidth: true; spacing: 20
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 5
                    Text { text: "包含子目录"; font.pixelSize: 13; font.weight: Font.Medium; color: "#34444c" }
                    Text { text: dialog.recursive ? "读取列表中每个目录及其所有子目录" : "只读取列表中各个目录的直属文件"; Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 11; color: "#74838b" }
                }
                UiSwitch { objectName: "sourceRecursiveSwitch"; Accessible.name: "包含子目录"; checked: dialog.recursive; enabled: !dialog.submitting && !backend.busy; onToggled: dialog.recursive = checked }
            }
        }
    }
    footer: ColumnLayout {
        spacing: 0
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#e5eaec" }
        ColumnLayout {
            Layout.fillWidth: true; Layout.margins: 24; Layout.topMargin: 16; spacing: 14
            Text {
                Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 11; color: "#74838b"
                text: dialog.submitting ? backend.status
                    : sourcePaths.text.trim().length ? "还有路径未加入列表，请先加入或清空输入。"
                    : !dialog.draftPaths.length && backend.sources.length ? "尚未保存。保存后停止浏览这些目录，文件和裁剪草稿保留。"
                    : dialog.rebuildsBatch ? "尚未保存。保存后将按新的浏览范围重新分批。"
                    : dialog.addedCount && backend.sources.length ? "尚未保存。新增文件进入待加载队列，保留当前批次。"
                    : "图片和视频分批加载，原文件不会被移动。"
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                UiButton {
                    objectName: "sourceCancelButton"
                    text: dialog.submitting ? (backend.cancelRequested ? "正在停止…" : "取消扫描") : dialog.changedScope || sourcePaths.text.length ? "取消" : "关闭"
                    enabled: !dialog.submitting || (!!backend.cancelAction && !backend.cancelRequested)
                    implicitWidth: 96
                    onClicked: { if (dialog.submitting) backend.cancel(); else dialog.reject(); }
                }
                UiButton {
                    objectName: "sourceSubmitButton"; primary: true; implicitWidth: 126
                    iconName: !dialog.changedScope && backend.sources.length ? "refresh" : ""
                    text: dialog.submitting ? "正在保存…" : !backend.sources.length ? "开始整理" : dialog.changedScope ? "保存更改" : "刷新列表"
                    enabled: !dialog.submitting && !backend.busy && !sourcePaths.text.trim().length && (dialog.draftPaths.length > 0 || backend.sources.length > 0)
                    onClicked: dialog.submit()
                }
            }
        }
    }
}
