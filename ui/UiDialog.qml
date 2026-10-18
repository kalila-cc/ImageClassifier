import QtQuick
import QtQuick.Controls

Dialog {
    id: dialog
    property string acceptTone: "normal"
    // Dialog connects standard button roles to accept/reject automatically.
    footer: DialogButtonBox {
        visible: count > 0
        spacing: 12
        alignment: Qt.AlignRight
        delegate: UiButton {
            implicitWidth: Math.max(96, implicitContentWidth + 28)
            primary: DialogButtonBox.buttonRole === DialogButtonBox.AcceptRole || DialogButtonBox.buttonRole === DialogButtonBox.YesRole
            tone: DialogButtonBox.buttonRole === DialogButtonBox.DestructiveRole ? "danger" : primary ? dialog.acceptTone : "normal"
        }
    }
}
