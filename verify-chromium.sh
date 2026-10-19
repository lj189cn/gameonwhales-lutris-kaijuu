#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# verify-chromium.sh —— 验证「Chromium 直连」镜像
#
# 检查：
#   1. 新固化文件就位；旧 browser-picker 文件确实不存在
#   2. chromium-open 能把 URL 原样（含 &）传给 Chromium
#   3. 在新卷上模拟旧会话：卷里预置 picker 关联 + discord + picker 残留文件
#      → 启动钩子执行后：三个键校正为 chromium.desktop、discord 保留、
#        picker 残留被清掉、文件属主 retro
#   4. xdg-mime 解析到 chromium.desktop
#
# 用法：./verify-chromium.sh [镜像名]
#   默认：gameonwhales/lutris:kaijuu
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

IMAGE="${1:-gameonwhales/lutris:kaijuu}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$HERE"

# ── 本容器路径 → 宿主机路径（docker -v 由宿主机解析）─────────────────────
host_path_of() {
  local p="$1" best_src="" best_dst="" map
  map="$(docker inspect "$(hostname)" --format '{{range .Mounts}}{{.Source}}|{{.Destination}}{{"\n"}}{{end}}' 2>/dev/null || true)"
  while IFS='|' read -r src dst; do
    [ -z "${dst:-}" ] && continue
    case "$p" in
      "$dst"|"$dst"/*)
        if [ "${#dst}" -gt "${#best_dst}" ]; then best_src="$src"; best_dst="$dst"; fi ;;
    esac
  done <<< "$map"
  if [ -n "$best_dst" ]; then printf '%s%s\n' "$best_src" "${p#"$best_dst"}"; else printf '%s\n' "$p"; fi
}

LOCAL_VOL="$WORKDIR/日志/验证卷-chromium"
HOST_VOL="$(host_path_of "$LOCAL_VOL")"
rm -rf "$LOCAL_VOL"
mkdir -p "$LOCAL_VOL/.config" "$LOCAL_VOL/.local/share/applications"

# 预置旧卷：picker 关联 + discord + picker 残留
cat > "$LOCAL_VOL/.config/mimeapps.list" <<'EOF'
[Default Applications]
x-scheme-handler/http=browser-picker.desktop
x-scheme-handler/https=browser-picker.desktop
text/html=browser-picker.desktop
x-scheme-handler/discord-1221314350216646828=discord-1221314350216646828.desktop
EOF
cat > "$LOCAL_VOL/.local/share/applications/browser-picker.desktop" <<'EOF'
[Desktop Entry]
Name=Browser Picker
Exec=/usr/local/bin/browser-picker %u
Type=Application
EOF
echo "BROWSERS=(x)" > "$LOCAL_VOL/.config/browser-picker.conf"
chmod -R 777 "$LOCAL_VOL"

echo "▶ 镜像      : $IMAGE"
echo "▶ 卷(本容器): $LOCAL_VOL"
echo "▶ 卷(宿主)  : $HOST_VOL"

echo
echo "════════ 容器内检查 ════════"
docker run --rm -v "$HOST_VOL:/home/retro" --entrypoint bash "$IMAGE" -c '
set -u
ok=1
chk() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "    ✓ $d"; else echo "    ✗ $d"; ok=0; fi }

echo "── 0. 卷挂载生效 ──"
if [ -s /home/retro/.config/mimeapps.list ]; then echo "    ✓ 预置 mimeapps.list 可见"; else echo "    ✗ 卷未生效"; exit 9; fi

echo "── 1. 新固化文件 ──"
for f in /usr/local/bin/chromium-open \
         /usr/share/applications/chromium.desktop \
         /etc/xdg/mimeapps.list \
         /opt/gow/startup.d/90-chromium-default.sh; do
  if [ -s "$f" ]; then printf "    ✓ %-56s %s B\n" "$f" "$(stat -c%s "$f")";
  else printf "    ✗ %s 缺失或为空\n" "$f"; ok=0; fi
done
echo "── 2. 旧 picker 已移除 ──"
for f in /usr/local/bin/browser-picker \
         /usr/share/applications/browser-picker.desktop \
         /opt/gow/startup.d/90-browser-picker.sh; do
  if [ -e "$f" ]; then echo "    ✗ 仍存在: $f"; ok=0; else echo "    ✓ 不存在: $f"; fi
done
chk "mimeapps.list 指向 chromium.desktop" grep -q "x-scheme-handler/https=chromium.desktop" /etc/xdg/mimeapps.list
chk "desktop Exec 指向 chromium-open" grep -q "Exec=/usr/local/bin/chromium-open %u" /usr/share/applications/chromium.desktop

echo "── 3. chromium-open URL 传参（CHROMIUM=/bin/echo）──"
_out="$(CHROMIUM=/bin/echo /usr/local/bin/chromium-open "https://example.com/a?x=1&y=2" 2>&1 || true)"
printf "    %s\n" "$_out"
case "$_out" in
  *"--no-sandbox"*"--new-window"*"https://example.com/a?x=1&y=2"*) echo "    ✓ 参数与 URL 原样传递（& 未被吞）" ;;
  *) echo "    ✗ 参数传递不符"; ok=0 ;;
esac

echo "── 3b. xdg-open → chromium.desktop 链路 ──"
_out2="$(DISPLAY=:0 CHROMIUM=/bin/echo HOME=/tmp \
        XDG_DATA_DIRS=/usr/local/share:/usr/share \
        xdg-open "https://example.com/a?x=1&y=2" 2>&1 || true)"
printf "    %s\n" "$_out2"
case "$_out2" in
  *"--no-sandbox"*"--new-window"*"https://example.com/a?x=1&y=2"*) echo "    ✓ xdg-open 解析到 chromium.desktop 并调用 chromium-open" ;;
  *) echo "    ✗ xdg-open 链路不符"; ok=0 ;;
esac

echo "── 4. 创建 retro 用户（镜像内真实 cont-init）──"
mkdir -p /tmp/xdg
source /opt/gow/bash-lib/utils.sh 2>/dev/null || true
export UNAME=retro HOME=/home/retro PUID=1000 PGID=1000 UMASK=000 XDG_RUNTIME_DIR=/tmp/xdg
source /etc/cont-init.d/10-setup_user.sh
id retro >/dev/null 2>&1 && echo "    ✓ retro 已创建" || { echo "    ✗ retro 创建失败"; ok=0; }

echo "── 5. 执行启动钩子（retro 身份 source）──"
gosu retro env HOME=/home/retro bash -c ". /opt/gow/startup.d/90-chromium-default.sh" || true

echo "── 6. 钩子执行后的 ~/.config/mimeapps.list ──"
sed "s/^/    /" /home/retro/.config/mimeapps.list

echo "── 7. 断言 ──"
for k in "x-scheme-handler/http" "x-scheme-handler/https" "text/html"; do
  grep -q "^${k}=chromium.desktop$" /home/retro/.config/mimeapps.list \
    && echo "    ✓ ${k} → chromium.desktop" \
    || { echo "    ✗ ${k} 未校正"; ok=0; }
done
grep -q "discord-1221314350216646828" /home/retro/.config/mimeapps.list \
  && echo "    ✓ discord 关联保留" || { echo "    ✗ discord 关联丢失"; ok=0; }
[ ! -e /home/retro/.local/share/applications/browser-picker.desktop ] \
  && echo "    ✓ 卷内 picker desktop 残留已清" || { echo "    ✗ picker desktop 残留仍在"; ok=0; }
[ ! -e /home/retro/.config/browser-picker.conf ] \
  && echo "    ✓ 卷内 browser-picker.conf 已清" || { echo "    ✗ browser-picker.conf 仍在"; ok=0; }
[ "$(stat -c %U /home/retro/.config/mimeapps.list)" = "retro" ] \
  && echo "    ✓ 文件属主 retro" || { echo "    ✗ 属主不是 retro"; ok=0; }

echo "── 8. xdg-mime 解析 ──"
printf "    用户级 https → %s\n" "$(gosu retro env HOME=/home/retro xdg-mime query default x-scheme-handler/https)"

echo "── 9. 沙箱 URL 桥接 ──"
for f in /usr/local/bin/url-bridge-daemon.sh \
         /usr/local/bin/url-bridge-start.sh \
         /usr/local/share/url-bridge/xdg-open-sandbox-proxy \
         /opt/gow/startup.d/91-url-bridge.sh; do
  [ -e "$f" ] && echo "    ✓ $f" || { echo "    ✗ 缺失 $f"; ok=0; }
done
grep -q "chromium-open" /usr/local/bin/url-bridge-daemon.sh \
  && echo "    ✓ daemon 默认调用 chromium-open" \
  || { echo "    ✗ daemon 未指向 chromium-open"; ok=0; }

# 功能测试：FIFO → 假浏览器脚本，URL 必须原样送达
cat > /tmp/fake-browser <<"FAKE"
#!/bin/sh
printf "%s\n" "$@" > /tmp/fake-browser-args
FAKE
chmod +x /tmp/fake-browser
rm -f /tmp/ub.fifo /tmp/ub.pid /tmp/ub.log /tmp/fake-browser-args
URL_BRIDGE_FIFO=/tmp/ub.fifo URL_BRIDGE_PID=/tmp/ub.pid URL_BRIDGE_LOG=/tmp/ub.log \
  URL_BRIDGE_BROWSER=/tmp/fake-browser \
  setsid /usr/local/bin/url-bridge-daemon.sh >/dev/null 2>&1 &
sleep 2
if [ -p /tmp/ub.fifo ]; then
  printf "%s\n" "https://example.com/b?x=1&y=2" > /tmp/ub.url
  timeout 5 sh -c "cat /tmp/ub.url > /tmp/ub.fifo" 2>/dev/null || true
  sleep 2
  if grep -q "https://example.com/b?x=1&y=2" /tmp/fake-browser-args 2>/dev/null; then
    echo "    ✓ FIFO 链路把 URL 原样送达浏览器脚本（& 保留）"
  else
    echo "    ✗ FIFO 链路未送达 URL"; ok=0
  fi
  [ -f /tmp/ub.pid ] && kill "$(cat /tmp/ub.pid)" 2>/dev/null || true
else
  echo "    ✗ FIFO 未创建"; ok=0
fi
rm -f /tmp/ub.fifo /tmp/ub.pid /tmp/ub.log /tmp/ub.url /tmp/fake-browser /tmp/fake-browser-args

echo "── 10. Mesa 版本（顺带）──"
dpkg-query -W -f="\${Version}\n" mesa-vulkan-drivers:amd64 2>/dev/null | sed "s/^/    /"

echo
if [ "$ok" = 1 ]; then echo "✔ 全部通过"; else echo "✗ 有检查失败"; exit 1; fi
'
rc=$?
echo "════════ 验证结束 (exit=$rc) ════════"
cp -f "$LOCAL_VOL/.config/mimeapps.list" "$WORKDIR/日志/验证卷-chromium-钩子结果.txt" 2>/dev/null || true
rm -rf "$LOCAL_VOL"
exit $rc
