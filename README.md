# gameonwhales/lutris:kaijuu —— Chromium 直连 + 沙箱 URL 桥接 + Mesa 26.2.4+git

在 Games-on-Whales `gameonwhales/lutris:edge` 之上固化 Battle.net 网页登录所需的浏览器链路，
并升级 Mesa 到 **26.2.4+git**（AMD RADV，含 `VK_KHR_cooperative_matrix` / `VK_EXT_shader_float8`）。

> 历史：本仓库早期版本使用「浏览器选择器（browser-picker）」；现方案已移除 picker，
> 改为**直接拉起 Chromium**。旧实现仍可在 git 历史中查看。

## 解决什么问题

- 战网点「使用浏览器完成验证」没反应；
- 战网跑在 umu/Proton 的 **pressure-vessel 沙箱**里，沙箱内的 `xdg-open`
  是 `steam-runtime-urlopen`，只尝试 Steam 管道/D-Bus portal，两者在 Wolf 环境都不可用；
- 需要给 DLSSNR-AMD 等新 Vulkan 程序提供 Mesa 26.2.4+ 的扩展；
- 不再需要用户选浏览器：直接用 Chromium。

## 方案

```
Wine / Battle.net
   └─ winebrowser.exe
        └─ xdg-open
             ├─ 沙箱内：xdg-open 代理
             │    └─ 写 FIFO（按 WOLF_SESSION_ID 隔离）
             │         └─ url-bridge-daemon（沙箱外）
             │              └─ /usr/local/bin/chromium-open
             │                   └─ /mnt/WD4/public/software/linux/Chromium-stable-*.AppImage
             └─ 沙箱外：xdg-open
                  └─ chromium.desktop
                       └─ /usr/local/bin/chromium-open
```

启动时（`/opt/gow/startup.d/`，retro 身份、Lutris 之前、被 source）：

| 钩子 | 作用 |
|---|---|
| `90-chromium-default.sh` | 清理旧卷里的 picker 残留；把 `~/.config/mimeapps.list` 校正为 `chromium.desktop`（保留 discord 等关联） |
| `91-url-bridge.sh` | 把沙箱代理装进各 Proton 的 `bin/`，并按会话拉起 `url-bridge-daemon.sh` |

**为什么不能把文件放 `$HOME`**：Wolf 启动会话容器时用卷覆盖
`/home/retro`、`/home/retro/.config`、`/home/retro/.local`、`/var/lutris`，
放进去会被遮蔽。因此所有固化内容都在 `/usr/local`、`/usr/share`、`/etc/xdg`、`/opt/gow`。

## 仓库结构

```
├── Dockerfile                     # 镜像：原 kaijuu 层 + Mesa 26.2.4+git + Chromium 直连 + 沙箱桥接
├── context/
│   ├── chromium-open              → /usr/local/bin/chromium-open
│   ├── chromium.desktop           → /usr/share/applications/chromium.desktop
│   ├── mimeapps.list              → /etc/xdg/mimeapps.list
│   ├── 90-chromium-default.sh     → /opt/gow/startup.d/（开机自愈）
│   └── 91-url-bridge.sh           → /opt/gow/startup.d/（桥接启动）
├── sandbox-bridge/
│   ├── url-bridge-daemon.sh       → /usr/local/bin/（FIFO → chromium-open）
│   ├── url-bridge-start.sh        → /usr/local/bin/（部署代理 + 拉起 daemon）
│   ├── xdg-open-sandbox-proxy     → /usr/local/share/url-bridge/（沙箱内代理）
│   ├── install-bridge.sh          # 运行中容器的桥接修复（可选）
│   └── sway-custom-cfg            # 运行时装法的 sway 自启片段（可选）
├── build.sh                       # 构建（含上下文自检）
├── verify-chromium.sh             # 验证 Chromium 链路 + 旧卷迁移 + 沙箱 FIFO
├── verify-mesa.sh                 # 验证 Mesa 26.2.4+git（真实 GPU）
└── screenshots/                   # 01 修复前 / 03 登录完成
```

## 构建

```bash
docker build -t gameonwhales/lutris:kaijuu .
# 或
./build.sh
```

Mesa 层说明（`Dockerfile` §2.5）：

- Mesa `26.2.4+git2610011653.9a0169f2a72~r~mesarc0`，来自 `ernstp/mesarc` 的 **resolute(26.04)** 源；
- Mesa 26.2 需要 **libc6 >= 2.43 / libllvm22**，从 Ubuntu resolute 归档安装；
- RADV 需要 **libdrm 2.4.134+**（plucky 的 2.4.124 会让 `amdgpu_query_sw_info` 初始化失败）；
- `libwayland` 仍从 questing 池补 1.24（plucky 只有 1.23.1）；
- 因此这是**跨发行版升级**（libc/locales 到 resolute），只发生在镜像内；已实测 RADV GFX1200 正常、`apt-get check` 无破损。
- 不要用 `dpkg --force-depends` 绕过依赖。

## 使用

- Wolf / Lutris 的镜像名直接使用 `gameonwhales/lutris:kaijuu`；
- 换 Chromium 路径：容器内设 `CHROMIUM=/path/to/chromium`；
- 换共享盘目录：设 `CHROMIUM_DIR=/path/to/dir`
  （**不要用 `APP_DIR`**：GOW 容器里已导出 `APP_DIR=/opt/gow/app`，会把默认路径顶掉）；
- 启动参数：`--no-sandbox <url>`（**不加 `--new-window`**，复用已有 Chromium 窗口/标签页）；
- 停用开机自愈：`touch ~/.config/chromium-default.no-autofix`。

## 验证

```bash
./verify-chromium.sh   # 需要本机 docker
./verify-mesa.sh       # 需要宿主 /dev/dri（真实 GPU）
```

实测（2026-10-19）：

| 检查 | 结果 |
|---|---|
| 固化文件就位；旧 picker 三件套不存在 | ✅ |
| `xdg-open → chromium.desktop → chromium-open` | ✅ |
| URL（含 `&`）原样传递 | ✅ |
| 启动参数不含 `--new-window` | ✅ |
| 旧卷迁移：picker 关联 → `chromium.desktop`，discord 保留，picker 残留清除 | ✅ |
| 旧用户级 `chromium.desktop`（Exec 无 `%u`，会吞 URL）被清除 | ✅ |
| GOW 的 `APP_DIR=/opt/gow/app` 污染下仍能定位 Chromium（用私有 `CHROMIUM_DIR`） | ✅ |
| 沙箱桥接：FIFO → `chromium-open`，URL 原样送达 | ✅ |
| Chromium AppImage `--version` = 152.0.7977.64 | ✅ |
| Mesa 26.2.4+git（RADV GFX1200 / RENOIR）+ 两个扩展 | ✅ |

## 关键坑

1. **卷覆盖**：`$HOME` 下的固化文件会被 Wolf 的卷遮蔽，必须放系统目录。
2. **pressure-vessel**：没有 FIFO 桥接，战网的 URL 根本出不了沙箱。
3. **按会话隔离**：多会话共用宿主 `var/lutris/.local`，FIFO/pidfile 必须带
   `WOLF_SESSION_ID`，否则抢读、串台。
4. **Mesa/libwayland**：先升 libwayland 1.24，再 apt 装 Mesa；`--force-depends` 会留下
   `wl_display_dispatch_queue_timeout` 未定义符号，Wayland 显示时才炸。
5. **旧 chromium.desktop 吞 URL**：用户卷里若残留
   `Exec=...AppImage --no-sandbox --new-window`（没有 `%u`），xdg-open 会打开 Chromium
   但不带 URL；`90-chromium-default.sh` 会删除它，让镜像里的
   `/usr/share/applications/chromium.desktop`（含 `%u`）生效。
6. **GOW 的 `APP_DIR` 污染**：容器里已导出 `APP_DIR=/opt/gow/app`（GOW 自用），
   浏览器路径**不能**用 `${APP_DIR:-...}`，否则会去 `/opt/gow/app` 找 Chromium 并失败；
   `chromium-open` 使用私有变量 `CHROMIUM_DIR`。
7. **URL 传参**：一律用 `"$URL"` 独立参数，不能字符串拼接（`&` 会被 shell 破坏）。
8. **验证脚本的挂载**：`docker run -v` 的源路径由宿主机解析，脚本内置了容器路径→宿主路径换算。
9. **retro 用户是运行时创建的**（cont-init 会先删掉基础镜像里的 `ubuntu` 用户），
   验证脚本直接 source 镜像内真实的 `10-setup_user.sh`。

## 历史与迁移

- 早期版本：`browser-picker`（zenity 选择器）+ 沙箱桥接；
- 现在：桥接保留，FIFO 的消费端从 picker 改为 `chromium-open`；
- 旧卷里的 picker desktop/conf 会被 `90-chromium-default.sh` 自动清理。

## License

未添加 LICENSE（由仓库所有者决定）。
