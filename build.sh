#!/bin/bash
# 📦 构建 会议纪要录音器 macOS App

set -e
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

echo "═══════════════════════════════════"
echo "  📦  构建 会议纪要录音器.app       "
echo "═══════════════════════════════════"

# 清理
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ===========================================
# 方案 1: 基于 Shell 的 .app（推荐）
# 双击打开启动服务，Cmd+Q 正常退出关闭进程
# ===========================================
APP_NAME="会议纪要录音器"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Info.plist
cat > "$APP_PATH/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MeetingMinutes</string>
    <key>CFBundleIdentifier</key>
    <string>com.meeting-minutes.app</string>
    <key>CFBundleName</key>
    <string>会议纪要录音器</string>
    <key>CFBundleDisplayName</key>
    <string>会议纪要录音器</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>需要使用麦克风进行录音</string>
</dict>
</plist>
PLIST

# 可执行脚本（带信号处理和 App 生命周期管理）
cat > "$APP_PATH/Contents/MacOS/MeetingMinutes" << 'SCRIPT'
#!/bin/bash

PROJECT_DIR="$(cd "$(dirname "$0")/../../../../" && pwd)"
cd "$PROJECT_DIR"

# 信号处理：App 退出时关闭服务
cleanup() {
    echo "🛑 停止服务..."
    kill $SERVER_PID 2>/dev/null
    wait $SERVER_PID 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT SIGHUP

# 检查环境
if [ ! -f "server.js" ]; then
    osascript -e 'display dialog "找不到 server.js\n请确认 .app 放在项目根目录" buttons {"知道了"} default button 1 with title "错误" with icon stop'
    exit 1
fi
if [ ! -d "node_modules" ]; then
    osascript -e 'display dialog "未安装依赖\n\n终端执行: cd '"$PROJECT_DIR"' && npm install" buttons {"知道了"} default button 1 with title "安装依赖" with icon stop'
    exit 1
fi

# 检测是否已运行
if lsof -i :19924 -P 2>/dev/null | grep LISTEN > /dev/null 2>&1; then
    open "http://localhost:19924"
    osascript -e 'display dialog "服务已在运行" buttons {"打开页面"} default button 1 with title "🎙️ 会议纪要录音器"'
    # 保持前台进程，让 App 不退出
    while true; do sleep 1; done
    exit 0
fi

# 启动服务
nohup node server.js > /dev/null 2>&1 &
SERVER_PID=$!

# 等待就绪
for i in {1..20}; do
    sleep 0.3
    if curl -s http://localhost:19924/health > /dev/null 2>&1; then
        break
    fi
done

open "http://localhost:19924"

# 常驻前台（App 不退出，直到用户 Cmd+Q）
wait $SERVER_PID 2>/dev/null
SCRIPT

chmod +x "$APP_PATH/Contents/MacOS/MeetingMinutes"

# ===========================================
# 生成应用图标（简易版 - 用 Python 画 🎙️）
# ===========================================
python3 << 'PYICON'
import struct, zlib, base64, os

def create_png(w, h, pixels):
    """从 RGBA 像素数据生成 PNG"""
    def chunk(ctype, data):
        c = ctype + data
        crc = struct.pack('>I', zlib.crc32(c) & 0xffffffff)
        return struct.pack('>I', len(data)) + c + crc
    
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
    raw = b''
    for y in range(h):
        raw += b'\x00' + bytes(pixels[y * w * 4:(y + 1) * w * 4])
    idat = chunk(b'IDAT', zlib.compress(raw))
    iend = chunk(b'IEND', b'')
    return sig + ihdr + idat + iend

size = 256
pixels = []

import math
cx, cy = size//2, size//2 - 10
r = size//2 - 8

for y in range(size):
    for x in range(size):
        dx, dy = x - cx, y - cy
        dist = math.sqrt(dx*dx + dy*dy)
        
        if dist <= r:
            # 圆内：深蓝渐变背景
            t = dist / r
            rv = int(30 + 60 * (1-t))
            gv = int(30 + 60 * (1-t))
            bv = int(60 + 100 * (1-t))
            a = 255
            
            # 画一个简单的 🎙️ 符号（白色麦克风）
            mx, my = cx, cy + 10
            mic_r = r * 0.22
            if abs(x - cx) < mic_r and abs(y - cy) < mic_r * 1.8:
                rv, gv, bv = 255, 255, 255
            # 麦克风底座
            if abs(x - cx) < mic_r * 0.35 and (y > cy + mic_r * 1.5 and y < cy + mic_r * 2.5):
                rv, gv, bv = 255, 255, 255
            # 支架
            if abs(x - cx) < 3 and y > cy + mic_r * 1.0 and y < cy + mic_r * 1.5:
                rv, gv, bv = 200, 200, 200
        else:
            rv, gv, bv, a = 0, 0, 0, 0
        
        pixels.extend([rv, gv, bv, a])

png_bytes = create_png(size, size, pixels)

# 写入 .icns（简化为只放一个 png，macOS 会自动缩放）
icon_path = os.path.expanduser('~/projects/meeting-minutes/build/会议纪要录音器.app/Contents/Resources/icon.png')
with open(icon_path, 'wb') as f:
    f.write(png_bytes)
PYICON

# 在 Info.plist 中引用图标
defaults write "$APP_PATH/Contents/Info" CFBundleIconFile icon 2>/dev/null || true

echo ""
echo "✅ 构建完成！"
echo ""

echo "打开方式："
echo "   1. Finder 中双击 → 启动服务 + 打开浏览器"
echo "   2. Cmd+Q → 关闭服务 + 退出 App"
echo "   3. 拖到 Dock 固定 → 随时一键启动"
echo ""

echo "📌 App 位置:"
echo "   $APP_PATH"
echo ""

# 打开 Finder 展示
open "$BUILD_DIR"