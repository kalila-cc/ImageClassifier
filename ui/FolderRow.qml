import QtQuick
import QtQuick.Layouts
Rectangle {
    id: row
    property string label: ""
    property string count: ""
    property int depth: 0
    property bool selected: false
    property bool expandable: false
    property bool expanded: false
    signal clicked()
    signal toggled()
    implicitHeight: 38
    radius: 6
    color: enabled&&hit.pressed ? "#c6d9c2" : enabled&&hit.containsMouse ? "#d2e3cc" : selected ? "#dfeae2" : "transparent"
    MouseArea { id: hit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: row.clicked() }
    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 6 + row.depth * 22; anchors.rightMargin: 12; spacing: 8
        Text { text: row.expandable ? (row.expanded ? "⌄" : "›") : ""; color: "#7d857d"; font.pixelSize: 16; Layout.preferredWidth: 12
            MouseArea { anchors.fill: parent; anchors.margins: -5;enabled:row.expandable;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked: row.toggled() }
        }
        Glyph { name: "folder"; ink: row.selected ? "#285c49" : "#899087"; Layout.preferredWidth: 17; Layout.preferredHeight: 17 }
        Text { text: row.label; color: row.selected ? "#285c49" : "#4c554d"; font.pixelSize: 13; font.weight: row.selected ? Font.DemiBold : Font.Normal; Layout.fillWidth: true }
        Text { text: row.count; color: "#92998e"; font.pixelSize: 11 }
    }
}
