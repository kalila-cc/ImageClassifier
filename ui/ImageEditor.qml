import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

ColumnLayout {
    id: editor
    spacing:0
    property var asset: ({})
    property string targetFolder:""
    property int position:0
    property int total:0
    property bool cropActive:true
    property real cropX:.1
    property real cropY:.1
    property real cropW:.8
    property real cropH:.8
    property real angle:0
    property real ratio:0
    property real zoom:1
    property var drafts:[]
    property int selectedDraft:-1
    property string loadedId:""
    property bool loadingDraft:false
    property var dimensions:({})
    property real canvasWidth:1
    property real canvasHeight:1
    property real imageCenterX:0
    property real imageCenterY:0
    readonly property bool keyboardAdjusting:rotationSlider.activeFocus||angleInput.activeFocus
    property bool isVideo:asset.type==="视频"
    signal previous()
    signal next()
    signal notice(string message)
    function uid(){return Date.now().toString(36)+Math.random().toString(36).slice(2)}
    function spec(){return {id:selectedDraft>=0&&drafts[selectedDraft]?drafts[selectedDraft].id:uid(),x:cropX,y:cropY,w:cropW,h:cropH,angle:angle,ratio:ratio,target:selectedDraft>=0&&drafts[selectedDraft]?drafts[selectedDraft].target:targetFolder}}
    function capture(){
        if(loadingDraft||selectedDraft<0)return;
        let list=drafts.slice();list[selectedDraft]=spec();drafts=list;
    }
    function flushDraft(){if(!loadedId||isVideo||loadingDraft)return;capture();backend.saveDraft(loadedId,drafts)}
    function enterEditing(){cropActive=!isVideo;zoom=1}
    function loadCurrent(){
        // All edits are saved on change; never apply a new asset's values to an old draft.
        if(loadedId && drafts.length && !loadingDraft) backend.saveDraft(loadedId,drafts);
        saveTimer.stop();
        player.stop();loadingDraft=true;loadedId=asset.id||"";selectedDraft=-1;zoom=1;
        dimensions=loadedId&&!isVideo?backend.imageDimensions(loadedId):{};
        drafts=loadedId&&!isVideo?backend.loadDraft(loadedId):[];
        if(loadedId&&!isVideo&&drafts.length===0) drafts=[{id:uid(),x:.1,y:.1,w:.8,h:.8,angle:0,ratio:0,target:targetFolder}];
        cropActive=!isVideo;loadingDraft=false;
        if(drafts.length)selectDraft(0);else angle=0
    }
    function selectDraft(index){
        capture();loadingDraft=true;selectedDraft=index;let d=drafts[index];
        cropX=d.x;cropY=d.y;cropW=d.w;cropH=d.h;angle=d.angle;ratio=d.ratio||0;loadingDraft=false;
        applyCrop(spec());
    }
    function schedule(){if(loadingDraft||!loadedId||isVideo)return;capture();saveTimer.restart()}
    function applyCrop(request,previous){
        if(loadingDraft||!dimensions.width)return;
        const safe=backend.constrainCrop(dimensions,request,previous||{});
        if(safe.w===undefined)return;
        loadingDraft=true;
        cropX=safe.x;cropY=safe.y;cropW=safe.w;cropH=safe.h;canvasWidth=safe.canvasWidth;canvasHeight=safe.canvasHeight;
        imageCenterX=safe.imageCenterX;imageCenterY=safe.imageCenterY;
        loadingDraft=false;schedule();
    }
    function setRatio(value){
        ratio=value;applyCrop(spec());
    }
    function exportDrafts(){flushDraft();if(drafts.length===0){notice("至少保留一个子图");return}backend.exportCrops(loadedId,drafts)}
    function stopPlayback(){player.stop()}
    function relocateTargets(from,to){
        saveTimer.stop();
        drafts=drafts.map(d=>Object.assign({},d,{target:backend.relocatedPath(d.target||"",from,to)}));
    }
    function assignTarget(path){if(selectedDraft<0||loadingDraft)return;let list=drafts.slice();let d=Object.assign({},list[selectedDraft]);d.target=path;list[selectedDraft]=d;drafts=list;schedule()}
    onAssetChanged:loadCurrent()
    onTargetFolderChanged:{if(selectedDraft>=0&&!loadingDraft&&!drafts[selectedDraft].target)assignTarget(targetFolder)}
    onAngleChanged:if(!loadingDraft)applyCrop(spec())
    Timer {id:saveTimer;interval:400;onTriggered:editor.flushDraft()}
    Component.onDestruction:flushDraft()
    RowLayout {
        Layout.fillWidth:true;Layout.preferredHeight:52;Layout.leftMargin:14;Layout.rightMargin:14;spacing:8
        UiButton {text:"‹";quiet:true;implicitWidth:32;enabled:editor.position>0&&!backend.busy;onClicked:{editor.flushDraft();editor.previous()}}
        Text {text:(editor.total?editor.position+1:0)+" / "+editor.total;font.pixelSize:12;color:"#718763"}
        UiButton {text:"›";quiet:true;implicitWidth:32;enabled:editor.position<editor.total-1&&!backend.busy;onClicked:{editor.flushDraft();editor.next()}}
        Text {text:editor.asset.name||"没有图片";elide:Text.ElideMiddle;Layout.fillWidth:true;font.pixelSize:12;color:"#4b6340"}
        UiButton {text:"−";quiet:true;implicitWidth:30;enabled:editor.zoom>1;onClicked:editor.zoom=Math.max(1,editor.zoom-.25)}
        UiButton {text:editor.zoom===1?"适应":Math.round(editor.zoom*100)+"%";quiet:true;onClicked:editor.zoom=1}
        UiButton {text:"+";quiet:true;implicitWidth:30;enabled:editor.zoom<3;onClicked:editor.zoom=Math.min(3,editor.zoom+.25)}
        UiButton {text:"所在目录";quiet:true;enabled:!!editor.asset.path;onClicked:backend.reveal(editor.asset.path)}
        UiButton {text:editor.isVideo?"播放 / 暂停":"裁剪 / 旋转";chosen:editor.cropActive&&!editor.isVideo;enabled:!!editor.asset.id;onClicked:{if(editor.isVideo){if(player.playbackState===MediaPlayer.PlayingState)player.pause();else player.play()}else editor.cropActive=!editor.cropActive}}
    }
    Rectangle {visible:!!editor.asset.blocked;Layout.fillWidth:true;Layout.preferredHeight:36;color:"#f5ead8"
        Text {anchors.fill:parent;anchors.margins:8;text:editor.asset.blocked||"";elide:Text.ElideRight;font.pixelSize:11;color:"#9c6a3c"}
    }
    RowLayout {
        Layout.fillWidth:true;Layout.fillHeight:true;spacing:0
        Rectangle {
            Layout.fillWidth:true;Layout.fillHeight:true;color:"#242c27";clip:true
            Flickable {
                id:canvas;anchors.fill:parent;anchors.margins:10;visible:!editor.isVideo
                contentWidth:width*editor.zoom;contentHeight:height*editor.zoom;clip:true;boundsBehavior:Flickable.StopAtBounds
                interactive:editor.zoom>1&&!editor.cropActive
                onContentWidthChanged:contentX=Math.max(0,(contentWidth-width)/2)
                onContentHeightChanged:contentY=Math.max(0,(contentHeight-height)/2)
                Item {
                    id:frame;width:canvas.contentWidth;height:canvas.contentHeight
                    RotatingPreview {
                        id:preview;objectName:"rotationPreview";anchors.fill:parent
                        source:editor.asset.id&&!editor.isVideo?"image://media/"+editor.asset.id+"/0/"+editor.asset.mtime:""
                        angle:editor.angle;sourceWidth:editor.dimensions.width||1;sourceHeight:editor.dimensions.height||1
                        canvasWidth:editor.canvasWidth;canvasHeight:editor.canvasHeight
                        imageCenterX:editor.imageCenterX;imageCenterY:editor.imageCenterY
                    }
                    Rectangle {
                        id:cropBox;objectName:"cropBox";visible:editor.cropActive&&!!editor.asset.id&&!!editor.dimensions.width&&preview.status===Image.Ready
                        x:(frame.width-preview.paintedWidth)/2+editor.cropX*preview.paintedWidth
                        y:(frame.height-preview.paintedHeight)/2+editor.cropY*preview.paintedHeight
                        width:editor.cropW*preview.paintedWidth;height:editor.cropH*preview.paintedHeight
                        color:"transparent";border.width:1;border.color:"white"
                        Repeater {model:2;Rectangle {required property int index;x:parent.width/3*(index+1);width:1;height:parent.height;color:"#70ffffff"}}
                        Repeater {model:2;Rectangle {required property int index;y:parent.height/3*(index+1);height:1;width:parent.width;color:"#70ffffff"}}
                        MouseArea {anchors.fill:parent;cursorShape:Qt.SizeAllCursor;preventStealing:true
                            property real startX;property real startY;property real originX;property real originY
                            onPressed:mouse=>{const p=mapToItem(frame,mouse.x,mouse.y);startX=p.x;startY=p.y;originX=editor.cropX;originY=editor.cropY}
                            onPositionChanged:mouse=>{if(!pressed)return;const p=mapToItem(frame,mouse.x,mouse.y);let next=editor.spec();const previous=editor.spec();next.x=originX+(p.x-startX)/preview.paintedWidth;next.y=originY+(p.y-startY)/preview.paintedHeight;editor.applyCrop(next,previous)}
                            onReleased:editor.flushDraft()
                        }
                        Repeater {model:4
                            Rectangle {required property int index;width:12;height:12;radius:2;color:"white";x:index%2?cropBox.width-6:-6;y:index>1?cropBox.height-6:-6;z:2
                                MouseArea {objectName:"cropCorner"+index;anchors.fill:parent;anchors.margins:-8;preventStealing:true;cursorShape:index===0||index===3?Qt.SizeFDiagCursor:Qt.SizeBDiagCursor
                                    property real oppositeX;property real oppositeY
                                    onPressed:{oppositeX=editor.cropX+(index%2?0:editor.cropW);oppositeY=editor.cropY+(index>1?0:editor.cropH)}
                                    onPositionChanged:mouse=>{
                                        if(!pressed)return;const p=mapToItem(frame,mouse.x,mouse.y);
                                        let nx=Math.max(0,Math.min(1,(p.x-(frame.width-preview.paintedWidth)/2)/preview.paintedWidth));
                                        let ny=Math.max(0,Math.min(1,(p.y-(frame.height-preview.paintedHeight)/2)/preview.paintedHeight));
                                        let w=Math.max(.02,index%2?nx-oppositeX:oppositeX-nx),h=Math.max(.02,index>1?ny-oppositeY:oppositeY-ny);
                                        w=Math.min(w,index%2?1-oppositeX:oppositeX);h=Math.min(h,index>1?1-oppositeY:oppositeY);
                                        if(editor.ratio>0){const r=editor.ratio*editor.canvasHeight/editor.canvasWidth;h=w/r;const maxH=index>1?1-oppositeY:oppositeY;if(h>maxH){h=maxH;w=h*r}}
                                        let next=editor.spec();next.w=w;next.h=h;next.x=index%2?oppositeX:oppositeX-w;next.y=index>1?oppositeY:oppositeY-h;
                                        editor.applyCrop(next,editor.spec());
                                    }
                                    onReleased:editor.flushDraft()
                                }
                            }
                        }
                    }
                }
            }
            MediaPlayer {id:player;source:editor.isVideo?(editor.asset.url||""):"";audioOutput:AudioOutput {} videoOutput:video;onErrorOccurred:editor.notice("视频播放失败："+errorString)}
            VideoOutput {id:video;anchors.fill:parent;visible:editor.isVideo;fillMode:VideoOutput.PreserveAspectFit}
            UiButton {anchors.centerIn:parent;visible:editor.isVideo&&player.playbackState!==MediaPlayer.PlayingState;text:"播放视频";onClicked:player.play()}
            UiSlider {visible:editor.isVideo;anchors.bottom:parent.bottom;anchors.left:parent.left;anchors.right:parent.right;anchors.margins:15;from:0;to:Math.max(1,player.duration);value:player.position;onMoved:player.setPosition(value)}
        }
        Rectangle {
            visible:editor.cropActive&&!editor.isVideo;Layout.preferredWidth:265;Layout.fillHeight:true;color:"#f8faf5"
            ScrollView {id:tools;anchors.fill:parent;anchors.margins:16;clip:true;contentWidth:availableWidth
                ColumnLayout {width:tools.availableWidth;spacing:13
                    RowLayout {Layout.fillWidth:true;spacing:8
                        Text {text:"裁剪与旋转";font.pixelSize:13;font.weight:Font.DemiBold;color:"#49623e";Layout.fillWidth:true}
                        UiButton {text:"×";quiet:true;hint:"收起裁剪面板";implicitWidth:25;onClicked:editor.cropActive=false}
                    }
                    Flow {Layout.fillWidth:true;spacing:8
                        Repeater {model:[{t:"自由",r:0},{t:"1:1",r:1},{t:"4:3",r:4/3},{t:"3:4",r:3/4},{t:"16:9",r:16/9}]
                            UiButton {required property var modelData;text:modelData.t;chosen:Math.abs(editor.ratio-modelData.r)<.001;implicitWidth:52;implicitHeight:30;onClicked:editor.setRatio(modelData.r)}
                        }
                    }
                    RowLayout {Layout.fillWidth:true;spacing:8
                        Text {text:"角度";font.pixelSize:12;color:"#819373";Layout.fillWidth:true}
                        TextField {
                            id:angleInput;objectName:"angleInput";Layout.preferredWidth:75;text:"0.0"
                            validator:DoubleValidator {bottom:-360;top:360;decimals:1;notation:DoubleValidator.StandardNotation;locale:"C"}
                            selectByMouse:true
                            onTextEdited:if(acceptableInput)editor.angle=Number(text)
                            onEditingFinished:{if(acceptableInput)editor.angle=Number(text);text=editor.angle.toFixed(1)}
                            Binding {target:angleInput;property:"text";value:editor.angle.toFixed(1);when:!angleInput.activeFocus;restoreMode:Binding.RestoreNone}
                        }
                        UiButton {text:"重置";quiet:true;implicitHeight:28;onClicked:editor.angle=0}
                    }
                    UiSlider {id:rotationSlider;objectName:"rotationSlider";Layout.fillWidth:true;from:-180;to:180;stepSize:.1;value:editor.angle;onMoved:editor.angle=value;onPressedChanged:if(!pressed)editor.flushDraft()}
                    RowLayout {spacing:8;UiButton {text:"↶ 90°";onClicked:editor.angle=(editor.angle-90)%360} UiButton {text:"↷ 90°";onClicked:editor.angle=(editor.angle+90)%360}}
                    Rectangle {Layout.fillWidth:true;height:1;color:"#dce5d4"}
                    RowLayout {Layout.fillWidth:true;spacing:8
                        Text {text:"输出子图 "+editor.drafts.length;font.pixelSize:12;color:"#49623e";Layout.fillWidth:true}
                        UiButton {text:"＋ 添加";quiet:true;implicitHeight:28;onClicked:{editor.capture();let d=editor.spec();d.id=editor.uid();d.target=editor.targetFolder;editor.drafts=editor.drafts.concat([d]);editor.selectDraft(editor.drafts.length-1);editor.flushDraft()}}
                    }
                    Repeater {model:editor.drafts
                        Rectangle {required property var modelData;required property int index;Layout.fillWidth:true;Layout.preferredHeight:83;radius:5;color:editor.selectedDraft===index?"#e3eddb":"white";border.color:"#d6e1cd"
                            ColumnLayout {anchors.fill:parent;anchors.margins:9;spacing:5
                                RowLayout {Layout.fillWidth:true;spacing:8
                                    Text {text:"子图 "+(index+1);font.pixelSize:12;color:"#49623e";Layout.fillWidth:true}
                                    UiButton {text:"编辑";quiet:true;implicitHeight:24;implicitWidth:43;onClicked:editor.selectDraft(index)}
                                    UiButton {text:"移除";tone:"danger";hint:"移除此裁剪子图，不删除原图";implicitHeight:26;implicitWidth:48;enabled:editor.drafts.length>1;onClicked:{editor.capture();let d=editor.drafts.slice();d.splice(index,1);editor.loadingDraft=true;editor.drafts=d;editor.selectedDraft=-1;editor.loadingDraft=false;editor.selectDraft(Math.min(index,d.length-1));editor.flushDraft()}}
                                }
                                Text {text:modelData.target||"请在左侧选择目标目录";Layout.fillWidth:true;elide:Text.ElideMiddle;font.pixelSize:11;color:modelData.target?"#819373":"#a36044"}
                                Text {text:Number(modelData.angle).toFixed(1)+"° · PNG";font.pixelSize:10;color:"#98a48d"}
                            }
                        }
                    }
                    Text {text:"拖动四角缩放，拖动框内移动。\n裁剪区域始终限制在图片内。\n全部输出成功后才归档原图。";font.pixelSize:11;color:"#819373";lineHeight:1.6}
                }
            }
        }
    }
}
