#!/usr/bin/env bash
# 一键构建「kaijuu + Chromium 直连 + Mesa 25.3.3+git」镜像
#
# 用法：./build.sh [镜像标签]
#   默认标签：gameonwhales/lutris:kaijuu
set -euo pipefail

TAG="${1:-gameonwhales/lutris:kaijuu}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "▶ 构建上下文: $HERE"
echo "▶ 目标标签  : $TAG"

# 构建前本地自检（与 Dockerfile 内自检呼应，失败即中止，避免烤出坏镜像）
for f in "$HERE/context/chromium-open" \
         "$HERE/context/chromium.desktop" \
         "$HERE/context/mimeapps.list" \
         "$HERE/context/90-chromium-default.sh" \
         "$HERE/context/91-url-bridge.sh" \
         "$HERE/sandbox-bridge/url-bridge-daemon.sh" \
         "$HERE/sandbox-bridge/url-bridge-start.sh" \
         "$HERE/sandbox-bridge/xdg-open-sandbox-proxy"; do
  [ -s "$f" ] || { echo "✗ 缺失或为空: $f" >&2; exit 1; }
done
bash -n "$HERE/context/chromium-open"
bash -n "$HERE/context/90-chromium-default.sh"
sh -n "$HERE/sandbox-bridge/url-bridge-daemon.sh"
sh -n "$HERE/sandbox-bridge/url-bridge-start.sh"
sh -n "$HERE/sandbox-bridge/xdg-open-sandbox-proxy"
grep -q 'chromium-open' "$HERE/sandbox-bridge/url-bridge-daemon.sh" \
  || { echo "✗ url-bridge-daemon.sh 未指向 chromium-open" >&2; exit 1; }
grep -q 'x-scheme-handler/https=chromium.desktop' "$HERE/context/mimeapps.list" \
  || { echo "✗ mimeapps.list 内容不符" >&2; exit 1; }
grep -q 'Exec=/usr/local/bin/chromium-open %u' "$HERE/context/chromium.desktop" \
  || { echo "✗ chromium.desktop 内容不符" >&2; exit 1; }
# 旧选择器文件不应再出现在构建上下文里
if [ -e "$HERE/context/browser-picker" ] \
   || [ -e "$HERE/context/browser-picker.desktop" ] \
   || [ -e "$HERE/context/90-browser-picker.sh" ]; then
  echo "✗ 构建上下文里仍有 browser-picker 残留（应已移除，见 git 历史）" >&2
  exit 1
fi
echo "✓ 上下文自检通过"

docker build -t "$TAG" "$HERE"

echo
echo "✔ 构建完成: $TAG"
cat <<EOF

下一步：
  1) 让 Wolf 用这个镜像启动 Lutris 会话（把会话镜像名改成 $TAG）
  2) 进入容器后验证（宿主机执行）：
       docker exec -u retro <容器> sh -c 'cat ~/.config/mimeapps.list; xdg-mime query default x-scheme-handler/https'
     期望：三个 http/https/text/html 键都指向 chromium.desktop
  3) 战网里点「使用浏览器完成验证」→ 应直接拉起 Chromium（不再弹选择器）

提示：
  * Chromium AppImage 在宿主共享盘：/mnt/WD4/public/software/linux/Chromium-stable-*.AppImage
  * 换可执行文件/目录：在容器里设 CHROMIUM=/path 或 APP_DIR=/path
  * 想停用启动自愈：touch ~/.config/chromium-default.no-autofix
EOF
