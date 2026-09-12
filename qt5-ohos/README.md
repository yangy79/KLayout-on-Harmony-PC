# qt5-ohos/ —— Qt 5.12.12 for OpenHarmony 的构建配置

本目录是**我们在 HarmonyOS PC 上构建 Qt 5.12.12（仅 `qtbase`）所用的配置与配套脚本**。
它不含 Qt 源码，也不含 Qt 的二进制；只含「怎么编的」和「改了什么」。

## 1. 源码标识

| 项 | 值 |
|---|---|
| Qt 版本 | 5.12.12 |
| 发行标识 | Qt for OpenHarmony 源码包 `qt-harmonyos-src-5.12.12` |
| 主分支 | `tqtc/harmonyos-5.12.12`（The Qt Company 的 HarmonyOS 支持分支） |
| 源码包 `.tag` | `a5efc71951a53c045a89b9049761723576cc404a` |
| `qtbase/.tag` | `15afb070c694be2513facf20dbcfc54d4249f035` |
| 许可 | LGPL-3.0（源码包内 `LICENSE.LGPLv3` 等原样保留） |

源码包按上面标识可从 Qt 官方渠道取得。**本仓库只包含我们对它的改动**，见第 4 节。

## 2. 我们构建了哪些 Qt 模块

**只有 `qtbase`**（`make module-qtbase` + `module-qtbase-install_subtargets`）。
其余模块要么被 `-skip`，要么对 KLayout 无用。KLayout 实际用到并随包分发的 Qt 库：

```
libQt5Core.so  libQt5Gui.so  libQt5Widgets.so  libQt5Network.so
libQt5Xml.so   libQt5PrintSupport.so  libQt5Sql.so
libqohos.so   ← Ohos 平台插件（QPA），负责启动宿主进程并 dlopen 应用库
```

**未构建**：QtSvg、QtMultimedia、QtDesigner、QtUiTools、QtSvg（因此 KLayout 侧
相应功能被关闭）。`qtsvg` / `qttools` 等模块在 `configure` 里被 `-skip`。

## 3. 构建步骤

```sh
# 0) 环境变量（NDK 路径按你本机改）
export NATIVE_OHOS_SDK=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native
export OHOS_SDK_ROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos

# 1) 配置（产出 build-arm64/ 下的 Makefile）
sh configure.sh

# 2) 编译 qtbase
sh build_qtbase.sh

# 3) 安装到 -extprefix（configure.sh 里指定）
sh install_qtbase.sh
```

产物在 `install/5.12.12/ohos-arm64-v8a-clang/`，其中
`bin/qmake` 就是编译 KLayout 时要传给 `build.sh -qmake` 的那个。

### 3.1 configure 的三个关键选择

| 参数 | 为什么 |
|---|---|
| `-platform linux-clang-native` | 本机 `uname -s` 返回 `HarmonyOS`，`configure` 无法自动识别宿主；且本机**无 g++**，官方 `linux-clang` mkspec 里 `-ccc-gcc-name g++` 会直接失败，故自建不依赖 g++ 的 mkspec |
| `-xplatform ohos-clang` | 目标平台的 mkspec |
| `-extprefix <本机可写目录>` | NDK 目录只读，不能作为安装目标 |

因为宿主与目标用同一个 clang（本机 clang 就是 OHOS NDK clang），编出的
`qmake` / `moc` / `uic` / `rcc` 在本机可直接运行 —— 这叫「本机自持构建」，
不需要交叉编译宿主机工具。

## 4. 我们对 Qt 的改动：只有 1 行

`qtbase/mkspecs/ohos-clang/qmake.conf`：

```diff
@@ -57,7 +57,7 @@
     -no-canonical-prefixes \
     -fno-addrsig \
     -Wformat \
-    -Werror
+    -Wno-error
```

**原因**：本机 clang 15 会对 KLayout（以及其它真实世界的 C++ 代码）报出若干
良性告警（如 `-Wimplicit-const-int-float-conversion`），mkspec 里写死的
`-Werror` 会把它们全部变成编译失败。移植期必须放开。

补丁文件：[`../patches/qt5-ohos-mkspec-no-werror.patch`](../patches/qt5-ohos-mkspec-no-werror.patch)。
修改后的完整 mkspec 也在本目录：`mkspecs/ohos-clang/`。

> ⚠️ 同一 mkspec 里还有一处**上游自带**的、对我们影响很大的设定：
> app 模板（`TEMPLATE = app`）被强制加 `-shared`。所以 KLayout 编出来的
> `main()` 在 `libklayout.so` 里，由 `libqohos.so` 通过 `dlopen` + `dlsym("main")`
> 启动 —— 这也是 `klayout_main.pro` 里必须加 `-Wl,--export-dynamic` 的原因
> （mkspec 同时带 `-fvisibility=hidden`，不加的话 `main` 会被隐藏）。

## 5. hostbin/ —— 本机 shim

| 文件 | 作用 |
|---|---|
| `rm` | 干净的 `rm` 转发脚本。WorkBuddy 注入的 PATH 里有一个坏 `rm`（bad interpreter），会让所有 Makefile 的 `rm -f` 规则 `Error 127`。构建时把 `hostbin` 放到 `PATH` 最前面即可 |
| `ohos-host-linux-shim.cjs` | Node preload shim，把 `os.type()` 从 `HarmonyOS` 伪装成 `Linux`。hvigor 用它判平台，不伪装会去加载不存在的 `*.dylib` |

## 6. prepare_qt_hap_shell.py

把 Qt 官方 DevEco 壳工程模板（`qtbase/src/harmonyos/templates`）改造成指定应用的工程：

```sh
python3 prepare_qt_hap_shell.py \
    --template <qt-src>/qtbase/src/harmonyos/templates \
    --out ./myapp-ohos \
    --bundle-name com.example.myapp \
    --app-lib libmyapp.so \
    --app-label MyApp
```

它做四件事：复制模板 → 可选删除 `qEmbeddedUiExtensionHost` 模块 →
改 `bundleName` / `vendor` / `label` / `APP_LIBRARY_NAME` → 收敛 `abiFilters` 为 `arm64-v8a`。

> `APP_LIBRARY_NAME`（在 `entry/src/main/ets/common/QtAppConstants.ets`）必须与
> HAP 内 `libs/arm64-v8a/` 下的 `.so` 文件名**逐字一致** —— `libqohos.so` 会
> `dlopen` 它并 `dlsym("main")`。本应用该值为 `libklayout.so`。
