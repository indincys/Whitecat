# Release Guide

## 推荐流程

Whitecat 现在采用和 Learningcat 一样的“本地发布机脚本”模型。以后正式发版直接在本机执行：

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
PRIVATE_ED_KEY_PATH="$HOME/.config/whitecat/sparkle_private_key" \
TEAM_BUNDLE_PREFIX="TEAMID" \
./Scripts/release.sh 0.1.8
```

要求：

- 当前分支必须是 `main`
- 工作区必须干净
- 本地 `main` 不能落后于 `origin/main`
- 本机已经具备 Sparkle 私钥、GitHub 发布凭据，以及用于正式签名的 Developer ID 身份

## 脚本会做什么

`Scripts/release.sh` 会在本地依次完成：

1. 解析 release notes，默认优先读取 `release-notes.txt`，没有则回退到上一版 tag 之后的 git commit subject。
2. 用 `Scripts/package_app.sh` 构建 `.app`、`.zip`、`.dmg`。
3. 只把“本次新 ZIP + 已发布 appcast”送进 `Scripts/generate_appcast.sh`，避免把 `dist/releases` 里历史调试包重新写回更新源。
4. 更新 `docs/appcast.xml` 和 `docs/old_updates`。
5. 提交 appcast 变更，并创建或复用 `v<version>` tag。
6. 先推 tag，再创建或更新 GitHub Release，并上传 ZIP / DMG / appcast。
7. 最后推送 `main`，让 GitHub Pages 发布新的 appcast。

这样官方 release 会天然具备应用内更新能力：

- 正式签名构建：Sparkle 直接检查、下载、安装更新。
- 非正式签名构建：回退到内置安装器，但仍会校验 Sparkle EdDSA 签名。

## 一次性准备

1. 生成 Sparkle 公私钥：

```bash
Vendor/SparkleTools/generate_keys
```

2. Whitecat 当前仓库已经把 `SUFeedURL` 和 `SUPublicEDKey` 固定在 `Configs/Info.plist.template` 里；如果以后你要换仓库或轮换 Sparkle 密钥，再更新这里。
3. 把 Sparkle 私钥保存在本机，例如：`$HOME/.config/whitecat/sparkle_private_key`。
4. 确认本机能用 `git credential fill` 或 `GITHUB_TOKEN` 调 GitHub API。
5. 如果发正式签名版本，准备 `Developer ID Application` 证书和团队前缀，并渲染 entitlements：

```bash
TEAM_BUNDLE_PREFIX=YOURTEAM ./Scripts/render_entitlements.sh build/Whitecat.entitlements
```

## 常用环境变量

- `BUILD_NUMBER`: 默认是当前 `HEAD` 的 git commit 数。
- `CODESIGN_IDENTITY`: 默认 `-`，表示 ad-hoc 签名，只适合本地试包。
- `PRIVATE_ED_KEY` 或 `PRIVATE_ED_KEY_PATH`: 二选一，Sparkle 更新签名必填。
- `TEAM_BUNDLE_PREFIX`: 正式签名时必填，用来生成 iCloud entitlements。
- `ENTITLEMENTS_PATH`: 如果你已经手工生成过 entitlements，可以直接传这个路径。
- `RELEASE_NOTES_FILE`: 自定义 release notes 文件。
- `DRY_RUN=1`: 只在本地打包并生成 appcast，不推送 tag、不创建 GitHub Release。

## 更新链路

- GitHub Pages 托管 `docs/appcast.xml`，这是 app 内检查更新读取的更新源。
- GitHub Releases 托管 `Whitecat-<version>.zip` 和 `Whitecat-<version>.dmg`。
- app 内更新优先走 ZIP 资产，DMG 留给浏览器手工下载安装。
- 脚本先上传 Release 资产，再推送 `main`，避免客户端先读到新 appcast 但远端资产还没准备好。

## 发布产物

- `dist/releases/Whitecat-<version>.zip`
- `dist/releases/Whitecat-<version>.dmg`
- `dist/releases/appcast.xml`
- `build/release-body.md`
- `build/release-metadata.txt`
