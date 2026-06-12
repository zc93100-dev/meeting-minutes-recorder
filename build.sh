#!/bin/bash
# 📦 构建 会议纪要录音器 macOS App

set -e
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
LAUNCHER_TPL="$PROJECT_DIR/setup/app-launcher.sh"

echo "═══════════════════════════════════"
echo "  📦  构建 会议纪要录音器.app       "
echo "═══════════════════════════════════"

# 清理
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

APP_NAME="会议纪要录音器"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# ========== Info.plist ==========
cat > "$APP_PATH/Contents/Info.plist" << PLIST
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

# ========== 生成可执行脚本（嵌入项目绝对路径，支持 .app 移动到任意位置）==========
sed "s|__PROJECT_ROOT__|$PROJECT_DIR|g" "$LAUNCHER_TPL" > "$APP_PATH/Contents/MacOS/MeetingMinutes"
chmod +x "$APP_PATH/Contents/MacOS/MeetingMinutes"

# ========== 生成应用图标 ==========
python3 << PYICON
import struct, zlib, math, os

def create_png(w, h, pixels):
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
cx, cy = size//2, size//2 - 10
r = size//2 - 8
for y in range(size):
    for x in range(size):
        dx, dy = x - cx, y - cy
        dist = math.sqrt(dx*dx + dy*dy)
        if dist <= r:
            t = dist / r
            rv, gv, bv = int(30 + 60*(1-t)), int(30 + 60*(1-t)), int(60 + 100*(1-t))
            a = 255
            mic_r = r * 0.22
            if abs(x - cx) < mic_r and abs(y - cy) < mic_r * 1.8:
                rv, gv, bv = 255, 255, 255
            if abs(x - cx) < mic_r * 0.35 and (y > cy + mic_r * 1.5 and y < cy + mic_r * 2.5):
                rv, gv, bv = 255, 255, 255
            if abs(x - cx) < 3 and y > cy + mic_r * 1.0 and y < cy + mic_r * 1.5:
                rv, gv, bv = 200, 200, 200
        else:
            rv, gv, bv, a = 0, 0, 0, 0
        pixels.extend([rv, gv, bv, a])

png_bytes = create_png(size, size, pixels)
icon_path = os.path.join('$APP_PATH', 'Contents', 'Resources', 'icon.png')
with open(icon_path, 'wb') as f:
    f.write(png_bytes)
PYICON

# 注册图标
defaults write "$APP_PATH/Contents/Info" CFBundleIconFile icon 2>/dev/null || true

echo ""
echo "✅ 构建完成！"
echo ""
echo "📌 App 位置: $APP_PATH"
echo ""
echo "   Project: $PROJECT_DIR"
echo "   (已嵌入 app 中，可移动到 /Applications/ 或任意位置)"
echo ""
echo "打开方式："
echo "   1. Finder 中双击 → 启动服务 + 打开浏览器"
echo "   2. Cmd+Q → 关闭服务 + 退出 App"
echo "   3. 设置 Dock / /Applications/ → 随时一键启动"
echo ""

open "$BUILD_DIR"