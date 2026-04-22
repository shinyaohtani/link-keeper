# Project Rules

## Xcode Project Management

This project uses **XcodeGen** to generate the Xcode project.

**NEVER directly edit or create files inside `LinkKeeper.xcodeproj/`.**
This includes `project.pbxproj`, `.xcscheme` files, and any other file within the `.xcodeproj` bundle.

To change the Xcode project configuration:
1. Edit `project.yml` (XcodeGen spec)
2. Run `xcodegen generate`

**Do NOT manually add file references to `project.pbxproj`.** XcodeGen handles it automatically.

### Adding files or resources

XcodeGen auto-discovers all files under the directories listed in `sources:` of `project.yml`.
When you add a new `.swift`, image, or any resource file to the `LinkKeeper/` directory:

1. Just create the file in the correct directory
2. Run `xcodegen generate`

## Build & Run

**ビルドは必ず `./gen_build_install.zsh` を使うこと。`xcodebuild` を直接実行してはならない。**

`gen_build_install.zsh` は XcodeGen の実行からビルド・インストールまで一括で行う。

```bash
# ビルドチェック（インストールなし、Releaseのみ ← リファクタリング時に推奨）
./gen_build_install.zsh --build-check

# ビルドチェック（Debug と Release の両方）
./gen_build_install.zsh --build-check=Debug,Release

# macOS にビルド＆インストール（/Applications にコピー）
./gen_build_install.zsh --mac
```

### ビルド構成の違い（重要）

| コマンド | 構成 | 用途 |
|---|---|---|
| `--build-check` | Release | **コード変更後の確認に使うこと** |
| `--build-check=Debug,Release` | 両方 | 両構成での確認が必要な場合 |
| `--mac` | Release | **/Applications へのインストール** |

`--mac` は Release ビルドを行ってからインストールするため、`--build-check && --mac` とする必要はない。`--mac` のみで十分。
