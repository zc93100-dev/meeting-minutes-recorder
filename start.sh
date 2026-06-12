#!/bin/bash
# 🎙️ 会议纪要录音器 - 一键启动

echo "═══════════════════════════════════"
echo "  🎙️  会议纪要录音器              "
echo "═══════════════════════════════════"

# 检查 Node.js
if ! command -v node &> /dev/null; then
  echo "❌ 未找到 Node.js，请先安装: https://nodejs.org"
  exit 1
fi

# 检查 FFmpeg
if ! command -v ffmpeg &> /dev/null; then
  echo "❌ 未找到 FFmpeg"
  echo "   macOS: brew install ffmpeg"
  echo "   Linux: sudo apt install ffmpeg"
  exit 1
fi

# 检查依赖
if [ ! -d "node_modules" ]; then
  echo "📦 安装依赖..."
  npm install
fi

# 检查 .env
if [ ! -f ".env" ]; then
  echo "⚠️  未找到 .env 文件"
  echo "   请执行: cp .env.example .env"
  echo "   然后编辑 .env 填入 API Key"
  if [ -f ".env.example" ]; then
    cp .env.example .env
    echo "   已自动创建 .env，请填入 API Key 后重新运行"
  fi
  exit 1
fi

echo "🚀 启动服务..."
echo "   地址: http://localhost:${PORT:-19924}"
echo ""
node server.js
