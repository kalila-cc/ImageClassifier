import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
ColumnLayout {
    id: field
    property string label: "主色"
    property string value: "#16756a"
    property bool invalid: false
    signal colorSelected(string value)
    onValueChanged:invalid=false
    spacing: 7
    Text {text:field.label;font.pixelSize:12;color:"#45545b"}
    RowLayout {
        Layout.fillWidth:true;spacing:10
        UiButton {
            objectName:field.objectName+"Picker";implicitWidth:38;implicitHeight:36;hint:"选择"+field.label
            background:Rectangle {color:field.value;radius:6;border.color:"#33000000"}
            onClicked:{picker.selectedColor=field.value;picker.open()}
        }
        UiTextField {
            id:input;objectName:field.objectName+"Hex";Layout.fillWidth:true
            text:field.value.toUpperCase();maximumLength:7;Accessible.name:field.label+"颜色值"
            onTextEdited:field.invalid=false
            onEditingFinished:{
                const value=text.trim()
                if(/^#[0-9a-fA-F]{6}$/.test(value)){field.invalid=false;field.colorSelected(value.toLowerCase())}
                else field.invalid=true
            }
            Keys.onEscapePressed:{text=field.value.toUpperCase();field.invalid=false}
        }
    }
    Text {visible:field.invalid;text:"请输入 # 加六位十六进制颜色值";color:"#a33636";font.pixelSize:11;Layout.fillWidth:true;wrapMode:Text.Wrap}
    ColorDialog {id:picker;title:"选择"+field.label;onAccepted:{field.invalid=false;field.colorSelected(selectedColor.toString().slice(0,7))}}
}
