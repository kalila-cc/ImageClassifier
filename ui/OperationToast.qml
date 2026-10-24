import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: toast
    property string outcome: "success"
    property string title: ""
    property string detail: ""
    property var queue: []
    property bool present: false
    readonly property color accent: outcome === "success" ? "#16756a" : outcome === "error" ? "#b34242" : "#99651f"
    signal detailsRequested(string text)

    function show(outcome, title, detail) {
        queue=queue.concat([{outcome:outcome,title:title,detail:detail}]);
        if(!present)advance();
    }
    function advance() {
        if(!queue.length)return;
        const next=queue[0];queue=queue.slice(1);
        outcome=next.outcome;title=next.title;detail=next.detail;
        present=true;entrance.restart();iconDraw.restart();if(!hover.hovered)expiry.restart();
    }
    function dismiss() { if(present&&!exitAnimation.running){expiry.stop();exitAnimation.start();} }

    width: Math.min(420, parent.width-32)
    height: content.implicitHeight+28
    visible: present
    opacity: 0
    radius: 12
    color: "#ffffff"
    border.color: outcome === "success" ? "#bcd9d2" : outcome === "error" ? "#e5c5c5" : "#e2d2b9"
    Accessible.role: Accessible.AlertMessage
    Accessible.name: title+"。"+detail
    property real entranceOffset: 8
    transform: Translate { y: toast.entranceOffset }

    ParallelAnimation {
        id:entrance
        NumberAnimation {target:toast;property:"opacity";from:0;to:1;duration:160}
        NumberAnimation {target:toast;property:"entranceOffset";from:8;to:0;duration:220;easing.type:Easing.OutCubic}
    }
    NumberAnimation {
        id:exitAnimation;target:toast;property:"opacity";to:0;duration:140
        onFinished:{toast.present=false;toast.advance()}
    }
    Timer {id:expiry;interval:toast.outcome==="success"?3600:7000;onTriggered:toast.dismiss()}
    HoverHandler {id:hover;onHoveredChanged:{if(hovered)expiry.stop();else if(toast.present&&!exitAnimation.running)expiry.restart()}}
    MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons}
    RowLayout {
        id:content;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:14;spacing:12
        Rectangle {
            Layout.alignment:Qt.AlignTop;Layout.topMargin:1
            width:32;height:32;radius:16;color:Qt.rgba(toast.accent.r,toast.accent.g,toast.accent.b,0.08)
            Canvas {
                id:statusIcon;objectName:"toastStatusIcon";anchors.fill:parent
                property real progress:0
                onProgressChanged:requestPaint()
                Connections {target:toast;function onOutcomeChanged(){statusIcon.requestPaint()}}
                onPaint:{
                    const c=getContext("2d");c.reset();c.strokeStyle=toast.accent;c.lineWidth=1.8;c.lineCap="round";c.lineJoin="round";
                    c.beginPath();c.arc(16,16,11,-Math.PI/2,-Math.PI/2+Math.PI*2*Math.min(1,progress*1.7));c.stroke();
                    c.globalAlpha=Math.max(0,(progress-0.3)/0.7);
                    c.beginPath();
                    if(toast.outcome==="success"){c.moveTo(10.5,16);c.lineTo(14.2,19.7);c.lineTo(21.5,12);}
                    else if(toast.outcome==="error"){c.moveTo(12,12);c.lineTo(20,20);c.moveTo(20,12);c.lineTo(12,20);}
                    else {c.moveTo(16,10.5);c.lineTo(16,17);c.moveTo(16,21);c.lineTo(16,21.1);}
                    c.stroke();
                }
                NumberAnimation {id:iconDraw;target:statusIcon;property:"progress";from:0;to:1;duration:420;easing.type:Easing.OutCubic}
            }
        }
        ColumnLayout {
            Layout.fillWidth:true;spacing:5
            Text {text:toast.title;textFormat:Text.PlainText;Layout.fillWidth:true;wrapMode:Text.Wrap;color:"#263b43";font.pixelSize:14;font.weight:Font.DemiBold}
            Text {text:toast.detail;textFormat:Text.PlainText;Layout.fillWidth:true;wrapMode:Text.Wrap;maximumLineCount:3;elide:Text.ElideRight;color:"#60717a";font.pixelSize:12;lineHeight:1.2}
            UiButton {
                objectName:"toastDetailsButton";visible:toast.outcome!=="success";text:"查看详情";quiet:true;implicitHeight:28
                onClicked:{const message=toast.title+"\n\n"+toast.detail;toast.dismiss();toast.detailsRequested(message)}
            }
        }
        UiButton {objectName:"toastCloseButton";Layout.alignment:Qt.AlignTop;iconName:"close";quiet:true;implicitWidth:24;implicitHeight:24;hint:"关闭提示";onClicked:toast.dismiss()}
    }
}
