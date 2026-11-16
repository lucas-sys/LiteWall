#!/usr/bin/env bash
# Install LiteWall into ~/Applications and register a per-user LaunchAgent.
#
#   ./tools/install.sh              install (or update) app + login item
#   ./tools/install.sh --no-build   reuse an existing build/LiteWall.app
#   ./tools/install.sh --uninstall  remove the login item (keeps the app)
#
# The LaunchAgent is used instead of SMAppService because this project is
# ad-hoc signed; a plist login item needs no Apple signature or admin rights.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/build/LiteWall.app"
DST="$HOME/Applications/LiteWall.app"
LABEL="dev.litewall.LiteWall"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

if [[ "${1:-}" == "--uninstall" ]]; then
    launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "已移除开机自启：$PLIST"
    echo "App 仍保留在：$DST（如需彻底删除请手动移到废纸篓）"
    exit 0
fi

if [[ "${1:-}" != "--no-build" ]] || [[ ! -d "$SRC" ]]; then
    "$ROOT/build.sh"
fi

[[ -d "$SRC" ]] || { echo "error: build/LiteWall.app 不存在，请先运行 ./build.sh" >&2; exit 1; }

echo "== [1/4] 安装 App 到 ~/Applications =="
mkdir -p "$HOME/Applications"
if [[ -d "$DST" ]]; then
    EXISTING_ID="$(defaults read "$DST/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
    if [[ "$EXISTING_ID" != "dev.litewall.LiteWall" ]]; then
        echo "error: $DST 不是 LiteWall（CFBundleIdentifier=$EXISTING_ID），拒绝覆盖" >&2
        exit 1
    fi
    rm -rf "$DST"
fi
ditto "$SRC" "$DST"
echo "      $DST"

echo "== [2/4] 写入登录项 =="
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>$DST</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST
plutil -lint "$PLIST"

echo "== [3/4] 加载到当前登录会话 =="
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
if launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>&1; then
    echo "      job 已加载（RunAtLoad 会启动 App）"
else
    echo "      当前会话加载失败；plist 已写入，下次登录会自动生效。"
fi

echo "== [4/4] 状态 =="
sleep 1
if pgrep -x LiteWall >/dev/null; then
    echo "      LiteWall 正在运行（PID $(pgrep -x LiteWall | tr '\n' ' ')）"
else
    echo "      未检测到进程；可手动启动： open \"$DST\""
fi
launchctl print "gui/$UID_NUM/$LABEL" 2>/dev/null | head -6 || true

echo
echo "完成。启动： open \"$DST\""
echo "关闭自启： ./tools/install.sh --uninstall  或  菜单栏取消勾选「开机自启」"
