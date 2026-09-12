# KLayout for HarmonyOS 开源合规声明

**应用**：KLayout（`com.yangy79.klayout`）· 版本 1.0.0 · 设备形态 `2in1`
**本声明日期**：2026 年 9 月 12 日
**适用对象**：华为应用市场（AppGallery）上架审核 + 用户查阅

---

## 一、一句话说明

本应用是开源软件 **KLayout（GPL-3.0）** 在 **HarmonyOS / OpenHarmony** 平台上的移植版本，
使用 **Qt 5.12.12 for OpenHarmony（LGPL-3.0）** 构建。本应用**不是原创软件**，而是遵循原许可
条款的**再分发**。我们在此完整披露所使用的开源组件、许可条款，以及我们履行相应义务的方式。

> **给审核同事**：本应用不含任何我方闭源代码，全部为开源组件 + 公开的移植适配代码。
> 源码获取方式见第五节，仓库地址：<https://github.com/yangy79/KLayout-on-Harmony-PC>

---

## 二、开源组件清单

### 2.1 主要组件

| 组件 | 版本 | 许可协议 | 在本应用中的角色 | 源码 |
|---|---|---|---|---|
| **KLayout** | 0.30.10 | **GPL-3.0** | 应用本体：版图查看与编辑器 | <https://www.klayout.org/downloads/source/klayout-0.30.10.tar.gz><br><https://github.com/klayoutmatthias/klayout> |
| **Qt** | 5.12.12 for OpenHarmony | **LGPL-3.0** | GUI 框架（Core/Gui/Widgets/Network/Xml/PrintSupport/Sql）+ Ohos 平台插件 | Qt TQtC `harmonyos-5.12.12` 分支，见 2.3 |
| **libc++** | HarmonyOS NDK 随附 | Apache-2.0 with LLVM Exception | C++ 标准库（`libc++_shared.so`） | <https://libcxx.llvm.org/> |
| **zlib** | 随 HarmonyOS 系统 | zlib License | DEFLATE 压缩（GDS2 `.gz`、OASIS 压缩流） | <https://zlib.net/> |

### 2.2 本构建的实测依赖（可复核）

对发布包内全部 native 库做 `DT_NEEDED` 解析（`llvm-readelf -d`）后，**除系统库与 Qt 自身外，
唯一的外部动态依赖是 `libz.so`（zlib License）**：

```
libklayout.so + libklayout_*.so（共 21 个）          ← KLayout 本体模块（GPL-3.0）
libgds2.so / liboasis.so / libcif.so / libdxf.so /
liblefdef.so / libmag.so / libmaly.so / libpcb.so…    ← KLayout stream 插件（GPL-3.0，共 25 个）
libQt5Core/Gui/Widgets/Network/Xml/PrintSupport/Sql.so ← Qt（LGPL-3.0）
libqohos.so                                           ← Qt Ohos 平台插件（LGPL-3.0）
libc++_shared.so                                      ← HarmonyOS NDK（Apache-2.0 with LLVM Exception）
libz.so                                               ← zlib（zlib License）
libc.so / libGLESv3.so / libohenvironment.so /
libhilog_ndk.z.so / libace_napi.z.so /
libdeviceinfo_ndk.z.so                                ← HarmonyOS 系统库（随系统分发，不随本包分发）
```

> 本次构建关闭了 Ruby / Python 脚本绑定（`HAVE_RUBY=0` / `HAVE_PYTHON=0` /
> `HAVE_QTBINDINGS=0`）与 QtSvg / QtMultimedia / QtDesigner / QtUiTools / libgit2 /
> LStream / libcurl / libpng / libexpat（构建日志 `Build flags` 段可复核）。
> 被关闭的组件**不包含在本发布包中**，不构成本次分发的合规义务。

### 2.3 Qt 的精确标识与来源

| 项 | 值 |
|---|---|
| 版本 | Qt 5.12.12 |
| 发行标识 | Qt for OpenHarmony 源码包 `qt-harmonyos-src-5.12.12` |
| 主分支 | `tqtc/harmonyos-5.12.12`（The Qt Company 的 HarmonyOS 支持分支） |
| 源码包 tag | `a5efc71951a53c045a89b9049761723576cc404a` |
| qtbase 模块 commit | `15afb070c694be2513facf20dbcfc54d4249f035` |
| 我们对其的改动 | **仅 1 行**：mkspec `ohos-clang/qmake.conf` 中 `-Werror` → `-Wno-error`（见 `patches/qt5-ohos-mkspec-no-werror.patch`） |
| 许可文件 | 源码包内 `LICENSE.LGPLv3` / `LICENSE.GPLv2` / `LICENSE.GPLv3` / `LICENSE.QT-LICENSE-AGREEMENT` 原样保留 |

本应用按 Qt 的**开源许可（LGPL-3.0）**使用 Qt，**未使用任何 Qt 商业模块**
（如 Qt Charts 商业版、Qt for Device Creation 等）。Qt 的库代码未被修改；
我们的改动仅涉及构建配置文件。

### 2.4 Qt 内嵌的第三方组件

Qt 5.12.12 内部静态包含若干第三方库（libpng、FreeType、HarfBuzz、PCRE2、
double-conversion、SQLite 及若干哈希实现等），许可均为宽松许可
（zlib / MIT / BSD / Apache-2.0 等）。完整清单见 Qt 源码树
`qtbase/src/3rdparty/*/qt_attribution.json` 与各子目录的 `LICENSE*` 文件。

### 2.5 壳工程骨架

`ohos-app/` 的工程骨架源自 Qt 5.12.12 for OpenHarmony 随附的官方 DevEco 模板
（`qtbase/src/harmonyos/templates`，LGPL-3.0）。我们对其的改动仅限：包名、应用名、
图标资源、`deviceTypes`、`APP_LIBRARY_NAME` 与 SDK 版本配置。

---

## 三、GPL-3.0 合规义务与履行方式

GPL-3.0 允许以任何目的（含商业目的）再分发，但要求再分发者履行以下义务。
我们逐条对应说明：

| GPL-3.0 要求 | 我们的履行方式 | 状态 |
|---|---|---|
| 提供完整对应的**源代码**（含修改） | 完整对应源码见第五节；上游源码包 + 我们全部改动（补丁 7 文件 + 新增 1 文件）均可公开获取 | ✅ |
| 保留**版权声明与许可声明**，不得移除 | 上游各源文件版权头、`LICENSE`、`COPYRIGHT` 原样保留在源码与二进制中 | ✅ |
| 分发时附带 **GPL-3.0 许可全文** | 源码树携带 `LICENSE`（GPL-3.0 全文）；应用内 Help → About 显示许可信息与源码入口 | ✅ |
| 标明**修改过的文件**与修改内容 | `patches/klayout-0.30.10-ohos.patch`（7 个文件，835 行 diff）+ `overlay/`（新增文件），逐条带中文说明 | ✅ |
| **不得附加额外限制** | 不附加任何超出 GPL-3.0 的限制；无 DRM、不限制再分发 | ✅ |
| 分发**目标代码**时须同时提供源码获取方式 | 应用内 Help → About 已标注源码地址；本文件与商店详情页同步提供 | ✅ |

### 3.1 关于「软著 / APP 电子版权认证」—— 本项目不适用

工信部 APP 备案与部分应用市场流程要求提交「计算机软件著作权登记证书」或
「APP 电子版权认证证书」。该类证书的登记对象是**申请人独立创作完成的软件作品**。

**本项目不是原创作品，而是 GPL-3.0 开源软件 KLayout 的移植分发**：著作权属于原作者
（Matthias Köfferlein 及贡献者），我们不主张原创著作权。相应地，以
「上游开源许可 + 修改后源码公开 + 版权声明保留」这组材料证明分发的合法性 ——
这既是 GPL-3.0 的强制义务，也是开源软件上架通行的资质路径：

1. **开源许可证明**：KLayout 的 GPL-3.0 许可全文（证明原作者已授权任何人再分发）；
2. **上游来源证明**：源码下载地址 / 版本号 / 大小 / SHA-256 校验值（见第五节）；
3. **移植工作说明**：`patches/` 与 `overlay/` 给出了本包与上游的完整差异；
4. **本合规声明**：说明义务履行方式；
5. **修改后源码公开**：<https://github.com/yangy79/KLayout-on-Harmony-PC>。

> 备注：华为开发者社区的通用口径中，对「修改他人源码二次开发」的软件也提及版权归属证明。
> 对 GPL 类开源软件，我们以「上游 GPL 授权链 + 修改后源码公开 + 应用内版权声明」作为对应材料；
> 若审核环节另有具体要求，可按本声明第一、五节补充（两者并不冲突）。

---

## 四、LGPL-3.0 合规义务（Qt 部分）

Qt 以 LGPL-3.0 授权。LGPL 对「动态链接使用库」的场景要求：

| LGPL-3.0 要求 | 我们的履行方式 | 状态 |
|---|---|---|
| 以**动态链接**方式使用 Qt（不静态并入） | Qt 编译为独立 `.so`，运行时动态加载（包内 `libs/arm64-v8a/libQt5*.so`） | ✅ |
| 允许用户**替换 Qt 库** | HarmonyOS 应用沙箱不允许用户替换已安装应用的 `libs/`，此项在上架形态下客观上受限。我们通过**公开全部构建脚本与源码**保证：任何人都可用自己修改过的 Qt 重新构建整个应用，从而达成 LGPL 的等价目的 | ⚠️ 已说明 |
| 提供 Qt 的**对应源码**（含修改） | Qt 源码按 2.3 节精确标识；我方对其的唯一改动（mkspec 单行）以补丁形式公开；Qt 官方源码可自 The Qt Company 官方渠道取得 | ✅ |
| 提供 **LGPL-3.0 许可全文** | Qt 源码包内 `LICENSE.LGPLv3` 原样保留；本仓库与商店详情页提供许可声明 | ✅ |
| 声明 Qt 的使用与版本 | 本文件 2.1/2.3 节 + 应用内 Help → About 页 | ✅ |

---

## 五、源码获取方式

| 内容 | 地址 |
|---|---|
| **移植版完整源码（含全部改动）** | <https://github.com/yangy79/KLayout-on-Harmony-PC> |
| 相对上游 0.30.10 的适配补丁 | 仓库内 `patches/klayout-0.30.10-ohos.patch` |
| 上游 KLayout 原版 | <https://www.klayout.org/downloads/source/klayout-0.30.10.tar.gz> |
| 上游源码包校验值 | 大小 `103949878` 字节；SHA-256 `96f7db5a744d9cd8ac913bb9186ce3b51e836321665d8f874336d0d43d2275c0` |
| 一键还原可编译源码树 | 仓库内 `scripts/setup-source.sh` |
| Qt 5.12.12 for OpenHarmony 构建说明 | 仓库内 `qt5-ohos/README.md` + `docs/BUILD.md` |

**本移植相对上游的改动范围**（完整清单，即 `patches/` 全部内容）

| # | 文件 | 改动内容 |
|---|---|---|
| 1 | `src/klayout_main/klayout_main/klayout.cc` | HarmonyOS 启动引导：注入 `KLAYOUT_PATH`（OHOS 上 `tl::get_inst_path()` 经 `/proc/pid/exe` 只能看到宿主壳、无法定位资源）；导出 `main` 供 QPA 插件 `dlsym`；启动时显式 `dlopen` stream 插件（OHOS 禁止从可写分区加载 `.so`）；About 页补版权与源码入口；诊断日志改走 hilog |
| 2 | `src/klayout_main/klayout_main/klayout_main.pro` | 加入 QtCore 私有头路径；`-Wl,--export-dynamic`；把 GDS2 reader 源码直接编入主库 |
| 3 | `src/plugins/db_plugin.pri` | `-Wl,--no-gc-sections`（见第 6 节说明） |
| 4 | `src/plugins/lay_plugin.pri` | 同上 |
| 5 | `src/laybasic/laybasic/layAbstractMenu.cc` | 菜单图标路径 `<:/foo.png>` 在 OHOS 上解析失败，回退为 `:/`；改用 pixmap 可获取性判断图标有效性 |
| 6 | `src/lay/lay/layMainWindow.cc` | OHOS 平台样式下侧栏 `sizeHint` 过小导致标题被截断，强制最小宽度 280 |
| 7 | `src/tl/tl/tlStream.cc` | `FileOpenErrorException` 附 hilog 诊断（`errno` + 调用栈模块偏移） |
| 8 | `overlay/apply_ohos_resource_patch.py`（新增） | 向 `klayout_main()` 注入资源路径逻辑的补丁脚本 |
| 9 | `qtbase/mkspecs/ohos-clang/qmake.conf`（Qt 侧） | `-Werror` → `-Wno-error` |

**未改动**：KLayout 的核心数据库、几何运算、版图读写算法、GUI 框架代码均保持上游原样。
上游源码树 8408 个文件中，被修改的只有上表 7 个。

---

## 六、两个关键移植问题的说明（供技术审核）

1. **为什么要把 GDS2 reader 编进主库？**
   GDS2 是独立插件 `libgds2.so`，靠文件末尾的静态对象
   `static tl::RegisteredClass<db::StreamFormatDeclaration> format_decl(..., "GDS2")` 自我注册。
   在本机工具链下，插件的 `.init_array` 会被 `-Wl,--gc-sections` 裁掉该构造 —— 结果是
   插件 `dlopen` 成功却从未注册，任何 `.gds` 都报 *"Stream has unknown format"*。
   解决方式：关闭插件链接的 gc-sections（改动 3、4），同时把 GDS2 reader 直接编入主库
   （改动 2），使注册与查询同进程、无加载时序依赖。

2. **为什么插件必须放在 `libs/` 而不是资源目录？**
   OHOS 安全策略**禁止从用户可写分区加载 `.so`**。KLayout 默认从
   `KLAYOUT_PATH/db_plugins/` 加载插件，而该路径指向应用可写目录 → 全部插件加载失败。
   故插件改放应用安装目录 `libs/arm64-v8a/`（必然允许加载），由改动 1 显式 `dlopen`。

---

## 七、商标与名称

- "**KLayout**" 是上游项目的名称。本应用以 "KLayout" 命名，是为**如实标明软件身份**
  （即 KLayout 的 HarmonyOS 移植版），属描述性合理使用，**不主张任何商标权**，
  也不代表上游作者的官方背书。
- 本应用图标由上游 KLayout 官方 logo（`src/icons/images/logo@2x.png`，随 GPL-3.0 分发）
  加工而成（添加背景层以适配 HarmonyOS 分层图标规范），未引入第三方素材。
- 界面字体使用 HarmonyOS 系统内置字体，未内嵌任何商业字体。
- 若上游作者对名称或标识的使用有异议，我们将立即调整并重新提交。

---

## 八、免责与担保（源自 GPL-3.0 第 15、16 条）

> 本程序为自由软件，在适用法律允许的范围内**不提供任何担保**。
> 除非另有书面约定，版权持有人和/或其他提供者"按原样"提供本程序，
> 不附带任何明示或默示的担保，包括但不限于对适销性和特定用途适用性的默示担保。
> 本程序的全部质量与性能风险由使用者承担。

KLayout 是版图查看与编辑工具，输出结果**不构成任何工程或制造决策依据**；
使用者需自行校验流片数据的正确性。

---

## 九、附：给审核方的应答模板

若审核方就"开源软件上架资质"提出质询，可回复：

> 本应用为开源项目 KLayout（GPL-3.0）的 HarmonyOS 平台移植版，属 GPL-3.0 许可下的合法再分发。
> 依据该许可，原作者已授权任何人复制、修改与再分发本软件。
> 我们已在 <https://github.com/yangy79/KLayout-on-Harmony-PC> 公开完整的、与发布包一一对应的
> 源代码（含移植适配改动与一键还原脚本），并完整保留上游版权声明与许可文件；
> 应用内"关于"页面亦提供许可与源码入口。
> 本应用不含我方拥有的闭源代码，因此不适用「软件著作权登记」这一资质路径；
> 如需进一步材料（如上游许可证明、源码比对报告、与上游的沟通记录），我们可随时提供。

---

*本声明随应用版本更新而更新。最新版见源码仓库根目录 `OPENSOURCE-COMPLIANCE.md`。*
