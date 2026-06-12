#!/bin/bash
# 📦 构建 会议纪要录音器 macOS App（AppleScript 原生）

set -e
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

echo "═══════════════════════════════════"
echo "  📦  构建 会议纪要录音器.app       "
echo "═══════════════════════════════════"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

APP_NAME="会议纪要录音器"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

# ========== 生成 AppleScript App ==========
osacompile -o "$APP_PATH" -e "
-- 会话 ID（每次构建不同，用于定位进程）
property sessionId : \"$(date +%s)$RANDOM\"

on run
    set projectDir to \"$PROJECT_DIR\"
    
    -- 启动 Node.js 服务
    try
        do shell script \"cd \" & quoted form of projectDir & \" && nohup node server.js > /dev/null 2>&1 &\"
    end try
    
    -- 等待服务就绪
    delay 3
    
    -- 打开页面
    open location \"http://localhost:19924\"
end run

on quit
    try
        do shell script \"pkill -f 'node.*server.js' 2>/dev/null; exit 0\"
    end try
    continue quit
end quit
"

# ========== 设置图标（从 build.sh 的 Python 脚本生成）==========
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
# 写入 app 的资源目录
icon_path = os.path.join('$APP_PATH', 'Contents', 'Resources', 'icon.png')
with open(icon_path, 'wb') as f:
    f.write(png_bytes)
PYICON

# 设置图标引用
defaults write "$APP_PATH/Contents/Info" CFBundleIconFile icon 2>/dev/null || true

# 添加麦克风权限声明
plutil -insert NSMicrophoneUsageDescription -string "需要使用麦克风进行录音" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true

echo ""
echo "✅ 构建完成！"
echo ""
echo "📌 App 位置: $APP_PATH"
echo ""
echo "   双击 → 启动服务 + 浏览器自动打开"
echo "   Cmd+Q → 关闭服务 + 退出 App"
echo "   服务端口: http://localhost:19924"
echo ""
echo "📌 拖到程序坞固定后："
echo "   点击图标启动，Cmd+Q 关闭"
echo ""

open "$BUILD_DIR"