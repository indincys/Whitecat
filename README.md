# Whitecat

Whitecat 是一个面向 Apple Silicon 的原生 macOS 笔记应用原型，目标体验是 Things 3 风格的三栏布局，以及“先写正文，再由 AI 自动补标题、分类、标签、文件夹”。

## 当前实现

- `Swift 6 + SwiftUI + AppKit bridge`
- 三栏主界面：侧栏 / 笔记列表 / 正文编辑
- 新建笔记直接进入正文输入
- 自动本地保存，切换离开笔记时触发 AI 整理
- 多平台模型配置：OpenAI、DeepSeek、Qwen、Kimi、Z.ai、Doubao、Custom
- API Key 存 Keychain
- Sparkle 2 二进制已 vendoring 到仓库，设置页可发起原生检查更新
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

## 打包发布

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
PRIVATE_ED_KEY=YOUR_PRIVATE_KEY \
./Scripts/generate_appcast.sh dist/releases
```

更多细节见 `docs/release.md`。

## 仓库结构

- `Sources/WhitecatApp`: SwiftUI 应用和三栏界面
- `Sources/NotesCore`: 笔记、文件夹、标签、配置、持久化
- `Sources/AIOrchestrator`: OpenAI-compatible 适配器、整理器、Keychain
- `Sources/AppUpdates`: Sparkle 桥接和 appcast 回退解析
- `Vendor/Sparkle.xcframework`: 官方 Sparkle 2.7.3 二进制
- `Vendor/SparkleTools`: `generate_appcast`、`generate_keys` 等工具
