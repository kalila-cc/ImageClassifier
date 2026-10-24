import QtQuick
import QtQuick.Controls

Menu {
    id: menu
    implicitWidth: {
        let widest = 0;
        for (let i = 0; i < menu.count; ++i) {
            const entry = menu.itemAt(i);
            if (entry && entry.text !== undefined) widest = Math.max(widest, entry.implicitWidth);
        }
        return Math.ceil(widest + leftPadding + rightPadding);
    }
    padding: 5
    background: Rectangle {color: "#ffffff"; radius: 8; border.color: "#d6dfe2"}
}
