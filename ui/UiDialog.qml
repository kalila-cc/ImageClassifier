import QtQuick
import QtQuick.Controls

Dialog {
    id: dialog
    focus: true
    padding: 20
    property string acceptTone: "normal"
    property string acceptText: ""
    property string rejectText: ""
    // Keep Qt's standard buttons and roles; change only their visible labels.
    function updateButtonLabels() {
        const buttons = [
            [DialogButtonBox.Ok, acceptText || "确定"],
            [DialogButtonBox.Save, acceptText || "保存"],
            [DialogButtonBox.SaveAll, acceptText || "全部保存"],
            [DialogButtonBox.Open, acceptText || "打开"],
            [DialogButtonBox.Yes, acceptText || "是"],
            [DialogButtonBox.YesToAll, acceptText || "全部确认"],
            [DialogButtonBox.No, rejectText || "否"],
            [DialogButtonBox.NoToAll, rejectText || "全部拒绝"],
            [DialogButtonBox.Abort, "中止"],
            [DialogButtonBox.Retry, "重试"],
            [DialogButtonBox.Ignore, "忽略"],
            [DialogButtonBox.Close, rejectText || "关闭"],
            [DialogButtonBox.Cancel, rejectText || "取消"],
            [DialogButtonBox.Discard, "放弃"],
            [DialogButtonBox.Help, "帮助"],
            [DialogButtonBox.Apply, "应用"],
            [DialogButtonBox.Reset, "重置"],
            [DialogButtonBox.RestoreDefaults, "恢复默认"]
        ];
        for (const entry of buttons) {
            const button = dialogButtons.standardButton(entry[0]);
            if (button) button.text = entry[1];
        }
    }
    Component.onCompleted: Qt.callLater(updateButtonLabels)
    onStandardButtonsChanged: Qt.callLater(updateButtonLabels)
    onAcceptTextChanged: Qt.callLater(updateButtonLabels)
    onRejectTextChanged: Qt.callLater(updateButtonLabels)
    background: Rectangle {color: "#fafbfc"; radius: 12; border.color: "#dce2e4"}
    header: Label {
        text: dialog.title
        visible: text.length > 0
        padding: 20; bottomPadding: 8
        font.pixelSize: 17; font.weight: Font.DemiBold
        color: "#263238"
        elide: Text.ElideRight
    }
    // Dialog connects standard button roles to accept/reject automatically.
    footer: DialogButtonBox {
        id: dialogButtons
        onCountChanged: Qt.callLater(dialog.updateButtonLabels)
        visible: count > 0
        spacing: 12
        leftPadding: 20; rightPadding: 20; topPadding: 12; bottomPadding: 20
        alignment: Qt.AlignRight
        background: Rectangle {color: "transparent"}
        delegate: UiButton {
            implicitWidth: Math.max(96, implicitContentWidth + 28)
            primary: DialogButtonBox.buttonRole === DialogButtonBox.AcceptRole || DialogButtonBox.buttonRole === DialogButtonBox.YesRole
            tone: DialogButtonBox.buttonRole === DialogButtonBox.DestructiveRole ? "danger" : primary ? dialog.acceptTone : "normal"
        }
    }
}
