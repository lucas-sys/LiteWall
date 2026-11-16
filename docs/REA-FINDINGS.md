# REA 调查记录：LiteWall 格式契约

**调查日期**：2026-11-06
**路径约定**：本文中的路径按仓库相对路径或 `<工作区>` 占位书写。
**目标问题**：为 macOS 轻量化动态壁纸宿主确定「必须复刻什么」——具体是 Wallpaper Engine 壁纸包的格式判定顺序，以及 web 壁纸作者脚本依赖的宿主 API 集合。
**结论性质**：本文严格区分 **观察（Evidence）**、**推断（设计决策）** 与 **未知（未覆盖）**。REA 只用于建立前两类的证据基础，产品实现由原生 Swift 完成。

---

## 1. 调查范围与问题清单

| # | 问题 | 所需证据 | 结论 |
|---|---|---|---|
| Q1 | 本机是否存在可逆向的 Wallpaper Engine 目标？ | 本地文件清单 | **否**，见 §2 |
| Q2 | macOS 壁纸子系统能否作为已发布二进制被静态分析？ | bundle 布局 / 二进制可达性 | **否**，见 §2 |
| Q3 | 本机 REA 具备哪些分析能力？ | `rea doctor --json` / `capabilities` | 仅静态 JS 路径可用，见 §3 |
| Q4 | web 壁纸作者脚本到底依赖哪些 `window.wallpaper*` API？ | REA 语义图（精确行号） | **已回答**，见 §5 |
| Q5 | `project.json` 的字段与类型判定顺序是什么？ | 官方公开文档 + 第三方兼容实现 | **部分回答**，见 §6 |
| Q6 | `scene.pkg` 场景格式能否复刻？ | 需要真实场景包 + native provider | **未解决**，明确不做 |

---

## 2. 目标解析（观察）

- Wallpaper Engine 是 Windows 平台 Steam 应用。对工作区、`~/Desktop`、`~/Downloads` 做名称匹配（`*wallpaper*`、`project.json`、`scene.json`）**无任何命中**；本机也没有 WE 的安装包或二进制。按 REA 的目标路由规则，没有目标就不能声称对 WE 程序本体做过逆向。
- `/System/Library/PrivateFrameworks/` 下确实存在 `Wallpaper.framework`、`WallpaperFoundation.framework`、`WallpaperServices.framework`、`WallpaperTypes.framework`、`WallpaperExtensionKit.framework` 等 10 个与壁纸相关的私有框架（**观察**）。但 `Wallpaper.framework/Versions/A/Wallpaper` 路径不存在，框架目录内只有指向 `Versions/Current` 的符号链接，没有独立 Mach-O 文件——在 macOS 27.2 上这些实现位于 dyld shared cache 中，磁盘上没有可供 `open_binary` 绑定的文件（**观察**）。
- 因此 **Q2 无法通过 native provider 回答**；本项目不使用任何私有壁纸 API，而是采用公开的 `CGWindowLevel` 桌面层级方案。`CGWindowLevelForKey(.desktopWindow) = -2147483623`、`.desktopIconWindow = -2147483603` 由本机 SDK 实测得到（**观察**）。

---

## 3. 环境诊断（观察）

`rea --version` = `6.8.0`（`/opt/homebrew/bin/rea`）。`rea doctor --json` 关键结果：

| 检查项 | 状态 | 说明 |
|---|---|---|
| `node` | `missing_dependency` | WorkBuddy 自带 Node 22.22.2，低于 REA 要求（≥22.23.4 / 24.x≥24.22.1 / 26.12.1+） |
| `host` | `healthy` | macOS 27.2 |
| `hopper` / `ghidra` / `ida-registration` / `jadx` / `kuna` | `missing_analysis_engine` | 均未安装或未配置 |
| `registration:claude_code` | `config_drift` | 本次执行的是 `rea doctor --json`（audit-wide 全客户端审计），报的是 claude_code 客户端的陈旧注册，**不代表 WorkBuddy 注册失效** |

**注册上下文**：本工作区此前已把 REA 注册为**项目级** MCP（`<工作区>/.workbuddy/mcp.json`），用户级 `~/.workbuddy/mcp.json` 仅保留 zotero；以 `HOME=<工作区> rea doctor --client workbuddy --skill --json` 校验为 healthy。但当前会话的工具列表中没有加载 REA MCP 工具（注册变更需新建会话 / 重启后生效），因此本次调查**全部走 CLI**。CLI 与 MCP 使用同一套分析引擎，Evidence 格式一致，不影响结论。

**处置**：所有 REA 命令显式前置 `PATH=/opt/homebrew/bin:/usr/bin:/bin`，使 `/opt/homebrew/bin/node`（v26.13.0）生效。所选工具 `analyze-javascript-application` 是纯静态 JS/HTML 分析，按 REA 文档不需要 Hopper 或 Ghidra，因此缺失 native 引擎不影响本次调查的有效性。

### CLI 关闭阶段错误（重要限定）

两次 `analyze-javascript-application` 均以 **exit code 1** 结束，错误为：

```
ProviderAdapterError: process table could not be inspected: spawn EPERM
cleanupIncomplete: true
userMessage: Provider cleanup could not be fully confirmed. Review the reported local resources before opening another target.
at JavaScriptAnalysisWorker.close → ArtifactResourceScope.#finishClose
```

这是沙箱禁止进程表检查导致的 **provider 关闭阶段**失败，不是分析失败：stdout 已返回完整的 `summary` + `evidence_bundle`，Evidence 文件完整落盘，且二次独立运行的 `root_artifact_sha256` 与 `inventory_graph_sha256` 完全一致（见 §4）。**结论**：Evidence 可用，但 provider 的进程清理未被确认；本次未打开任何 native 目标，故无残留会话需要关闭。

---

## 4. REA 分析执行记录

```bash
PATH=/opt/homebrew/bin:/usr/bin:/bin rea analyze-javascript-application \
  "$PWD/Wallpapers/Aurora Flow" \
  --detail summary \
  --evidence_output ".../docs/rea-aurora.evidence.json" --format json

PATH=/opt/homebrew/bin:/usr/bin:/bin rea analyze-javascript-application \
  "$PWD/Wallpapers/Particle Clock" \
  --detail summary \
  --evidence_output ".../docs/rea-particle-clock.evidence.json" --format json
```

| 项 | Aurora Flow | Particle Clock |
|---|---|---|
| Evidence ID | `ev_38a37beb2c48176c9e75376a550418ca082e5b94c3bd917c53f5d1e2f6c2de05` | `ev_eec4caeca318dd592efff748faff0a32e639baa0d29c0b142d4eea7c8848c431` |
| root_artifact_sha256 | `8eee072b…348da3de` | `46b82702…8848c431` |
| inventory_graph_sha256 | `041a1682…74d1820843b` | `deb8b72c…6d4d01` |
| semantic graph | `jsrg_0db4276a…7f39c7a` | `jsrg_3b1b9d89…44392719` |
| Evidence 大小 | 1,454,609 B | 969,058 B |
| `relevant_files` / 已解析 JS | 3 / 1 | 3 / 1 |
| `visited_ast_nodes` | 1,285 | 927 |
| `parse_failures` | 0 | 0 |

**字节一致性复核**：分析完成后对 `Aurora Flow` 做过一次等幂编辑（删除并原样恢复 `preview` 行）。为此重新运行了一次 REA 到 `/tmp/recheck-aurora.evidence.json`，`root_artifact_sha256` 与 `inventory_graph_sha256` **两项均完全一致**，确认 Evidence 对应当前仓库中的壁纸包字节。

### REA 自身声明的 limitations（原文要点）

- JavaScript 与 HTML 作为**惰性文本**解析，bundle bootstrap 代码从未执行。
- 静态导入、入口、worker、endpoint、storage 关系**不证明运行时执行**。
- CommonJS / ESM 绑定关系只在已清点产物容器内解析。
- 动态或混淆的属性访问可能保持未解析。
- 语义图是静态语法观察与保守的关系候选。

因此 §5 的 API 清单是「**静态可见的标识符引用**」，不是运行时观测。运行时契约另由 `tools/shim-probe.swift` 在真实 WKWebView 中验证（见 §7）。

---

## 5. Q4：作者 API 证据表

提取方法：遍历 `records[0].normalized_result.semantic_graph.nodes`，对 `label` 中的 `read:/…` / `write:/…` 与 `evidence.location.value.start.line` 做过滤。

| API | Particle Clock `app.js` 行号 | Aurora Flow `app.js` 行号 | REA 节点形态 |
|---|---|---|---|
| `wallpaperPropertyListener` | L86 | L173 | `write:/wallpaperPropertyListener` |
| `wallpaperRegisterAudioListener` | L107, L108 | L194, L195 | `read:/…` |
| `wallpaperRegisterMediaPropertiesListener` | L110, L111 | — | `read:/…` |
| `wallpaperRegisterMediaThumbnailListener` | L113, L114 | — | `read:/…` |
| `wallpaperRegisterMediaPlaybackListener` | L116, L117 | — | `read:/…` |
| `wallpaperRegisterMediaTimelineListener` | L119, L120 | — | `read:/…` |
| `wallpaperRegisterMediaStatusListener` | L122, L123 | — | `read:/…` |
| `wallpaperRequestRandomFileForProperty` | L125, L126 | — | `read:/…` |
| `wallpaperMediaIntegration` | L131, L132 | L203, L205 | `read:/…/PLAYBACK_PLAYING` |
| `wallpaperPluginListener` | L133, L134 | — | `read:/…/onPluginLoaded` |

**观察结论**：两张独立编写的壁纸包共出现 **10 个不同的 `window.wallpaper*` 标识符**，与公开文档列出的 10 项官方 web 作者 API 一一对应；`wallpaperPropertyListener` 是唯一被**赋值**（write）的全局，其余均为读取。这直接决定了 shim 的接口面：1 个 getter/setter + 6 个注册函数 + 1 个请求函数 + 2 个常量/对象。

---

## 6. Q5：格式契约的来源与边界

**公开文档（非 REA 证据）**：

- `docs.wallpaperengine.io/en/web/customization/properties.html`：`general.properties` 的 7 种属性类型（color / slider / bool / combo / textinput / file / directory）；color 值格式为 `"R G B"` 的 0–1 字符串；`applyUserProperties(properties)` 收到 `{key: {value: …}}` 形状，且**加载后必定触发一次全量快照**；`file:///…` 路径拼接约定；`fetchall` 模式使用 `userDirectoryFilesAddedOrChanged` / `…Removed`。
- `docs.wallpaperengine.io/web/api/propertylistener`：`applyUserProperties` / `applyGeneralProperties`（含 `fps`）/ `setPaused` / 两个 directory 事件；文档强调 listener 必须**在任何事件之外**作为全局对象初始化。
- `github.com/xhr666/dsh-mpkg-wallpaper` 的 `docs/WEB-WALLPAPER.md`（MIT 兼容实现）：明确列出 10 项官方 API 与「内容优先、声明只作线索」的七步类型判定顺序；指出 `wallpaperPropertyListener` 回调必须**延后到微任务**，否则会重入作者渲染循环导致 React 类壁纸白屏；明确 `$media*` 属于场景脚本而非 web 宿主。

**推断（本项目设计决策，非 REA 观察）**：

1. 注入顺序采用 `seed → shim → 作者脚本`，因为 WE 要求 listener 在文档早期全局赋值。
2. 采用 `WKUserScript(injectionTime: .atDocumentStart)` 而非 HTML 文本改写，是因为 macOS 端直接 `loadFileURL`，无需第三方实现里的代理服务与沙箱 iframe。
3. 音频/媒体监听器只提供接口、不伪造数据，是轻量化与权限成本的取舍。
4. `scene` / `application` 类型拒绝挂载，避免把不可执行/不可解析的内容当作黑屏。

**未知（未覆盖）**：官方 `project.json` 的完整字段集（本文只依赖 `title` / `type` / `file` / `general.properties` / `preview`）；Windows CEF 宿主对各 API 的精确时序；`scene.pkg` 二进制结构；`fetchall` 目录模式下 Windows 绝对路径在 macOS 的映射。

---

## 7. 运行时验证（与静态证据互相印证）

REA 的 limitations 明确说明静态分析不证明运行时执行，因此另用 `tools/shim-probe.swift` 在真实 `WKWebView` 中加载两张壁纸并求值：

```
RESULT[Aurora Flow]:    bridge=object, listener=object, listenerApply=function,
                        mediaPlaying=1, 6 个 register*=function, randomFile=function,
                        plugin=function, propertyKeys=[5 项], canvasWidth=1800
RESULT[Particle Clock]: 同上，propertyKeys=[4 项], canvasWidth=1800
```

`canvasWidth = 1800`（900pt × 2 DPR）说明作者脚本的 `resize()` 确实执行，即 shim 注入顺序与属性快照交付均生效。`tools/window-probe.swift` 另验证 app 运行时存在 2 个 `layer = -2147483622` 的窗口（两个显示器各一），等于 `kCGDesktopWindowLevel + 1`。

---

## 8. 问题清单复核

| # | 状态 | 说明 |
|---|---|---|
| Q1 | **answered** | 本机无 WE 二进制 / 安装包 / workshop 壁纸包，未对 WE 本体逆向 |
| Q2 | **answered（否定）** | 私有壁纸框架无磁盘 Mach-O，位于 dyld shared cache；native provider 亦未安装 |
| Q3 | **answered** | 仅 `analyze-javascript-application` 可用；Node 版本与 provider 缺失已记录并绕开 |
| Q4 | **answered** | 10 项 API + 精确行号，Evidence ID 已保留 |
| Q5 | **partially answered** | 字段与判定顺序来自公开文档，非 WE 二进制逆向；完整字段集未知 |
| Q6 | **unresolved** | 需要真实 `scene.pkg` 样本与 native 分析引擎；本项目明确不实现 |

**总体结论**：本次调查足以支撑「web 类壁纸格式兼容层」的实现，但**不构成对 Wallpaper Engine 程序的完整逆向复刻**。任何关于 WE 内部实现、场景格式或精确宿主时序的断言，在本项目中均未作出。
