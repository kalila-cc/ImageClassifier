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
    property var navigationItems:[]
    readonly property bool cropActive:backend.cropMode&&!isVideo&&!livePreview.playing
    property real cropX:.1
    property real cropY:.1
    property real cropW:.8
    property real cropH:.8
    property real angle:0
    property real ratio:0
    property alias zoom:canvas.zoom
    property var drafts:[]
    property int selectedDraft:-1
    property string loadedId:""
    property string loadedVersion:""
    property bool activeView:false
    property url videoSource:""
    property bool touched:false
    property bool smartApplied:false
    property string suggestionToken:""
    property string smartMessage:""
    property bool loadingDraft:false
    property var dimensions:({})
    property real canvasWidth:1
    property real canvasHeight:1
    property real imageCenterX:0
    property real imageCenterY:0
    readonly property bool keyboardAdjusting:rotationSlider.activeFocus||angleInput.activeFocus
    property bool isVideo:asset.type==="视频"
    readonly property bool previewReady:!!editor.dimensions.width&&preview.ready
    signal refreshRequested()
    signal previous()
    signal next()
    signal imageRequested(string assetId)
    signal notice(string message)
    signal exportRejected(string message)
    function uid(){return Date.now().toString(36)+Math.random().toString(36).slice(2)}
    function spec(){return {id:selectedDraft>=0&&drafts[selectedDraft]?drafts[selectedDraft].id:uid(),x:cropX,y:cropY,w:cropW,h:cropH,angle:angle,ratio:ratio,touched:touched,smartApplied:smartApplied,target:selectedDraft>=0&&drafts[selectedDraft]?drafts[selectedDraft].target:targetFolder}}
    function invalidateSuggestion(){suggestTimer.stop();suggestionToken=""}
    function manualEdit(){invalidateSuggestion();touched=true;smartMessage="已手动调整"}
    function queueSuggestion(force){
        if(!activeView||!cropActive||!backend.smartCrop.available||!backend.smartCrop.enabled||backend.busy||isVideo||asset.blocked||!loadedId||!dimensions.width)return;
        if(!force&&(suggestionToken!==""||suggestTimer.running))return;
        if(!force&&(touched||smartApplied))return;
        invalidateSuggestion();smartMessage="";suggestTimer.restart();
    }
    function requestSuggestion(){
        if(!activeView||!cropActive||!backend.smartCrop.available||!backend.smartCrop.enabled||backend.busy||isVideo||asset.blocked||!loadedId)return;
        suggestionToken=uid();smartMessage="正在生成裁剪建议…";
        backend.suggestCrop(loadedId,dimensions,spec(),suggestionToken);
    }
    function capture(){
        if(loadingDraft||selectedDraft<0)return;
        let list=drafts.slice();list[selectedDraft]=spec();drafts=list;
    }
    function flushDraft(){if(!loadedId||isVideo)return true;if(loadingDraft)return false;saveTimer.stop();capture();return backend.saveDraft(loadedId,drafts)}
    function enterEditing(){canvas.resetZoom()}
    function toggleZoomFrom(item,x,y){const p=item.mapToItem(canvas,x,y);canvas.toggleZoomAt(p.x,p.y)}
    function playVideo(){if(activeView&&isVideo&&!backend.busy){videoSource=asset.url||"";player.play()}}
    function toggleVideoPlayback(){
        if(!activeView||!isVideo||backend.busy)return;
        if(player.playbackState===MediaPlayer.PlayingState)player.pause();else playVideo();
    }
    function setCropMode(enabled){stopPlayback();flushDraft();backend.cropMode=enabled}
    function loadCurrent(){
        const stamp=(asset.id||"")+":"+(asset.size||0)+":"+(asset.mtime||0);
        const video=asset.type==="视频";
        if(stamp===loadedVersion)return;
        invalidateSuggestion();smartMessage="";
        // All edits are saved on change; never apply a new asset's values to an old draft.
        if(loadedId && loadedId!==(asset.id||"") && drafts.length && !loadingDraft) backend.saveDraft(loadedId,drafts);
        saveTimer.stop();
        stopPlayback();loadingDraft=true;loadedId=asset.id||"";loadedVersion=stamp;selectedDraft=-1;zoom=1;
        // Read the incoming type directly: the isVideo binding may update after onAssetChanged.
        dimensions=loadedId&&!video?backend.imageDimensions(loadedId):{};
        drafts=loadedId&&!video?backend.loadDraft(loadedId):[];
        if(loadedId&&!video&&drafts.length===0) drafts=[{id:uid(),x:.1,y:.1,w:.8,h:.8,angle:0,ratio:0,touched:false,smartApplied:false,target:targetFolder}];
        if(!drafts.length)angle=0;
        loadingDraft=false;
        if(drafts.length)selectDraft(0);
    }
    function selectDraft(index){
        invalidateSuggestion();smartMessage="";
        capture();loadingDraft=true;selectedDraft=index;let d=drafts[index];
        touched=d.touched===undefined?true:d.touched;smartApplied=!!d.smartApplied;
        cropX=d.x;cropY=d.y;cropW=d.w;cropH=d.h;angle=d.angle;ratio=d.ratio||0;loadingDraft=false;
        applyCrop(spec());
        queueSuggestion(false);
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
        manualEdit();ratio=value;applyCrop(spec());
    }
    function exportDrafts(onlyCrop,recycleOriginal,replaceOriginal){invalidateSuggestion();if(!flushDraft()){exportRejected("裁剪草稿未能保存，请检查数据目录后重试");return}if(drafts.length===0){exportRejected("至少保留一个裁剪区域");return}backend.exportCrops(loadedId,drafts,!!onlyCrop,!!recycleOriginal,!!replaceOriginal)}
    function stopPlayback(){player.stop();videoSource="";videoSound.muted=true;backend.livePhoto.stop()}
    function addDraft(){capture();let d=spec();d.id=uid();d.target=targetFolder;drafts=drafts.concat([d]);selectDraft(drafts.length-1);flushDraft()}
    function removeSelectedDraft(){
        if(drafts.length<=1||selectedDraft<0)return;
        capture();const index=selectedDraft;let list=drafts.slice();list.splice(index,1);
        loadingDraft=true;drafts=list;selectedDraft=-1;loadingDraft=false;
        selectDraft(Math.min(index,list.length-1));flushDraft();
    }
    function relocateTargets(from,to){
        saveTimer.stop();
        drafts=drafts.map(d=>Object.assign({},d,{target:backend.relocatedPath(d.target||"",from,to)}));
    }
    function assignTarget(path){if(selectedDraft<0||loadingDraft)return;let list=drafts.slice();let d=Object.assign({},list[selectedDraft]);d.target=path;list[selectedDraft]=d;drafts=list;schedule()}
    onAssetChanged:loadCurrent()
    onTargetFolderChanged:{if(selectedDraft>=0&&!loadingDraft&&!drafts[selectedDraft].target)assignTarget(targetFolder)}
    onAngleChanged:if(!loadingDraft){manualEdit();applyCrop(spec())}
    onActiveViewChanged:{if(activeView)queueSuggestion(false);else {invalidateSuggestion();stopPlayback()}}
    onCropActiveChanged:{if(cropActive)queueSuggestion(false);else {invalidateSuggestion();smartMessage=""}}
    Connections {
        target:backend
        function onChanged(){if(backend.busy){editor.invalidateSuggestion();editor.stopPlayback()}else editor.queueSuggestion(false)}
    }
    Connections {
        target:backend.smartCrop
        function onSuggested(token,crop,explanation){
            if(token!==editor.suggestionToken||!editor.activeView||!editor.cropActive||!backend.smartCrop.enabled||backend.busy)return;
            editor.suggestionToken="";editor.smartApplied=true;editor.applyCrop(crop);editor.smartMessage=explanation;editor.flushDraft();
        }
        function onSuggestionFailed(token,reason){if(token===editor.suggestionToken){editor.suggestionToken="";editor.smartMessage=reason}}
    }
    Timer {id:suggestTimer;interval:150;onTriggered:editor.requestSuggestion()}
    Timer {id:saveTimer;interval:400;onTriggered:editor.flushDraft()}
    NeighborPreload {
        objectName:"neighborPreload"
        active:editor.activeView&&!editor.isVideo
        settled:editor.previewReady&&!preview.slideRunning&&!backend.busy
        records:editor.navigationItems;currentId:editor.asset.id||""
    }
    Component.onDestruction:flushDraft()
    RowLayout {
        Layout.fillWidth:true;Layout.preferredHeight:52;Layout.leftMargin:14;Layout.rightMargin:14;spacing:8
        UiButton {iconName:"back";hint:"上一张";Accessible.name:hint;quiet:true;implicitWidth:32;enabled:editor.position>0&&!backend.busy;onClicked:{editor.flushDraft();editor.previous()}}
        Text {text:(editor.total?editor.position+1:0)+" / "+editor.total;font.pixelSize:13;font.weight:Font.Medium;color:"#69767b";Layout.minimumWidth:40;horizontalAlignment:Text.AlignHCenter}
        UiButton {iconName:"forward";hint:"下一张";Accessible.name:hint;quiet:true;implicitWidth:32;enabled:editor.position<editor.total-1&&!backend.busy;onClicked:{editor.flushDraft();editor.next()}}
        Text {text:editor.asset.name||"没有图片";elide:Text.ElideMiddle;Layout.fillWidth:true;font.pixelSize:13;font.weight:Font.Medium;color:"#263238"}
        UiButton {text:"打开所在目录";iconName:"folderOpen";hint:"在文件资源管理器中打开当前文件所在目录";quiet:true;enabled:!!editor.asset.path;onClicked:backend.reveal(editor.asset.path)}
        UiButton {objectName:"editorMediaAction";iconName:editor.isVideo?(player.playbackState===MediaPlayer.PlayingState?"pause":"play"):"crop";text:editor.isVideo?(player.playbackState===MediaPlayer.PlayingState?"暂停视频":"播放视频"):"裁剪 / 旋转";hint:editor.isVideo?text:editor.cropActive?"关闭裁剪模式，保留调整并记住此选择":"开启裁剪模式，并记住此选择";chosen:editor.cropActive&&!editor.isVideo;enabled:!!editor.asset.id;onClicked:{if(editor.isVideo)editor.toggleVideoPlayback();else editor.setCropMode(!editor.cropActive)}}
    }
    Rectangle {visible:!!editor.asset.blocked;Layout.fillWidth:true;Layout.preferredHeight:36;color:"#f5ead8"
        Text {anchors.fill:parent;anchors.margins:8;text:editor.asset.blocked||"";elide:Text.ElideRight;font.pixelSize:11;color:"#9c6a3c"}
    }
    RowLayout {
        Layout.fillWidth:true;Layout.fillHeight:true;spacing:0
        Rectangle {
            Layout.fillWidth:true;Layout.fillHeight:true;color:"#181d20";clip:true
            PhotoViewport {
                id:canvas;objectName:"photoViewport";anchors.fill:parent
                // Browsing uses the full viewport; crop handles need room at the image edges.
                anchors.margins:editor.cropActive?10:0
                anchors.bottomMargin:filmstrip.height+(editor.cropActive?10:0);visible:!editor.isVideo
                imageWidth:editor.canvasWidth;imageHeight:editor.canvasHeight
                gesturesEnabled:editor.activeView&&editor.previewReady&&!preview.slideRunning&&!editor.isVideo&&!livePreview.playing&&!backend.busy
                Item {
                    id:frame;width:canvas.contentWidth;height:canvas.contentHeight
                    RotatingPreview {
                        id:preview;objectName:"rotationPreview";anchors.fill:parent
                        // Move only the rendered photo; keep the pointer's coordinates and crop geometry stable.
                        gestureOffset:previewPointer.visualOffset
                        transform:Translate {x:preview.presentationOffset}
                        source:editor.asset.id&&!editor.isVideo?"image://media/"+editor.asset.id+"/0/detail/"+editor.asset.mtime:""
                        previewZoom:editor.zoom
                        shareDecodedImage:true
                        angle:editor.angle;sourceWidth:editor.dimensions.width||1;sourceHeight:editor.dimensions.height||1
                        canvasWidth:editor.canvasWidth;canvasHeight:editor.canvasHeight
                        imageCenterX:editor.imageCenterX;imageCenterY:editor.imageCenterY
                    }
                    PhotoSwipeArea {
                        id:previewPointer;objectName:"previewPointer";anchors.fill:parent
                        enabled:canvas.gesturesEnabled
                        navigationEnabled:enabled&&!backend.cropMode&&editor.zoom<=1.000001
                        zoomed:editor.zoom>1.000001
                        canPrevious:editor.position>0;canNext:editor.position<editor.total-1
                        assetKey:editor.loadedVersion
                        imageBounds:Qt.rect((width-preview.paintedWidth)/2,(height-preview.paintedHeight)/2,preview.paintedWidth,preview.paintedHeight)
                        onNavigate:direction=>{
                            if(!editor.flushDraft())return
                            const previousVersion=editor.loadedVersion
                            preview.holdSwipePosition()
                            if(direction<0)editor.previous();else editor.next()
                            if(editor.loadedVersion===previousVersion)preview.clearSwipePosition()
                        }
                        onZoomRequested:(x,y)=>editor.toggleZoomFrom(previewPointer,x,y)
                    }
                    Item {
                        objectName:"cropOutsideShade";anchors.fill:parent;visible:cropBox.visible
                        // Four rectangles leave the retained crop unobscured without extra image decoding.
                        Rectangle {x:0;y:0;width:parent.width;height:Math.max(0,cropBox.y);color:"#66121619"}
                        Rectangle {x:0;y:cropBox.y+cropBox.height;width:parent.width;height:Math.max(0,parent.height-y);color:"#66121619"}
                        Rectangle {x:0;y:cropBox.y;width:Math.max(0,cropBox.x);height:cropBox.height;color:"#66121619"}
                        Rectangle {x:cropBox.x+cropBox.width;y:cropBox.y;width:Math.max(0,parent.width-x);height:cropBox.height;color:"#66121619"}
                    }
                    Rectangle {
                        id:cropBox;objectName:"cropBox";visible:editor.cropActive&&!!editor.asset.id&&editor.previewReady
                        x:(frame.width-preview.paintedWidth)/2+editor.cropX*preview.paintedWidth
                        y:(frame.height-preview.paintedHeight)/2+editor.cropY*preview.paintedHeight
                        width:editor.cropW*preview.paintedWidth;height:editor.cropH*preview.paintedHeight
                        color:"transparent";border.width:1;border.color:"white"
                        Repeater {model:2;Rectangle {required property int index;x:parent.width/3*(index+1);width:1;height:parent.height;color:"#70ffffff"}}
                        Repeater {model:2;Rectangle {required property int index;y:parent.height/3*(index+1);height:1;width:parent.width;color:"#70ffffff"}}
                        MouseArea {id:cropMover;anchors.fill:parent;cursorShape:Qt.SizeAllCursor;preventStealing:true
                            property real startX;property real startY;property bool dragging:false;property bool suppressDrag:false
                            onPressed:mouse=>{const p=mapToItem(frame,mouse.x,mouse.y);startX=p.x;startY=p.y;dragging=false;suppressDrag=false}
                            onPositionChanged:mouse=>{
                                if(!pressed||suppressDrag)return;const p=mapToItem(frame,mouse.x,mouse.y);
                                if(!dragging&&Math.abs(p.x-startX)+Math.abs(p.y-startY)<2)return;
                                dragging=true;editor.manualEdit();const previous=editor.spec();let next=Object.assign({},previous);
                                next.x+=(p.x-startX)/preview.paintedWidth;next.y+=(p.y-startY)/preview.paintedHeight;
                                editor.applyCrop(next,previous);
                                // Discard rejected motion at the boundary so reversing
                                // direction reacts immediately, even outside the image.
                                startX=p.x;startY=p.y;
                            }
                            onReleased:editor.flushDraft()
                            onDoubleClicked:mouse=>{suppressDrag=true;editor.toggleZoomFrom(cropMover,mouse.x,mouse.y)}
                        }
                        Repeater {model:4
                            MouseArea {
                                id:edge;required property int index;objectName:"cropEdge"+index
                                // Left, top, right, bottom. Corners sit above these
                                // full-length edge targets and retain their gestures.
                                readonly property bool vertical:index===0||index===2
                                x:index===0?-10:index===2?cropBox.width-10:14
                                y:index===1?-10:index===3?cropBox.height-10:14
                                width:vertical?20:Math.max(0,cropBox.width-28)
                                height:vertical?Math.max(0,cropBox.height-28):20
                                z:1;preventStealing:true;cursorShape:vertical?Qt.SizeHorCursor:Qt.SizeVerCursor
                                property var initial:({})
                                property real start:0
                                onPressed:mouse=>{editor.manualEdit();initial=editor.spec();const p=mapToItem(frame,mouse.x,mouse.y);start=vertical?p.x:p.y}
                                onPositionChanged:mouse=>{
                                    if(!pressed)return;
                                    const p=mapToItem(frame,mouse.x,mouse.y);
                                    const delta=((vertical?p.x:p.y)-start)/(vertical?preview.paintedWidth:preview.paintedHeight);
                                    let next=Object.assign({},initial);
                                    if(vertical){next.w=Math.max(.02,initial.w+(index===0?-delta:delta));next.x=index===0?initial.x+initial.w-next.w:initial.x;}
                                    else {next.h=Math.max(.02,initial.h+(index===1?-delta:delta));next.y=index===1?initial.y+initial.h-next.h:initial.y;}
                                    if(editor.ratio>0){
                                        const r=editor.ratio*editor.canvasHeight/editor.canvasWidth;
                                        if(vertical){next.h=next.w/r;next.y=initial.y+(initial.h-next.h)/2;}
                                        else {next.w=next.h*r;next.x=initial.x+(initial.w-next.w)/2;}
                                    }
                                    editor.applyCrop(next,editor.spec());
                                    initial=editor.spec();start=vertical?p.x:p.y;
                                }
                                onReleased:editor.flushDraft()
                                Rectangle {
                                    anchors.centerIn:parent;width:edge.vertical?4:20;height:edge.vertical?20:4
                                    radius:2;color:"white"
                                }
                            }
                        }
                        Repeater {model:4
                            Rectangle {required property int index;width:12;height:12;radius:2;color:"white";x:index%2?cropBox.width-6:-6;y:index>1?cropBox.height-6:-6;z:2
                                MouseArea {objectName:"cropCorner"+index;anchors.fill:parent;anchors.margins:-8;preventStealing:true;cursorShape:index===0||index===3?Qt.SizeFDiagCursor:Qt.SizeBDiagCursor
                                    property real startX;property real startY
                                    onPressed:mouse=>{editor.manualEdit();const p=mapToItem(frame,mouse.x,mouse.y);startX=p.x;startY=p.y}
                                    onPositionChanged:mouse=>{
                                        if(!pressed)return;const p=mapToItem(frame,mouse.x,mouse.y);
                                        const oppositeX=editor.cropX+(index%2?0:editor.cropW),oppositeY=editor.cropY+(index>1?0:editor.cropH);
                                        const dx=(p.x-startX)/preview.paintedWidth,dy=(p.y-startY)/preview.paintedHeight;
                                        let w=Math.max(.02,editor.cropW+(index%2?dx:-dx)),h=Math.max(.02,editor.cropH+(index>1?dy:-dy));
                                        w=Math.min(w,index%2?1-oppositeX:oppositeX);h=Math.min(h,index>1?1-oppositeY:oppositeY);
                                        if(editor.ratio>0){const r=editor.ratio*editor.canvasHeight/editor.canvasWidth;h=w/r;const maxH=index>1?1-oppositeY:oppositeY;if(h>maxH){h=maxH;w=h*r}}
                                        let next=editor.spec();next.w=w;next.h=h;next.x=index%2?oppositeX:oppositeX-w;next.y=index>1?oppositeY:oppositeY-h;
                                        editor.applyCrop(next,editor.spec());
                                        startX=p.x;startY=p.y;
                                    }
                                    onReleased:editor.flushDraft()
                                }
                            }
                        }
                    }
                }
            }
            ColumnLayout {
                id: previewFeedback
                objectName:"previewFeedback"
                anchors.centerIn:canvas;width:Math.min(400,canvas.width-40);spacing:12
                readonly property bool waiting:editor.activeView&&!!editor.asset.id&&!editor.isVideo&&!editor.previewReady
                readonly property bool failed:preview.status===Image.Error||!editor.dimensions.width
                readonly property string requestKey:preview.source.toString()
                property bool delayElapsed:false
                visible:waiting&&(failed||delayElapsed)
                function resetDelay(){
                    loadingHintDelay.stop();delayElapsed=false;
                    if(waiting&&!failed)loadingHintDelay.start();
                }
                onWaitingChanged:resetDelay()
                onFailedChanged:resetDelay()
                onRequestKeyChanged:resetDelay()
                Timer {
                    id:loadingHintDelay;interval:300
                    onTriggered:if(previewFeedback.waiting&&!previewFeedback.failed)previewFeedback.delayElapsed=true
                }
                Glyph {Layout.alignment:Qt.AlignHCenter;name:"image";width:36;height:36;ink:"#94a2a9"}
                Text {Layout.fillWidth:true;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap;text:parent.failed?"无法预览这张图片":"正在加载图片…";font.pixelSize:15;color:"#e6ebee"}
                Text {Layout.fillWidth:true;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap;visible:parent.failed;text:"文件可能已移动、损坏，或格式暂不支持。";font.pixelSize:12;color:"#a9b5bc"}
                UiButton {objectName:"retryPreviewButton";Layout.alignment:Qt.AlignHCenter;text:"重新加载";visible:parent.failed;onClicked:{editor.dimensions=backend.imageDimensions(editor.loadedId);editor.applyCrop(editor.spec());preview.reload();editor.refreshRequested()}}
            }
            LivePhotoPreview {
                id:livePreview;objectName:"editorLivePreview"
                anchors.fill:parent;anchors.bottomMargin:filmstrip.height
                asset:editor.asset;ownerKey:"large";available:editor.activeView&&!backend.busy
                onBeforePlay:{editor.flushDraft();editor.invalidateSuggestion()}
            }
            Image {objectName:"editorVideoCover";anchors.fill:video;visible:editor.isVideo&&player.playbackState===MediaPlayer.StoppedState;source:editor.isVideo?(editor.asset.thumb||""):"";asynchronous:true;sourceSize.width:960;fillMode:Image.PreserveAspectFit}
            MediaPlayer {id:player;objectName:"editorVideoPlayer";source:editor.videoSource;audioOutput:AudioOutput {id:videoSound;objectName:"editorVideoAudio";muted:true} videoOutput:video;onSourceChanged:videoSound.muted=true;onErrorOccurred:(error,errorString)=>editor.notice("视频播放失败："+errorString)}
            VideoOutput {id:video;anchors.fill:parent;anchors.bottomMargin:filmstrip.height;visible:editor.isVideo&&player.playbackState!==MediaPlayer.StoppedState;fillMode:VideoOutput.PreserveAspectFit}
            MouseArea {
                objectName:"editorVideoClickArea";anchors.fill:video
                visible:editor.isVideo;enabled:editor.activeView&&editor.isVideo&&!backend.busy
                acceptedButtons:Qt.LeftButton;cursorShape:Qt.PointingHandCursor
                onClicked:editor.toggleVideoPlayback()
            }
            UiButton {
                id:videoSoundButton;objectName:"editorVideoSoundButton"
                anchors.top:video.top;anchors.right:video.right;anchors.margins:12
                implicitWidth:36;implicitHeight:32;visible:editor.isVideo&&player.hasAudio
                iconName:videoSound.muted?"muted":"volume"
                hint:videoSound.muted?"开启视频声音":"静音";Accessible.name:hint
                background:Rectangle {radius:8;color:videoSoundButton.down?Theme.alpha(Theme.soft,.8):videoSoundButton.pointerHovered?"#ccf5faf8":"#99f5f7f6";border.width:1;border.color:"#33ffffff"}
                onClicked:videoSound.muted=!videoSound.muted
            }
            UiButton {
                id:videoPlay;objectName:"editorVideoPlayButton";anchors.centerIn:video;width:64;height:64;padding:0
                visible:editor.isVideo&&player.playbackState!==MediaPlayer.PlayingState;hint:"播放视频";Accessible.name:hint
                contentItem:Item {Glyph {anchors.centerIn:parent;width:30;height:30;name:"play";ink:"white"}}
                background:Rectangle {radius:32;color:videoPlay.down?"#d920292d":videoPlay.pointerHovered?"#b320292d":"#8020292d";border.width:1;border.color:"#55ffffff"}
                onClicked:editor.playVideo()
            }
            UiSlider {objectName:"editorVideoSeek";Accessible.name:"视频播放进度";visible:editor.isVideo;anchors.bottom:parent.bottom;anchors.left:parent.left;anchors.right:parent.right;anchors.margins:15;anchors.bottomMargin:filmstrip.height+15;from:0;to:Math.max(1,player.duration);value:player.position;onMoved:player.setPosition(value)}
            ThumbnailStrip {
                id:filmstrip;objectName:"editorFilmstrip"
                anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom
                height:visible?implicitHeight:0;visible:editor.activeView&&backend.showFilmstrip&&editor.navigationItems.length>0
                active:visible;records:editor.navigationItems;currentId:editor.asset.id||""
                onActivated:assetId=>editor.imageRequested(assetId)
            }
        }
        Rectangle {
            visible:editor.cropActive&&!editor.isVideo&&!!editor.asset.id
            Layout.preferredWidth:268;Layout.fillHeight:true;color:"#fafbfc"
            Rectangle {anchors.left:parent.left;anchors.top:parent.top;anchors.bottom:parent.bottom;width:1;color:"#e3e7e9"}
            ScrollView {
                id:tools;objectName:"cropToolsScroll";anchors.fill:parent;anchors.margins:14;clip:true;contentWidth:availableWidth
                ScrollBar.horizontal.policy:ScrollBar.AlwaysOff
                ColumnLayout {
                    width:tools.availableWidth;spacing:6;enabled:editor.previewReady
                    RowLayout {Layout.fillWidth:true;spacing:8
                        Glyph {name:"crop";width:17;height:17;ink:Theme.primary}
                        Text {text:"裁剪与旋转";font.pixelSize:14;font.weight:Font.DemiBold;color:"#263238";Layout.fillWidth:true}
                        UiButton {objectName:"closeCropTools";iconName:"close";quiet:true;hint:"关闭裁剪模式，保留调整并记住此选择";Accessible.name:hint;implicitWidth:26;implicitHeight:26;onClicked:editor.setCropMode(false)}
                    }
                    ColumnLayout {
                        Layout.fillWidth:true;spacing:3;Layout.topMargin:4
                        RowLayout {Layout.fillWidth:true;spacing:8
                            CheckBox {
                                id:smartToggle;objectName:"smartMode";text:"智能模式";checked:backend.smartCrop.enabled;Layout.fillWidth:true
                                enabled:backend.smartCrop.available;opacity:enabled?1:.4
                                Accessible.description:enabled?"为图片自动推荐裁剪区域，可继续手动调整":"请前往设置安装智能裁剪模型"
                                ToolTip.visible:smartPointer.containsMouse;ToolTip.text:Accessible.description;ToolTip.delay:600
                                implicitHeight:28;spacing:8;padding:0
                                indicator:Rectangle {x:0;y:(smartToggle.height-height)/2;width:18;height:18;radius:5
                                    color:smartToggle.checked?Theme.primary:smartPointer.containsMouse?"#edf1f2":"white"
                                    border.color:smartToggle.checked?Theme.primary:"#b9c5c9"
                                    Glyph {anchors.centerIn:parent;name:"check";width:14;height:14;visible:smartToggle.checked;ink:"white"}
                                    Rectangle {anchors.fill:parent;anchors.margins:-3;radius:8;color:"transparent";border.color:Theme.primary;border.width:2;visible:smartToggle.visualFocus}
                                }
                                contentItem:Text {text:smartToggle.text;leftPadding:26;verticalAlignment:Text.AlignVCenter;font.pixelSize:13;font.weight:Font.Medium;color:"#263238"}
                                MouseArea {id:smartPointer;anchors.fill:parent;hoverEnabled:true;acceptedButtons:Qt.NoButton;cursorShape:smartToggle.enabled?Qt.PointingHandCursor:Qt.ArrowCursor}
                                onClicked:{backend.smartCrop.enabled=checked;if(backend.smartCrop.enabled)editor.queueSuggestion(true);else {editor.invalidateSuggestion();editor.smartMessage=""}}
                            }
                            UiButton {objectName:"suggestAgain";text:"重新推荐";hint:"重新生成建议并替换当前裁剪区域，其他区域不变";quiet:true;implicitHeight:28;enabled:backend.smartCrop.available&&backend.smartCrop.enabled&&!!editor.loadedId&&!editor.asset.blocked
                                onClicked:editor.queueSuggestion(true)}
                        }
                        Text {
                            Layout.fillWidth:true;visible:backend.smartCrop.enabled||!backend.smartCrop.available
                            text:!backend.smartCrop.available?(backend.smartCrop.installer.installing?"模型安装中，可继续手动裁剪":"可前往设置安装智能裁剪模型"):editor.smartMessage||backend.smartCrop.status;elide:Text.ElideRight;font.pixelSize:11;color:"#69767b"
                            ToolTip.visible:smartStatusHover.hovered;ToolTip.text:text;ToolTip.delay:500
                            HoverHandler {id:smartStatusHover}
                        }
                    }
                    Rectangle {Layout.fillWidth:true;Layout.topMargin:4;Layout.bottomMargin:4;implicitHeight:1;color:"#e3e7e9"}
                    RowLayout {Layout.fillWidth:true;spacing:8
                        Text {text:"裁剪区域";font.pixelSize:14;font.weight:Font.DemiBold;color:"#263238"}
                        Text {text:editor.drafts.length;font.pixelSize:11;color:"#69767b";Layout.fillWidth:true}
                        UiButton {objectName:"removeCropDraft";iconName:"remove";quiet:true;hint:"移除当前裁剪区域，不删除任何文件";Accessible.name:hint;implicitWidth:26;implicitHeight:26;enabled:editor.drafts.length>1;onClicked:editor.removeSelectedDraft()}
                    }
                    Flow {
                        objectName:"cropDraftTabs";Layout.fillWidth:true;Layout.preferredHeight:implicitHeight;spacing:6
                        Repeater {model:editor.drafts
                            UiButton {
                                required property var modelData;required property int index
                                objectName:"cropDraftTab"+index;width:56;height:28;text:"区域 "+(index+1);quiet:true;chosen:editor.selectedDraft===index
                                hint:"裁剪区域 "+(index+1)+"\n旋转角度："+Number(modelData.angle).toFixed(1)+"°"
                                onClicked:editor.selectDraft(index)
                            }
                        }
                        UiButton {objectName:"addCropDraft";width:28;height:28;iconName:"plus";hint:"添加裁剪区域，用于生成另一张子图";Accessible.name:hint;onClicked:editor.addDraft()}
                    }
                    Rectangle {Layout.fillWidth:true;Layout.topMargin:4;Layout.bottomMargin:4;implicitHeight:1;color:"#e3e7e9"}
                    Text {text:"画幅比例";font.pixelSize:14;font.weight:Font.DemiBold;color:"#263238"}
                    GridLayout {Layout.fillWidth:true;columns:3;columnSpacing:6;rowSpacing:2
                        Repeater {model:[{t:"自由",r:0,icon:"free"},{t:"1:1",r:1,icon:"1-1"},{t:"4:3",r:4/3,icon:"4-3"},{t:"3:4",r:3/4,icon:"3-4"},{t:"16:9",r:16/9,icon:"16-9"}]
                            UiButton {
                                id:ratioButton
                                required property var modelData
                                text:modelData.t;chosen:Math.abs(editor.ratio-modelData.r)<.001
                                Layout.fillWidth:true;Layout.preferredWidth:64;Layout.minimumWidth:56;implicitHeight:44
                                Accessible.name:modelData.r===0?"自由裁剪":"裁剪比例 "+modelData.t
                                hint:modelData.r===0?"自由调整宽高":"锁定宽高比 "+modelData.t
                                onClicked:editor.setRatio(modelData.r)
                                background:Rectangle {
                                    radius:7
                                    color:ratioButton.chosen?(ratioButton.down?Theme.softHover:Theme.soft):ratioButton.down?"#e5eaec":ratioButton.pointerHovered?"#eff2f3":"transparent"
                                    border.width:ratioButton.activeFocus?1:0;border.color:Theme.focus
                                }
                                contentItem:Item {
                                    Column {anchors.centerIn:parent;spacing:0;scale:ratioButton.down?.96:1
                                        ThemedIcon {
                                            anchors.horizontalCenter:parent.horizontalCenter
                                            width:23;height:23;sourceSize:Qt.size(46,46)
                                            opacity:ratioButton.chosen||ratioButton.pointerHovered||ratioButton.activeFocus?1:.65
                                            name:"crop-"+ratioButton.modelData.icon
                                        }
                                        Text {
                                            anchors.horizontalCenter:parent.horizontalCenter
                                            text:ratioButton.text;font.pixelSize:11
                                            font.weight:ratioButton.chosen?Font.DemiBold:Font.Normal
                                            color:ratioButton.chosen?Theme.primary:"#69767b"
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Rectangle {Layout.fillWidth:true;Layout.topMargin:4;Layout.bottomMargin:4;implicitHeight:1;color:"#e3e7e9"}
                    RowLayout {Layout.fillWidth:true;spacing:6
                        Text {text:"旋转";font.pixelSize:14;font.weight:Font.DemiBold;color:"#263238";Layout.fillWidth:true}
                        UiTextField {
                            id:angleInput;objectName:"angleInput";Accessible.name:"旋转角度，单位度";Layout.preferredWidth:64;implicitHeight:30;text:"0.0";horizontalAlignment:TextInput.AlignRight
                            validator:DoubleValidator {bottom:-360;top:360;decimals:1;notation:DoubleValidator.StandardNotation;locale:"C"}
                            selectByMouse:true
                            onTextEdited:if(acceptableInput)editor.angle=Number(text)
                            onEditingFinished:{if(acceptableInput)editor.angle=Number(text);text=editor.angle.toFixed(1)}
                            Binding {target:angleInput;property:"text";value:editor.angle.toFixed(1);when:!angleInput.activeFocus;restoreMode:Binding.RestoreNone}
                        }
                        Text {text:"°";font.pixelSize:12;color:"#69767b"}
                        UiButton {text:"归零";hint:"将旋转角度恢复为 0°";Accessible.name:"旋转角度归零";quiet:true;implicitHeight:28;implicitWidth:42;onClicked:editor.angle=0}
                    }
                    UiSlider {id:rotationSlider;objectName:"rotationSlider";Accessible.name:"旋转角度";Layout.fillWidth:true;implicitHeight:24;from:-180;to:180;stepSize:.1;value:editor.angle;onMoved:editor.angle=value;onPressedChanged:if(!pressed)editor.flushDraft()}
                    RowLayout {Layout.fillWidth:true;spacing:8
                        Repeater {model:[{label:"左转 90°",icon:"rotate-left",angle:-90},{label:"右转 90°",icon:"rotate-right",angle:90}]
                            UiButton {
                                id:rotateButton;objectName:modelData.angle<0?"rotateLeftButton":"rotateRightButton"
                                required property var modelData
                                Layout.fillWidth:true;Layout.preferredWidth:100;implicitHeight:32
                                text:modelData.label;Accessible.name:text;hint:modelData.angle<0?"逆时针旋转 90°":"顺时针旋转 90°"
                                onClicked:editor.angle=(editor.angle+modelData.angle)%360
                                background:Rectangle {
                                    color:rotateButton.down?"#e0e8e9":rotateButton.pointerHovered?"#edf1f2":"transparent";radius:6
                                    border.width:rotateButton.activeFocus?1:0;border.color:Theme.focus
                                }
                                contentItem:Item {
                                    Row {anchors.centerIn:parent;spacing:7;scale:rotateButton.down?.96:1
                                        ThemedIcon {width:20;height:20;sourceSize:Qt.size(40,40);name:rotateButton.modelData.icon;opacity:rotateButton.pointerHovered||rotateButton.activeFocus?1:.8}
                                        Text {anchors.verticalCenter:parent.verticalCenter;text:rotateButton.text;font.pixelSize:12;color:rotateButton.pointerHovered||rotateButton.down?Theme.primary:"#69767b"}
                                    }
                                }
                            }
                        }
                    }
                    Text {text:"裁剪结果保存在原目录，可随后移动或复制";Layout.fillWidth:true;Layout.topMargin:3;font.pixelSize:11;color:"#839095"}
                }
            }
        }
    }
}
