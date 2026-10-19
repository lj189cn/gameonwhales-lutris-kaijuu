#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# 90-chromium-default.sh —— GOW 启动钩子（固化于镜像）
#
# 执行时机：/opt/gow/startup-app.sh 以 retro 身份、在 Lutris 启动前 source。
#           父脚本带 set -e，故本文件内命令必须容错，且**禁止 exit**。
#
# 为什么需要：
#   Wolf 用卷覆盖 /home/retro/.config，用户级 ~/.config/mimeapps.list 会压过
#   镜像里的 /etc/xdg/mimeapps.list。旧卷里可能还留着 browser-picker 的关联
#   （选择器已从镜像移除，留着会指向不存在的 handler）。本钩子每次开机：
#     1. 删除旧选择器的用户级残留（desktop / conf / no-autofix）
#     2. 把 http/https/text/html 校正为 chromium.desktop，保留其他关联（如 discord://）
#
# 停用自愈：mkdir -p ~/.config 后 touch ~/.config/chromium-default.no-autofix
# ═══════════════════════════════════════════════════════════════════════════

_cd_home="${HOME:-/home/retro}"
_cd_dir="${_cd_home}/.config"
_cd_file="${_cd_dir}/mimeapps.list"

_cd_log() {
  if command -v gow_log >/dev/null 2>&1; then gow_log "[chromium-default] $*"; fi
}

# ── 清理旧选择器残留（用户卷里可能有）────────────────────────────────────
rm -f "${_cd_home}/.local/share/applications/browser-picker.desktop" \
      "${_cd_dir}/browser-picker.conf" \
      "${_cd_dir}/browser-picker.no-autofix" 2>/dev/null || true

if [ -f "${_cd_dir}/chromium-default.no-autofix" ]; then
  _cd_log "检测到 no-autofix，跳过 mimeapps.list 校正"
else
  if mkdir -p "${_cd_dir}" 2>/dev/null; then
    # 保留既有的非 http/https/html 关联
    _cd_keep=""
    if [ -f "${_cd_file}" ]; then
      _cd_keep="$(grep '=' "${_cd_file}" 2>/dev/null \
        | grep -vE '^(x-scheme-handler/(http|https)|text/html)=' || true)"
    fi

    _cd_tmp="${_cd_file}.tmp.$$"
    {
      echo "[Default Applications]"
      echo "x-scheme-handler/http=chromium.desktop"
      echo "x-scheme-handler/https=chromium.desktop"
      echo "text/html=chromium.desktop"
      if [ -n "${_cd_keep}" ]; then
        echo "${_cd_keep}"
      fi
    } > "${_cd_tmp}" 2>/dev/null

    if [ -s "${_cd_tmp}" ]; then
      mv -f "${_cd_tmp}" "${_cd_file}" 2>/dev/null \
        && _cd_log "mimeapps.list 已指向 chromium.desktop"
    fi
    rm -f "${_cd_tmp}" 2>/dev/null
  fi
fi

# 刷新用户级 desktop 数据库（卷里可能还有自定义 .desktop）
if [ -d "${_cd_home}/.local/share/applications" ] \
   && command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${_cd_home}/.local/share/applications" >/dev/null 2>&1 || true
fi

true
