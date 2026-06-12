#!/bin/bash
# 🍎 安装 macOS 开机自启服务（崩溃自动重启）
# 用法: bash setup/install-service.sh

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_SRC="$PROJECT_DIR/setup/launchd.plist.example"
PLIST_DST="$HOME/Library/LaunchAgents/com.meeting-minutes.server.plist"
NODE_PATH="$(which node 2>/dev/null || echo '/usr/local/bin/node')"

echo "═══════════════════════════════════"
echo "  🎙️  安装会议纪要录音器自启服务   "
echo "═══════════════════════════════════"
echo ""
echo "项目路径: $PROJECT_DIR"
echo "Node 路径: $NODE_PATH"
echo ""

# 检查 .env
if [ ! -f "$PROJECT_DIR/.env" ]; then
  echo "⚠️  未找到 .env 文件"
  echo "   请先配置: cp .env.example .env"
  echo "   然后填入 API Key"
  exit 1
fi

# 卸载旧服务
if [ -f "$PLIST_DST" ]; then
  echo "🔄 卸载旧服务..."
  launchctl unload "$PLIST_DST" 2>/dev/null || true
fi

# 生成 plist（替换路径占位符）
sed "s|SERVER_PATH|$PROJECT_DIR|g" "$PLIST_SRC" > "$PLIST_DST"

# 修正 node 路径
sed -i '' "s|/usr/local/bin/node|$NODE_PATH|g" "$PLIST_DST"

# 加载服务
echo "🚀 加载服务..."
launchctl load "$PLIST_DST"

echo ""
echo "✅ 安装成功！服务已启动："
echo "   - 地址: http://localhost:${PORT:-19924}"
echo "   - 开机自启: ✅"
echo "   - 崩溃自动重启: ✅"
echo ""
echo "📋 常用命令："
echo "   查看状态: launchctl list | grep meeting-minutes"
echo "   查看日志: cat $PROJECT_DIR/server.log"
echo "   停止服务: launchctl unload $PLIST_DST"
echo "   启动服务: launchctl load $PLIST_DST"
echo "   卸载服务: rm -f $PLIST_DST"
