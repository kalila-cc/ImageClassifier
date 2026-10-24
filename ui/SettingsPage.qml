import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: page
    color: "#fafbfc"
    property int section: 0
    signal backRequested()
    onSectionChanged: settingsScroll.contentItem.contentY=0

    component SettingLabel: ColumnLayout {
        property string title
        property string description
        Layout.fillWidth: true; spacing: 6
        Text {text: parent.title; font.pixelSize: 14; color: "#263238"; Layout.fillWidth: true; wrapMode: Text.Wrap}
        Text {text: parent.description; visible: text.length>0; font.pixelSize: 12; color: "#69777e"; Layout.fillWidth: true; wrapMode: Text.Wrap; lineHeight: 1.35}
    }
    component Divider: Rectangle {Layout.fillWidth: true; implicitHeight: 1; color: "#dce2e4"}
    component SectionHeading: ColumnLayout {
        property string title
        property string description
        Layout.fillWidth: true; spacing: 10; Layout.bottomMargin: 10
        Text {text: parent.title; font.pixelSize: 23; font.weight: Font.DemiBold; color: "#263238"}
        Text {text: parent.description; font.pixelSize: 12; color: "#69777e"; Layout.fillWidth: true; wrapMode: Text.Wrap}
    }

    ColumnLayout {
        anchors.fill: parent; spacing: 0
        ThemeHeader {
            objectName:"settingsHeader"
            Layout.fillWidth: true; Layout.preferredHeight: 60
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 24; anchors.rightMargin: 32; spacing: 20
                UiButton {objectName:"settingsBack";text:"返回整理";iconName:"back";onAccent:true;quiet:true;implicitWidth:116;onClicked:page.backRequested()}
                Rectangle {width: 1; height: 22; color: Theme.alpha(Theme.surfaceInk,.25)}
                Text {text: "设置"; font.pixelSize: 18; font.weight: Font.DemiBold; color: Theme.surfaceInk}
                Item {Layout.fillWidth: true}
                Text {text: "更改自动保存"; font.pixelSize: 12; color: Theme.surfaceInk}
            }
        }
        Rectangle {Layout.fillWidth: true; height: 1; color: "#dce2e4"}
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            Rectangle {
                Layout.preferredWidth: 220; Layout.fillHeight: true; color: "#edf0f2"
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 20; spacing: 8
                    Text {text: "偏好设置"; font.pixelSize: 11; color: "#71828a"; Layout.topMargin: 12; Layout.bottomMargin: 12; Layout.leftMargin: 12}
                    Repeater {
                        model: ["浏览与批次", "裁剪与智能", "本地数据", "主题配色"]
                        UiButton {
                            id: navButton
                            required property string modelData
                            required property int index
                            objectName: "settingsSection"+index
                            Layout.fillWidth: true; implicitHeight: 44
                            text: modelData; chosen: page.section===index; quiet: true
                            onClicked: page.section=index
                            contentItem: Text {text: navButton.text; leftPadding: 14; verticalAlignment: Text.AlignVCenter; font.pixelSize: 13; font.weight: navButton.chosen?Font.DemiBold:Font.Normal; color: navButton.chosen?Theme.primary:"#5e7079"}
                        }
                    }
                    Item {Layout.fillHeight: true}
                    Text {text: "归图\n你的整理习惯，保留在本机。"; font.pixelSize: 11; color: "#71828a"; lineHeight: 1.8; Layout.leftMargin: 12; Layout.bottomMargin: 8}
                }
            }
            ScrollView {
                id: settingsScroll; objectName: "settingsScroll"
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: Math.min(820,settingsScroll.availableWidth-80); x: 40; y: 36
                    spacing: 24
                    // Bottom padding belongs to the content so all controls remain reachable in short windows.
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 24; visible: page.section===0
                        SectionHeading {title: "浏览与批次"; description: "调整图片的浏览方式和每批处理数量。"}
                        RowLayout {
                            Layout.fillWidth: true; spacing: 28
                            SettingLabel {title: "浏览模式"; description: "与工作区同步，重启后恢复上次选择。"}
                            RowLayout {spacing: 8; enabled: !backend.busy
                                UiButton {objectName: "settingsBatchMode"; text: "批量模式"; chosen: !backend.largeMode; onClicked: backend.largeMode=false}
                                UiButton {objectName: "settingsLargeMode"; text: "大图模式"; chosen: backend.largeMode; onClicked: backend.largeMode=true}
                            }
                        }
                        Divider {}
                        RowLayout {
                            Layout.fillWidth: true; spacing: 28
                            SettingLabel {title: "批量缩略图大小"; description: "放大查看细节，缩小查看更多；窗口变大时图片同步放大。"}
                            ColumnLayout {spacing: 6; Layout.preferredWidth: 220; Layout.maximumWidth: 220; Layout.minimumWidth: 220
                                UiSlider {objectName: "settingsThumbnailSize"; Layout.fillWidth: true; from: 170; to: 730; stepSize: 35; value: backend.thumbnailSize; onMoved: backend.thumbnailSize=value; Accessible.name: "批量缩略图大小"}
                                RowLayout {Layout.fillWidth: true
                                    Text {text: "小图"; font.pixelSize: 11; color: "#71828a"}
                                    Item {Layout.fillWidth: true}
                                    Text {text: "大图"; font.pixelSize: 11; color: "#71828a"}
                                }
                            }
                        }
                        Divider {}
                        RowLayout {
                            Layout.fillWidth: true; spacing: 28
                            SettingLabel {title: "每批目标数量"; description: "10–500 项，从下一批起生效。边界图片相近时，实际数量可能增加。"}
                            UiSpinBox {objectName: "settingsBatchSize"; from: 10; to: 500; stepSize: 10; editable: true; value: backend.batchSize; enabled: !backend.busy; onValueModified: backend.setBatchSize(value); Accessible.name: "每批目标数量"}
                        }
                        Divider {}
                        RowLayout {
                            Layout.fillWidth: true; spacing: 28
                            SettingLabel {title: "默认勾选“包含子目录”"; description: "设置添加来源时的默认勾选。本次扫描会对全部来源应用该选项；双击左侧目录仅浏览其直属文件。"}
                            UiSwitch {objectName: "settingsRecursive"; checked: backend.defaultRecursive; onClicked: backend.defaultRecursive=checked; Accessible.name: "默认勾选“包含子目录”"}
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 24; visible: page.section===1
                        SectionHeading {title: "裁剪与智能"; description: "让大图工作区适合你的逐张处理习惯。"}
                        RowLayout {
                            Layout.fillWidth: true; spacing: 28
                            SettingLabel {title: "显示底部缩略栏"; description: "在大图模式下快速切图。关闭后，仍可使用左右方向键切换。"}
                            UiSwitch {objectName: "settingsFilmstrip"; checked: backend.showFilmstrip; onClicked: backend.showFilmstrip=checked; Accessible.name: "显示底部缩略栏"}
                        }
                        Divider {}
                        RowLayout {
                            Layout.fillWidth: true; spacing: 28
                            SettingLabel {title: "智能裁剪"; description: "开启裁剪模式时自动建议人物裁剪区域，保留已有手动调整。与编辑区“智能模式”同步。"}
                            UiSwitch {objectName: "settingsSmartCrop"; enabled: backend.smartCrop.available; checked: backend.smartCrop.enabled; onClicked: backend.smartCrop.enabled=checked; Accessible.name: "智能裁剪"}
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 12
                            Rectangle {width: 7; height: 7; radius: 4; color: backend.smartCrop.available?"#4e8666":backend.smartCrop.installer.state==="failed"?"#b15c48":"#93a0a6"}
                            Text {
                                objectName:"modelInstallState";Layout.fillWidth:true
                                text:({notInstalled:"模型 · 未安装",installing:"模型 · 安装中",installed:"模型 · 已安装",failed:"模型 · 安装失败"})[backend.smartCrop.installer.state]||"模型 · 未安装"
                                font.pixelSize:13;font.weight:Font.Medium;color:"#35464e"
                            }
                            UiButton {
                                objectName:"installModelsButton"
                                visible:!backend.smartCrop.available
                                text:backend.smartCrop.installer.installing?"安装中":backend.smartCrop.installer.state==="failed"?"重试安装":"安装模型"
                                enabled:!backend.smartCrop.installer.installing;primary:true
                                onClicked:backend.smartCrop.installer.install()
                            }
                            UiButton {objectName:"checkModelsButton";text:"重新检测";quiet:true;enabled:!backend.smartCrop.installer.installing;onClicked:backend.smartCrop.refreshAvailability()}
                        }
                        Text {Layout.fillWidth:true;wrapMode:Text.Wrap;text:"可选下载，安装后约占 520 MB；首次安装临时需要约 1.5 GB 空间。使用本地 CPU，无需独立显卡。";font.pixelSize:12;color:"#69777e"}
                        ProgressBar {objectName:"modelInstallProgress";Layout.fillWidth:true;visible:backend.smartCrop.installer.installing;indeterminate:visible}
                        Text {objectName:"modelInstallDetail";Layout.fillWidth:true;wrapMode:Text.Wrap;text:backend.smartCrop.installer.detail;visible:text.length>0;font.pixelSize:12;color:backend.smartCrop.installer.state==="failed"?"#a34e3c":"#69777e"}
                        Text {Layout.fillWidth:true;wrapMode:Text.Wrap;visible:backend.smartCrop.installer.installing;text:"正在后台安装，可返回继续整理。关闭或重启归图不会中断安装。";font.pixelSize:12;color:"#69777e"}
                        UiButton {objectName:"modelInstallLog";text:"打开日志目录";iconName:"folderOpen";quiet:true;visible:backend.smartCrop.installer.installing||backend.smartCrop.installer.state==="failed";onClicked:backend.reveal(backend.smartCrop.installer.logPath)}
                        Text {Layout.fillWidth: true; wrapMode: Text.Wrap; text: backend.smartCrop.status; visible: backend.smartCrop.available&&text.length>0&&text!=="本地模型已就绪"; font.pixelSize: 12; color: "#69777e"}
                        Divider {}
                        RowLayout {
                            Layout.fillWidth: true; spacing: 28
                            SettingLabel {title: "近期学习记录 · "+backend.smartCrop.recordCount+" / 100"; description: "成功完成裁剪后自动记录，最多保留最近 100 次操作，用于本机偏好学习。关闭智能裁剪后，成功记录仍会保留。"}
                            UiButton {text: "打开记录目录"; iconName: "folderOpen"; enabled: backend.smartCrop.recordCount>0; onClicked: backend.reveal(backend.smartCrop.recordsPath)}
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 24; visible: page.section===2
                        SectionHeading {title: "本地数据"; description: "设置、整理进度和裁剪学习记录都保存在这台电脑上。"}
                        SettingLabel {title: "应用数据目录"; description: "保存偏好设置、当前批次、编辑草稿、操作记录和智能裁剪学习数据。"}
                        TextEdit {objectName: "settingsDataPath"; Layout.fillWidth: true; text: backend.dataDirectory; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; font.pixelSize: 13; color: "#3a505b"}
                        UiButton {text: "打开数据目录"; iconName: "folderOpen"; onClicked: backend.reveal(backend.dataDirectory)}
                        Divider {}
                        SettingLabel {title: "原图与子图"; description: "移动原文件会校验内容一致；复制会保留来源。裁剪结果统一保存在原目录。仅裁剪保留原图；单子图可覆盖原图，多子图可全部保存并校验后回收原图。Live 图裁剪为普通静态图，配套视频一并回收。"}
                        Divider {}
                        SettingLabel {title: "配置保存"; description: "更改会自动保存，无需点击保存按钮。设置页与工作区共用同一份配置，返回整理会保留当前图片、选择和裁剪草稿。"}
                    }
                    ThemeSettings {Layout.fillWidth:true;visible:page.section===3}
                    Item {Layout.preferredHeight: 40}
                }
            }
        }
    }
}
