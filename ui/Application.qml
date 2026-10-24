import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: app
    visible: true; width: 1460; height: 920; minimumWidth: 1120; minimumHeight: 720
    title: "归图 · ImageClassifier"; color: "#f3f5f6"
    palette.highlight: "#16756a"; palette.buttonText: "#3e4c53"; palette.text: "#3e4c53"
    palette.base: "#ffffff"; palette.window: "#fafbfc"; palette.button: "#edf1f2"; palette.windowText: "#3e4c53"; palette.highlightedText: "#ffffff"
    property bool largeMode: false
    property bool preferencesLoaded: false
    property bool settingsOpen: false
    property string focusId: ""
    property var selection: []
    property string destination: ""
    readonly property string browsingPath: backend.sources.length === 1 && !backend.recursive ? backend.sources[0] : ""
    property string mediaFilter: "全部"
    property var filtered: backend.items.filter(a => (mediaFilter === "全部" || a.type === mediaFilter) && a.name.toLowerCase().includes(search.text.toLowerCase()))
    property var current: filtered.find(a => a.id === focusId) || ({})
    property int currentIndex: filtered.findIndex(a => a.id === focusId)
    property bool allSelected: filtered.length > 0 && filtered.every(a => selection.includes(a.id))
    property string pickerPurpose: "source"
    property string notice: ""
    property var previousFiltered: []
    property var directorySelectionSnapshot: ({})
    readonly property int hiddenSelectedCount: selection.filter(id=>!filtered.some(a=>a.id===id)).length
    readonly property bool modalOpen: backend.restarting||noticeDialog.visible||sourcesDialog.visible||historyDialog.visible||clearHistoryDialog.visible||newDirectory.visible||renameDirectoryDialog.visible||folderPicker.visible
    readonly property bool textEditing: activeFocusItem && activeFocusItem.cursorPosition !== undefined
    onFilteredChanged: {
        if(!filtered.some(a=>a.id===focusId)) {
            const oldIndex=previousFiltered.findIndex(a=>a.id===focusId);
            const surviving=previousFiltered.slice(Math.max(0,oldIndex+1)).concat(previousFiltered.slice(0,Math.max(0,oldIndex)).reverse()).find(a=>filtered.some(b=>b.id===a.id));
            focusId=surviving?surviving.id:(filtered.length?filtered[0].id:"");
        }
        previousFiltered=filtered.slice();
    }
    function clearFilters(){mediaFilter="全部";search.clear()}
    function emptyAction(){if(backend.items.length)clearFilters();else if(backend.remaining>0)backend.nextBatch(backend.batchSize);else if(backend.sources.length)refreshWorkspace();else sourcesDialog.open()}
    readonly property string emptyTitle: backend.busy?"正在准备图片":backend.items.length?("没有匹配的"+(app.mediaFilter==="全部"?"图片或视频":app.mediaFilter)):backend.remaining>0?"当前批已整理完":backend.sources.length?"当前目录没有待整理文件":"添加目录，开始整理"
    readonly property string emptyDetail: backend.busy?backend.status:backend.items.length?"调整筛选条件，或清除文件名搜索。":backend.remaining>0?"后续还有 "+backend.remaining+" 项，继续下一批即可。":backend.sources.length?"可双击左侧目录浏览文件，或刷新读取新加入的图片和视频。":"添加存放图片或视频的目录，文件会分批展示；在左侧选择归类目标。"
    readonly property string emptyActionText: backend.items.length?"清除筛选":backend.remaining>0?"继续下一批":backend.sources.length?"刷新文件":"添加来源目录"
    onLargeModeChanged: {
        backend.livePhoto.stop();
        if(!preferencesLoaded)return;
        backend.largeMode=largeMode;
        if(largeMode)editor.enterEditing();
    }
    function tell(s) {notice=s;noticeDialog.open()}
    function openSettings() {
        editor.flushDraft();editor.stopPlayback();editor.invalidateSuggestion();
        settingsOpen=true;settingsPage.forceActiveFocus();
    }
    function restartApplication() {
        if(backend.busy||backend.restarting||modalOpen)return;
        editor.invalidateSuggestion();editor.stopPlayback();
        if(!editor.flushDraft())return;
        backend.restartApplication();
    }
    function openImage(id) {
        if(backend.busy||id===focusId||!filtered.some(a=>a.id===id))return;
        editor.flushDraft();editor.stopPlayback();editor.invalidateSuggestion();focusId=id;
    }
    function activateImage(id) {
        if(backend.busy||!filtered.some(a=>a.id===id))return;
        openImage(id);largeMode=true;
    }
    function playVideo(id) {
        if(backend.busy||modalOpen)return;
        activateImage(id);
        Qt.callLater(function(){if(app.largeMode&&app.focusId===id&&!backend.busy&&!app.modalOpen)editor.playVideo()});
    }
    function navigate(n) {let i=currentIndex+n;if(i>=0&&i<filtered.length)openImage(filtered[i].id)}
    function transferSelection(copyOnly) {
        editor.flushDraft();editor.stopPlayback();editor.invalidateSuggestion();
        const ids=largeMode?[focusId]:selection;
        if(copyOnly)backend.copyAssets(ids,destination);else backend.moveAssets(ids,destination);
    }
    function toggle(id) {focusId=id;let a=selection.slice();let i=a.indexOf(id);if(i>=0)a.splice(i,1);else a.push(id);selection=a}
    function chooseFolder(purpose) {pickerPurpose=purpose;folderPicker.open()}
    function createChildDirectory(path) {newDirectory.parentPath=path;newDirectory.open()}
    function viewDirectory(path) {
        if(backend.busy)return;
        editor.flushDraft();editor.stopPlayback();
        selection=[];mediaFilter="全部";search.clear();
        backend.openSource(path,false);
    }
    function refreshWorkspace() {
        if(backend.busy)return;
        if(backend.sources.length){editor.flushDraft();editor.stopPlayback();backend.refresh()}
        else backend.refreshDirectories();
    }
    Connections {
        target: backend
        function onLargeModeChanged() {if(app.preferencesLoaded)app.largeMode=backend.largeMode}
        function onMessage(text) {if(sourcesDialog.submitting)sourcesDialog.report(text,true);else app.tell(text)}
        function onDirectoryCreated(parent,path) {directoryTree.expandDirectory(parent)}
        function onDirectoryRenamed(from,to) {
            editor.relocateTargets(from,to);
            app.destination=backend.relocatedPath(app.destination,from,to);
            directoryTree.relocateDirectories(from,to);
        }
        function onChanged() {
            app.selection=app.selection.filter(id=>backend.items.some(a=>a.id===id));
            if(!app.destination && backend.targetRoot)app.destination=backend.targetRoot;
        }
    }
    Component.onCompleted: {
        destination=backend.targetRoot;
        largeMode=backend.largeMode;
        preferencesLoaded=true;
        if(largeMode)editor.enterEditing();
    }
    onClosing: close => { if(backend.busy){close.accepted=false;tell("当前操作尚未结束，请完成后再关闭。")}else editor.flushDraft() }
    Shortcut {sequence:"Left";enabled:!app.settingsOpen&&app.largeMode&&!backend.busy&&!editor.keyboardAdjusting&&!app.modalOpen&&!app.textEditing;onActivated:app.navigate(-1)}
    Shortcut {sequence:"Right";enabled:!app.settingsOpen&&app.largeMode&&!backend.busy&&!editor.keyboardAdjusting&&!app.modalOpen&&!app.textEditing;onActivated:app.navigate(1)}
    Shortcut {sequence:"Escape";enabled:app.settingsOpen&&!noticeDialog.visible&&!backend.restarting;onActivated:settingsPage.backRequested()}
    Shortcut {sequence:"Ctrl+A";enabled:!app.settingsOpen&&!app.largeMode&&!backend.busy&&!app.modalOpen&&!app.textEditing;onActivated:app.selection=Array.from(new Set(app.selection.concat(app.filtered.map(a=>a.id))))}
    Shortcut {sequence:"Escape";enabled:!app.settingsOpen&&!app.largeMode&&!backend.busy&&!app.modalOpen&&!app.textEditing&&!batchSelection.dragging&&app.selection.length>0;onActivated:app.selection=[]}
    Shortcut {sequence:"F5";enabled:!app.settingsOpen&&!backend.busy&&!app.modalOpen;onActivated:app.refreshWorkspace()}
    ColumnLayout {
        anchors.fill:parent;spacing:0;visible:!app.settingsOpen;enabled:visible&&!backend.restarting
        Rectangle {
            Layout.fillWidth:true;Layout.preferredHeight:60;color:"#202629"
            RowLayout {
                anchors.left:parent.left;anchors.leftMargin:20;anchors.verticalCenter:parent.verticalCenter
                width:Math.min(440,parent.width/2-132);spacing:12
                Image {
                    objectName:"applicationLogo"
                    Layout.minimumWidth:28;Layout.preferredWidth:28;Layout.maximumWidth:28
                    Layout.minimumHeight:28;Layout.preferredHeight:28;Layout.maximumHeight:28
                    source:"brand/guitu-header.svg";sourceSize:Qt.size(84,84);fillMode:Image.PreserveAspectFit
                }
                Text {text:"归图";font.pixelSize:18;font.weight:Font.DemiBold;color:"#f4f7f7"}
                Rectangle {width:1;height:18;color:"#465054";Layout.leftMargin:6;Layout.rightMargin:2}
                UiButton {objectName:"sourcesButton";text:backend.sources.length?"来源目录 · "+backend.sources.length:"添加来源";hint:"管理当前浏览的来源目录，或添加其他目录";iconName:"folder";dark:true;quiet:true;enabled:!backend.busy;onClicked:sourcesDialog.open()}
                Text {
                    Layout.fillWidth:true;Layout.minimumWidth:0
                    text:backend.sources.length?((app.browsingPath?app.browsingPath.replace(/\\/g,"/").split("/").pop()+" · ":"")+backend.items.length+" 项"):"本地图片整理"
                    elide:Text.ElideMiddle;color:"#a5b2b7";font.pixelSize:12
                    ToolTip.visible:sourceHover.hovered;ToolTip.text:backend.sources.join("\n");ToolTip.delay:600
                    HoverHandler {id:sourceHover}
                }
            }
            Rectangle {
                anchors.centerIn:parent;width:218;height:38;radius:9;color:"#141b1e";border.color:"#3c464b"
                Row {anchors.centerIn:parent;spacing:4
                    UiButton {objectName:"batchModeButton";text:"批量模式";hint:"多选图片或视频，批量移动到目标目录";iconName:"grid";dark:true;implicitWidth:103;implicitHeight:30;chosen:!app.largeMode;quiet:true;onClicked:{editor.flushDraft();app.largeMode=false}}
                    UiButton {objectName:"largeModeButton";text:"大图模式";hint:"逐张查看图片，保留上次的裁剪模式选择";iconName:"image";dark:true;implicitWidth:103;implicitHeight:30;chosen:app.largeMode;quiet:true;onClicked:app.largeMode=true}
                }
            }
            Row {anchors.right:parent.right;anchors.rightMargin:18;anchors.verticalCenter:parent.verticalCenter;spacing:8
                UiButton {objectName:"restartApplicationButton";text:backend.restarting?"正在重启…":"重启应用";iconName:"restart";dark:true;quiet:true;enabled:!backend.busy&&!backend.restarting&&!app.modalOpen;hint:backend.busy?"当前操作完成后可重启":"保存当前草稿并重新打开归图";onClicked:app.restartApplication()}
                UiButton {objectName:"historyButton";text:"操作记录"+(backend.pending?" · "+backend.pending+" 待处理":"");hint:"查看文件操作记录、撤销移动或继续未完成的操作";iconName:"history";dark:true;quiet:true;enabled:!backend.busy;onClicked:{backend.loadHistory();historyDialog.open()}}
                UiButton {objectName:"settingsButton";text:"设置";iconName:"settings";dark:true;quiet:true;implicitWidth:76;hint:"打开设置";onClicked:app.openSettings()}
            }
            Rectangle {anchors.bottom:parent.bottom;width:parent.width;height:1;color:"#354047"}
        }
        RowLayout {
            Layout.fillWidth:true;Layout.fillHeight:true;spacing:0
            Rectangle {
                Layout.preferredWidth:220;Layout.fillHeight:true;color:"#edf0f2"
                Rectangle {anchors.right:parent.right;width:1;height:parent.height;color:"#dce2e4"}
                ColumnLayout {anchors.fill:parent;anchors.margins:12;spacing:7
                    RowLayout {Layout.fillWidth:true;spacing:8
                        Text {text:"归类目录";font.pixelSize:13;font.weight:Font.DemiBold;color:"#34444c";Layout.fillWidth:true}
                        UiButton {
                            objectName:"refreshDirectoriesButton";iconName:"refresh";quiet:true;implicitWidth:30;implicitHeight:30
                            hint:"刷新目录与图片";Accessible.name:hint
                            enabled:!backend.busy&&(backend.targetRoot!==""||backend.sources.length>0)
                            onClicked:app.refreshWorkspace()
                        }
                        UiButton {
                            id:directoryMoreButton;objectName:"directoryMoreButton"
                            quiet:true;implicitWidth:30;implicitHeight:30;hint:"目录管理";Accessible.name:hint
                            onClicked:directoryMenu.popup(0,height)
                            contentItem:Item {
                                Row {anchors.centerIn:parent;spacing:3
                                    Repeater {model:3;Rectangle {width:3;height:3;radius:1.5;color:"#687a82"}}
                                }
                            }
                            UiMenu {
                                id:directoryMenu;objectName:"directoryManagementMenu";parent:directoryMoreButton
                                UiMenuItem {objectName:"changeRootMenuItem";iconName:"folderOpen";text:backend.targetRoot?"更换根目录":"选择根目录";enabled:!backend.busy;onTriggered:app.chooseFolder("target")}
                            }
                        }
                    }
                    Text {text:"单击选目标 · 双击浏览";font.pixelSize:11;color:"#6c7b83";visible:backend.targetRoot!=="";Layout.bottomMargin:4}
                    ColumnLayout {
                        visible:backend.targetRoot==="";Layout.fillWidth:true;Layout.topMargin:20;spacing:12
                        Text {text:"选择归类目录后，可将图片\n分配到其中任意一层。";Layout.fillWidth:true;wrapMode:Text.Wrap;font.pixelSize:12;color:"#6c7b83";lineHeight:1.5}
                        UiButton {objectName:"chooseRootButton";text:"选择归类目录";Layout.fillWidth:true;enabled:!backend.busy;onClicked:app.chooseFolder("target")}
                    }
                    DirectoryTree {
                        id:directoryTree
                        objectName:"directoryTree"
                        Layout.fillWidth:true;Layout.fillHeight:true
                        directories:backend.directories;rootPath:backend.targetRoot
                        selectedPath:app.destination;workingPath:app.browsingPath;enabled:!backend.busy
                        onSelectionGestureStarted:{
                            editor.capture();
                            app.directorySelectionSnapshot={target:app.destination,asset:editor.loadedId,index:editor.selectedDraft,cropTarget:editor.selectedDraft>=0?editor.drafts[editor.selectedDraft].target||"":""};
                        }
                        onSelectionGestureReverted:{
                            const prior=app.directorySelectionSnapshot;
                            if(prior.target!==undefined){app.destination=prior.target;if(app.largeMode&&prior.asset===editor.loadedId&&prior.index===editor.selectedDraft)editor.assignTarget(prior.cropTarget)}
                            app.directorySelectionSnapshot=({});
                        }
                        onDirectorySelected:path=>{app.destination=path;if(app.largeMode)editor.assignTarget(path)}
                        onDirectoryOpened:path=>app.viewDirectory(path)
                        onNewDirectoryRequested:path=>app.createChildDirectory(path)
                        onRenameDirectoryRequested:(path,name)=>{renameDirectoryDialog.directoryPath=path;renameDirectoryDialog.currentName=name;renameDirectoryDialog.open()}
                        onDirectoryRevealRequested:path=>backend.reveal(path)
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth:true;Layout.fillHeight:true;spacing:0
                ColumnLayout {
                    visible:!app.largeMode;Layout.fillWidth:true;Layout.fillHeight:true;spacing:0
                    Rectangle {Layout.fillWidth:true;Layout.preferredHeight:52;color:"#fafbfc"
                        Rectangle {anchors.bottom:parent.bottom;width:parent.width;height:1;color:"#e0e5e8"}
                        RowLayout {anchors.fill:parent;anchors.leftMargin:14;anchors.rightMargin:14;spacing:8
                            UiButton {objectName:"selectAllButton";text:app.allSelected?"取消全选":"全选";quiet:true;enabled:!backend.busy&&app.filtered.length>0;hint:app.allSelected?"取消当前列表中的选择，保留被筛选隐藏的选择":"选择当前列表中的所有文件 · Ctrl+A";onClicked:{if(app.allSelected)app.selection=app.selection.filter(id=>!app.filtered.some(a=>a.id===id));else app.selection=Array.from(new Set(app.selection.concat(app.filtered.map(a=>a.id))))}}
                            UiButton {text:"取消选择";quiet:true;enabled:!backend.busy&&app.selection.length>0;hint:"取消全部选择，包括被筛选隐藏的文件 · Esc";onClicked:app.selection=[]}
                            Repeater {model:["全部","图片","视频"]
                                UiButton {required property string modelData;text:modelData;chosen:app.mediaFilter===modelData;quiet:true;implicitWidth:50;onClicked:app.mediaFilter=modelData}
                            }
                            Text {text:app.filtered.length+" 项";font.pixelSize:11;color:"#718088"}
                            Item {Layout.fillWidth:true}
                            Text {text:"缩略图";font.pixelSize:11;color:"#6c7b83"}
                            UiSlider {
                                id:thumbSize;objectName:"workspaceThumbnailSize";Layout.preferredWidth:95
                                from:170;to:310;value:backend.thumbnailSize;stepSize:35
                                onMoved:{backend.thumbnailSize=value;grid.queueSelectionReveal()}
                                onPressedChanged:if(!pressed&&grid.pendingSelectionId!=="")selectionRevealTimer.restart()
                            }
                            UiTextField {id:search;objectName:"filenameSearch";Accessible.name:"按文件名筛选当前批次";Layout.preferredWidth:180;placeholderText:"搜索文件名";rightPadding:30
                                UiButton {anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;width:28;height:28;implicitWidth:28;iconName:"close";quiet:true;visible:search.text.length>0;hint:"清除搜索";onClicked:{search.clear();search.forceActiveFocus()}}
                            }
                        }
                    }
                    GridView {id:grid;objectName:"batchGrid";Layout.fillWidth:true;Layout.fillHeight:true;Layout.margins:12;clip:true;model:app.filtered
                        cacheBuffer:Math.max(height,cellHeight*2)
                        property string pendingSelectionId:""
                        function queueSelectionReveal() {
                            pendingSelectionId="";
                            if(app.largeMode||app.settingsOpen)return;
                            const visibleIds=new Set(app.filtered.map(a=>a.id));
                            for(let i=app.selection.length-1;i>=0;--i) {
                                if(visibleIds.has(app.selection[i])){pendingSelectionId=app.selection[i];break;}
                            }
                            if(pendingSelectionId!==""&&!thumbSize.pressed)selectionRevealTimer.restart();
                        }
                        Timer {
                            id:selectionRevealTimer;interval:0
                            onTriggered:{
                                if(thumbSize.pressed)return;
                                const id=grid.pendingSelectionId;grid.pendingSelectionId="";
                                if(app.largeMode||app.settingsOpen||!app.selection.includes(id))return;
                                const index=app.filtered.findIndex(a=>a.id===id);
                                if(index<0)return;
                                // Finish the new column/row layout before positioning by asset ID.
                                grid.cancelFlick();grid.forceLayout();
                                grid.positionViewAtIndex(index,GridView.Center);
                            }
                        }
                        property int columns:Math.max(2,Math.floor(width/thumbSize.value))
                        cellWidth:Math.floor(width/columns);cellHeight:cellWidth*.73+36
                        ScrollBar.vertical:ScrollBar {}
                        GridSelection {
                            id:batchSelection
                            parent:grid;anchors.fill:parent;gridView:grid;records:app.filtered;selectedIds:app.selection
                            enabled:!backend.busy&&grid.count>0;visible:!app.largeMode
                            onSelectionRequested:ids=>app.selection=ids
                            onFocusRequested:id=>app.focusId=id
                            onActivated:id=>app.activateImage(id)
                        }
                        delegate:PhotoCard {
                            onPlayRequested:app.playVideo(modelData.id)
                            required property var modelData
                            required property int index
                            enabled:!backend.busy
                            externalHovered:batchSelection.hoveredIndex===index
                            externalPressed:batchSelection.downIndex===index
                            width:grid.cellWidth-10;height:grid.cellHeight-10
                            photo:modelData.thumb;filename:modelData.name;kind:modelData.kind
                            asset:modelData;liveAvailable:!app.largeMode&&!app.settingsOpen&&!backend.busy
                            selected:app.selection.includes(modelData.id);focused:app.focusId===modelData.id
                            onClicked:app.toggle(modelData.id)
                            onOpened:app.activateImage(modelData.id)
                        }
                        WorkspaceEmpty {parent:grid;anchors.fill:parent;visible:grid.count===0;title:app.emptyTitle;detail:app.emptyDetail;actionText:app.emptyActionText;busy:backend.busy;onActivated:app.emptyAction()}
                    }
                }
                ImageEditor {id:editor;objectName:"imageEditor";visible:app.largeMode&&app.filtered.length>0;activeView:visible&&!app.settingsOpen;enabled:!backend.busy;Layout.fillWidth:true;Layout.fillHeight:true;asset:app.current;targetFolder:app.destination
                    position:app.currentIndex;total:app.filtered.length
                    navigationItems:app.filtered;onImageRequested:assetId=>app.openImage(assetId)
                    onRefreshRequested:app.refreshWorkspace()
                    onPrevious:app.navigate(-1);onNext:app.navigate(1);onNotice:msg=>app.tell(msg)
                }
                WorkspaceEmpty {objectName:"largeEmptyState";visible:app.largeMode&&app.filtered.length===0;Layout.fillWidth:true;Layout.fillHeight:true;title:app.emptyTitle;detail:app.emptyDetail;actionText:app.emptyActionText;busy:backend.busy;onActivated:app.emptyAction()}
                Rectangle {Layout.fillWidth:true;Layout.preferredHeight:62;color:"#fafbfc"
                    Rectangle {width:parent.width;height:1;color:"#dce2e4"}
                    RowLayout {anchors.fill:parent;anchors.leftMargin:18;anchors.rightMargin:18;spacing:12
                        Text {text:app.largeMode?(app.current.id&&editor.cropActive?"当前图片 · "+editor.drafts.length+" 个裁剪区域":(app.current.id?"仅处理当前 1 项":"未选择文件")):"已选 "+app.selection.length+" 项";font.pixelSize:12;font.weight:Font.DemiBold;color:"#334950"}
                        UiButton {objectName:"clearHiddenSelection";visible:!app.largeMode&&app.hiddenSelectedCount>0;text:app.hiddenSelectedCount+" 项已隐藏 · 取消选择";quiet:true;tone:"warning";hint:"这些已选文件被筛选隐藏，移动和复制仍会包含它们；点击只取消隐藏文件的选择";onClicked:app.selection=app.selection.filter(id=>app.filtered.some(a=>a.id===id))}
                        Item {Layout.fillWidth:true}
                        Text {text:app.destination?(app.largeMode?"原文件移至：":"移至：")+app.destination:"请选择目标目录";Layout.fillWidth:true;ToolTip.visible:destinationHover.hovered;ToolTip.text:app.destination;ToolTip.delay:500;HoverHandler{id:destinationHover}Layout.maximumWidth:240;Layout.minimumWidth:0;elide:Text.ElideMiddle;font.pixelSize:11;color:"#667780"}
                        UiButton {objectName:"cropOnlyButton";text:"仅裁剪";quiet:true;implicitHeight:40;visible:app.largeMode&&!!app.current.id&&editor.cropActive&&!editor.isVideo;enabled:!backend.busy&&editor.previewReady&&!app.current.blocked
                            hint:"子图保存在原图所在目录并加入列表，原图保留，无需选择目标目录"
                            onClicked:{editor.stopPlayback();editor.exportDrafts(true)}
                        }
                        UiButton {objectName:"cropToTargetsButton";text:"裁剪并归类";implicitHeight:40;visible:app.largeMode&&!!app.current.id&&editor.cropActive&&!editor.isVideo;enabled:!backend.busy&&editor.previewReady&&!app.current.blocked
                            hint:"按右侧各子图的独立目标保存，保留原图"
                            onClicked:{editor.stopPlayback();editor.exportDrafts(false)}
                        }
                        UiButton {objectName:"moveOriginalButton";text:app.largeMode?(editor.isVideo?"移动视频":"移动原图"):"移动所选 "+app.selection.length+" 项";primary:true;iconName:"move";implicitHeight:40;enabled:!backend.busy&&app.destination!==""&&(app.largeMode?!!app.current.id&&!app.current.blocked:app.selection.length>0)
                            hint:app.largeMode?"将当前文件完整移到所选目录，不应用裁剪或旋转；原位置不再保留":"将全部已选文件移到所选目录（包含筛选隐藏的选择）；原位置不再保留"
                            onClicked:app.transferSelection(false)
                        }
                        UiButton {
                            id:fileMoreButton;objectName:"fileMoreButton";text:"更多";hint:"更多文件操作：复制到所选目录并保留来源文件";quiet:true;implicitWidth:48;implicitHeight:40
                            enabled:!backend.busy&&app.destination!==""&&(app.largeMode?!!app.current.id&&!app.current.blocked:app.selection.length>0)
                            onClicked:fileMenu.popup(0,-fileMenu.implicitHeight)
                            UiMenu {id:fileMenu;parent:fileMoreButton
                                UiMenuItem {objectName:"copyOriginalMenuItem";iconName:"copy";text:app.largeMode?"复制当前文件到所选目录":"复制所选 "+app.selection.length+" 项到所选目录";onTriggered:app.transferSelection(true)}
                            }
                        }
                    }
                }
            }
        }
        Rectangle {Layout.fillWidth:true;Layout.preferredHeight:30;color:"#edf0f2"
            RowLayout {anchors.fill:parent;anchors.leftMargin:15;anchors.rightMargin:12;spacing:8
                Text {text:backend.status;elide:Text.ElideRight;Layout.fillWidth:true;font.pixelSize:11;color:"#63757e"}
                Text {text:"待加载 "+backend.remaining+" 项";font.pixelSize:11;color:"#6c7b83"}
                UiButton {objectName:"extendBatchButton";text:"再加入 "+Math.min(10,backend.remaining)+" 项";quiet:true;implicitHeight:24;visible:backend.remaining>0;enabled:!backend.busy;hint:"把接下来的文件加入本批，便于将相关照片一起处理";onClicked:backend.extendBatch(10)}
                UiButton {objectName:"batchTaskButton";text:backend.busy?(backend.cancelRequested?"正在停止…":backend.cancelAction||"处理中…"):"下一批";quiet:true;tone:backend.busy&&backend.cancelAction?"warning":"normal";implicitHeight:24;enabled:backend.busy?(!!backend.cancelAction&&!backend.cancelRequested):(backend.items.length===0&&backend.remaining>0);hint:backend.busy?"在安全位置停止，已完成的文件操作不会撤销":"当前批次移出全部文件后，加载下一批";onClicked:{if(backend.busy)backend.cancel();else backend.nextBatch(backend.batchSize)}}
            }
        }
    }
    SettingsPage {
        id:settingsPage;objectName:"settingsPage";anchors.fill:parent;visible:app.settingsOpen;enabled:visible&&!backend.restarting
        onBackRequested:{app.settingsOpen=false;app.contentItem.forceActiveFocus()}
    }
    FolderDialog {id:folderPicker;title:app.pickerPurpose==="target"?"选择目标根目录":"选择来源目录"
        onAccepted:{if(app.pickerPurpose==="target"){backend.setTargetRoot(selectedFolder.toString());app.destination=backend.localPath(selectedFolder.toString())}else sourcesDialog.addPaths([selectedFolder.toString()])}
    }
    SourcesDialog {
        id:sourcesDialog;anchors.centerIn:parent
        onChooseRequested:app.chooseFolder("source")
        onBeforeApply:{editor.flushDraft();editor.stopPlayback();editor.invalidateSuggestion()}
        onScopeApplied:scopeChanged=>{if(scopeChanged){app.selection=[];app.clearFilters()}}
    }
    UiDialog {id:noticeDialog;acceptText:"知道了";anchors.centerIn:parent;width:600;modal:true;title:"提示";standardButtons:Dialog.Ok
        ScrollView {width:parent.width;height:Math.min(300,noticeText.implicitHeight+10);clip:true
            Text {id:noticeText;width:noticeDialog.availableWidth;text:app.notice;wrapMode:Text.Wrap;font.pixelSize:13;color:"#3e4c53"}
        }
    }
    UiDialog {id:newDirectory;objectName:"newDirectoryDialog";acceptText:"新建";anchors.centerIn:parent;width:410;modal:true;title:"新建子目录";standardButtons:Dialog.Ok|Dialog.Cancel
        property string parentPath:""
        ColumnLayout {width:parent.width;spacing:12;Label {text:"创建位置："+newDirectory.parentPath;Layout.fillWidth:true;elide:Text.ElideMiddle} UiTextField {id:newName;objectName:"newDirectoryName";Accessible.name:"新建子目录名称";placeholderText:"目录名称";Layout.fillWidth:true;selectByMouse:true}}
        onOpened:{newName.clear();newName.forceActiveFocus()}
        onAccepted:backend.createDirectory(parentPath,newName.text)
    }
    UiDialog {id:renameDirectoryDialog;objectName:"renameDirectoryDialog";acceptText:"重命名";anchors.centerIn:parent;width:410;modal:true;title:"重命名目录";standardButtons:Dialog.Ok|Dialog.Cancel
        property string directoryPath:""
        property string currentName:""
        ColumnLayout {width:parent.width;spacing:12;Label {text:"当前目录："+renameDirectoryDialog.directoryPath;Layout.fillWidth:true;elide:Text.ElideMiddle} UiTextField {id:renameName;objectName:"renameDirectoryName";Accessible.name:"目录新名称";placeholderText:"新目录名称";Layout.fillWidth:true;selectByMouse:true}}
        onOpened:{renameName.text=currentName;renameName.forceActiveFocus();renameName.selectAll()}
        onAccepted:{editor.flushDraft();editor.stopPlayback();backend.renameDirectory(directoryPath,renameName.text)}
    }
    UiDialog {id:historyDialog;objectName:"historyDialog";anchors.centerIn:parent;width:820;height:520;modal:true;title:"操作记录 · 最近 100 项";standardButtons:Dialog.Close
        ColumnLayout {anchors.fill:parent;spacing:12
        RowLayout {Layout.fillWidth:true;spacing:12
            Text {Layout.fillWidth:true;text:backend.busy?backend.status:backend.pending?"未完成操作会保留，供后续核对处理":"清空记录不会改动图片、视频或文件夹";font.pixelSize:12;color:"#69777e";elide:Text.ElideRight}
            UiButton {objectName:"clearHistoryButton";text:"清空记录";iconName:"trash";tone:"danger";enabled:backend.canClearHistory&&!backend.busy&&!backend.restarting;onClicked:clearHistoryDialog.open()}
        }
        ListView {objectName:"historyList";Layout.fillWidth:true;Layout.fillHeight:true;clip:true;model:backend.history;spacing:8
            Column {anchors.centerIn:parent;spacing:10;visible:backend.history.length===0
                Glyph {anchors.horizontalCenter:parent.horizontalCenter;name:"history";width:28;height:28}
                Text {anchors.horizontalCenter:parent.horizontalCenter;text:"暂无操作记录";font.pixelSize:14;color:"#45545b"}
                Text {anchors.horizontalCenter:parent.horizontalCenter;text:"移动、复制、裁剪保存和目录操作会显示在这里";font.pixelSize:12;color:"#69777e"}
            }
            ScrollBar.vertical:ScrollBar {}
            delegate:Rectangle {required property var modelData;width:ListView.view.width;height:105;color:"#f0f3f4";radius:5
                ColumnLayout {anchors.fill:parent;anchors.margins:10;spacing:4
                    Text {text:({move:"文件移动",copy:"文件复制",live_move:"Live 图成组移动",live_copy:"Live 图成组复制",mkdir:"创建目录",export:"保存裁剪子图",rename_directory:"目录重命名"}[modelData.kind]||modelData.kind)+" · "+({planned:"等待执行",running:"执行中",copied:"已复制，等待校验",target_ready:"目标文件已保存",source_removed:"原位置文件已移除",committed:"已完成",undone:"已撤销",abandoned:"已结束"}[modelData.state]||modelData.state)+" · "+modelData.created;font.pixelSize:11;color:"#3e4c53"}
                    Text {text:modelData.source+" → "+modelData.target;Layout.fillWidth:true;elide:Text.ElideMiddle;font.pixelSize:11;color:"#667780"}
                    Text {text:modelData.error;visible:!!modelData.error;Layout.fillWidth:true;elide:Text.ElideRight;font.pixelSize:11;color:"#a36044"}
                    RowLayout {spacing:8;UiButton {text:"打开目标目录";iconName:"folderOpen";implicitHeight:27;onClicked:backend.reveal(modelData.target)}
                        UiButton {text:"撤销移动";iconName:"undo";tone:"warning";hint:modelData.kind==="live_move"?"将 Live 图的照片和视频一起移回原位置":"将文件从目标目录移回原位置";implicitHeight:27;visible:(modelData.kind==="move"||modelData.kind==="live_move")&&modelData.state==="committed";enabled:!backend.busy;onClicked:{backend.undo(modelData.id);historyDialog.close()}}
                        UiButton {text:"核对并继续";iconName:"forward";tone:"warning";hint:"核对文件后继续这项操作；若是移动，将在目标完整后移除原位置的文件";implicitHeight:27;visible:!["committed","undone","abandoned"].includes(modelData.state);enabled:!backend.busy;onClicked:{backend.recover(modelData.id);historyDialog.close()}}
                    }
                }
            }
        }
        }
    }
    UiDialog {
        id:clearHistoryDialog;objectName:"clearHistoryDialog";anchors.centerIn:parent;width:460;modal:true
        title:"清空操作记录？";acceptText:"确认清空";acceptTone:"danger";standardButtons:Dialog.Ok|Dialog.Cancel
        Text {width:parent.width;wrapMode:Text.Wrap;font.pixelSize:13;color:"#45545b";text:"将清空所有已结束的操作记录，包括列表中未显示的旧记录。\n\n清空后，无法再通过操作记录撤销这些移动。图片、视频和文件夹不会改变，未完成的操作会保留。"}
        onAccepted:backend.clearHistory()
    }
}
