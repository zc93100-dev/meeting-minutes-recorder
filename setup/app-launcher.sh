#!/bin/bash
# 🎙️ 会议纪要录音器 App 启动脚本（模板）
# 构建时 PROJECT_ROOT 会被替换为实际路径

PROJECT_ROOT="__PROJECT_ROOT__"
cd "$PROJECT_ROOT" || {
    osascript -e 'display dialog "项目目录不存在\n请重新运行 bash build.sh 构建" buttons {"知道了"} default button 1 with title "错误" with icon stop'
    exit 1
}

# 信号处理：App 退出时关闭服务
cleanup() {
    kill $SERVER_PID 2>/dev/null
    wait $SERVER_PID 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT SIGHUP

# 检查环境
if [ ! -f "$PROJECT_ROOT/server.js" ]; then
    osascript -e 'display dialog "找不到 server.js\n请重新运行 bash build.sh 构建" buttons {"知道了"} default button 1 with title "错误" with icon stop'
    exit 1
fi
if [ ! -d "$PROJECT_ROOT/node_modules" ]; then
    osascript -e 'display dialog "未安装依赖\n\n终端执行: cd '"$PROJECT_ROOT"' && npm install" buttons {"知道了"} default button 1 with title "安装依赖" with icon stop'
    exit 1
fi

# 判断是否从登录项启动（开机自启模式 - 不弹浏览器）
IS_LOGIN_ITEM=false
if [ "$(ps -o ppid= -p $$ | xargs)" = "1" ]; then
    IS_LOGIN_ITEM=true
fi

# 检测是否已运行
if lsof -i :19924 -P 2>/dev/null | grep LISTEN > /dev/null 2>&1; then
    if [ "$IS_LOGIN_ITEM" = false ]; then
        open "http://localhost:19924"
    fi
    while true; do sleep 1; done
    exit 0
fi

# 启动服务
nohup node "$PROJECT_ROOT/server.js" > /dev/null 2>&1 &
SERVER_PID=$!

# 等待就绪
for i in {1..20}; do
    sleep 0.3
    if curl -s http://localhost:19924/health > /dev/null 2>&1; then
        break
    fi
done

# 非登录项模式才打开浏览器
if [ "$IS_LOGIN_ITEM" = false ]; then
    # 用 AppleScript 打开并激活浏览器窗口（不会在后台静默）
    osascript -e 'display notification "服务已启动" with title "🎙️ 会议纪要录音器" subtitle "http://localhost:19924"'
    osascript -e 'open location "http://localhost:19924"'
fi

# 常驻前台（App 不退出，直到用户 Cmd+Q）
wait $SERVER_PID 2>/dev/null
