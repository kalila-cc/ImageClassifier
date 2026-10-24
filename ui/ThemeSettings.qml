import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
ColumnLayout {
    id: panel
    objectName:"themeSettings"
    spacing:24
    readonly property var presets: Theme.gradient ? [
        {name:"海盐",primary:"#a8dfcf",secondary:"#afd5f0"},
        {name:"朝霞",primary:"#f0b8c5",secondary:"#f5d5ad"},
        {name:"春日",primary:"#c6dfad",secondary:"#f2dfa5"},
        {name:"晴空",primary:"#b9c8f0",secondary:"#aae0e0"}
    ] : [
        {name:"薄荷",primary:"#a8dfcf"},{name:"晴蓝",primary:"#afd5f0"},
        {name:"蜜桃",primary:"#f5c7ad"},{name:"樱粉",primary:"#f0b8c5"},
        {name:"奶杏",primary:"#f2dfa5"},{name:"浅藤",primary:"#cfc5ee"}
    ]
    function apply(primary,secondary,mode){backend.theme={primary:primary,secondary:secondary,mode:mode}}
    ColumnLayout {spacing:9;Layout.fillWidth:true
        Text {text:"主题配色";font.pixelSize:23;font.weight:Font.DemiBold;color:"#263238"}
        Text {text:"选一个喜欢的颜色，整理时处处呼应。";font.pixelSize:12;color:"#69777e"}
    }
    Rectangle {
        objectName:"themePreview";Layout.fillWidth:true;implicitHeight:154;radius:10;color:"#ffffff";border.color:"#dce2e4"
        RowLayout {anchors.fill:parent;anchors.margins:22;spacing:24
            ColumnLayout {Layout.fillWidth:true;spacing:12
                Text {text:"你的归图";font.pixelSize:18;font.weight:Font.DemiBold;color:"#263238"}
                Text {text:Theme.gradient?"大色块双色渐变，细节使用主色":"简洁统一的单色界面";font.pixelSize:12;color:"#69777e";Layout.fillWidth:true;wrapMode:Text.Wrap}
                RowLayout {spacing:14
                    Glyph {name:"folder";ink:Theme.primary;width:18;height:18}
                    Text {text:"已选 12 项";font.pixelSize:12;color:Theme.ink}
                    UiSwitch {checked:true;focusPolicy:Qt.NoFocus;checkable:false;Accessible.name:"主题开关效果预览"}
                }
            }
            ColumnLayout {spacing:10
                UiButton {objectName:"themePreviewAction";text:"移动所选";iconName:"move";primary:true;selectionAccent:true;implicitWidth:140;implicitHeight:40;hint:"主题效果预览，不执行文件操作"}
                UiButton {objectName:"themePreviewSelected";text:"当前目录";iconName:"folder";chosen:true;implicitWidth:140;implicitHeight:36;hint:"选中效果预览"}
            }
        }
    }
    RowLayout {spacing:8
        UiButton {objectName:"themeSingle";text:"单色";chosen:!Theme.gradient;onClicked:panel.apply(backend.theme.primary,backend.theme.secondary,"single")}
        UiButton {objectName:"themeGradient";text:"双色渐变";chosen:Theme.gradient;onClicked:panel.apply(backend.theme.primary,backend.theme.secondary,"gradient")}
        Item {Layout.fillWidth:true}
        UiButton {objectName:"themeReset";text:"恢复默认";quiet:true;onClicked:panel.apply("#a8dfcf","#afd5f0","single")}
    }
    GridLayout {
        Layout.fillWidth:true;columns:3;rowSpacing:10;columnSpacing:12
        Repeater {
            model:panel.presets
            UiButton {
                id:swatch;required property var modelData;required property int index
                objectName:"themePreset"+index
                Layout.fillWidth:true;implicitHeight:66
                chosen:backend.theme.primary===modelData.primary&&(!Theme.gradient||backend.theme.secondary===modelData.secondary)
                Accessible.name:modelData.name+(Theme.gradient?"渐变主题":"单色主题");hint:Accessible.name
                onClicked:panel.apply(modelData.primary,modelData.secondary||backend.theme.secondary,Theme.gradient?"gradient":"single")
                background:Rectangle {radius:8;color:swatch.down?Theme.softPressed:swatch.pointerHovered?"#f0f3f4":"#ffffff";border.width:swatch.chosen?2:1;border.color:swatch.chosen?Theme.primary:"#dce2e4"}
                contentItem:RowLayout {spacing:10
                    Rectangle {Layout.leftMargin:14;width:30;height:30;radius:8;color:swatch.modelData.primary
                        gradient:Theme.gradient?sampleGradient:null
                        Gradient {id:sampleGradient;orientation:Gradient.Horizontal;GradientStop{position:0;color:swatch.modelData.primary}GradientStop{position:1;color:swatch.modelData.secondary||swatch.modelData.primary}}
                    }
                    Text {Layout.fillWidth:true;text:swatch.modelData.name;font.pixelSize:13;color:"#35464e"}
                    Glyph {Layout.rightMargin:12;width:16;height:16;name:"check";ink:Theme.primary;visible:swatch.chosen}
                }
            }
        }
    }
    Rectangle {Layout.fillWidth:true;implicitHeight:1;color:"#dce2e4"}
    ColumnLayout {Layout.fillWidth:true;spacing:14
        Text {text:"自定义颜色";font.pixelSize:14;font.weight:Font.DemiBold;color:"#263238"}
        RowLayout {Layout.fillWidth:true;spacing:24
            ThemeColorField {objectName:"themePrimary";Layout.fillWidth:true;label:"主色";value:backend.theme.primary;onColorSelected:value=>panel.apply(value,backend.theme.secondary,backend.theme.mode)}
            ThemeColorField {objectName:"themeSecondary";Layout.fillWidth:true;visible:Theme.gradient;label:"副色";value:backend.theme.secondary;onColorSelected:value=>panel.apply(backend.theme.primary,value,backend.theme.mode)}
        }
        Text {Layout.fillWidth:true;wrapMode:Text.Wrap;lineHeight:1.4;font.pixelSize:12;color:"#69777e";text:"点击色块选色，也可输入颜色值。亮色背景搭配深色文字，图标与细边框使用同色系深色。渐变用于顶部栏、较大的主按钮和选中背景；自定义配色会适配文字对比度。"}
    }
}
