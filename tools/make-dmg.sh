#!/usr/bin/env bash
# Build a distributable DMG: LiteWall.app + an /Applications symlink.
#
# This is a plain drag-and-drop image. It deliberately does NOT install the
# LaunchAgent: macOS DMGs cannot run postinstall scripts, and quarantine-free
# execution of arbitrary code at install time would be worse than an explicit
# one-shot `tools/install.sh`. Login-item setup stays in the app's menu.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/LiteWall.app"
STAGE="$ROOT/build/dmg-stage"
DMG="$ROOT/LiteWall-1.0.0.dmg"

[[ -d "$APP" ]] || "$ROOT/build.sh"

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/LiteWall.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/安装说明.txt" <<'EOF'
LiteWall · 轻壁纸 1.0.0
========================

安装
----
把 LiteWall.app 拖到本窗口中的 Applications 文件夹。

首次打开
--------
本包使用 ad-hoc 签名（没有 Apple Developer ID），macOS 可能提示
「无法验证开发者」。请右键点击 App → 「打开」，或在终端执行：

    xattr -dr com.apple.quarantine /Applications/LiteWall.app

启动
----
    open /Applications/LiteWall.app

菜单栏会出现照片图标，从这里切换壁纸、暂停、调整音量、
选择切换间隔，以及勾选「开机自启」。

开机自启
--------
勾选菜单栏「开机自启」即可（写入 ~/Library/LaunchAgents，
下次登录生效）。若从源码使用，也可运行 ./tools/install.sh
一键完成「安装 App + 注册登录项」。

说明
----
本包不包含 Wallpaper Engine 的任何代码或素材。
内置《凡人女修》轮播壁纸的图片来自本项目自带的素材目录。
EOF

rm -f "$DMG"
hdiutil create \
  -volname "LiteWall 轻壁纸" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

ls -lh "$DMG"
echo "DMG 已生成：$DMG"
