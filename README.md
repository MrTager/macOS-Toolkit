# macOS-Toolkit

本地自用的菜单栏工具中枢：系统监控 + 进程管理 + 常用工具统一启停。

## 功能

- **菜单栏实时状态**：CPU 占用 + 内存使用，颜色分级（绿 <60% / 黄 <90% / 红 ≥90%）
- **监控面板**：CPU 总览曲线 + 每核仪表、内存构成（已用/缓存/压缩/空闲 + Swap）、网络上下行速率曲线、磁盘容量、温度（电池温度 + CPU 热压力）
- **进程管理**：全量进程列表（CPU/内存排序、搜索），支持 SIGTERM / SIGKILL 结束进程
- **工具中枢**：工具列表可增删改、拖拽排序，支持「从已安装应用选择」自动填 Bundle ID；一键启停 + 实时运行状态；支持开机自启开关
- **自动化规则**：CPU/内存/电池温度/CPU 热压力阈值告警，系统通知推送，冷却间隔防骚扰，规则持久化 + 最近事件记录
- **风扇监控与控制**：直接读取 Intel Mac 的 AppleSMC 风扇转速、转速上下限及温度；每个风扇可选系统自动、固定转速或按温度传感器调速，菜单栏可显示风扇转速和 CPU 温度。写入需要一次性安装特权助手；温度传感器失效、退出应用或控制心跳中断时恢复系统自动控制。
- **Touch Bar**：下载/上传网速、CPU 占用、风扇转速、CPU 温度、内存与系统盘使用率进度条，以及“打开窗口”按钮跨应用常驻；右侧系统 Control Strip 保留。轻触常驻入口可收起或重新展开，菜单栏右键也可控制。

## 使用

```bash
# 打包并运行
./scripts/build-app.sh
open "dist/macOS Toolkit.app"

# 打包并安装到 /Applications（自动重启）
./scripts/build-app.sh --install
```

应用图标由 `scripts/make-icon.swift` 程序化生成（首次打包自动执行），改完图标脚本后删除 `Resources/AppIcon.icns` 重新打包即可更新。

- 左键菜单栏图标：打开面板
- 右键菜单栏图标：退出应用
- 风扇页：先查看实时读数；要修改转速，点击“安装风扇控制助手…”并完成 macOS 管理员授权。

## 开发

```bash
swift build          # 调试编译
swift build -c release
```

纯 Swift + SwiftUI，SPM 管理，无第三方依赖。最低 macOS 13。

## 结构

```
Sources/Toolkit/
├── main.swift / AppDelegate.swift   # 菜单栏生命周期
├── Services/
│   ├── SystemMonitor.swift          # CPU/内存/网络/磁盘采样内核
│   ├── ProcessMonitor.swift         # 进程列表与结束
│   ├── ToolManager.swift            # 工具统一启停
│   └── Format.swift                 # 格式化
└── Views/
    ├── ToolkitView.swift            # 主框架（Tab）
    ├── DashboardView.swift          # 监控面板
    ├── ProcessListView.swift        # 进程页
    └── ToolsView.swift              # 工具页
```

## 风扇控制说明

`scripts/probe-smc.c` 使用 80 字节的 AppleSMC 请求结构；先前 88 字节结构导致了 macOS 26 不支持 SMC 的误判。当前在 Intel MacBookPro16,2 / macOS 26.6.2 上验证了只读风扇与温度数据。控制写入由特权助手执行，并仅允许风扇模式与设备允许范围内的目标转速。Apple Silicon 和其他机型的写入兼容性尚需实机验证。

此功能使用独立的 AppleSMC 实现，不依赖 Macs Fan Control 进程。退出 Toolkit 会恢复由 Toolkit 接管的风扇为系统自动控制。若辅助程序尚未安装，风扇页保持只读。

Touch Bar 常驻功能使用系统私有 Control Strip 接口（实现参考 [MacDuo](https://github.com/bugwz/MacDuo)，授权见 `THIRD_PARTY_LICENSES/MacDuo-MIT.txt`）。接口通过运行时检测加载；若系统版本不支持，Toolkit 仍保留前台 Touch Bar 控件、菜单栏和主窗口。退出应用会注销常驻入口。
