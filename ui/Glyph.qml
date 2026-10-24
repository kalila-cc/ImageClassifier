import QtQuick
Canvas {
    id: icon
    property string name: "folder"
    property color ink: "#687a82"
    property real strokeWidth: 1.6
    onStrokeWidthChanged: requestPaint()
    width: 20; height: 20
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onInkChanged: requestPaint()
    onNameChanged: requestPaint()
    onPaint: {
        const c = getContext("2d"); c.reset(); c.scale(width/24, height/24);
        c.strokeStyle = ink; c.lineWidth = icon.strokeWidth; c.lineCap = "round"; c.lineJoin = "round";
        c.beginPath();
        if (name === "folder") { c.moveTo(3,6); c.lineTo(9,6); c.lineTo(11,9); c.lineTo(21,9); c.lineTo(21,20); c.lineTo(3,20); c.closePath(); }
        else if(name === "grid") { for(let y=4;y<20;y+=10) for(let x=4;x<20;x+=10) c.rect(x,y,6,6); }
        else if(name === "image") { c.rect(3,4,18,16); c.moveTo(3,17); c.lineTo(9,11); c.lineTo(14,16); c.lineTo(17,13); c.lineTo(21,17); c.moveTo(17,8); c.arc(16,8,1,0,6.28); }
        else if(name === "plus") { c.moveTo(12,5); c.lineTo(12,19); c.moveTo(5,12); c.lineTo(19,12); }
        else if(name === "close") { c.moveTo(6,6); c.lineTo(18,18); c.moveTo(18,6); c.lineTo(6,18); }
        else if(name === "trash") { c.moveTo(4,7); c.lineTo(20,7); c.moveTo(9,7); c.lineTo(9,4); c.lineTo(15,4); c.lineTo(15,7); c.moveTo(6,7); c.lineTo(7,21); c.lineTo(17,21); c.lineTo(18,7); c.moveTo(10,11); c.lineTo(10,17); c.moveTo(14,11); c.lineTo(14,17); }
        else if(name === "search") { c.arc(10,10,6,0,6.28); c.moveTo(15,15); c.lineTo(21,21); }
        else if(name === "crop") { c.moveTo(7,2); c.lineTo(7,17); c.lineTo(22,17); c.moveTo(2,7); c.lineTo(17,7); c.lineTo(17,22); }
        else if(name === "check") { c.moveTo(5,12); c.lineTo(10,17); c.lineTo(20,6); }
        else if(name === "archive") { c.rect(4,8,16,12); c.rect(3,4,18,4); c.moveTo(9,12); c.lineTo(15,12); }
        else if(name === "back" || name === "chevronLeft") { c.moveTo(15,5); c.lineTo(8,12); c.lineTo(15,19); }
        else if(name === "forward" || name === "chevronRight") { c.moveTo(9,5); c.lineTo(16,12); c.lineTo(9,19); }
        else if(name === "chevronDown") { c.moveTo(5,9); c.lineTo(12,16); c.lineTo(19,9); }
        else if(name === "history") { c.arc(12,12,8,-2.4,3.9); c.moveTo(3,4); c.lineTo(3,9); c.lineTo(8,9); c.moveTo(12,7); c.lineTo(12,12); c.lineTo(16,14); }
        else if(name === "settings") {
            // A continuous toothed outline reads as a gear, not a sun.
            for(let tooth=0;tooth<8;tooth++) {
                const center=tooth*Math.PI/4;
                const angles=[-Math.PI/8,-Math.PI/20,-Math.PI/20,Math.PI/20,Math.PI/20,Math.PI/8];
                const radii=[7.2,7.2,9.5,9.5,7.2,7.2];
                for(let point=0;point<angles.length;point++) {
                    const x=12+Math.cos(center+angles[point])*radii[point];
                    const y=12+Math.sin(center+angles[point])*radii[point];
                    if(tooth===0&&point===0)c.moveTo(x,y);else c.lineTo(x,y);
                }
            }
            c.closePath();c.moveTo(15,12);c.arc(12,12,3,0,Math.PI*2);
        }
        else if(name === "play") { c.moveTo(8,5); c.lineTo(19,12); c.lineTo(8,19); c.closePath(); }
        else if(name === "pause") { c.rect(6,5,4,14); c.rect(14,5,4,14); }
        else if(name === "stop") { c.rect(6,6,12,12); }
        else if(name === "volume" || name === "muted") {
            c.moveTo(3,9);c.lineTo(7,9);c.lineTo(12,5);c.lineTo(12,19);c.lineTo(7,15);c.lineTo(3,15);c.closePath();
            if(name === "muted") {c.moveTo(16,9);c.lineTo(22,15);c.moveTo(22,9);c.lineTo(16,15);}
            else {c.moveTo(16,8);c.bezierCurveTo(19,10,19,14,16,16);c.moveTo(19,5);c.bezierCurveTo(24,9,24,15,19,19);}
        }
        else if(name === "remove") { c.arc(12,12,8,0,Math.PI*2); c.moveTo(8,12); c.lineTo(16,12); }
        else if(name === "move") {
            c.moveTo(11,20);c.lineTo(3,20);c.lineTo(3,6);c.lineTo(9,6);c.lineTo(11,9);c.lineTo(21,9);c.lineTo(21,11);
            c.moveTo(11,16);c.lineTo(22,16);c.moveTo(18,12);c.lineTo(22,16);c.lineTo(18,20);
        }
        else if(name === "copy") {
            c.rect(8,8,12,13);c.moveTo(16,8);c.lineTo(16,3);c.lineTo(3,3);c.lineTo(3,16);c.lineTo(8,16);
        }
        else if(name === "rename") {
            c.moveTo(4,16);c.lineTo(16,4);c.quadraticCurveTo(17,3,18,4);
            c.lineTo(20,6);c.quadraticCurveTo(21,7,20,8);c.lineTo(8,20);c.lineTo(3,21);c.closePath();
            c.moveTo(14,6);c.lineTo(18,10);c.moveTo(4,16);c.lineTo(8,20);
        }
        else if(name === "refresh") {
            c.moveTo(20,8);c.bezierCurveTo(18,4,13,2,9,4);c.bezierCurveTo(5,5,3,9,4,13);
            c.moveTo(20,3);c.lineTo(20,8);c.lineTo(15,8);
            c.moveTo(4,16);c.bezierCurveTo(6,20,11,22,15,20);c.bezierCurveTo(19,19,21,15,20,11);
            c.moveTo(4,21);c.lineTo(4,16);c.lineTo(9,16);
        }
        else if(name === "restart") {
            c.moveTo(20,10);c.bezierCurveTo(19,5,14,2,9,4);c.bezierCurveTo(4,6,2,12,5,17);
            c.bezierCurveTo(8,22,16,22,20,16);
            c.moveTo(20,4);c.lineTo(20,10);c.lineTo(14,10);
        }
        else if(name === "folderOpen") {
            c.moveTo(3,19);c.lineTo(3,6);c.lineTo(9,6);c.lineTo(11,9);c.lineTo(20,9);c.lineTo(20,12);
            c.moveTo(3,19);c.lineTo(7,12);c.lineTo(22,12);c.lineTo(18,20);c.lineTo(3,20);c.closePath();
        }
        else if(name === "undo") {
            c.moveTo(4,9);c.lineTo(14,9);c.bezierCurveTo(22,9,22,20,14,20);c.lineTo(10,20);
            c.moveTo(9,4);c.lineTo(4,9);c.lineTo(9,14);
        }
        c.stroke();
    }
}
