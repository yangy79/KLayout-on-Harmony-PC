# 三方组件与许可清单（NOTICE）

本应用（KLayout for HarmonyOS，包名 `com.yangy79.klayout`）分发时包含以下组件。
所有组件的许可文件均随源码或二进制一并提供，未被修改或移除。

## 1. 主要组件

| 组件 | 版本 | 许可协议 | 角色 | 源码来源 |
|---|---|---|---|---|
| **KLayout** | 0.30.10 | **GPL-3.0** | 应用本体（版图查看 / 编辑器） | <https://www.klayout.org/downloads/source/klayout-0.30.10.tar.gz><br><https://github.com/klayoutmatthias/klayout> |
| **Qt** | 5.12.12（`harmonyos-5.12.12` 分支） | **LGPL-3.0**（另有 GPL-2.0 / GPL-3.0 / 商业授权可选） | GUI 框架；以动态库形式随应用分发 | Qt TQtC `tqtc-qubase` / `harmonyos-5.12.12`，见 [`qt5-ohos/README.md`](qt5-ohos/README.md) |
| **Qt 官方 DevEco 壳工程模板** | 随 Qt 5.12.12 for OpenHarmony | LGPL-3.0 | `ohos-app/` 的骨架来源（`qtbase/src/harmonyos/templates`） | 同上 |

> Qt 是**动态链接**使用的。HarmonyOS 应用沙箱不允许用户替换已安装应用的 `.so`，
> 因此 LGPL「允许用户替换库」的等价目的，通过**公开完整构建脚本与全部源码**来满足：
> 任何人都可以用自己修改过的 Qt 重新构建整个应用。详见
> [`OPENSOURCE-COMPLIANCE.md`](OPENSOURCE-COMPLIANCE.md) 第 4 节。

## 2. KLayout 内部集成的第三方代码

KLayout 源码树本身（`src/3rdparty/`、`src/plugins/` 等）内含若干宽松许可的第三方代码，
其许可与版权声明原样保留在上游源码树中，随本仓库 `patches/` 所还原的完整源码一并提供。

本移植**未新增**任何第三方代码：`overlay/` 下的文件均为本项目自行编写。

## 3. 运行时动态依赖

对已构建的 `libklayout.so`、各 `libklayout_*.so` 与全部 stream 插件做过 DT_NEEDED
核验（`llvm-readelf -d`），**没有**任何其它外部动态依赖。实际出现的 DT_NEEDED 只有三类：

**① 系统库（由 HarmonyOS 设备提供，不随包分发）**

`libc.so`、`libGLESv3.so`、`libohenvironment.so`、`libhilog_ndk.z.so`、
`libace_napi.z.so`、`libdeviceinfo_ndk.z.so` 等。

**② 编译器运行时（随包分发）**

`libc++_shared.so` —— LLVM libc++，Apache-2.0 WITH LLVM-exception。
源文件与许可文本随 HarmonyOS NDK（`<sdk>/native/llvm/`）提供。

**③ Qt 子集（随包分发，LGPL-3.0）**

`libQt5Core` / `libQt5Gui` / `libQt5Widgets` / `libQt5Network` / `libQt5Xml` /
`libQt5PrintSupport` / `libQt5Sql`，以及 Ohos 平台插件 `libqohos.so`。

**④ zlib（`libz.so`，zlib 许可）**

KLayout 读写压缩流需要；由 HarmonyOS 系统提供，未随包分发。

**确认未包含**（对应构建时全部关闭，见 `build-ohos.log` 的 `Build flags` 段）：
`libpng`(HAVE_PNG=0)、`libexpat`(HAVE_EXPAT=0)、`libcurl`(HAVE_CURL=0)、
`libgit2`(HAVE_GIT2=0)、Ruby(HAVE_RUBY=0)、Python(HAVE_PYTHON=0)、
LStream(HAVE_LSTREAM=0)。

## 4. 版权声明保留情况

| 位置 | 内容 |
|---|---|
| 源码树 `LICENSE` | KLayout GPL-3.0 全文（原样） |
| 源码树 `COPYRIGHT` | KLayout 上游版权声明（原样） |
| 源码树各源文件头 | 上游版权头与许可声明（原样，未被删除） |
| 应用内 `Help → About` | 移植说明、GPL/LGPL 声明、上游与本移植仓库地址 |
| 本仓库 `LICENSE` / `NOTICE.md` | 同上，供应用市场审核查阅 |

---

*本文件随应用版本更新而更新。*
