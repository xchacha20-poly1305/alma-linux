# Alma Linux Packages

自动打包工具，用于为 [Alma](https://alma.now) 构建多种 Linux 包格式。

## 概述

该仓库每天自动检查 Alma 是否发布新版本，并构建以下包格式：

- **RPM** (Fedora, RHEL, openSUSE 等)
- **Pacman** (Arch Linux, Manjaro 等)
- **DEB** (Debian, Ubuntu 等)

包变体：

- **Standalone** - 包含完整 Electron 运行时，开箱即用
- **System** - 只提供 RPM 和 Pacman。使用发行版提供的 Electron 运行时，启动器会拒绝主版本不匹配的 Electron 可执行文件。

## 安装

### Arch Linux

**Standalone 版本:**
```bash
wget https://github.com/xchacha20-poly1305/alma-linux/releases/latest/download/alma-VERSION-1-x86_64.pkg.tar.zst
sudo pacman -U alma-VERSION-1-x86_64.pkg.tar.zst
```

**System 版本** (需要安装对应的 Arch Electron 包):
```bash
sudo pacman -S electronXX  # XX 为对应的主版本号，如 electron38
wget https://github.com/xchacha20-poly1305/alma-linux/releases/latest/download/alma-system-VERSION-1-x86_64.pkg.tar.zst
sudo pacman -U alma-system-VERSION-1-x86_64.pkg.tar.zst
```

### Fedora/RHEL

**Standalone 版本:**
```bash
wget https://github.com/xchacha20-poly1305/alma-linux/releases/latest/download/alma-VERSION-1.x86_64.rpm
sudo rpm -i alma-VERSION-1.x86_64.rpm
```

**System 版本:**

仅在发行版提供兼容 Electron 运行时时使用该变体。不同 RPM 发行版的包名和可执行文件名并不统一。

```bash
wget https://github.com/xchacha20-poly1305/alma-linux/releases/latest/download/alma-system-VERSION-1.x86_64.rpm
sudo rpm -i alma-system-VERSION-1.x86_64.rpm
```

### Debian/Ubuntu

只提供 standalone DEB 包。本仓库不提供 system-Electron DEB，因为 Debian/Ubuntu 并不稳定通过 apt 提供兼容的 Electron 运行时。

```bash
wget https://github.com/xchacha20-poly1305/alma-linux/releases/latest/download/alma_VERSION-1_amd64.deb
sudo dpkg -i alma_VERSION-1_amd64.deb
sudo apt-get install -f  # 安装依赖（如果需要）
```

## 系统要求

### Standalone 版本
- **无特殊要求** - 包含所有运行时依赖
- 磁盘空间：约 300-500 MB

### System 版本
- 提供的包格式：RPM 和 Pacman
- **需要系统 Electron** - 必须安装发行版提供的兼容 Electron 运行时
- 磁盘空间：约 50-100 MB
- 支持的 Electron 版本：查看 [Releases](https://github.com/xchacha20-poly1305/alma-linux/releases) 页面了解当前版本所需的 Electron 版本
- 启动器查找顺序：`ALMA_ELECTRON`、`electronXX`、`electron-XX`、`electron`、`electronjs`；每个候选都必须通过 `--version` 报告所需主版本

检查 Alma 需要的 Electron 版本：
```bash
# 查看最新 release 的描述，会标明所需的 Electron 版本
```

## 隐私默认行为

本仓库构建的 Linux 包会在首次运行时默认禁用 Alma 的 Activity Recorder。这样新安装不会立即开始周期性屏幕截图，避免在 Wayland/xdg-desktop-portal 环境下反复弹出共享屏幕提示。

用户仍然可以在 Alma 中手动开启，或使用：

```bash
alma activity start
alma activity config set enabled true
```

## 自动更新

Alma 内置了 [electron-updater](https://github.com/electron-userland/electron-builder) 自动更新功能。**本仓库打包的版本已预配置为从本仓库获取更新**，无需手动修改配置。

安装后，Alma 会自动从本仓库检查并下载更新。更新配置已内置在包中：

```yaml
provider: github
owner: xchacha20-poly1305
repo: alma-linux
```

如需切换回官方更新源，可手动修改配置文件：
- **Standalone 版本**：`/opt/Alma/resources/app-update.yml`
- **System 版本**：`/usr/lib/alma/resources/app-update.yml`

改为：
```yaml
provider: generic
url: https://updates.alma.now/
updaterCacheDirName: alma-updater
```

**技术说明**：Alma 使用 electron-updater 6.6.2，完全支持 GitHub Releases 作为更新源。`latest-linux.yml` 包含版本信息、文件列表、SHA512 校验和以及 blockmap 大小，确保更新安全可靠。每个发布包都会有一个对应的 `.blockmap` 资产用于差分更新元数据。

## 工作原理

1. **每日检查** - GitHub Actions 每天 UTC 02:00 自动运行
2. **版本检测** - 获取 `https://updates.alma.now/latest-linux.yml` 并解析版本号
3. **构建包** - 如果发现新版本：
   - 下载上游 DEB 包
   - 验证 SHA512 校验和
   - 提取应用内容和元数据
   - 应用本仓库维护的补丁，包括将 Linux 包的首次运行 Activity Recorder 默认值设为禁用
   - 标准化文件时间戳以实现可重复构建
   - 使用 nFPM 2.47.0 重新打包成 RPM 和 Pacman 格式
   - 构建 system RPM/Pacman 版本（仅包含 app 资源，使用主版本匹配的系统 Electron 运行时）
   - 为每个发布包生成 `.blockmap` 文件
   - 生成 `latest-linux.yml` 更新清单
4. **发布** - 创建 GitHub Release 并上传所有包、blockmap 和更新清单

### 可重复构建

本项目实现了可重复构建（Reproducible Builds），确保相同的输入产生完全相同的输出：

- **固定工具版本**: nFPM 2.47.0, yq 4.53.3
- **固定构建环境**: Ubuntu 24.04
- **标准化时间戳**: 使用 `SOURCE_DATE_EPOCH` 环境变量
- **确定性打包**: 所有文件时间戳统一为发布日期

这意味着任何人都可以验证构建产物的完整性，增强安全性和可信度。

## 技术栈

- **打包工具**: [nFPM](https://nfpm.goreleaser.com)
- **CI/CD**: GitHub Actions
- **源格式**: DEB (从上游下载)

## 开发

### 本地构建

```bash
# 1. 克隆仓库
git clone https://github.com/xchacha20-poly1305/alma-linux.git
cd alma-linux

# 2. 安装依赖
echo 'deb [trusted=yes] https://repo.goreleaser.com/apt/ /' | sudo tee /etc/apt/sources.list.d/goreleaser.list
sudo apt update
sudo apt install nfpm
sudo apt-get install binutils tar xz-utils wget curl
npm install -g app-builder-bin@4.2.0

# 3. 下载最新版本
wget https://updates.alma.now/alma-0.0.809-linux-amd64.deb -O alma.deb

# 4. 提取 DEB 包
chmod +x scripts/extract-deb.sh
./scripts/extract-deb.sh alma.deb

# 5. 检测 Electron 版本
chmod +x scripts/determine-electron.sh
ELECTRON_MAJOR=$(./scripts/determine-electron.sh)

# 6. 构建所有包（可重复构建）
chmod +x scripts/build-packages.sh
export SOURCE_DATE_EPOCH=$(date -d "2024-01-01" +%s)  # 使用固定日期或发布日期
./scripts/build-packages.sh 0.0.809 $ELECTRON_MAJOR

# 生成的包在 dist/ 目录
ls -lh dist/
```

### 项目结构

```
.
├── .github/workflows/
│   └── package.yml           # GitHub Actions 工作流
├── scripts/
│   ├── extract-deb.sh        # DEB 提取脚本
│   ├── build-packages.sh     # 主打包脚本
│   ├── determine-electron.sh # Electron 版本检测
│   └── generate-latest-yml.sh # 更新清单生成器
├── metadata/
│   └── alma-wrapper.sh       # System 版本启动脚本
└── dist/                     # 构建产物（不提交到 git）
```

## FAQ

### Q: Standalone 和 System 版本有什么区别？

**Standalone**: 自带完整的 Electron 运行时，开箱即用，但体积较大（~300MB）。

**System**: 使用系统安装的 Electron，体积小（~50MB），但要求发行版提供兼容的 Electron 包和可执行文件。System 变体不提供 DEB 包。

### Q: System 版本提示找不到 Electron？

确保安装了对应主版本的 Electron：

```bash
# Arch Linux
sudo pacman -S electronXX
```

其中 `XX` 是主版本号，可以在 Release 页面查看所需版本。

启动器会依次查找 `electronXX`、`electron-XX`、`electron` 和 `electronjs`，但只有 `--version` 报告所需 Electron 主版本时才会使用。如果发行版使用其他名称，可以把 `ALMA_ELECTRON` 设置为主版本匹配的可执行文件：

```bash
ALMA_ELECTRON=/path/to/electron alma
```

### Q: 为什么不直接用上游的 AppImage/DEB？

- 上游只提供 AppImage 和 DEB 格式
- RPM 和 Pacman 用户需要原生包格式以便更好地集成到包管理器
- RPM/Pacman system 版本在存在匹配 Electron 运行时时可以减少磁盘占用

### Q: 包会自动更新吗？

会的。Alma 通过 electron-updater 内置了自动更新支持，**本仓库的包已预配置为自动从本仓库接收更新**，无需手动配置。

安装后，Alma 会自动从本仓库检查新版本并提示你更新。

## License

本打包脚本采用 MIT License。Alma 应用本身不开源，如本项目侵犯了您的权益，请联系删除。
