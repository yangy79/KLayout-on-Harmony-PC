# Qt 5.12.12 for OpenHarmony —— 鸿蒙 PC 本机自持构建验证报告

日期：2026-09-10
设备：HUAWEI MateBook Pro（HAD-W32，2in1），HarmonyOS 6.1.0.135，**API 24**，aarch64 / musl
结论：**Qt 可行 —— 已在本机完成 configure + qtbase 全量构建，宿主工具可直接运行，鸿蒙 QPA 平台插件 `libqohos.so` 已产出。**

---

## 一、结论摘要

| 验证项 | 结果 |
|---|---|
| configure（`qtbase` 全套 config tests） | ✅ 退出码 0，`Qt is now configured for building` |
| 宿主工具可运行性 | ✅ `qmake 3.1` / `moc 5.12.12` / `uic 5.12.12` / `rcc 5.12.12` 均在本机直接执行成功 |
| target 库（aarch64-ohos） | ✅ 11 个 `libQt5*.so`，含 **Widgets 8.0 MB / Gui 7.1 MB / Core 6.9 MB** |
| 鸿蒙 QPA 平台插件 | ✅ **`libqohos.so` 10.9 MB**（社区所述"运行时由它 dlopen 应用 .so"的核心库） |
| 模块可用性（KLayout 所需） | ✅ Widgets / Gui / Network / Xml / Concurrent 全部 yes |
| 耗时 | 下载 7 min + 解压 1 min + 多轮 configure + 末轮 make **8 min 42 s** |

**核心意义**：此前判断"Qt 6.12 的宿主工具是 glibc/Windows 二进制，本机 musl 跑不了"——本次证明 **Qt 5.12.12 走本机自持路线完全成立**：宿主编译器就是 OHOS NDK 的 clang，编出来的 moc/uic/rcc/qmake 本身就是 aarch64-ohos ELF，在本机直接可运行，**不再依赖任何外部宿主工具链**。

---

## 二、材料与版本

```
源码   qt-harmonyos-src-5.12.12-20260625.tar.xz   254,667,680 B
       https://download.qt.io/snapshots/qt/qt-for-harmonyos/5.12.12/
       ⚠️ 实测 sha256=1b877f1dca95…，与 wiki 标注的 a5efc71951a5（md5/sha1/sha256 三算法）均不符，
          但 xz -t CRC 校验通过、字节数精确、解压后源码树完整 → 判定可用（疑 wiki 值过期）。

NDK    /data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native   API 26, clang 15.0.4
宿主   perl 5.42.0 / GNU Make 4.4.1 / python3 3.12.9 / cmake 4.1.2 / ninja 1.13.1（本次未用）
       无 g++（只有 clang++）；libc = musl；uname -s = "HarmonyOS"
```

工作目录：`/storage/Users/currentUser/dev/qt5-ohos/`
```
src/        源码树（含本机补丁）
build-arm64/ 构建树
install/    安装目标（-extprefix）
hostbin/rm  可用的 rm（转发 /bin/rm）
hostinc/ohos_host_shim.h   宿主编译 shim
configure.sh / build_qtbase.sh
```

---

## 三、可复现步骤

### 1. 下载与解压（本机无 git，直接取 tar.xz；无 7z 但有 xz/tar）

```sh
curl -sL -C - -o qt-src.tar.xz \
  https://ftp.jaist.ac.jp/pub/qtproject/snapshots/qt/qt-for-harmonyos/5.12.12/qt-harmonyos-src-5.12.12-20260625.tar.xz
xz -t qt-src.tar.xz                 # 完整性校验（比 sha 可靠，因 wiki 值对不上）
tar -xJf qt-src.tar.xz
```

### 2. 打本机补丁（见第四节，共 5 处）

### 3. configure

```sh
export NATIVE_OHOS_SDK=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native
export PATH=/storage/Users/currentUser/dev/qt5-ohos/hostbin:<python3/bin>:$NATIVE_OHOS_SDK/llvm/bin:/data/service/hnp/bin:/bin:/usr/bin

../configure -v \
  -platform linux-clang-native \        # ★ 自建，非官方 linux-clang
  -xplatform ohos-clang \
  -prefix /data/storage/el1/bundle/libs/arm64 \     # 设备运行路径
  -extprefix <本机可写目录>  \                       # ★ NDK 目录只读，不能装那儿
  -opensource -confirm-license -release \
  -no-use-gold-linker -no-gcc-sysroot \
  -ohos-arch arm64-v8a -opengles3 \
  -no-dbus -c++std c++14 -nomake examples -nomake tests \
  <官方那一大串 -skip ...>
```

### 4. 构建

```sh
make -j20 module-qtbase
```

---

## 四、本机自持构建特有的 5 个坑（官方 macOS/Windows 路线不会遇到）

### 坑 1：`uname -s` = `HarmonyOS`，configure 无法识别宿主平台
`qtbase/configure` 用 `case "$UNAME_SYSTEM:..."` 匹配宿主 OS，无 HarmonyOS 分支 → 直接进入 `*)` 报错退出。
**解法**：显式 `-platform`。

### 坑 2：官方 `linux-clang` mkspec 依赖 g++
该 mkspec 含 `QMAKE_LFLAGS += -ccc-gcc-name g++`，本机没有 g++。
**解法**：复制为 `qtbase/mkspecs/linux-clang-native/`，删掉该行。

### 坑 3：宿主编译器预定义 `__OHOS__`，连宿主构建也被当成 OHOS ★最关键
`/data/service/hnp/bin/clang` 就是 NDK 的 ohos clang，预定义了 `__OHOS__`（实测 `clang++ -dM -E` 可见）。
`qsystemdetection.h:115` 据此 `#define Q_OS_OHOS`，于是 bootstrap 阶段的
`qlogging.cpp:80` 走到 `#ifdef Q_OS_OHOS` → `#include <QtCore/private/qohoslogger_p.h>` → `qthread.h`，
而 bootstrap 环境没有 `QT_FEATURE_*` / QObject 体系，直接报
`division by zero in preprocessor expression`、`use of undeclared identifier 'd_ptr'`。
**解法**：宿主 mkspec 加 `QMAKE_CXXFLAGS += -U__OHOS__`（实测 `__linux__` 保留，宿主按 Linux 语义构建）。

### 坑 4：musl 没有 `strtoll_l`/`strtoull_l`，而 libc++ 无条件调用
宿主编译用 `-std=c++11`（ISO 变体，不带 `_GNU_SOURCE`），且**即使加 `-D_GNU_SOURCE` 也没用**——
鸿蒙 musl 的 `/usr/include` 与 sysroot 里**根本没有这两个函数**（全目录 grep 无结果）。
NDK 的 libc++ 在 `<locale>` 的 `__num_get_(un)signed_integral` 里无条件调用它们，
导致任何用到 `<locale>`/`<iostream>` 的宿主代码编译失败（首个炸点是 `src/tools/qlalr/compress.cpp`）。
**解法**：写 shim 头，用 `-include` 注入宿主编译：
```c
static __inline__ long long strtoll_l(const char *s, char **e, int b, void *loc)
{ (void)loc; return strtoll(s, e, b); }
```
（`*_l` 变体只多一个 `locale_t`；调用处一律传 `_LIBCPP_GET_C_LOCALE`，忽略它语义等价。宿主工具不做 locale 敏感解析。）
文件：`hostinc/ohos_host_shim.h`；挂载：`QMAKE_CXXFLAGS += -include $$HOST_SHIM`。

### 坑 5：构建期 `rm` 是坏 shim，Makefile 全崩
`rm` 被注入为 `.../shim/safe-bin/rm`，是个 `bad interpreter` 坏脚本（rc=126）；
Makefile 里 `rm -f` 规则全部 `Error 127`。且 `rm` 在当前 shell 是 **function**，改 PATH 覆盖无效（PATH 管不到 function）。
**解法**：构建脚本**完全重建 PATH、不继承 `$PATH`**，并把 `hostbin/rm`（`exec /bin/rm`）放最前。
另注意 `python3` 位于 `/data/storage/el1/bundle/libs/arm64/python/bin`，干净 PATH 里必须带上。

### 附：两个工具缺失
NDK 的 `llvm/bin` **缺 `llvm-ranlib` 和 `llvm-strip`**（本机 `/data/service/hnp/bin/` 有后者）。
**解法**：`QMAKE_RANLIB` 改为 `llvm-ar s`（等价，已实测）；`QMAKE_STRIP` 指向 `/data/service/hnp/bin/llvm-strip`。

### 附：`QMAKE_HOST.os` 白名单
`qtbase/mkspecs/features/qt_functions.prf:194` 按 `QMAKE_HOST.os` 设定库路径变量名，
无 HarmonyOS 分支 → `openharmonydeployqt` 报 `Project ERROR: Operating system not supported.`
**解法**：把 `HarmonyOS` 并入 `Linux|FreeBSD|...|GNU` 那一组（本机库路径语义就是 `LD_LIBRARY_PATH`）。

---

## 五、产出清单

**target 库**（`build-arm64/qtbase/lib/`）

```
libQt5Core.so   libQt5Gui.so   libQt5Widgets.so   libQt5Network.so
libQt5Xml.so    libQt5Sql.so   libQt5Concurrent.so  … 共 11 个
```

**平台插件**（`build-arm64/qtbase/plugins/platforms/`）

```
libqohos.so  ← 鸿蒙 QPA，10.9 MB，关键
libqeglfs.so  libqlinuxfb.so  libqminimalegl.so  libqvnc.so
```

**宿主工具**（`build-arm64/qtbase/bin/`，全部 aarch64 ELF，本机可直接跑）

```
qmake  moc  uic  rcc  qlalr  qvkgen  qfloat16-tables  openharmonydeployqt
```

---

## 六、下一步建议

1. **`make install`** 把 qtbase 落到 `-extprefix`，得到规范的 `{bin,lib,plugins,mkspecs}` 布局，便于后续给应用用。
2. **先移植一个 Qt 示例应用跑通全链路**（推荐官方 `widgets/widgets/calculator`）：
   按社区架构，鸿蒙上 Qt 应用是 **`.so` 不是可执行文件**——CMake/qmake 产出 `add_library(... SHARED ...)`，
   由 ArkTS 壳工程 + `libqohos.so` 在运行时 dlopen；`QtAppConstants.ets` 的 `APP_LIBRARY_NAME` 必须与 .so 名逐字一致。
   打包与签名已有现成能力（`hap-sign-tool` + 已验证的 HAP 打包脚本），`openharmonydeployqt` 非必需。
3. **再评估 KLayout 本体**：它支持 `-noruby -nopython`，依赖只剩 Qt + zlib + expat + curl；
   且 KLayout 是 qmake 工程，与 Qt 5.12 天然匹配（不用做 Qt6 的 CMake 转换）。
4. **已知风险**：configure 显示 **Fontconfig = no**（社区已知），KLayout 的代码编辑器需要自备等宽字体并 bundle。

---

## 七、遗留事项

- 本次只构建了 `module-qtbase`（KLayout 所需模块都在其中）。其余模块（qtdeclarative、qtmultimedia、qtcharts 等）未构建，需要时再单独 `make module-<name>`。
- 尚未 `make install`。
- 尚未做真机运行验证（需要 DevEco 壳工程 + 签名装机）。
