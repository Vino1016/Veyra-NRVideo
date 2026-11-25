# 专业模式分离画面（2026-11-25）

分支 `feat/separate_window`。本记录只描述源码改动；本机为 macOS，未构建、未运行，Windows 实测由用户完成。

## 做法

- 不新增渲染链路。仍是一块原生视频 HWND `g_video` 和一个 swapchain；分离时 `SetParent` 到新的顶层窗口 `VideoWindow.qml`，收回时挂回主窗口。
- `apps/veyra-qml/main.cpp`：
  - `desiredVideoHost()` 根据主窗口 `videoInWindow` 选择宿主（主窗口 `videoHost` 或独立窗口 `detachedVideoHost`）。
  - `attachVideo()` 统一负责改父窗口、子窗口样式、清除旧区域，以及几何/区域缓存（原函数内 `static` 缓存改为全局，换父窗口时清空）。
  - `follow` 和 pre-open hook 改为按当前宿主同步几何、cover 和光标；独立窗口的 `afterAnimating`、`visibleChanged` 也驱动 `follow`。
  - 主窗口 `closing` 时先把画面挂回主窗口，避免子 HWND 随独立窗口一起销毁。
- 呈现器每帧用 `MonitorFromWindow(window_)`，跨屏后的刷新率、HDR 峰值、XeSS 缓冲走既有显示变更与 resize 路径，未改引擎代码。
- QML：
  - `VideoWindow.qml`：带系统边框，可移动、最大化，双击或 F11 全屏，Esc 退出，全屏 1.6 s 无操作隐藏光标；支持空格播放暂停和左右键快进退。关闭窗口即收回画面。位置、最大化和“已分离”状态保存在 data-dir 的 `video-window.ini`；保存位置所在屏幕不在时放到主窗口以外的屏幕（若有）。
  - 专业列表页播放条、节点页统计条各加一个“分离画面/收回画面”按钮；分离后原视频区显示“画面已在独立窗口中显示 · 收回画面”。
  - 以下情况画面临时回到主窗口，独立窗口保持打开并提示：离开专业/节点页、主窗口全屏、绘制保护区域、移动排除区域、屏幕裁剪编辑。
- 新增 7 条界面文案，9 种语言已补齐；`extract.py --check` 缺译 0、占位符问题 0。

## 未验证（需 Windows 实测）

1. flip-model swapchain 在 `SetParent` 跨顶层窗口后能否继续 present（最先确认；若黑屏需在切换时重建 swapchain）。
2. 双屏不同 DPI/刷新率/HDR 下画面尺寸、HDR 输出与 VRR。
3. 独立窗口全屏能否进入独立翻转。
4. OBS 游戏采集是否锁到视频 swapchain。
5. Moonlight 输入捕获：分离后点击主窗口画面区不会触发捕获，捕获窗口取 `GetAncestor(video, GA_ROOT)`。
6. 切源、seek、暂停恢复、device lost 期间分离/收回。
