# 构建说明

从零把 KLayout 0.30.10 编到 HarmonyOS PC 上、并打出可上架的 `.app` 的完整流程。

> **实测环境**：HarmonyOS PC（aarch64 / musl）、无 Java、无 g++、无包管理器。
> OHOS SDK `26.0.0.18`（`/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos`）。
> 部分步骤包含**本机专有的绕坑手段**，换机器时见每节的提示。

---

## 0. 总览

```
上游 KLayout 0.30.10 源码包 ──┐
       + patches/ 补丁        ├─► 完整可编译源码树 ──┐
       + overlay/ 新增文件    ┘                      │
                                                     │
Qt 5.12.12 for OpenHarmony ──► qtbase 构建（仅此模块）┘
                                                     │
                                    build.sh（KLayout 官方构建脚本）
                                                     │
                              libklayout.so + libklayout_*.so + stream 插件
                                                     │
                            注入 ohos-app/（build_klayout_hap.sh）
                                                     │
                       hvigor release 构建 + 原生打包（build_release.sh）
                                                     │
                       签 HAP → 打 .app → 签 .app（build_app_pack.sh）
                                                     │
                                      klayout-1.0.0-release.app
```

---

## 1. 准备源码树

```sh
sh scripts/setup-source.sh --out ~/dev/klayout-0.30.10
```

脚本会校验上游源码包的 SHA-256 并打上全部移植补丁。校验值：

```
URL      https://www.klayout.org/downloads/source/klayout-0.30.10.tar.gz
大小     103949878 字节
SHA-256  96f7db5a744d9cd8ac913bb9186ce3b51e836321665d8f874336d0d43d2275c0
```

---

## 2. 构建 Qt 5.12.12 for OpenHarmony（仅 qtbase）

见 [`../qt5-ohos/README.md`](../qt5-ohos/README.md)。要点：

1. 取得 Qt for OpenHarmony 源码包（`harmonyos-5.12.12` 分支）；
2. 对 `qtbase/mkspecs/ohos-clang/qmake.conf` 打上
   `patches/qt5-ohos-mkspec-no-werror.patch`（`-Werror` → `-Wno-error`）；
3. `sh configure.sh` → `sh build_qtbase.sh` → `sh install_qtbase.sh`。

产物：`install/5.12.12/ohos-arm64-v8a-clang/`，其中的 `bin/qmake` 供下一步使用。

> **本机坑**：`PATH` 必须重建（把 `qt5-ohos/hostbin` 放最前），否则注入的坏 `rm`
> 会让所有 Makefile 的 `rm -f` 规则报 `Error 127`。同时本机 `uname -s` 返回
> `HarmonyOS`，`configure` 无法自动识别宿主，必须显式 `-platform linux-clang-native`。

---

## 3. 编译 KLayout

```sh
cd ~/dev/klayout-0.30.10

export NATIVE_OHOS_SDK=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native

./build.sh \
  -qmake ~/dev/qt5-ohos/install/5.12.12/ohos-arm64-v8a-clang/bin/qmake \
  -noruby -nopython -without-qtbinding \
  -without-qt-svg -without-qt-multimedia \
  -without-qt-designer -without-qt-uitools \
  -nolibgit2 -nolstream \
  -build ~/dev/klayout-0.30.10/build-ohos \
  -bin   ~/dev/klayout-0.30.10/bin-ohos
```

产物（`build-ohos/` 下）：

| 产物 | 说明 |
|---|---|
| `libklayout.so` | 主程序。**注意不叫 `klayout`** —— OHOS mkspec 把 `TEMPLATE=app` 强制成 `-shared`，`main()` 就在这个 `.so` 里，由 QPA 插件 `dlsym` 启动 |
| `libklayout_*.so` | 20 个模块库（tl / db / gsi / lay / laybasic / layview / …） |
| `db_plugins/*.so`、`lay_plugins/*.so` | 25 个 stream 插件（GDS2 / OASIS / CIF / DXF / LEF-DEF / MAG / MALY / PCB …） |

### 关闭这些可选依赖的原因

| 开关 | 原因 |
|---|---|
| `-noruby` / `-nopython` / `-without-qtbinding` | 本机无 Ruby / Python 解释器；关掉 qtbinding 同时也去掉了对 QtSvg 与 X11 `gsiqt` 的引用 |
| `-without-qt-svg` / `-without-qt-multimedia` | 这两个 Qt 模块未构建 |
| `-without-qt-designer` / `-without-qt-uitools` | 未构建 QtUiTools |
| `-nolibgit2` / `-nolstream` | 避免额外的外部依赖（`libgit2`、LStream） |

**后果**：应用内不含脚本引擎，DRC/LVS 脚本与宏不可用；**版图查看与编辑等 CAD 核心功能不受影响**。

### 增量重编

只改了 `libklayout.so` 的源码时，不必重跑整个 `build.sh`：

```sh
cd ~/dev/klayout-0.30.10/build-ohos/klayout_main/klayout_main
make -j8        # 产出 ../../../build-ohos/libklayout.so
```

> **两个坑**：
> 1. `PATH` 必须包含 `/data/service/hnp/bin`（`make` 在那里，不在 `/bin`）；
> 2. `klayout_main/Makefile` 会在 `.pro` 比它新时**自动重跑 qmake**，而重跑用的参数
>    是 Makefile 头部 `# Command:` 行里那一长串。若 `.pro` 被改动，请先确认 Makefile
>    没有被覆盖成"裸参数"版（症状：版本宏为空、`HAVE_QT_SVG=1`）。真被覆盖了，就照
>    `build-ohos/lay/lay/Makefile` 头部的 `# Command:` 行逐字重跑 qmake。

---

## 4. 注入并打包 HAP

见 [`../build-scripts/README.md`](../build-scripts/README.md)。顺序：

```sh
sh build-scripts/build_klayout_hap.sh   # 注入 .so + 资源树到 ohos-app/
sh build-scripts/build_release.sh       # release 编译 + 原生打包 + 自检
sh build-scripts/build_app_pack.sh      # 签 HAP → .app → 双验
```

产物：

```
klayout-1.0.0-release.hap    106,037,546 字节
klayout-1.0.0-release.app    106,053,081 字节   ← 上传 AGC 的是这个
```

### 三个必知点

1. **必须走 `build_release.sh`**。`hvigorw assembleHap` 不传 `buildMode` 默认是
   DEBUG，产出包内 `app.debug=true` 且带 `ets/sourceMaps.map` —— AGC 明令 API≥11
   的包不得含调试信息，**上架必拒**。`build_release.sh` 末尾会自检并断言。
2. **`PackageHap` 失败是预期的**。本机无 java，hvigor 一定在
   `spawn java -jar app_packing_tool.jar` 处报 `Error Code 00308018`；只要它前面的
   编译任务都完成了，中间产物就齐备，随后用 SDK 自带的原生 `ohos_packing_tool` 补
   上打包即可（`pack_hap_native.sh`）。
3. **发布包不能侧载**。发布 Profile 是 `app_gallery` 分发类型，设备不信任
   （`code:9568322`）。要真机验证 release 构建，用
   `smoke_test_release.sh`（临时改回调试包名 + 调试证书签同一份 release 产物）。

---

## 5. 依赖版本速查

| 组件 | 版本 / 标识 |
|---|---|
| KLayout | 0.30.10（源码包 SHA-256 `96f7db5a…`） |
| Qt | 5.12.12 for OpenHarmony，`tqtc/harmonyos-5.12.12` |
| OHOS SDK | `26.0.0.18`（NDK clang 15） |
| compatibleSdkVersion | `5.0.0(12)` |
| 目标 ABI | `arm64-v8a` |
| 设备形态 | `2in1` |
