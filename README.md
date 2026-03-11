# Whitecat

Whitecat 是一个面向 Apple Silicon 的原生 macOS 笔记应用原型，目标体验是 Things 3 风格的三栏布局，以及“先写正文，再由 AI 自动补标题、分类、标签、文件夹”。

## 当前实现

- `Swift 6 + SwiftUI + AppKit bridge`
- 三栏主界面：侧栏 / 笔记列表 / 正文编辑
- 新建笔记直接进入正文输入
- 自动本地保存，切换离开笔记时触发 AI 整理
- 多平台模型配置：OpenAI、DeepSeek、Qwen、Kimi、Z.ai、Doubao、Custom
- 每个模型配置都支持自定义整理提示词
- API Key 存 Keychain
- 全局快捷键 `⌥⌘N` 打开快速收集窗口，只输入正文
- Sparkle 2 二进制已 vendoring 到仓库，GitHub Pages 提供 appcast，GitHub Releases 提供 zip 安装包
- 官方 release 由 GitHub Actions 自动生成；正式签名构建可直接在 app 内检查、下载并安装更新，不依赖浏览器重新下载安装
- iCloud 优先存储，拿不到 ubiquity container 时回退到 `Application Support`
- 基础测试覆盖数据模型、AI 适配器和 appcast 解析

## 本地运行

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  CLANG_MODULE_CACHE_PATH=/tmp/whitecat-clang-module-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/tmp/whitecat-swiftpm-module-cache \
  swift run --disable-sandbox --scratch-path /tmp/whitecat-build WhitecatApp
```

## 本地测试

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  CLANG_MODULE_CACHE_PATH=/tmp/whitecat-clang-module-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/tmp/whitecat-swiftpm-module-cache \
  swift test --disable-sandbox --scratch-path /tmp/whitecat-build
```

## 自动发版

推荐入口有两个，二选一：

1. 本地执行一键发版脚本：

```bash
./Scripts/release.sh 0.1.6
```

2. 在 GitHub Actions 里手动运行 `Cut Release`，填入 `0.1.6` 和目标 ref。

这两个入口都会创建并推送 `v0.1.6` tag。tag 推上去后，`Release` workflow 会自动：

- 导入 Developer ID 证书
- 运行测试
- 构建签名 app
- notarize 并 staple 发布包
- 生成 Sparkle `appcast.xml`
- 创建或更新 GitHub Release
- 把最新 `appcast.xml` 发布到 GitHub Pages

只要仓库 secrets 配齐，之后用户安装官方 release，就可以直接在 app 内检查、下载并安装后续更新。

## 手工打包

如果需要在本地排查发布问题，仍然可以手工执行：

1. 生成 Sparkle EdDSA 密钥：

```bash
Vendor/SparkleTools/generate_keys
```

2. 生成签名 app bundle、zip、dmg：

```bash
VERSION=0.1.0 \
BUILD_NUMBER=1 \
APPCAST_URL=https://YOUR_NAME.github.io/Whitecat/appcast.xml \
SPARKLE_PUBLIC_ED_KEY=YOUR_PUBLIC_KEY \
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./Scripts/package_app.sh
```

3. 生成 appcast：

```bash
DOWNLOAD_URL_PREFIX=https://github.com/YOUR_NAME/Whitecat/releases/download/v0.1.0 \
FULL_RELEASE_NOTES_URL=https://github.com/YOUR_NAME/Whitecat/releases/tag/v0.1.0 \
PRIVATE_ED_KEY=YOUR_PRIVATE_KEY \
./Scripts/generate_appcast.sh dist/releases
```

自动发布流程已经按这个顺序处理：先上传 GitHub Release 资产，再对外发布 GitHub Pages 上的 `appcast.xml`。更多细节见 `docs/release.md`。

## 仓库结构

- `Sources/WhitecatApp`: SwiftUI 应用和三栏界面
- `Sources/NotesCore`: 笔记、文件夹、标签、配置、持久化
- `Sources/AIOrchestrator`: OpenAI-compatible 适配器、整理器、Keychain
- `Sources/AppUpdates`: Sparkle 桥接和 appcast 回退解析
- `Vendor/Sparkle.xcframework`: 官方 Sparkle 2.7.3 二进制
- `Vendor/SparkleTools`: `generate_appcast`、`generate_keys` 等工具
