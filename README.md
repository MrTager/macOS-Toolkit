# macOS-Toolkit

本地自用的菜单栏工具中枢：系统监控 + 进程管理 + 常用工具统一启停。

## 功能

- **菜单栏实时状态**：CPU 占用 + 内存使用，颜色分级（绿 <60% / 黄 <90% / 红 ≥90%）
- **监控面板**：CPU 总览曲线 + 每核仪表、内存构成（已用/缓存/压缩/空闲 + Swap）、网络上下行速率曲线、磁盘容量、温度（电池温度 + CPU 热压力）
- **进程管理**：全量进程列表（CPU/内存排序、搜索），支持 SIGTERM / SIGKILL 结束进程
- **工具中枢**：工具列表可增删改、拖拽排序，支持「从已安装应用选择」自动填 Bundle ID；一键启停 + 实时运行状态；支持开机自启开关

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

## 后续规划

- P2 完整版：SMJobBless 特权助手，直读 CPU die 温度/风扇转速并控制调速（macOS 26 已封死无特权 SMC 通道，见 scripts/probe-smc.c）
- P4：自动化规则（温度阈值联动、内存告警清理）

