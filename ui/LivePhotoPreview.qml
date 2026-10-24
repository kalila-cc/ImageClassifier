import QtQuick
import QtQuick.Controls
import QtMultimedia

Item {
    id: live
    property var asset: ({})
    property string ownerKey: ""
    property bool available: true
    property bool compact: false
    readonly property bool ownsPlayback: backend.livePhoto.owner === ownerKey && backend.livePhoto.assetId === (asset.id || "")
    readonly property bool playing: ownsPlayback && available
    readonly property bool muted: playback.item ? playback.item.muted : true
    signal beforePlay()
    visible: !!asset.isLive && available

    function stop() { if (ownsPlayback) backend.livePhoto.stop() }
    function hitTest(item, x, y) {
        if (!visible) return false;
        const point=controls.mapFromItem(item,x,y);
        return point.x>=0 && point.y>=0 && point.x<controls.width && point.y<controls.height;
    }
    onAvailableChanged: if (!available) stop()
    onVisibleChanged: if (!visible) stop()
    onAssetChanged: if (backend.livePhoto.owner === ownerKey && backend.livePhoto.assetId !== (asset.id || "")) backend.livePhoto.stop()
    Component.onDestruction: stop()

    // Delegates allocate a decoder only for the one explicitly requested photo.
    Loader {
        id: playback; anchors.fill: parent
        active: live.playing && backend.livePhoto.source.length > 0
        sourceComponent: Rectangle {
            id: surface
            color: "#181d20"
            property bool frameReady: false
            visible: frameReady
            property alias muted: sound.muted
            property alias hasAudio: motion.hasAudio
            MediaPlayer {
                id: motion; objectName: "liveMediaPlayer"
                source: backend.livePhoto.source
                loops: MediaPlayer.Infinite
                audioOutput: AudioOutput {id: sound; objectName: "liveAudioOutput"; muted: true}
                videoOutput: output
                Component.onCompleted: play()
                onErrorOccurred: (error,errorString) => {
                    live.stop();
                    backend.message("实况视频无法播放："+errorString);
                }
            }
            VideoOutput {id: output; objectName: "liveVideoOutput"; anchors.fill: parent; fillMode: live.compact ? VideoOutput.PreserveAspectCrop : VideoOutput.PreserveAspectFit}
            Connections {
                target: output.videoSink
                enabled: !surface.frameReady
                function onVideoFrameChanged() {surface.frameReady=true}
            }
            Component.onDestruction: {motion.stop();motion.source=""}
        }
    }
    Row {
        id: controls; objectName: "liveControls"
        anchors.top: parent.top; anchors.right: parent.right
        anchors.margins: live.compact ? 7 : 12
        spacing: 6
        UiButton {
            id: soundButton
            objectName: "liveSoundButton"
            visible: live.playing && !!playback.item && playback.item.hasAudio
            implicitWidth: 34; implicitHeight: 32
            iconName: live.muted ? "muted" : "volume"
            hint: live.muted ? "开启实况声音" : "静音"; Accessible.name: hint
            background: Rectangle {
                radius: 8
                color: soundButton.down ? Theme.softPressed : soundButton.pointerHovered ? "#f5faf8" : "#d9f5f7f6"
                border.width: 1; border.color: "#55ffffff"
            }
            onClicked: if (playback.item) playback.item.muted=!playback.item.muted
        }
        UiButton {
            id: playButton
            objectName: "livePlayButton"
            implicitWidth: 36; implicitHeight: 32
            hint: live.playing ? (backend.livePhoto.loading ? "正在准备实况，点击取消" : "停止播放，返回封面") : "循环播放实况照片，默认静音"
            Accessible.name: hint; Accessible.checkable: true; Accessible.checked: live.playing
            contentItem: Item {
                Image {
                    id: liveIcon; objectName: "livePhotoIcon"
                    anchors.centerIn: parent; width: 24; height: 24
                    source: "icons/live-photo.svg"; sourceSize.width: 48; sourceSize.height: 48
                    RotationAnimator on rotation {
                        from: 0; to: 360; duration: 1200; loops: Animation.Infinite
                        running: live.playing && backend.livePhoto.loading
                    }
                }
            }
            background: Rectangle {
                radius: 8
                color: playButton.down ? Theme.alpha(Theme.soft,.8) : live.playing ? (playButton.pointerHovered ? Theme.alpha(Theme.softHover,.8) : Theme.alpha(Theme.soft,.7)) : playButton.pointerHovered ? "#ccf5faf8" : "#99f5f7f6"
                border.width: 1; border.color: live.playing ? Theme.alpha(Theme.focus,.4) : "#33ffffff"
            }
            onClicked: {if(live.playing)live.stop();else {live.beforePlay();backend.playLive(live.asset.id,live.ownerKey)}}
        }
    }
}
