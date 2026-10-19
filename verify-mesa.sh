#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# verify-mesa.sh —— 验证镜像内 Mesa 25.3.3+git（含真实 GPU 检查）
#
# 检查项：
#   1. amd64 / i386 的 mesa-vulkan-drivers 版本均为 25.3.3+git…
#   2. apt-get check 无未满足依赖（证明不是 --force-depends 硬装）
#   3. libwayland-client.so.0 含 wl_display_dispatch_queue_timeout（1.24+ 符号）
#   4. 真实 GPU（--device /dev/dri）下 vulkaninfo：
#        driverInfo = Mesa 25.3.3+git…，且带
#        VK_KHR_cooperative_matrix、VK_EXT_shader_float8
#
# 用法：./verify-mesa.sh [镜像名]
#   默认：gameonwhales/lutris:kaijuu
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

IMAGE="${1:-gameonwhales/lutris:kaijuu}"

echo "▶ 镜像: $IMAGE"
echo "▶ 本工作容器 /dev/dri: $(ls -d /dev/dri 2>/dev/null || echo 缺失)（--device 由宿主机解析，不影响 GPU 检查）"

docker run --rm --device /dev/dri --entrypoint bash "$IMAGE" -c '
set -u
ok=1
chk() { # chk <描述> <命令...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "    ✓ $desc"; else echo "    ✗ $desc"; ok=0; fi
}

echo "── 1. Mesa 版本 ──"
for p in mesa-vulkan-drivers:amd64 mesa-vulkan-drivers:i386 \
         libgl1-mesa-dri:amd64 libgl1-mesa-dri:i386 \
         mesa-libgallium:amd64 mesa-libgallium:i386 \
         libegl-mesa0:amd64 libegl-mesa0:i386 \
         libglx-mesa0:amd64 libglx-mesa0:i386 \
         libgbm1:amd64 libgbm1:i386 mesa-va-drivers:amd64 mesa-va-drivers:i386; do
  v="$(dpkg-query -W -f="\${Version}" "$p" 2>/dev/null || echo MISSING)"
  case "$v" in
    25.3.3+git*) printf "    ✓ %-28s %s\n" "$p" "$v" ;;
    *)           printf "    ✗ %-28s %s\n" "$p" "$v"; ok=0 ;;
  esac
done

echo "── 2. 依赖闭合 ──"
chk "apt-get check 无破损依赖" apt-get check

echo "── 3. libwayland 1.24 符号 ──"
chk "wl_display_dispatch_queue_timeout 存在" \
    bash -c "nm -D /usr/lib/x86_64-linux-gnu/libwayland-client.so.0 | grep -q wl_display_dispatch_queue_timeout"

echo "── 4. 真实 GPU / Vulkan ──"
if [ -e /dev/dri/renderD128 ]; then
  chk "vulkaninfo 能枚举设备" vulkaninfo --summary
  echo "    driverInfo / deviceName:"
  vulkaninfo --summary 2>/dev/null | grep -E "deviceName|driverInfo" | sed "s/^/      /" | head -12
  chk "RADV 报告 Mesa 25.3.3+git" \
      bash -c "vulkaninfo --summary 2>/dev/null | grep -q \"Mesa 25\.3\.3+git\""
  chk "VK_KHR_cooperative_matrix 存在" \
      bash -c "vulkaninfo 2>/dev/null | grep -q VK_KHR_cooperative_matrix"
  chk "VK_EXT_shader_float8 存在" \
      bash -c "vulkaninfo 2>/dev/null | grep -q VK_EXT_shader_float8"
else
  echo "    ! 容器内看不到 /dev/dri，跳过 GPU 检查"
fi

echo
if [ "$ok" = 1 ]; then echo "✔ 全部通过"; else echo "✗ 有检查失败"; exit 1; fi
'
