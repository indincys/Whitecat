# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Whitecat is a native macOS notes app (Swift 6 + SwiftUI + AppKit bridge) targeting Apple Silicon / macOS 15+. Three-column layout (sidebar / note list / editor) inspired by Things 3. Core concept: "write first, AI organizes later" — notes are auto-organized by LLM on blur.

Default localization is Chinese (zh-Hans). All user-facing strings are in simplified Chinese.

## Build & Run Commands

All commands require these environment variables:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH=/tmp/whitecat-clang-module-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/whitecat-swiftpm-module-cache
```

**Run the app:**
```bash
swift run --disable-sandbox --scratch-path /tmp/whitecat-build WhitecatApp
```

**Run all tests:**
```bash
swift test --disable-sandbox --scratch-path /tmp/whitecat-build
```

**Run a single test:**
```bash
swift test --disable-sandbox --scratch-path /tmp/whitecat-build --filter <TestClassName>/<testMethodName>
```

No external SPM dependencies — only vendored Sparkle binary and Apple system frameworks.

## Architecture

Four modules defined in `Package.swift`:

- **WhitecatApp** (executable) — SwiftUI app entry, `AppModel` (central `@MainActor` observable state machine), three-column `ContentView`, settings, quick capture (⌥⌘N), detached note windows.
- **NotesCore** (library) — Data models (`NoteRecord`, `FolderRecord`, `TagRecord`, `AIProfileRecord`), `LibraryPersistence` (JSON-based, iCloud primary with local fallback to `~/Library/Application Support`).
- **AIOrchestrator** (library) — OpenAI-compatible LLM adapter supporting multiple providers (OpenAI, DeepSeek, Qwen, Kimi, Z.ai, Doubao, Custom). Keychain-based secret storage. Organization pipeline that auto-generates titles, tags, and folders.
- **AppUpdates** (library) — Sparkle 2.7.3 bridge for signed builds, manual appcast parser with EdDSA verification for unsigned builds.

`AppModel` is the hub: it owns the library snapshot, manages auto-save (350ms debounce), drives the AI organization queue (with exponential backoff retries), and coordinates updates.

## Release

`./Scripts/release.sh <version>` runs the full pipeline: build, sign, generate appcast, create GitHub Release, push. Requires local `Developer ID` signing identity and Sparkle private key at `~/.config/whitecat/sparkle_private_key`.

## CI

GitHub Actions (`.github/workflows/ci.yml`): runs `swift test` on macOS 15 for pushes to `main`/`codex/**` and all PRs.
