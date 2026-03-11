# Release Guide

## 必备项

- `Developer ID Application` 证书
- Apple notarization 凭据
- Sparkle 公私钥
- GitHub Releases 发布权限
- GitHub Pages 已启用

## 一次性准备

1. 用 `Vendor/SparkleTools/generate_keys` 生成 `SUPublicEDKey` 和私钥。
2. 把公钥放进 `SPARKLE_PUBLIC_ED_KEY`。
3. 把私钥放进 GitHub Secret `SPARKLE_PRIVATE_ED_KEY`。
4. 按团队标识生成 entitlements：

```bash
TEAM_BUNDLE_PREFIX=YOURTEAM ./Scripts/render_entitlements.sh
```

## 本地发布

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
- 发布顺序要保证先有 Release 资产，再发布新的 `appcast.xml`，否则客户端可能先读到新版本但下载地址还没准备好。

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
