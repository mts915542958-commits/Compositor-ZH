# Compositor 简体中文汉化版

[Compositor](https://github.com/robbietilton/Compositor) 的**非官方简体中文汉化版**（基于 v1.4.9）。

界面全部翻译为简体中文，术语参考 Adobe Photoshop 中文版，快捷键与原版完全一致。

## 下载安装

从右侧 **Releases** 下载 `Compositor-1.4.9-zh-Hans.app.zip`（仅 macOS，Apple Silicon / Intel 均可）。

1. 解压后把 `Compositor.app` 拖入「应用程序」文件夹
2. 首次打开如提示「无法验证开发者」，右键（或按住 Control 点击）应用图标 → 选择「打开」

> 本版本为社区自编译构建（ad-hoc 签名、未经过 Apple 公证），系统可能弹出安全提示，按上法打开即可。

## 汉化内容

- **主菜单**：文件 / 编辑 / 显示 / 选择 / 图像 / 滤镜 / 图层 / 窗口 / 帮助
- **全部工具面板**：变换、图层、混合模式（24 种 Photoshop 中文名）、不透明度、缩放/平移、画笔、裁剪、套索/选框/魔棒、渐变、形状、文字、吸管、抓手等
- **全部对话框**：新建画布、导出、图像大小、画布大小、色阶、曲线、HSL、相机原片（Camera Raw 全套）、滤镜、图层效果、网格、修剪、PSD 导入、Raw 显影、快捷键设置等
- **工具栏/状态栏**：工具提示、快捷键说明、操作提示全部中文
- **系统菜单**：通过 zh-Hans 本地化声明使 macOS 自动本地化标准菜单标题

## 与原版的兼容性

- **项目文件完全兼容**：所有参与保存/编码的枚举（混合模式、采样方式、画布单位、图层调整等）`rawValue` 保持英文，旧项目可正常打开，新项目仍可被原版打开
- **快捷键不变**：所有键盘快捷键与原版一致
- 功能与原版 1.4.9 完全一致，仅界面语言不同

## 从源码构建（可选）

```bash
git clone https://github.com/mts915542958-commits/Compositor-ZH.git
open Compositor.xcodeproj   # Xcode 打开后 ⌘B 构建
```

构建产物位于 `DerivedData/.../Build/Products/Debug/Compositor.app`。

## 许可

本项目基于 [Compositor](https://github.com/robbietilton/Compositor)（MIT License）修改，保留原版权声明；本汉化版本同样以 **MIT License** 发布。

汉化请求已提交上游：https://github.com/robbietilton/Compositor/issues/260

> 注意：本仓库与官方项目相互独立，并非官方版本。请勿将本仓库问题提交到上游。
