# ═══════════════════════════════════════════════════════════════════════════
# gameonwhales/lutris:kaijuu + Chromium 直连（Mesa 25.3.3+git 固化版）
#
# 原 kaijuu 层：
#     FROM gameonwhales/lutris:edge
#     RUN apt-get update && apt-get install -y libglew-dev steam && rm -rf /var/lib/apt/lists/*
#
# 本文件在其上固化两件事：
#   1) Mesa 25.3.3+git（AMD RADV；DLSSNR-AMD 需要 cooperative_matrix / float8）
#   2) 浏览器直连 Chromium：战网等 Wine 程序点击"使用浏览器验证"时，
#      xdg-open 直接拉起共享盘里的 Chromium AppImage，**不再弹选择器**
#      （旧的 browser-picker 已移除，见 git 历史）
#
# ⚠ 关键设计约束（否则固化了也会失效）
#   Wolf 启动会话容器时会用**卷覆盖**下列路径：
#       /home/retro              ← 宿主 <会话目录>/Lutris
#       /home/retro/.config      ← 宿主 var/lutris/.config
#       /home/retro/.local       ← 宿主 var/lutris/.local
#       /var/lutris              ← 宿主 var/lutris
#   写在这些路径下的镜像文件会被挂载**遮蔽**（看不到）。
#   因此本文件把内容放在：
#       /usr/local/bin/chromium-open             直连脚本本体
#       /usr/share/applications/chromium.desktop URL handler 注册
#       /etc/xdg/mimeapps.list                   系统级默认（XDG_CONFIG_DIRS）
#       /opt/gow/startup.d/90-chromium-default.sh 启动钩子（retro 身份，被 source）
#       /usr/local/bin/url-bridge-*.sh           沙箱 URL 桥接（Battle.net）
#       /opt/gow/startup.d/91-url-bridge.sh      桥接启动钩子
#   启动钩子负责清掉旧卷里的 picker 残留，并把用户级 ~/.config/mimeapps.list
#   校正为 chromium.desktop，实现「每次开机自愈」。
#
# 构建：
#     docker build -t gameonwhales/lutris:kaijuu .
# 运行：交给 Wolf 调度（镜像名填 gameonwhales/lutris:kaijuu）
# ═══════════════════════════════════════════════════════════════════════════

FROM gameonwhales/lutris:edge

LABEL org.opencontainers.image.title="gow-lutris-kaijuu-chromium-mesa" \
      org.opencontainers.image.description="kaijuu + direct Chromium handler + Mesa 25.3.3+git" \
      org.opencontainers.image.source="local"

# ── 1. 原 kaijuu 层（保持不变）────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y \
        libglew-dev steam && \
    rm -rf /var/lib/apt/lists/*

# ── 2. 依赖：URL 关联与证书 ───────────────────────────────────────────────
#   desktop-file-utils  —— update-desktop-database（生成 mimeinfo.cache）
#   xdg-utils           —— xdg-open / xdg-mime / xdg-settings
#   ca-certificates     —— https 页面根证书（战网登录页）
#   注：zenity 由 edge 基础镜像自带（Steam 弹窗仍会用到），不在此显式安装。
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        desktop-file-utils \
        xdg-utils \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# ── 2.5 Mesa 25.3.3+git（AMD RADV；DLSSNR-AMD 需要 cooperative_matrix / float8）──
#   来源：ernstp/mesarc PPA（plucky 已有 25.3.3+git2601081810.5bf1a7784af~p~mesarc2）
#   ⚠ 先补 libwayland 1.24：Mesa 25.3.3 的 mesa-vulkan-drivers 声明
#     libwayland-client0 (>= 1.24.0)，而 Ubuntu 25.04 只有 1.23.1。
#     若用 dpkg --force-depends 硬装会掩盖依赖，导致 Wayland 显示时
#     libvulkan_radeon.so 找不到 wl_display_dispatch_queue_timeout 而崩溃。
#     故从 Ubuntu 25.10（questing）池取 libwayland 1.24.0 + libxml2-16 先装上，
#     再用 apt 正常解析依赖安装整套 Mesa（amd64 + i386）。
#   验证：dpkg 版本 25.3.3+git…；libwayland 符号存在；apt-get check 无破损。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        software-properties-common curl ca-certificates; \
    add-apt-repository -y ppa:ernstp/mesarc; \
    apt-get update; \
    mkdir -p /tmp/wl && cd /tmp/wl; \
    pool=http://archive.ubuntu.com/ubuntu/pool/main; \
    for f in \
        libxml2-16_2.14.5+dfsg-0.2_amd64.deb \
        libwayland-client0_1.24.0-1build1_amd64.deb \
        libwayland-client0_1.24.0-1build1_i386.deb \
        libwayland-server0_1.24.0-1build1_amd64.deb \
        libwayland-server0_1.24.0-1build1_i386.deb \
        libwayland-egl1_1.24.0-1build1_amd64.deb \
        libwayland-egl1_1.24.0-1build1_i386.deb \
        libwayland-cursor0_1.24.0-1build1_amd64.deb \
        libwayland-cursor0_1.24.0-1build1_i386.deb \
        libwayland-bin_1.24.0-1build1_amd64.deb \
        libwayland-dev_1.24.0-1build1_amd64.deb ; do \
        case "$f" in \
            libxml2-16*) base="$pool/libx/libxml2" ;; \
            *)           base="$pool/w/wayland" ;; \
        esac; \
        curl -fsSLO "$base/$f"; \
    done; \
    dpkg -i libxml2-16_*.deb libwayland-*.deb; \
    ldconfig; \
    apt-get install -y --no-install-recommends \
        mesa-libgallium mesa-libgallium:i386 \
        libgl1-mesa-dri libgl1-mesa-dri:i386 \
        libegl-mesa0 libegl-mesa0:i386 \
        libglx-mesa0 libglx-mesa0:i386 \
        libgbm1 libgbm1:i386 \
        mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
        mesa-va-drivers mesa-va-drivers:i386; \
    apt-get check; \
    dpkg-query -W -f='${Version}\n' mesa-vulkan-drivers | grep -Eq '^25\.3\.3\+git'; \
    dpkg-query -W -f='${Version}\n' mesa-vulkan-drivers:i386 | grep -Eq '^25\.3\.3\+git'; \
    nm -D /usr/lib/x86_64-linux-gnu/libwayland-client.so.0 | \
        grep -q wl_display_dispatch_queue_timeout; \
    rm -rf /tmp/wl; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    echo "Mesa 25.3.3+git（amd64+i386）固化完成"

# ── 3. 固化文件 ───────────────────────────────────────────────────────────
COPY context/chromium-open           /usr/local/bin/chromium-open
COPY context/chromium.desktop        /usr/share/applications/chromium.desktop
COPY context/mimeapps.list           /etc/xdg/mimeapps.list
COPY context/90-chromium-default.sh  /opt/gow/startup.d/90-chromium-default.sh

RUN chmod 0755 /usr/local/bin/chromium-open \
               /opt/gow/startup.d/90-chromium-default.sh && \
    chmod 0644 /etc/xdg/mimeapps.list \
               /usr/share/applications/chromium.desktop && \
    update-desktop-database /usr/share/applications 2>/dev/null || true

# ── 3.5 沙箱 URL 桥接（Battle.net 在 pressure-vessel 内）──────────────────
#   战网等 Wine 程序跑在 umu/Proton 的 pressure-vessel 沙箱里，沙箱内的
#   xdg-open 是 steam-runtime-urlopen，根本不走容器的 mimeapps。
#   桥接做法：把沙箱内的 xdg-open 换成代理，URL 写进按会话隔离的 FIFO，
#   由沙箱外的守护进程读取后调用 chromium-open。
#   91-url-bridge.sh 在会话启动时（retro 身份、Lutris 之前）幂等部署并拉起。
COPY sandbox-bridge/url-bridge-daemon.sh      /usr/local/bin/url-bridge-daemon.sh
COPY sandbox-bridge/url-bridge-start.sh       /usr/local/bin/url-bridge-start.sh
COPY sandbox-bridge/xdg-open-sandbox-proxy    /usr/local/share/url-bridge/xdg-open-sandbox-proxy
COPY context/91-url-bridge.sh                 /opt/gow/startup.d/91-url-bridge.sh

RUN chmod 0755 /usr/local/bin/url-bridge-daemon.sh \
               /usr/local/bin/url-bridge-start.sh \
               /usr/local/share/url-bridge/xdg-open-sandbox-proxy \
               /opt/gow/startup.d/91-url-bridge.sh

# ── 4. 浏览器本体：不在镜像里 ─────────────────────────────────────────────
#   Chromium 用共享盘上的 AppImage（运行时挂载 /mnt/WD4/public）：
#       /mnt/WD4/public/software/linux/Chromium-stable-*.AppImage
#   chromium-open 会自动选版本号最新的那个；也可用环境变量覆盖：
#       CHROMIUM=/path/to/chromium   APP_DIR=/path/to/dir
#   如需镜像自带浏览器（不依赖共享盘），可自行下载 AppImage/压缩包到
#   /opt/browsers 并把 chromium-open 的 APP_DIR 默认值改过去。

# ── 5. 自检（构建期快速验收，失败即构建失败）──────────────────────────────
RUN set -eux; \
    test -x /usr/local/bin/chromium-open; \
    test -s /usr/share/applications/chromium.desktop; \
    test -s /etc/xdg/mimeapps.list; \
    test -x /opt/gow/startup.d/90-chromium-default.sh; \
    grep -q 'x-scheme-handler/https=chromium.desktop' /etc/xdg/mimeapps.list; \
    grep -q 'x-scheme-handler/http=chromium.desktop' /etc/xdg/mimeapps.list; \
    grep -q 'text/html=chromium.desktop' /etc/xdg/mimeapps.list; \
    grep -q 'Exec=/usr/local/bin/chromium-open %u' /usr/share/applications/chromium.desktop; \
    test ! -e /usr/local/bin/browser-picker; \
    test ! -e /usr/share/applications/browser-picker.desktop; \
    bash -n /usr/local/bin/chromium-open; \
    bash -n /opt/gow/startup.d/90-chromium-default.sh; \
    test -x /usr/local/bin/url-bridge-daemon.sh; \
    test -x /usr/local/bin/url-bridge-start.sh; \
    test -s /usr/local/share/url-bridge/xdg-open-sandbox-proxy; \
    test -x /opt/gow/startup.d/91-url-bridge.sh; \
    grep -q 'CHROMIUM\|chromium-open' /usr/local/bin/url-bridge-daemon.sh; \
    command -v xdg-open >/dev/null; \
    command -v update-desktop-database >/dev/null; \
    dpkg-query -W -f='${Version}' mesa-vulkan-drivers | grep -q '^25\.3\.3+git'; \
    dpkg-query -W -f='${Version}' mesa-vulkan-drivers:i386 | grep -q '^25\.3\.3+git'; \
    nm -D /usr/lib/x86_64-linux-gnu/libwayland-client.so.0 | \
        grep -q wl_display_dispatch_queue_timeout; \
    echo "Chromium 直连 + Mesa 25.3.3+git 固化自检通过"
