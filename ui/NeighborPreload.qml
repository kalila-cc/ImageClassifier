import QtQuick

// Keep two bounded, decoded previews alive so the foreground Image can share them.
Item {
    id: preload
    visible: false
    property bool active: false
    property bool settled: false
    property var records: []
    property string currentId: ""
    property url previousSource: ""
    property url nextSource: ""
    function sourceAt(index) {
        const item = records[index]
        return item && item.id && item.type !== "视频" ? "image://media/" + item.id + "/0/detail/" + item.mtime : ""
    }
    function schedule() {
        delay.stop()
        if (!active) { previousSource = ""; nextSource = ""; return }
        if (settled) delay.restart()
    }
    onActiveChanged: schedule()
    onSettledChanged: schedule()
    onRecordsChanged: schedule()
    onCurrentIdChanged: schedule()
    Timer {
        id: delay; interval: 120
        onTriggered: {
            const index = preload.records.findIndex(item => item.id === preload.currentId)
            preload.nextSource = index >= 0 ? preload.sourceAt(index + 1) : ""
            preload.previousSource = index >= 0 ? preload.sourceAt(index - 1) : ""
        }
    }
    Image { objectName: "preloadedNext"; source: preload.nextSource; asynchronous: true; cache: true; sourceSize.width: 2000; sourceSize.height: 2000 }
    Image { objectName: "preloadedPrevious"; source: preload.previousSource; asynchronous: true; cache: true; sourceSize.width: 2000; sourceSize.height: 2000 }
}
