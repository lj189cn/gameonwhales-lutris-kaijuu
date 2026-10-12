#!/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
# url-bridge-daemon.sh —— 跨 pressure-vessel 沙箱的 URL 转发守护进程（沙箱外运行）
#
# 【它解决什么】
#   沙箱内的 /usr/bin/xdg-open 是 steam-runtime-urlopen，打不开任何东西
#   （见 xdg-open-sandbox-proxy 的说明）。沙箱内又没有 zenity、也加载不了
#   容器库，无法就地弹窗。
#   因此：沙箱内用代理把 URL 写进共享 FIFO，本进程在沙箱外读取，
#   调用 browser-picker 弹选择器，再由选择器启动浏览器。
#
# 【启动方式】
#   - 镜像固化：由 /opt/gow/startup.d/91-url-bridge.sh 在会话启动时拉起
#   - 运行时装法：由 url-bridge-start.sh 拉起（sway 的 custom-cfg 触发）
#
# 环境变量（可选）：
#   URL_BRIDGE_FIFO    默认 $HOME/.local/share/url-bridge/requests.fifo
#   URL_BRIDGE_PICKER  默认 $HOME/.local/bin/browser-picker
#   URL_BRIDGE_LOG     默认 /tmp/url-bridge.log
#   URL_BRIDGE_PID     默认 $HOME/.local/share/url-bridge/daemon.pid
# ═══════════════════════════════════════════════════════════════════════════

# ⚠ 必须按会话隔离：多个 WolfLutris 会话容器共用宿主的 var/lutris/.local，
#   即共用 $HOME/.local —— FIFO 与 pidfile 若用固定名，会出现
#     ① 多个守护进程抢读同一 FIFO，URL 被撕碎（实测字符丢失）
#     ② 某个会话的守护进程读到另一个会话的 URL，弹窗出现在错误的画面上
#     ③ pidfile 互相覆盖，kill 到不相干的进程
SESSION="${WOLF_SESSION_ID:-default}"
FIFO="${URL_BRIDGE_FIFO:-$HOME/.local/share/url-bridge/$SESSION/requests.fifo}"
PICKER="${URL_BRIDGE_PICKER:-$HOME/.local/bin/browser-picker}"
LOGF="${URL_BRIDGE_LOG:-/tmp/url-bridge.log}"
PIDF="${URL_BRIDGE_PID:-$HOME/.local/share/url-bridge/$SESSION/daemon.pid}"

mkdir -p "$(dirname "$FIFO")" 2>/dev/null
if [ ! -p "$FIFO" ]; then rm -f "$FIFO" 2>/dev/null; mkfifo "$FIFO" 2>/dev/null; fi
if [ ! -p "$FIFO" ]; then echo "url-bridge: 无法创建 FIFO $FIFO" >>"$LOGF" 2>&1; exit 1; fi
[ -x "$PICKER" ] || echo "url-bridge: 警告，picker 不可执行：$PICKER" >>"$LOGF" 2>&1

echo $$ > "$PIDF" 2>/dev/null
echo "url-bridge: 就绪 pid=$$ session=$SESSION fifo=$FIFO picker=$PICKER DISPLAY=${DISPLAY:-<未设>}" >>"$LOGF" 2>&1

while :; do
  if IFS= read -r url < "$FIFO"; then
    case "$url" in
      http://*|https://*)
        echo "url-bridge: 收到 $url" >>"$LOGF" 2>&1
        setsid "$PICKER" "$url" >>"$LOGF" 2>&1 &
        ;;
      *)
        echo "url-bridge: 忽略非 http(s) 请求 [$url]" >>"$LOGF" 2>&1
        ;;
    esac
  fi
  sleep 1
done
