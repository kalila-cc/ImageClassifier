import QtQuick
Canvas {
    id: icon
    property string name: "folder"
    property color ink: "#747e75"
    width: 20; height: 20
    onInkChanged: requestPaint()
    onNameChanged: requestPaint()
    onPaint: {
        const c = getContext("2d"); c.reset(); c.scale(width/24, height/24);
        c.strokeStyle = ink; c.lineWidth = 1.6; c.lineCap = "round"; c.lineJoin = "round";
        c.beginPath();
        if (name === "folder") { c.moveTo(3,6); c.lineTo(9,6); c.lineTo(11,9); c.lineTo(21,9); c.lineTo(21,20); c.lineTo(3,20); c.closePath(); }
        else if(name === "grid") { for(let y=4;y<20;y+=10) for(let x=4;x<20;x+=10) c.rect(x,y,6,6); }
        else if(name === "image") { c.rect(3,4,18,16); c.moveTo(3,17); c.lineTo(9,11); c.lineTo(14,16); c.lineTo(17,13); c.lineTo(21,17); c.moveTo(17,8); c.arc(16,8,1,0,6.28); }
        else if(name === "plus") { c.moveTo(12,5); c.lineTo(12,19); c.moveTo(5,12); c.lineTo(19,12); }
        else if(name === "search") { c.arc(10,10,6,0,6.28); c.moveTo(15,15); c.lineTo(21,21); }
        else if(name === "crop") { c.moveTo(7,2); c.lineTo(7,17); c.lineTo(22,17); c.moveTo(2,7); c.lineTo(17,7); c.lineTo(17,22); }
        else if(name === "check") { c.moveTo(5,12); c.lineTo(10,17); c.lineTo(20,6); }
        else if(name === "archive") { c.rect(4,8,16,12); c.rect(3,4,18,4); c.moveTo(9,12); c.lineTo(15,12); }
        else if(name === "back") { c.moveTo(15,5); c.lineTo(8,12); c.lineTo(15,19); }
        else if(name === "play") { c.moveTo(8,5); c.lineTo(19,12); c.lineTo(8,19); c.closePath(); }
        c.stroke();
    }
}
