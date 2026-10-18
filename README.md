# 归图 · ImageClassifier

Windows 本地图片与视频归类工具，采用 C++ / Qt 6 / QML / SQLite。

安装依赖并构建后，双击 **`Start.cmd`** 打开原生功能版。选择来源目录和目标目录后，可以批量移动图片，或进入大图模式直接裁剪、旋转并导出子图。该入口会执行真实文件操作；`Preview.cmd` 是使用示例数据的独立 UI 演示。

首次使用：

```powershell
git clone https://github.com/kalila-cc/ImageClassifier.git
cd ImageClassifier
```

按[构建环境说明](docs/10-running.md#构建环境)安装 Qt、MinGW 和构建工具，再执行 `./Build.ps1`。测试仅在本地维护和运行；示例图片也不纳入版本控制。仓库不包含本地 SDK、虚拟环境、编译产物、运行日志或个人图库数据库。正式版不依赖示例图片，独立 UI 演示的素材准备见[预览说明](docs/09-ui-preview.md)。

- [使用及构建](docs/10-running.md)
- [开发进度](docs/08-development.md)
- [验证结果](docs/11-validation.md)
- [需求与设计导航](docs/README.md)

当前版本为 0.1.0 功能开发版。完整安装包、Live Photos、HEIC 和大量素材性能验收仍在开发范围内。
