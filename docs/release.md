# Release Guide

## 推荐流程

以后所有正式发版都走自动流程，不再手工创建 GitHub Release。

### 入口 1：本地一键发版

```bash
./Scripts/release.sh 0.1.6
```

要求：

- 当前分支必须是 `main`
- 工作区必须干净
- 本地 `main` 必须和 `origin/main` 完全同步

脚本只做一件事：创建并推送 `v0.1.6` tag。后续打包、签名、notarize、GitHub Release、GitHub Pages appcast 发布都由 GitHub Actions 自动完成。

### 入口 2：GitHub Actions

在仓库的 Actions 页面手动运行 `Cut Release` workflow，填写：

- `version`: 例如 `0.1.6`
- `ref`: 默认 `main`

它会创建并推送同样的 release tag，然后自动触发正式发布 workflow。

## 必备项

- `Developer ID Application` 证书
- Apple notarization 凭据
- Sparkle 公私钥
- GitHub Releases 发布权限
- GitHub Pages 已启用

## 自动发布产物

`Release` workflow 在 tag 推送后会自动完成：

1. 导入签名证书并渲染 entitlements。
2. 运行测试。
3. 构建签名 app。
4. 对 ZIP 做 notarization。
5. 对 `.app` 做 stapling，并重建 ZIP / DMG。
6. 对 DMG 做 notarization 和 stapling。
7. 生成带 Sparkle 签名的 `appcast.xml`。
8. 创建或更新 GitHub Release，并上传 ZIP / DMG / appcast 资产。
9. 把 `appcast.xml` 发布到 GitHub Pages。

这样官方 release 会天然具备应用内更新能力：

- 正式签名构建：Sparkle 直接检查、下载、安装更新。
- 非正式签名构建：回退到内置安装器，但仍会校验 Sparkle EdDSA 签名。

## 一次性准备

1. 用 `Vendor/SparkleTools/generate_keys` 生成 `SUPublicEDKey` 和私钥。
2. 把公钥放进 `SPARKLE_PUBLIC_ED_KEY`。
3. 把私钥放进 GitHub Secret `SPARKLE_PRIVATE_ED_KEY`。
4. 按团队标识生成 entitlements：

```bash
TEAM_BUNDLE_PREFIX=YOURTEAM ./Scripts/render_entitlements.sh
```

## 本地发布

只在排查自动流程或本地试包时使用，日常正式发版不需要手工执行下面这些命令。

```bash
TEAM_BUNDLE_PREFIX=YOURTEAM ./Scripts/render_entitlements.sh

VERSION=0.1.0 \
BUILD_NUMBER=1 \
APPCAST_URL=https://YOUR_NAME.github.io/Whitecat/appcast.xml \
SPARKLE_PUBLIC_ED_KEY=YOUR_PUBLIC_KEY \
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
ENTITLEMENTS_PATH=Configs/Whitecat.entitlements \
./Scripts/package_app.sh

DOWNLOAD_URL_PREFIX=https://github.com/YOUR_NAME/Whitecat/releases/download/v0.1.0 \
FULL_RELEASE_NOTES_URL=https://github.com/YOUR_NAME/Whitecat/releases/tag/v0.1.0 \
PRIVATE_ED_KEY=YOUR_PRIVATE_KEY \
./Scripts/generate_appcast.sh dist/releases
```

## 更新链路

- GitHub Pages 托管 `appcast.xml`，这是 app 内检查更新读取的更新源。
- GitHub Releases 托管 `Whitecat-<version>.zip`，这是 Sparkle 或内置安装器直接下载的安装包。
- GitHub Release 页面只作为版本说明入口，不是主安装路径。
- 自动发布流程已经保证先有 Release 资产，再发布新的 `appcast.xml`，避免客户端先读到新版本但下载地址还没准备好。

## GitHub Actions 约定的 Secrets

- `APPLE_DEVELOPER_IDENTITY`
- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `APPLE_NOTARY_APPLE_ID`
- `APPLE_NOTARY_TEAM_ID`
- `APPLE_NOTARY_APP_SPECIFIC_PASSWORD`
- `SPARKLE_PUBLIC_ED_KEY`
- `SPARKLE_PRIVATE_ED_KEY`
- `TEAM_BUNDLE_PREFIX`

## 发布产物

- `dist/releases/Whitecat-<version>.zip`
- `dist/releases/Whitecat-<version>.dmg`
- `dist/releases/appcast.xml`
