import QtQuick

// Application-level activation avoids treating our own dialogs as app switches.
Timer {
    id: refresh
    property bool applicationActive: Qt.application.state === Qt.ApplicationActive
    property bool ready: false
    property bool blocked: false
    property bool observedActive: false
    property bool pending: false
    signal refreshRequested()
    interval: 350
    repeat: false

    function schedule() {
        if (ready && applicationActive && !blocked && pending) restart()
        else stop()
    }
    function observeActivation() {
        if (!ready) { stop(); return }
        if (applicationActive) observedActive = true
        else if (observedActive) pending = true
        schedule()
    }
    function acknowledgeRefresh() { pending = false; stop() }
    onApplicationActiveChanged: observeActivation()
    onReadyChanged: observeActivation()
    onBlockedChanged: schedule()
    Component.onCompleted: observeActivation()
    onTriggered: {
        pending = false
        refreshRequested()
    }
}
