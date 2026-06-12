#!/bin/bash
# 🔧 安装 会议纪要录音器 到登录项（开机自启）
# 电脑重启后自动启动服务，不用手动打开 .app

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# 用 find 查找 .app（中文文件名兼容）
APP_FILE="$(find build -maxdepth 2 -name '*.app' -type d 2>/dev/null | head -1)"

if [ -z "$APP_FILE" ]; then
  echo "⚠️  未找到 .app，请先运行: bash build.sh"
  exit 1
fi

FULL_APP_PATH="$PROJECT_DIR/$APP_FILE"
APP_NAME="$(basename "$APP_FILE")"

echo "═══════════════════════════════════"
echo "  🔧  安装开机自启"
echo "═══════════════════════════════════"
echo ""
echo "App: $FULL_APP_PATH"
echo ""

# 用 AppleScript 添加到登录项
RESULT=$(osascript -e "
tell application \"System Events\"
    set loginItems to get the name of every login item
    if \"$APP_NAME\" is not in loginItems then
        make new login item at end with properties {path:\"$FULL_APP_PATH\", hidden:true}
        return \"added\"
    else
        return \"exists\"
    end if
end tell
")

if [ "$RESULT" = "added" ]; then
  echo "✅ 已添加「$APP_NAME」到登录项，开机自启 ✅"
  echo "   电脑重启后，服务会在后台自动启动"
  echo "   使用时直接打开 http://localhost:19924"
  echo "   不需要双击 .app"
elif [ "$RESULT" = "exists" ]; then
  echo "ℹ️  已在登录项中，无需重复添加"
fi

echo ""
echo "📋 验证：系统设置 → 通用 → 登录项"
echo "📋 卸载：系统设置 → 通用 → 登录项 → 点击移除"
echo "   或运行: osascript -e 'tell application \"System Events\" to delete login item \"$APP_NAME\"'"