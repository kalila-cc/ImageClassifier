import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: app
    visible: true; width: 1460; height: 920; minimumWidth: 1120; minimumHeight: 720
    title: "归图 · ImageClassifier"; color: "#f4f6f2"
    palette.highlight: "#285c49"; palette.buttonText: "#4c6344"; palette.text: "#4c6344"
    palette.base: "#ffffff"; palette.window: "#f8faf5"; palette.button: "#edf2e7"; palette.windowText: "#4c6344"; palette.highlightedText: "#ffffff"
    property bool largeMode: false
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
    onFilteredChanged: { if(!filtered.some(a=>a.id===focusId)) focusId = filtered.length ? filtered[0].id : "" }
    onLargeModeChanged: { if(largeMode) editor.enterEditing() }
    function tell(s) {notice=s;noticeDialog.open()}
    function navigate(n) {let i=currentIndex+n;if(i>=0&&i<filtered.length)focusId=filtered[i].id}
    function toggle(id) {focusId=id;let a=selection.slice();let i=a.indexOf(id);if(i>=0)a.splice(i,1);else a.push(id);selection=a}
    function chooseFolder(purpose) {pickerPurpose=purpose;folderPicker.open()}
    function createChildDirectory(path) {newDirectory.parentPath=path;newDirectory.open()}
    function viewDirectory(path) {
        if(backend.busy)return;
        editor.flushDraft();editor.stopPlayback();
        selection=[];mediaFilter="全部";search.clear();
        backend.openSource(path,false);
    }
    Connections {
        target: backend
        function onMessage(text) {app.tell(text)}
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
    Component.onCompleted: destination=backend.targetRoot
    onClosing: close => { if(backend.busy){close.accepted=false;tell("请等待文件操作完成，或先取消尚未开始的任务。")}else editor.flushDraft() }
    Shortcut {sequence:"Left";enabled:app.largeMode&&!backend.busy&&!editor.keyboardAdjusting&&!noticeDialog.visible&&!sourcesDialog.visible&&!historyDialog.visible;onActivated:app.navigate(-1)}
    Shortcut {sequence:"Right";enabled:app.largeMode&&!backend.busy&&!editor.keyboardAdjusting&&!noticeDialog.visible&&!sourcesDialog.visible&&!historyDialog.visible;onActivated:app.navigate(1)}
    ColumnLayout {
        anchors.fill:parent;spacing:0
        Rectangle {
            Layout.fillWidth:true;Layout.preferredHeight:58;color:"white"
            RowLayout {anchors.fill:parent;anchors.leftMargin:20;anchors.rightMargin:18;spacing:12
                Rectangle {width:29;height:29;radius:7;color:"#285c49";Glyph {anchors.centerIn:parent;name:"image";ink:"white";width:21;height:21}}
                Text {text:"归图";font.pixelSize:17;font.weight:Font.DemiBold;color:"#2c4436"}
                UiButton {text:backend.sources.length ? "来源 " + backend.sources.length + " 个  ▾" : "＋ 添加目录";quiet:true;enabled:!backend.busy;onClicked:sourcesDialog.open()}
                Text {text:(app.browsingPath?app.browsingPath.replace(/\\/g,"/").split("/").pop()+" · 仅当前目录 · ":"")+"第 " + backend.batchNumber + " 批 · " + backend.items.length + " 项";Layout.maximumWidth:280;elide:Text.ElideMiddle;color:"#8b9684";font.pixelSize:11}
                Item {Layout.fillWidth:true}
                Rectangle {width:204;height:40;radius:8;color:"#edf1e9"
                    Row {anchors.centerIn:parent;spacing:8
                        UiButton {text:"▦  批量模式";implicitWidth:90;implicitHeight:32;chosen:!app.largeMode;quiet:true;onClicked:{editor.flushDraft();app.largeMode=false}}
                        UiButton {text:"▣  大图模式";implicitWidth:90;implicitHeight:32;chosen:app.largeMode;quiet:true;onClicked:app.largeMode=true}
                    }
                }
                Item {Layout.fillWidth:true}
                UiButton {text:"操作记录"+(backend.pending?" · "+backend.pending:"");quiet:true;enabled:!backend.busy;onClicked:{backend.loadHistory();historyDialog.open()}}
                UiButton {text:"批次";quiet:true;enabled:!backend.busy;onClicked:batchDialog.open()}
            }
        }
        RowLayout {
            Layout.fillWidth:true;Layout.fillHeight:true;spacing:0
            Rectangle {
                Layout.preferredWidth:220;Layout.fillHeight:true;color:"#eef2e9"
                ColumnLayout {anchors.fill:parent;anchors.margins:12;spacing:7
                    RowLayout {Layout.fillWidth:true;spacing:8
                        Text {text:"目录";font.pixelSize:13;font.weight:Font.DemiBold;color:"#52624a";Layout.fillWidth:true}
                        UiButton {text:"刷新";quiet:true;implicitWidth:44;hint:"更新目录与媒体总数（含子目录）";enabled:!backend.busy&&backend.targetRoot!=="";onClicked:backend.refreshDirectories()}
                        UiButton {text:"＋";quiet:true;implicitWidth:28;enabled:!backend.busy&&app.destination!=="";onClicked:app.createChildDirectory(app.destination)}
                    }
                    UiButton {text:backend.targetRoot?"更换目标根目录":"选择目标根目录";Layout.fillWidth:true;enabled:!backend.busy;onClicked:app.chooseFolder("target")}
                    Text {text:"单击选目标 · 双击打开目录";font.pixelSize:10;color:"#7b8b70"}
                    DirectoryTree {
                        id:directoryTree
                        objectName:"directoryTree"
                        Layout.fillWidth:true;Layout.fillHeight:true
                        directories:backend.directories;rootPath:backend.targetRoot
                        selectedPath:app.destination;workingPath:app.browsingPath;enabled:!backend.busy
                        onDirectorySelected:path=>{app.destination=path;if(app.largeMode)editor.assignTarget(path)}
                        onDirectoryOpened:path=>app.viewDirectory(path)
                        onNewDirectoryRequested:path=>app.createChildDirectory(path)
                        onRenameDirectoryRequested:(path,name)=>{renameDirectoryDialog.directoryPath=path;renameDirectoryDialog.currentName=name;renameDirectoryDialog.open()}
                    }
                    UiButton {text:"刷新当前目录";Layout.fillWidth:true;quiet:true;enabled:!backend.busy&&app.browsingPath!=="";onClicked:app.viewDirectory(app.browsingPath)}
                    UiButton {text:"在资源管理器中打开";Layout.fillWidth:true;quiet:true;enabled:app.browsingPath!==""||app.destination!=="";onClicked:backend.reveal(app.browsingPath||app.destination)}
                }
            }
            ColumnLayout {
                Layout.fillWidth:true;Layout.fillHeight:true;spacing:0
                ColumnLayout {
                    visible:!app.largeMode;Layout.fillWidth:true;Layout.fillHeight:true;spacing:0
                    Rectangle {Layout.fillWidth:true;Layout.preferredHeight:52;color:"#f9faf7"
                        RowLayout {anchors.fill:parent;anchors.leftMargin:14;anchors.rightMargin:14;spacing:8
                            UiButton {text:app.allSelected?"取消全选":"全选";quiet:true;onClicked:{if(app.allSelected)app.selection=app.selection.filter(id=>!app.filtered.some(a=>a.id===id));else app.selection=Array.from(new Set(app.selection.concat(app.filtered.map(a=>a.id))))}}
                            UiButton {text:"清空选择";quiet:true;enabled:!backend.busy&&app.selection.length>0;hint:"取消所有已选图片，包括筛选后隐藏的选择";onClicked:app.selection=[]}
                            Repeater {model:["全部","图片","视频"]
                                UiButton {required property string modelData;text:modelData;chosen:app.mediaFilter===modelData;quiet:true;implicitWidth:50;onClicked:app.mediaFilter=modelData}
                            }
                            Text {text:app.filtered.length+" 项";font.pixelSize:11;color:"#8e9b81"}
                            Item {Layout.fillWidth:true}
                            Text {text:"缩略图";font.pixelSize:11;color:"#819174"}
                            UiSlider {id:thumbSize;Layout.preferredWidth:95;from:170;to:310;value:240;stepSize:35}
                            TextField {id:search;Layout.preferredWidth:145;placeholderText:"搜索文件名";font.pixelSize:11;selectByMouse:true}
                        }
                    }
                    GridView {id:grid;Layout.fillWidth:true;Layout.fillHeight:true;Layout.margins:12;clip:true;model:app.filtered
                        property int columns:Math.max(2,Math.floor(width/thumbSize.value))
                        cellWidth:width/columns;cellHeight:cellWidth*.73+36
                        ScrollBar.vertical:ScrollBar {}
                        GridSelection {
                            id:batchSelection
                            parent:grid;anchors.fill:parent;gridView:grid;records:app.filtered;selectedIds:app.selection
                            enabled:!backend.busy&&grid.count>0;visible:!app.largeMode
                            onSelectionRequested:ids=>app.selection=ids
                            onFocusRequested:id=>app.focusId=id
                            onActivated:id=>{app.focusId=id;app.largeMode=true}
                        }
                        delegate:PhotoCard {
                            required property var modelData
                            required property int index
                            enabled:!backend.busy
                            externalHovered:batchSelection.hoveredIndex===index
                            externalPressed:batchSelection.downIndex===index
                            width:grid.cellWidth-10;height:grid.cellHeight-10
                            photo:modelData.thumb;filename:modelData.name;kind:modelData.kind
                            selected:app.selection.includes(modelData.id);focused:app.focusId===modelData.id
                            onClicked:app.toggle(modelData.id)
                            onOpened:{app.focusId=modelData.id;app.largeMode=true}
                        }
                        ColumnLayout {parent:grid;anchors.centerIn:parent;width:Math.min(560,Math.max(0,grid.width-48));spacing:18;visible:grid.count===0
                            Text {Layout.fillWidth:true;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap;text:backend.busy?"正在准备图片…":backend.items.length?"没有匹配的图片":app.browsingPath?"此目录暂无直属图片或视频":backend.sources.length?"当前来源暂无图片，可双击左侧目录继续整理":"添加目录，开始整理";font.pixelSize:20;color:"#667c59"}
                            UiButton {Layout.alignment:Qt.AlignHCenter;text:backend.items.length?"清除筛选":app.browsingPath?"刷新当前目录":"添加来源目录";enabled:!backend.busy;onClicked:{if(backend.items.length){search.clear();app.mediaFilter="全部"}else if(app.browsingPath)app.viewDirectory(app.browsingPath);else sourcesDialog.open()}}
                        }
                    }
                }
                ImageEditor {id:editor;visible:app.largeMode;enabled:!backend.busy;Layout.fillWidth:true;Layout.fillHeight:true;asset:app.current;targetFolder:app.destination
                    position:app.currentIndex;total:app.filtered.length
                    onPrevious:app.navigate(-1);onNext:app.navigate(1);onNotice:msg=>app.tell(msg)
                }
                Rectangle {Layout.fillWidth:true;Layout.preferredHeight:62;color:"white"
                    RowLayout {anchors.fill:parent;anchors.leftMargin:18;anchors.rightMargin:18;spacing:12
                        Text {text:app.largeMode?(editor.cropActive?"当前原图 · "+editor.drafts.length+" 张子图":"仅处理当前 1 项"):"已选 "+app.selection.length+" 项";font.pixelSize:12;font.weight:Font.DemiBold;color:"#4e6444"}
                        Item {Layout.fillWidth:true}
                        Text {text:app.largeMode&&editor.cropActive?"输出 PNG · 裁剪限于图内":app.destination?"归类到："+app.destination:"请选择目标目录";Layout.maximumWidth:300;elide:Text.ElideMiddle;font.pixelSize:11;color:"#6a805e"}
                        UiButton {text:app.largeMode&&editor.cropActive?"导出子图并归档原图 →":"归类"+(app.largeMode?"当前图片":("所选 "+app.selection.length+" 项"))+" →";primary:true;implicitHeight:40;enabled:!backend.busy&&(app.largeMode?!!app.current.id:app.selection.length>0)
                            tone:app.largeMode&&editor.cropActive?"warning":"normal"
                            hint:app.largeMode&&editor.cropActive?"导出所有子图，并将原图移入已处理目录":"将所选原文件移动到目标目录"
                            onClicked:{editor.stopPlayback();if(app.largeMode&&editor.cropActive)editor.exportDrafts();else backend.moveAssets(app.largeMode?[app.focusId]:app.selection,app.destination)}
                        }
                    }
                }
            }
        }
        Rectangle {Layout.fillWidth:true;Layout.preferredHeight:30;color:"#e9eee3"
            RowLayout {anchors.fill:parent;anchors.leftMargin:15;anchors.rightMargin:12;spacing:8
                Text {text:backend.status;elide:Text.ElideRight;Layout.fillWidth:true;font.pixelSize:11;color:"#6c7f5d"}
                Text {text:"后续 "+backend.remaining+" 项";font.pixelSize:11;color:"#819373"}
                UiButton {text:backend.busy?"取消后续任务":"下一批";quiet:true;tone:backend.busy?"warning":"normal";implicitHeight:24;enabled:backend.busy||backend.items.length===0;onClicked:{if(backend.busy)backend.cancel();else backend.nextBatch(batchCount.value)}}
            }
        }
    }
    FolderDialog {id:folderPicker;title:app.pickerPurpose==="target"?"选择目标根目录":"选择来源目录"
        onAccepted:{if(app.pickerPurpose==="target"){backend.setTargetRoot(selectedFolder.toString());app.destination=backend.localPath(selectedFolder.toString())}else sourcePaths.text+=(sourcePaths.text?"\n":"")+selectedFolder.toString()}
    }
    UiDialog {id:sourcesDialog;anchors.centerIn:parent;width:560;modal:true;title:"来源目录";standardButtons:Dialog.Close
        ColumnLayout {width:parent.width;spacing:12
            Text {text:backend.sources.join("\n")||"尚未添加目录";Layout.fillWidth:true;wrapMode:Text.Wrap;font.pixelSize:12;color:"#6c7f5d"}
            Label {text:"添加目录（每行一个本地路径）"}
            TextArea {id:sourcePaths;Layout.fillWidth:true;Layout.preferredHeight:110;placeholderText:"D:\\照片\\相机\nE:\\手机导出";selectByMouse:true;wrapMode:Text.Wrap}
            CheckBox {id:recursiveScan;text:"包含子目录（排除“已处理”和目录链接）";checked:true;hoverEnabled:true
                background: Rectangle {radius:5;color:recursiveScan.down?"#c9dacc":recursiveScan.hovered?"#e2eae1":"transparent"}
                HoverHandler {enabled:recursiveScan.enabled;cursorShape:Qt.PointingHandCursor}
            }
            RowLayout {spacing:8;UiButton {text:"浏览…";onClicked:app.chooseFolder("source")}
                UiButton {text:"添加并扫描";primary:true;enabled:sourcePaths.text.trim().length>0&&!backend.busy;onClicked:{backend.addSources(sourcePaths.text.split(/\r?\n/).filter(p=>p.trim()).map(p=>p.trim()),recursiveScan.checked);sourcePaths.clear();sourcesDialog.close()}}
                UiButton {text:"刷新现有来源";enabled:!backend.busy;onClicked:{backend.refresh();sourcesDialog.close()}}
            }
        }
    }
    UiDialog {id:noticeDialog;anchors.centerIn:parent;width:600;modal:true;title:"提示";standardButtons:Dialog.Ok
        ScrollView {width:parent.width;height:Math.min(300,noticeText.implicitHeight+10);clip:true
            Text {id:noticeText;width:noticeDialog.availableWidth;text:app.notice;wrapMode:Text.Wrap;font.pixelSize:13;color:"#4c6344"}
        }
    }
    UiDialog {id:newDirectory;anchors.centerIn:parent;width:410;modal:true;title:"新建目标子目录";standardButtons:Dialog.Ok|Dialog.Cancel
        property string parentPath:""
        ColumnLayout {width:parent.width;spacing:12;Label {text:newDirectory.parentPath;Layout.fillWidth:true;elide:Text.ElideMiddle} TextField {id:newName;placeholderText:"目录名称";Layout.fillWidth:true;selectByMouse:true}}
        onOpened:{newName.clear();newName.forceActiveFocus()}
        onAccepted:backend.createDirectory(parentPath,newName.text)
    }
    UiDialog {id:renameDirectoryDialog;anchors.centerIn:parent;width:410;modal:true;title:"重命名目录";standardButtons:Dialog.Ok|Dialog.Cancel
        property string directoryPath:""
        property string currentName:""
        ColumnLayout {width:parent.width;spacing:12;Label {text:renameDirectoryDialog.directoryPath;Layout.fillWidth:true;elide:Text.ElideMiddle} TextField {id:renameName;placeholderText:"新目录名称";Layout.fillWidth:true;selectByMouse:true}}
        onOpened:{renameName.text=currentName;renameName.forceActiveFocus();renameName.selectAll()}
        onAccepted:{editor.flushDraft();editor.stopPlayback();backend.renameDirectory(directoryPath,renameName.text)}
    }
    UiDialog {id:batchDialog;anchors.centerIn:parent;width:440;modal:true;title:"批次";standardButtons:Dialog.Close
        ColumnLayout {width:parent.width;spacing:12
            Label {text:"每批目标数量"}
            UiSpinBox {id:batchCount;from:10;to:500;value:backend.batchSize;stepSize:10;enabled:!backend.busy;onValueModified:backend.setBatchSize(value)}
            Label {text:"对下一批生效，相邻图片相似时可延伸至两倍。";font.pixelSize:11}
            Text {text:backend.status;wrapMode:Text.Wrap;Layout.fillWidth:true;font.pixelSize:12}
            UiButton {text:"将后续 10 项纳入当前批";enabled:!backend.busy&&backend.remaining>0;onClicked:{backend.extendBatch(10);batchDialog.close()}}
            UiButton {text:"准备下一批";enabled:!backend.busy&&backend.items.length===0;onClicked:{backend.nextBatch(batchCount.value);batchDialog.close()}}
        }
    }
    UiDialog {id:historyDialog;anchors.centerIn:parent;width:820;height:520;modal:true;title:"操作记录 · 最近 100 项";standardButtons:Dialog.Close
        ListView {anchors.fill:parent;clip:true;model:backend.history;spacing:8
            ScrollBar.vertical:ScrollBar {}
            delegate:Rectangle {required property var modelData;width:ListView.view.width;height:105;color:"#eef3e8";radius:5
                ColumnLayout {anchors.fill:parent;anchors.margins:10;spacing:4
                    Text {text:({move:"文件移动",mkdir:"创建目录",export:"子图输出",rename_directory:"目录重命名"}[modelData.kind]||modelData.kind)+" · "+({planned:"等待执行",running:"执行中",copied:"临时文件已写入",target_ready:"目标已落盘",source_removed:"来源已清理",committed:"已完成",undone:"已撤销",abandoned:"已结束"}[modelData.state]||modelData.state)+" · "+modelData.created;font.pixelSize:11;color:"#4c6344"}
                    Text {text:modelData.source+" → "+modelData.target;Layout.fillWidth:true;elide:Text.ElideMiddle;font.pixelSize:11;color:"#7a8c6c"}
                    Text {text:modelData.error;visible:!!modelData.error;Layout.fillWidth:true;elide:Text.ElideRight;font.pixelSize:11;color:"#a36044"}
                    RowLayout {spacing:8;UiButton {text:"打开目标目录";implicitHeight:27;onClicked:backend.reveal(modelData.target)}
                        UiButton {text:"撤销移动";tone:"warning";hint:"将文件从目标目录移回原位置";implicitHeight:27;visible:modelData.kind==="move"&&modelData.state==="committed";enabled:!backend.busy;onClicked:{backend.undo(modelData.id);historyDialog.close()}}
                        UiButton {text:"核对并恢复";tone:"warning";hint:"核对文件状态并接续未完成的文件操作";implicitHeight:27;visible:!["committed","undone","abandoned"].includes(modelData.state);enabled:!backend.busy;onClicked:{backend.recover(modelData.id);historyDialog.close()}}
                    }
                }
            }
        }
    }
}
