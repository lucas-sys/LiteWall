# LiteWall · 轻壁纸

面向 macOS 的轻量化动态壁纸宿主，用 Swift / AppKit 实现，兼容 Wallpaper Engine 的 **web 类壁纸格式**（`project.json` + HTML/Canvas）与其 10 项 `window.wallpaper*` 作者 API，同时支持视频与静态图壁纸。无 Dock 图标、无 Electron、无后台常驻服务，仅一个菜单栏图标。

> **关于 REA 的定位**：REA 是逆向分析工具，不是应用框架。本项目用 REA 做的事是**验证壁纸格式与运行时契约**（静态分析壁纸包、提取作者脚本依赖的宿主 API），产品本体用原生 Swift 编写。本机没有 Wallpaper Engine 的 Windows 二进制或 workshop 壁纸包，因此**没有对 WE 程序本体做逆向**；完整的证据边界见 [`docs/REA-FINDINGS.md`](docs/REA-FINDINGS.md)。

---

## 1. 快速开始

环境要求：macOS 13+、Xcode Command Line Tools（**不需要完整 Xcode**）。`build.sh` 默认以 `arm64-apple-macosx13.0` 为目标；在 Intel Mac 上使用时请把 `-target` 改为 `x86_64-apple-macosx13.0`。

```bash
cd LiteWall                        # 或 clone 后的仓库目录
./tools/install.sh               # 构建 + 安装到 ~/Applications + 注册开机自启（推荐）
open ~/Applications/LiteWall.app # 手动启动（菜单栏出现照片图标）
```

退出：点击菜单栏图标 → 「退出 LiteWall」，或 `osascript -e 'tell application "LiteWall" to quit'`。

只构建、不安装时可用 `./build.sh` 生成 `build/LiteWall.app` 并 `open build/LiteWall.app`；但 `build.sh` 每次会重建该目录，**长期运行建议用 `~/Applications` 中的安装副本**。

### 启动与开机自启

`tools/install.sh` 做四件事：构建 → 复制 App 到 `~/Applications/LiteWall.app` → 写入 `~/Library/LaunchAgents/dev.litewall.LiteWall.plist` → `launchctl bootstrap` 加载到当前会话（立即启动一次）。**下次登录会自动启动**。

| 目的 | 命令 / 操作 |
|---|---|
| 启动 | `open ~/Applications/LiteWall.app` |
| 开机自启（推荐） | `./tools/install.sh` |
| 关闭自启 | `./tools/install.sh --uninstall` 或菜单栏取消勾选「开机自启」 |
| 检查是否在运行 | `pgrep -x LiteWall` |
| 检查登录项 | `launchctl print "gui/$(id -u)/dev.litewall.LiteWall" \| head` |

> `launchctl print` 显示 `state = not running` 是正常的：这个 job 只是一次性执行 `/usr/bin/open`，命令结束即完成，App 由 launchd 独立托管。判断 App 是否在跑请用 `pgrep -x LiteWall`。

**为什么用 LaunchAgent 而不是 SMAppService**：本项目是 ad-hoc 签名且默认位于 `build/`，`SMAppService.mainApp.register()` 在此条件下会失败。每用户 LaunchAgent plist 不需要 Apple 签名或管理员权限，用 `plutil -p` / `launchctl print` 就能直接检查，macOS「系统设置 → 通用 → 登录项与扩展」里也会显示。

菜单栏的「开机自启」开关与脚本写的是**同一个 plist**，勾选状态以文件是否存在为准，改完在下次登录生效。App 内置单实例保护：手动启动与登录项叠加、或 `open -n` 强制新实例，都只会保留一个进程，不会出现双份桌面窗口。

> 登录项设置为 `RunAtLoad=true` / `KeepAlive=false`，即**只在登录时启动一次**；中途手动退出 App 不会自动把它拉回来，这是有意的轻量化取舍。若希望退出后自动重启，把 plist 的 `KeepAlive` 改为 `true`。

### 分发包怎么选：DMG / ZIP / 一键脚本

| 方式 | 适用 | 判断 |
|---|---|---|
| `./tools/install.sh` | **自己用，推荐** | 一条命令完成构建 + 装到 `~/Applications` + 注册登录项。比 DMG 多做了自启注册，也不受 Gatekeeper 影响 |
| `LiteWall-1.0.0.dmg` | 发给别人 | 打开后把 App 拖进 Applications，最符合 macOS 使用习惯 |
| `LiteWall-1.0.0-macOS.zip` | CI / 网盘 / 自动化 | 纯文件包，解压即用 |
| `.pkg` | 无人值守装登录项 | 未做：pkg 可跑 `postinstall` 自动写 LaunchAgent，但对签名要求更高，对单文件工具收益有限 |

**APK 与 macOS 无关**：APK 是 Android 应用包格式，不能用于 macOS；macOS 原生分发形态是 `.app` / `.dmg` / `.pkg`。

**DMG 的局限**：本包为 ad-hoc 签名，没有 Apple Developer ID，因此**无法做开发者签名与公证**。从网络下载后 macOS 会加隔离属性并提示「无法验证开发者」，需右键 → 「打开」，或执行 `xattr -dr com.apple.quarantine /Applications/LiteWall.app`。DMG 也无法运行安装脚本，**不会自动注册开机自启**，装好后在菜单栏勾选即可。

生成：`./tools/make-dmg.sh`。因此结论是——本机自用没必要做安装包，`install.sh` 已经更完整；要对外分发，DMG 值得做，主要买的是「拖拽安装」的熟悉体验，而不是功能。

一键验证（编译 + shim 运行时契约 + 桌面窗口层级）：

```bash
./verify.sh
```

### 壁纸库位置

```
~/Library/Application Support/LiteWall/Wallpapers/
```

首次启动会把内置的三张壁纸播种过去。之后每次启动会用 App 包内的版本**刷新壁纸代码与清单**（`app.js` / `style.css` / `index.html` / `manifest.js`），但 `project.json` 只在缺失时播种、**永不覆盖**——壁纸的功能更新能生效，你调过的属性也不会丢。生成物 `images/` 仅在缺失时复制，避免每次启动搬运几十 MB。

把一个壁纸文件夹（或单个 mp4 / 图片）放进去，再从菜单栏「重新扫描壁纸」即可加载；也可以在 `config.json` 的 `extraLibraryPaths` 中追加其他目录。

### 《凡人女修》轮播壁纸（内置，已设为默认）

由素材目录下 47 张角色立绘生成，位于 `Wallpapers/凡人女修/`。素材图片本身不入库（`images/` 为生成物），clone 后按下方命令生成本地副本。

- **视觉**：双层交叉淡入 + 缓慢推移（Ken Burns）、模糊衬底填充留白。**默认纯净模式**——题名、朱红印章、角色名、计数、进度线全部隐藏，画面只有立绘。

![《凡人女修》轮播壁纸预览（纯净模式）](docs/preview-fanren.png)

- **8 项 WE 用户属性**：题名、停留秒数（2–300 秒，默认 12）、过渡秒数（0.3–5，默认 1.6）、朱印色、缓慢推移、模糊衬底、**显示文字**（`showtext`，默认 `false`）、随机次序。
- **切换频率在菜单栏直接选**：菜单栏图标 → 「壁纸切换间隔」→ 5 / 10 / 15 / 20 / 30 / 60 / 120 秒，**实时生效、无需重新选壁纸**，并写入 `config.json` 持久化。该菜单项只在壁纸声明了 `interval` 属性时出现；底层走通用的 `__weBridge.applyProperties` 通道，不重建渲染器。

> **如何改其他属性**：App 实际加载的是用户壁纸库中的副本 `~/Library/Application Support/LiteWall/Wallpapers/凡人女修/project.json`，**不是**项目源码里的那份。把 `general.properties.showtext.value` 改为 `true` 可恢复文字；编辑后在菜单栏「重新扫描壁纸」并重新点选一次《凡人女修》即可生效。`project.json` 首次播种后不会被覆盖，壁纸代码文件则由 App 每次启动自动刷新。

手动同步项目里改过的壁纸代码 / 素材到用户库（保留 `project.json`）：

```bash
rsync -a --exclude=project.json "Wallpapers/凡人女修/" \
  "$HOME/Library/Application Support/LiteWall/Wallpapers/凡人女修/"
```
- **实现要点**：帧清单 `manifest.js` 由脚本生成并用 `<script>` 加载（`file://` 下 fetch/XHR 会被拒绝）；图片重命名为 ASCII 文件，避免中文与空格的 URL 编码问题；切换前预加载单帧、坏图自动跳过；`setPaused` 同时暂停计时器与 CSS 动画；另有一层不依赖合成器时钟的终值兜底，避免桌面窗口被系统节流时停在透明状态。

生成或更新素材（原图 5504×3072、共 111 MB → 2560 宽 JPEG、共 34.2 MB）：

```bash
python3 tools/build-slideshow.py \
  --source "/你的/素材/目录" \
  --output "Wallpapers/凡人女修"
# 可选：--width 3200 --quality 88
```

往 `图/` 目录加新图片后重跑即可自动重排编号、更新角色名。`images/` 与 `manifest.js` 是生成物（已加入 `.gitignore`），手写的 `project.json` / `index.html` / `style.css` / `app.js` 不会被覆盖。重复角色会自动标为「· 其二 / 其三」，无后缀原图始终作为主名。

生成视觉预览：

```bash
./build/shim-probe "Wallpapers/凡人女修" "Sources/WEShim.js" /tmp/fanren.png
```

---

## 2. 功能与实现

| 能力 | 实现 |
|---|---|
| 桌面壁纸层级 | `NSWindow.Level = kCGDesktopWindowLevel + 1`，位于桌面背景之上、Finder 桌面图标之下；窗口 `ignoresMouseEvents = true`，完全点击穿透 |
| 多显示器 | 每个 `NSScreen` 独立窗口 + 独立渲染器，按 `CGDirectDisplayID` 跟踪，热插拔自动重建 |
| 所有空间 | `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]` |
| Web / Canvas 壁纸 | `WKWebView` + `WEShim.js`，在 `atDocumentStart` 阶段按 **seed → shim → 作者脚本** 顺序注入 |
| 视频壁纸 | `AVPlayer` + `AVPlayerLayer`，`AVPlayerItemDidPlayToEndTime` 无缝循环，默认静音 |
| 静态图 | 自定义 `NSView` 做 aspect-fill 绘制，无动画、近乎零 CPU |
| 省电 | 屏幕睡眠、以及检测到其他 App 全屏覆盖时自动暂停渲染；手动暂停与自动暂停状态互相独立 |
| 控制 | 菜单栏切换壁纸、暂停、音量（0/25/50/75/100%）、网页帧率上限（15/24/30/60）、开机自启、重新扫描 |

### 壁纸格式支持矩阵

| 类型 | 判定依据 | 状态 |
|---|---|---|
| `web` | `project.json` 的 `file` 指向 HTML，或目录含 `index.html` | ✅ 支持，含全部 10 项 WE 作者 API |
| `video` | 声明 `type: video` 且有视频文件；或目录中仅有视频 | ✅ mp4 / webm / mov / m4v / mkv（取体积最大者） |
| 静态图 | 目录中仅有图片 | ✅ jpg / png / heic / webp / gif / tiff |
| `scene` | 含 `scene.pkg` / `scene.json` / `*.pkg` | ❌ 专有二进制格式 + Windows 渲染器，显示明确占位提示而非黑屏 |
| `application` / `exe` / `app` | `project.json` 声明 | ❌ 一律拒绝加载（可执行文件永不挂载） |

判定采用**内容优先、声明仅作线索**的顺序（与 REA 分析所参照的格式文档一致），`declaredType` / `kindReason` / `mismatch` 仅用于诊断，不改变挂载行为。

### 已实现的 WE 作者 API

| API | 行为 |
|---|---|
| `wallpaperPropertyListener` | getter/setter；赋值后**微任务延迟**下发全量属性快照（`applyUserProperties`、`applyGeneralProperties`、`setPaused`），重复赋值不重放 |
| `wallpaperRegisterAudioListener` | 注册回调；**本机无音频频谱数据源，不伪造数据、不推送** |
| `wallpaperRegisterMedia{Properties,Thumbnail,Playback,Timeline,Status}Listener` | 5 个注册器；晚注册回放最近一帧 |
| `wallpaperRequestRandomFileForProperty` | 从壁纸目录内的图片/视频池随机返回；空池回调空串（对齐官方语义） |
| `wallpaperMediaIntegration` | `PLAYBACK_STOPPED/PLAYING/PAUSED = 0/1/2` |
| `wallpaperPluginListener` | `{ onPluginLoaded(){} }` 空实现 |

所有作者回调均被 `try/catch` 包裹，单张壁纸脚本抛错不会终止宿主进程。`window.__weBridge` 是 native 侧的控制入口（`setPaused` / `applyProperties` / `applyGeneral` / `setVolume` / `pushMedia` / `directoryAdded` 等）。

---

## 3. 项目结构

```
LiteWall/
├── Sources/
│   ├── App.swift                  @main、NSApplicationDelegate、观察者与定时器
│   ├── WallpaperEngine.swift      桌面层级窗口、多屏、渲染器生命周期
│   ├── WallpaperLibrary.swift     project.json 解析、内容优先类型判定
│   ├── Renderer.swift             渲染器协议
│   ├── WebRenderer.swift          WKWebView 宿主、seed/shim 注入、原生桥
│   ├── VideoRenderer.swift        AVPlayer 无缝循环
│   ├── ImageRenderer.swift        aspect-fill 静态图
│   ├── WEShim.js                  WE 作者 API 兼容层（注入脚本）
│   ├── StatusMenu.swift           菜单栏 UI、开机自启开关
│   ├── LaunchAtLogin.swift        每用户 LaunchAgent 登录项管理
│   ├── FullScreenDetector.swift   CGWindowList 全屏启发式
│   └── Settings.swift             配置持久化、内置壁纸播种
├── Wallpapers/
│   ├── Aurora Flow/               示例 web 壁纸（纯 Canvas）
│   ├── Particle Clock/            示例 web 壁纸（全 API 探针）
│   └── 凡人女修/                  47 帧轮播壁纸（含 images/ 生成物）
├── docs/
│   ├── REA-FINDINGS.md            REA 证据链与能力边界
│   ├── rea-aurora.evidence.json   REA Evidence bundle
│   ├── rea-particle-clock.evidence.json
│   └── preview-fanren.png         《凡人女修》纯净模式预览
├── tools/                         安装脚本、DMG 构建、验证探针、轮播素材构建脚本
├── Info.plist / build.sh / verify.sh / LICENSE
└── README.md
```

> 仓库内不含 `Wallpapers/凡人女修/images/`（34 MB 生成物）；帧清单 `manifest.js` 已随仓库提供。clone 后运行 `python3 tools/build-slideshow.py --source <素材目录>` 生成图片即可。

---

## 4. 已知限制

1. **Scene 壁纸不支持**：`scene.pkg` 是 WE 专有的二进制场景容器，需要逆向其格式与 Windows 渲染器，超出轻量化范围。
2. **无音频频谱数据源**：macOS 上获取系统音频需 ScreenCaptureKit / CoreAudio tap，会带来权限与显著开销；当前注册 listener 但不推送数据。依赖频谱的壁纸会退化为静态表现。
3. **`file:///` 绝对路径不兼容**：WE 壁纸常拼接 `'file:///' + "C:/Users/..."`，Windows 绝对路径在 macOS 无法映射。仅对不含路径分隔符的**相对文件名**做基于壁纸目录的解析。
4. **全屏检测是启发式**：基于 `CGWindowListCopyWindowInfo` 的窗口尺寸，接近全屏的「最大化窗口」可能被误判为全屏（只会导致提前暂停，不会在全屏后仍持续渲染）。
5. **WKWebView 存储**：`file://` 源下 `localStorage` 可能受 WebKit 安全策略限制；未实现第三方兼容层里的 storage facade。
6. **开机自启**：改用 `~/Library/LaunchAgents` 登录项而非 `SMAppService`（后者要求有效签名）。登录项只在登录时启动一次 App，`KeepAlive=false`，中途退出不会自动拉起；内置单实例保护可避免叠加启动。
7. **网页壁纸需自带背景**：未通过私有 KVC 关闭 WKWebView 的白色背景，改为在首次导航完成前隐藏视图以避免白闪。
8. **不读取网络内容**：壁纸通过 `loadFileURL(_:allowingReadAccessTo:)` 限制在自身目录内，跨域请求与远程资源按 WebKit 默认策略处理。

---

## 5. 用 REA 继续深入

如果你手上有真实的 WE workshop 壁纸包或 Windows 安装包，可以直接复用本项目的证据链方法：

```bash
# 分析一个 web 壁纸包的作者脚本依赖（不需要 Hopper / Ghidra）
PATH=/opt/homebrew/bin:/usr/bin:/bin rea analyze-javascript-application \
  "/absolute/path/to/wallpaper" \
  --detail summary \
  --evidence_output "/absolute/path/to/output.evidence.json" --format json

# 分析 Windows 安装包/归档的成员清单
PATH=/opt/homebrew/bin:/usr/bin:/bin rea open_binary "/absolute/path/to/setup.exe" ...
```

再从 Evidence 的 `records[0].normalized_result.semantic_graph.nodes` 中按 `label` 过滤 `read:/wallpaper*` 与 `write:/wallpaper*`，即可得到该壁纸实际依赖的宿主 API 与精确行号。`docs/REA-FINDINGS.md` 里有可直接复用的提取脚本思路与本次的 Evidence ID。

---

## 6. 合规说明

本项目**不包含 Wallpaper Engine 的任何二进制、代码或素材**。`project.json` 字段与 `window.wallpaper*` API 名称属于公开的创作者文档约定；三张内置壁纸的宿主代码、shim 与《凡人女修》轮播实现均为本项目原创（其立绘素材由使用者自行提供，不随仓库分发）。用途限定为本地格式兼容，不绕过任何软件的授权机制。

---

## 7. License

MIT，见 [LICENSE](LICENSE)。

仓库地址：<https://github.com/lucas-sys/LiteWall>
