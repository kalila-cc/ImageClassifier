# 归图架构

本文描述当前代码实现，是开发者了解模块、数据流和存储边界的入口。产品规则见 [docs](docs/README.md)，任务状态见[开发进度](docs/08-development.md)，环境安装见[运行说明](docs/10-running.md)。

## 1. 技术组成与目录

归图是 Windows 本地桌面应用：C++20 承担文件与媒体业务，Qt 6.10 / Qt Quick / QML 绘制界面，Qt Multimedia 处理视频，SQLite 保存应用数据。可选智能裁剪使用独立 Python 进程及 ONNX Runtime CPU 推理；普通浏览和手动裁剪无需启动 Python。

```text
ImageClassifier/
├── src/                    C++ 应用入口与业务模块
├── ui/                     正式工作区、编辑器和共享控件
│   ├── Application.qml     正式界面入口
│   ├── ImageEditor.qml     图片编辑与视频浏览
│   ├── icons/              SVG 图标
│   └── preview/            独立静态演示页面及本地素材
├── tools/ai/               智能裁剪推理、学习与模型准备
├── docs/                   按功能划分的设计、使用与验收文档
├── CMakeLists.txt          原生程序与核心库构建
├── Build.ps1               构建入口
├── Start.cmd               正式版启动入口
├── Setup-Media.ps1         可选媒体组件安装
├── Setup-AI.ps1            可选智能裁剪环境安装
├── Preview.cmd             静态演示启动入口
└── preview.py              演示版 QML 加载器
```

`.tools/`、`.venv/`、`build/` 和 `tests/` 分别存放本地依赖、构建环境、产物和本地测试，不进入版本控制；演示图片同样不提交。用户图库及数据库不放进源码仓库。

## 2. 模块与依赖

| 模块 | 代码入口 | 职责 |
| --- | --- | --- |
| 启动与进程 | [main.cpp](src/main.cpp)、[AppRestart](src/AppRestart.h) | 数据目录、单实例锁、QML 引擎和图片提供器；重启前保存状态，通过进程握手交接数据锁 |
| 工作区界面 | [Application.qml](ui/Application.qml) | 批量网格、选择、筛选、模式切换和弹窗协调；资产 ID 关联卡片与大图 |
| 功能界面 | [ImageEditor.qml](ui/ImageEditor.qml)、[DirectoryTree.qml](ui/DirectoryTree.qml)、[SettingsPage.qml](ui/SettingsPage.qml)、[SourcesDialog.qml](ui/SourcesDialog.qml) | 编辑、目录交互、设置和来源管理；基础控件使用 `Ui*.qml`，图标使用 `Glyph.qml` 和 SVG |
| 应用服务 | [Backend](src/Backend.h) | 通过 `Q_PROPERTY` 暴露状态、`Q_INVOKABLE` 接收命令；协调扫描、批次、文件操作、草稿和历史 |
| 媒体与时间 | [Media](src/Media.h)、[MediaTime.cpp](src/MediaTime.cpp) | 扫描、解码、拍摄时间排序、批次边界相似判断和输出时间继承 |
| 预览与封面 | [ImageProvider](src/ImageProvider.h)、[ThumbnailCache](src/ThumbnailCache.h) | 通过 `image://media/` 异步供应图片和视频封面；图片中心缩略图使用内存及磁盘缓存，视频代表帧使用有容量上限的内存缓存 |
| Live 与 HEIC | [LivePhoto](src/LivePhoto.h)、[AppleLivePhoto.cpp](src/AppleLivePhoto.cpp)、[HeifImage](src/HeifImage.h) | 单文件实况识别、iPhone 成员配对、HEIC 解码、播放副本准备；界面复用 `LivePhotoPreview.qml` |
| 裁剪几何 | [CropGeometry](src/CropGeometry.h)、[RotatingPreview.qml](ui/RotatingPreview.qml) | 旋转坐标、比例及图像边界约束；预览和导出使用一致几何规则 |
| 图片视口 | [PhotoViewport.qml](ui/PhotoViewport.qml) | 适合窗口／铺满切换、鼠标定位缩放和拖动平移；视口坐标与裁剪参数分离 |
| 文件操作 | [FileOps](src/FileOps.h) | 移动、复制、子图写入、目录重命名、冲突处理、内容校验、撤销和恢复 |
| 存储 | [Store](src/Store.h) | SQLite 连接、建表、参数化查询及键值设置 |
| 智能裁剪 | [SmartCrop](src/SmartCrop.h)、[worker.py](tools/ai/worker.py) | 模型进程管理、过期建议丢弃、近期样本管理、个人裁剪偏好更新 |
| 可选模型安装 | [ModelInstaller](src/ModelInstaller.h)、[Setup-AI.ps1](Setup-AI.ps1)、[setup_models.py](tools/ai/setup_models.py) | 用户主动安装、独立后台任务、阶段状态与日志、单任务锁、模型校验和失败重试；启动与构建不下载模型 |

界面通过 `Backend` 发出业务命令；`Backend` 调用媒体、文件和存储模块。`ImageProvider` 独立读取资产路径并解码。QML 不执行真实文件修改，Python 模型进程也不负责移动或导出用户文件。

CMake 将业务模块编译为 `classifier_core` 静态库；`ImageClassifier` 可执行程序再链接 QML、Quick Controls 和 Multimedia。正式程序从源码目录加载 `ui/Application.qml`，当前仍需要项目 QML 和本地 Qt 运行环境。静态演示只加载 `ui/preview/Main.qml`，向上复用共享控件，不连接 `Backend`。

## 3. 主要数据流

**可选模型安装：** 设置页主动安装 → `ModelInstaller` 启动隐藏的独立 PowerShell 进程 → 安装脚本持有模型目录锁、准备运行环境和模型 → 校验全部模型并原子写入清单 → 设置页自动显示已安装、智能控件恢复可用。`install-state.json` 原子保存阶段、结果及进程身份，重开应用可继续观察；后台任务不依赖窗口存活。失败或中断需用户重试，未安装时保留手动功能。

**扫描与分批：** 来源目录 → `Media::scan` 建立资产清单、识别 Live 成员 → 按拍摄时间降序排序 → `Backend` 保存当前批和剩余队列 → 网格按需请求缩略图。缺失拍摄时间时使用修改时间。扫描建立完整元数据清单，分批控制展示和图片解码，并非数据库分页扫描。批次默认 100 项；边界使用差异哈希和颜色距离比较相邻图片，相似则向后延伸，上限为目标数量的两倍，不确定时交给用户扩展。

**移动与复制：** 选择资产及目标 → 核对当前文件版本 → `FileOps` 持久化操作计划 → 执行并校验 → 更新列表、目录数量和历史。跨卷移动先写临时文件、校验并提交目标，再核对来源并移除；重名使用新文件名，不覆盖已有文件。iPhone Live 的照片和视频作为一组记录及处理。

**裁剪与学习：** 加载方向纠正后的图片及草稿 → 手动调整或接收智能建议 → `CropGeometry` 约束旋转后的有效区域 → 校验全部子图参数 → 输出 PNG 并继承拍摄时间 → 校验输出和原图 → 保存学习记录。仅裁剪将子图放在原目录并加入当前列表；裁剪并归类使用各子图目标。两种操作均保留原图。固定输出编号用于重复操作校验，部分输出失败时保留记录供核对。

**播放：** 普通视频先显示代表帧，点击播放后启用播放器；Live 默认显示静态封面，主动播放时准备视频源并循环。两者默认静音，离开当前媒体时停止播放。Live 服务用请求代次隔离过期结果，避免切图后播放错误媒体。

## 4. 持久化与文件安全

默认数据目录为 `%LOCALAPPDATA%\ImageClassifier\ImageClassifier`，主数据库是 `library.sqlite`；`IMAGECLASSIFIER_DATA_DIR` 可覆盖该位置，用于隔离测试。同一数据目录由 `app.lock` 限制为单实例。

| SQLite 表 | 内容 |
| --- | --- |
| `settings` | 全局偏好、来源、目标、批次数量，以及 JSON 格式的浏览会话快照 |
| `assets` | 资产 ID、路径、来源根、大小、修改时间、类型及阻止操作原因 |
| `drafts` | 关联资产和文件版本的 JSON 裁剪草稿 |
| `operations` | 文件操作意图、阶段、校验值、错误及父操作关联 |
| `live_members` | Live 组级操作的成员计划和校验信息 |
| `live_metadata` | 可重建的 Live 关联标识缓存 |
| `cleared_history` | 已从操作记录界面清空的操作编号 |

SQLite 使用 WAL、`synchronous=FULL` 和忙等待。每个 `Store` 实例创建独立命名连接并在所属线程内使用；文件系统修改不能依靠数据库事务回滚，需要操作日志、文件身份和 SHA-256 校验共同确认结果。

“清空记录”隐藏已结束历史，保留底层操作日志以支持导出幂等与故障恢复；未完成操作及其依赖记录保留可见。清空后无法从界面撤销被隐藏的移动，不删除图片、草稿或智能学习记录。恢复浏览会话不会自动重放文件修改。完整规则见[文件安全](docs/06-file-safety.md)。

智能学习数据位于同一数据目录下的 `smart-crop/`，最多保留最近 100 次成功裁剪操作，每次包含缩小原图及全部子图参数。YOLOX、RTMPose 和 DINOv2 权重固定，个性化发生在案例检索和轻量回归中；模型与 Python 环境安装到 `.tools/smart-crop/`。详细算法、容量及失败行为见[智能裁剪](docs/12-smart-crop.md)。

## 5. 线程与性能边界

- UI 线程负责交互及状态更新；`Backend::run` 使用 `QtConcurrent` 执行扫描、分批检查和文件任务，通过 `QFutureWatcher` 回传结果，同一时刻只接收一个此类业务任务。小型设置和草稿读写仍有同步路径。
- 图片提供器启用异步加载；视频取帧在独立解码线程中运行并设超时，成功帧按路径、大小和修改时间缓存，预算为 32 MiB。
- 网格及底部缩略栏通过 `image://media/.../cover` 请求按显示比例裁切的图片，`Media::thumbnail` 优先使用解码器的原图区域读取，并正确处理 EXIF 方向。无区域读取能力时使用满足铺满需求的整图中间结果，缩放结果限制为 1600 万像素及 32768 像素长边；解码器内部仍可能完整读取原图。最终只返回最长边不超过 1024 像素的中心缩略图，不把长图纹理传入卡片。
- 旋转预览复用图片纹理，通过场景变换实时更新；完整像素旋转与裁剪在导出时执行。图片缩放停止 180 毫秒后按档位提升预览清晰度，保留旧画面等待新纹理；`ImageProvider` 的 `detail` 请求限制为最长边 8192 像素及 1600 万像素，普通缩略图保留 2560 像素上限。
- 智能裁剪用 `QProcess` 和按行 JSON 协议连接 Python，CPU 推理与界面隔离；旧请求不能覆盖用户后续手动调整。模型缺失不影响手动编辑。

图片中心缩略图使用 128 MiB 内存 LRU 缓存和 512 MiB 本地 PNG 缓存，目录为应用数据目录下的 `cache/thumbnails-v1/`。缓存以文件路径、大小、修改时间、输出尺寸和算法版本区分；仅缓存成功结果，磁盘原子写入，损坏或写入失败回退到源文件解码。网格保留可见区域前后约一屏的委托，实现相邻图片预加载；大图预览不进入此缓存。

当前尚无统一优先级调度及数据库分页资产模型。批量清单仍保存在内存中，千张以上素材性能和更广泛媒体编码兼容性需要实测；现有验证范围见[验证结果](docs/11-validation.md)。

## 6. 维护边界

- 正式界面放在 `ui/`，演示专用页面及素材放在 `ui/preview/`；共享控件不依赖演示数据。演示素材仅本地保存。
- C++ 按模块文件维护，当前规模保持一层目录便于定位。扩展时优先从 `Backend` 提取独立的浏览会话或操作历史服务，并从 `Application.qml` 提取工作区组件；有独立职责和测试后再调整目录，避免只搬文件而保留耦合。
- 真实文件修改集中在后端服务，保持日志及校验顺序；新增媒体格式应接入扫描、封面、播放和成组操作的共同流程。
- 本文维护实际架构；`docs/` 各功能文档维护详细规则，开发清单维护任务状态。表结构、启动入口或模块位置变更时同步更新链接。
- 普通构建使用 `Build.ps1`；本地具备测试目录时使用 `Build.ps1 -Test`。文件操作和界面测试使用临时文件、独立数据目录及离屏窗口，测试代码和素材不上传仓库。
