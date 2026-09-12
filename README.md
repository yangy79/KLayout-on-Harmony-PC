# KLayout on HarmonyOS PC

把 **[KLayout](https://www.klayout.de) 0.30.10**（VLSI 版图查看 / 编辑器，C++ / Qt）
移植到 **HarmonyOS PC（2in1，aarch64）**，并以 Qt 5.12.12 for OpenHarmony 构建、
打包成可上架 AppGallery 的 HAP / App Pack。

本仓库是**移植层与配套构建脚本**，不是 KLayout 上游的 fork。上游源码原样使用，
只施加本仓库 `patches/` 中的补丁；任何人都能用 `scripts/setup-source.sh` 一键
还原出与已发布二进制**逐字节对应**的完整源码树。

---

## 1. 成品形态

| 项目 | 值 |
|---|---|
| 应用名 | KLayout |
| 包名 (bundleName) | `com.yangy79.klayout` |
| 版本 | `1.0.0` (versionCode `1000000`) |
| 设备形态 | `2in1`（PC / 平板二合一，HarmonyOS 桌面形态） |
| 目标 SDK | `5.0.0(12)`（compatibleSdkVersion，满足 NEXT 要求 `≥ 4.0.0(10)`） |
| 交付物 | `klayout-1.0.0-release.app`（App Pack，约 106 MB） |
| 上游版本 | KLayout 0.30.10（GPL-3.0） |
| 运行时 | Qt 5.12.12 for OpenHarmony（LGPL-3.0），静态链接进 HAP 的 Qt 子集 |

---

## 2. 仓库结构

```
.
├── README.md                      ← 本文件
├── LICENSE                        ← KLayout 上游 GPL-3.0 全文（原样保留）
├── COPYRIGHT                      ← 上游版权声明（原样保留）
├── CONTRIB                        ← 上游贡献者说明
├── NOTICE.md                      ← 三方组件与许可清单
├── OPENSOURCE-COMPLIANCE.md       ← 面向应用市场审核的开源合规声明
│
├── patches/                       ← 相对上游源码的改动（统一 diff）
│   ├── klayout-0.30.10-ohos.patch         7 个源文件
│   └── qt5-ohos-mkspec-no-werror.patch    Qt mkspec 单行改动
│
├── overlay/                       ← 上游源码树中不存在的新增文件
│   ├── apply_ohos_resource_patch.py       在 klayout_main() 入口注入 KLAYOUT_PATH
│   └── klayout-resources/                 运行时资源树（68 个文件）
│
├── ohos-app/                      ← HAP 壳工程（ArkTS，源自 Qt 官方 DevEco 模板）
├── qt5-ohos/                      ← Qt 侧构建配置（configure / mkspec / host 适配）
├── build-scripts/                 ← 实机使用的打包与签名脚本（原样收录）
├── scripts/                       ← 通用入口脚本（取源码 / 打补丁）
└── docs/                          ← 移植说明、构建说明、验证记录、截图
```

---

## 3. 快速开始

### 3.1 还原完整源码树（含全部移植改动）

```sh
sh scripts/setup-source.sh --out ./klayout-0.30.10
```

脚本会：下载上游 `klayout-0.30.10.tar.gz` → 校验 SHA-256 → 解包 → 打上
`patches/klayout-0.30.10-ohos.patch` → 复制 `overlay/` → 得到可直接编译的源码树。

若本机已有上游 tarball（离线场景）：

```sh
sh scripts/setup-source.sh --tarball /path/to/klayout-0.30.10.tar.gz --out ./klayout-0.30.10
```

**上游源码包（精确标识）**

| 项 | 值 |
|---|---|
| URL | `https://www.klayout.org/downloads/source/klayout-0.30.10.tar.gz` |
| 大小 | `103949878` 字节 |
| SHA-256 | `96f7db5a744d9cd8ac913bb9186ce3b51e836321665d8f874336d0d43d2275c0` |
| 官方仓库 | `https://github.com/klayoutmatthias/klayout`（tag `v0.30.10`） |

### 3.2 构建

完整步骤见 **[`docs/BUILD.md`](docs/BUILD.md)**。概要：

1. 用 `qt5-ohos/` 里的脚本构建 **Qt 5.12.12 for OpenHarmony**（只编 `qtbase`）。
2. 用 Qt 的 qmake 编 KLayout → 得到 `libklayout.so` 及各模块库。
3. 把库与资源树注入 `ohos-app/`，用 DevEco CLI + `build-scripts/` 打包并签名。

---

## 4. 这个移植做了什么

改动量刻意压到最小 —— 上游 8408 个文件中只动了 **7 个**，另加 1 个新文件与 1 处 Qt mkspec 单行改动。

| 类别 | 文件 | 改动 |
|---|---|---|
| 启动 / 资源定位 | `src/klayout_main/klayout_main/klayout.cc` | 注入 `KLAYOUT_PATH`（OHOS 上 `tl::get_inst_path()` 无法定位资源）；导出 `main` 供 QPA 插件 `dlsym`；显式 `dlopen` stream 插件；About 页补版权与源码入口；诊断日志改走 hilog |
| 构建配置 | `src/klayout_main/klayout_main/klayout_main.pro` | 加入 QtCore 私有头路径；`--export-dynamic`；把 GDS2 reader 源码直接编入主库 |
| 构建配置 | `src/plugins/{db,lay}_plugin.pri` | 关闭 `--gc-sections`（否则插件的静态自注册对象会被裁掉） |
| 平台细节 | `src/lay/lay/layMainWindow.cc` | OHOS 平台样式下侧栏 `sizeHint` 过小导致标题被省略号截断，强制最小宽度 |
| 平台细节 | `src/laybasic/laybasic/layAbstractMenu.cc` | 菜单图标路径形如 `<:/foo.png>`，在 OHOS 上解析失败，回退为 `:/` 形式；并改用「能否取到 pixmap」判断图标有效性 |
| 诊断 | `src/tl/tl/tlStream.cc` | `FileOpenErrorException` 里附 hilog 打印（含 `errno` 与调用栈偏移），便于定位打不开的文件 |
| 新增 | `overlay/apply_ohos_resource_patch.py` | 向 `klayout_main()` 注入资源路径逻辑的补丁脚本（幂等，可重复执行） |
| Qt | `qtbase/mkspecs/ohos-clang/qmake.conf` | `-Werror` → `-Wno-error`（clang 15 的若干良性告警会被当错误，移植期必须放开） |

技术细节与踩坑记录见 **[`docs/PORTING-NOTES.md`](docs/PORTING-NOTES.md)**。

---

## 5. 已知限制

- **不含脚本引擎**：构建时关闭了 Ruby / Python / Qt binding。因此 DRC/LVS 脚本、
  Ruby/Python 宏、`-b` 批处理脚本在应用内不可用；**版图查看与编辑等 CAD 核心功能不受影响**。
- **仅 `2in1` 形态**：清单只声明 PC 形态。Qt 侧存在已知问题（手机形态下窗口最小化后
  不恢复），故未声明 `phone` / `tablet`。
- **不含 QtSvg / QtMultimedia / QtDesigner 支持**：这些 Qt 模块未构建。
- **无内置示例库**：为控制包体，未随包分发 `demo` / `db_plugins` / `lay_plugins` 示例与插件目录。

---

## 6. 许可

- **KLayout** —— GNU General Public License v3.0（见 [`LICENSE`](LICENSE)）。
  本移植版同样以 GPL-3.0 分发，完整对应源码见第 3.1 节。
- **Qt 5.12.12 for OpenHarmony** —— LGPL-3.0（Qt for HarmonyOS 分支）。
  本应用以动态链接方式使用 Qt，构建配置与源码获取方式见 [`qt5-ohos/README.md`](qt5-ohos/README.md)。
- 三方组件完整清单见 [`NOTICE.md`](NOTICE.md)；面向审核的说明见
  [`OPENSOURCE-COMPLIANCE.md`](OPENSOURCE-COMPLIANCE.md)。

---

## 7. English summary

This repository contains the **HarmonyOS (2in1, aarch64) port layer** that brings
[KLayout](https://www.klayout.de) 0.30.10 to HarmonyOS PC, built with Qt 5.12.12 for
OpenHarmony. It is *not* a fork of upstream KLayout: upstream sources are used
unmodified except for the patches in `patches/` (7 files) plus one new file.
`scripts/setup-source.sh` downloads the pinned upstream source package, verifies its
SHA-256, and applies the patches to produce the complete corresponding source of the
released binary. KLayout is licensed under GPL-3.0; Qt is used under LGPL-3.0.

---

*移植与维护：yangy79 · 上游 KLayout © Matthias Köfferlein 及贡献者*
