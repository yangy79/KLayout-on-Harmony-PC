# 社区调研：Qt 跑在鸿蒙 PC 上——谁做成了，留了什么文档

日期：2026-09-10
结论：**已经有很多人跑通了，而且文档很完整。更重要的是，官方有一条我们之前完全没走的路。**

---

## 一、结论速览

| 问题 | 答案 |
|---|---|
| 有人跑通了吗？ | ✅ 有。**12+ 个开源 Qt 软件已在鸿蒙 PC 真机跑通** |
| 留文档了吗？ | ✅ 非常完整：官方 wiki（中文）+ 社区 50+ 篇实战博客 + 模板工程 + 预编译库 |
| 用什么 Qt？ | **Qt 5.12.12 鸿蒙开源版（LGPL）**，官方 2026-03-31 发布——**不是 Qt 6.12** |
| 我们之前的方向对吗？ | ❌ 不对。Qt 6.12 是 Technology Preview 且宿主工具跑不了；**Qt 5.12.12 才是社区主路** |
| 本机能不能自己构建？ | ✅ **能**。perl / make / clang / NDK / 磁盘 / CPU 全部具备（见第四节） |

---

## 二、官方资源（Qt 官方，中文）

### Qt 5.12.12 鸿蒙开源版

```
https://wiki.qt.io/Qt5.12.12_Open_Source_Release_for_HarmonyOS_zh
```

- 定位：面向**平板和 PC** 设备的 Qt 5.12.12 LTS 适配版
- 许可：原 Qt5 部分不变，**鸿蒙适配新增代码为「商业许可 + LGPL v3」双许可**
- 源码包（**实测可下载，254 MB**）：

| 版本 | 链接 | sha | 要求 |
|---|---|---|---|
| 20260625（新） | `https://download.qt.io/snapshots/qt/qt-for-harmonyos/5.12.12/qt-harmonyos-src-5.12.12-20260625.tar.xz` | `a5efc71951a5` | API 20+ |
| 20260403 | `.../qt-harmonyos-src-5.12.12-20260403.tar.xz` | `9affa9320102` | API 20+ |

> 我们的设备是 **API 24**，满足要求。

### Qt for OpenHarmony 中文文档（构建全流程）

```
https://wiki.qt.io/Qt_for_OpenHarmony/zh
```

关键构建命令（macOS 版；Windows 版用 `configure.bat` + mingw32-make）：

```sh
../configure \
    -v -xplatform ohos-clang \
    -prefix /data/storage/el1/bundle/libs/arm64 \
    -extprefix <安装路径>/5.12.12/ohos-arm64-v8a-clang/ \
    -opensource -confirm-license -release \
    -no-use-gold-linker -no-gcc-sysroot \
    -ohos-arch arm64-v8a -opengles3 \
    -no-dbus -c++std c++14 \
    -nomake examples -nomake tests \
    -skip qt3d -skip qtwebengine -skip qtwayland ...（大量 skip）
make -j16 && make install
```

需要的环境变量：`NATIVE_OHOS_SDK`、`OHOS_SDK_SYSROOT`、`LLVM_INSTALL_DIR`

> 注意：`-prefix` 是**设备上的运行路径** `/data/storage/el1/bundle/libs/arm64`，
> `-extprefix` 才是**宿主上的安装路径**。别搞混。

---

## 三、社区（中文，最活跃）

### 组织与入口

| 资源 | 地址 |
|---|---|
| Harmony PC 开发者社区 | https://harmonypc.csdn.net/ |
| 开源组织（100+ 项目） | https://atomgit.com/OpenHarmonyPCDeveloper |
| **预编译 Qt-OHOS 5.12.12** | https://gitcode.com/OpenHarmonyPCDeveloper/ohos_Qt5.12.12 |
| 50+ 篇实战导航 | https://harmonypc.csdn.net/6a3a2d9f10ee7a33f2811444.html |
| 从 0 创建项目指南（必读） | https://blog.csdn.net/weixin_52908342/article/details/161343743 |
| 环境搭建 + HelloWorld | https://blog.csdn.net/qq8864/article/details/159958545 |

`ohos_Qt5.12.12` 仓库内含三个目录：
- `qt_ohos_release` —— **预编译好的 Qt-OHOS 库**（省去自己编译）
- `qt_ohos_template` —— **DevEco 壳工程模板**（ArkTS + `QtAppConstants.ets`）
- `docs` —— 文档

### 已跑通的真实案例（12+）

| 项目 | 难度 | 关键坑 |
|---|---|---|
| **DiffPDF** | 中 | 第一个完整链路，**推荐第一个读** |
| NotePad-- (Ndd) | 入门 | 纯 Qt Widgets |
| glogg | 中 | qmake → CMake 重写；移除 boost |
| NitroShare | 中 | 去 SSL、鸿蒙网络限制 |
| nomacs | 中 | dlopen 期 symbol-not-found |
| CopyQ | 中偏难 | client/server 单进程双角色、QSystemTrayIcon |
| KDiff3 | 进阶 | KDE Frameworks 瘦身 |
| QElectroTech | 进阶 | qmake mkspec + 7 处错误修复 |
| **LiteIDE** | 最难 | qmake + 26 个插件 + ABI 降级 |
| TeXstudio | — | Qt 5.12.12（你本来就在用，可作参考） |
| 7-Zip | — | native 库直连 ArkTS（非 Qt） |

---

## 四、社区沉淀的核心架构认知（这几点之前我们都不知道）

**1. 鸿蒙上的 Qt 应用不是可执行文件，是 `.so`**

```
传统 PC：Qt Creator → 编译 → app.exe
鸿蒙：   Qt Creator → 编译 → libXXX.so
        → 塞进 DevEco 壳工程 → ArkTS 启动时由 libqohos.so (QPA) dlopen 加载
```

CMake 里的分水岭（社区原话）：

```cmake
if(OHOS)
    add_library(${PROJECT_NAME} SHARED ${SRC})   # 鸿蒙：共享库
else()
    add_executable(${PROJECT_NAME} ${SRC})       # 其它：可执行文件
endif()
```

**2. `QtAppConstants.ets` 里的库名必须和 .so 文件名完全一致**

```ts
export const APP_LIBRARY_NAME = 'libNotePad--.so';
```

**3. 已知高频坑**
- `dlopen` 不能加载可写路径的 .so（与官方 QTBUG-146624 一致）
- 部署后启动闪退，**crash 在 musl loader 里**（最致命的一个）
- `symbol not found`（nomacs 案例）
- fontconfig 的 `config.sub` 不认识 `aarch64-linux-ohos`，要换新版
- Qt-OHOS 的 `qobjectdefs.h` 缺 `SuperData`，moc 输出编译报错
- qmake 项目要改 mkspec；ABI 有时需要降级

---

## 五、对我们路线的重大影响

### 之前判断的问题

我此前主推 **Qt 6.12**，理由是官方提供预编译鸿蒙包。但实测发现：
- 6.12 是 **Technology Preview**
- 其宿主工具（`moc/uic/rcc/qmake6`）是 **glibc Linux** 或 **Windows MSVC** 二进制，
  **本机是 musl，跑不了** → 必须另建宿主 Qt

### Qt 5.12.12 路线的优势

| 维度 | Qt 6.12（原计划） | **Qt 5.12.12（社区主路）** |
|---|---|---|
| 成熟度 | Technology Preview | **LTS + 12+ 真机案例** |
| 许可 | 需确认 | LGPL v3（新增代码双许可） |
| 构建模型 | **强制 host + target 两次构建** | **单树构建**，宿主工具与目标库同编译器 |
| 本机可行性 | ❌ 宿主 glibc 跑不了 | ✅ **宿主工具用 ohos clang 编 → 直接在本机跑** |
| 与 KLayout 匹配度 | KLayout 是 qmake 工程，Qt6 用 CMake，要转换 | **KLayout 原生 qmake + Qt5，天然匹配** |
| 文档 | 英文 wiki 为主 | **中文 wiki + 50+ 篇中文实战** |

**关键点**：Qt5 没有 Qt6 那种强制的 host/target 分离。因为**开发机就是 aarch64-ohos**，
用 ohos clang 编出来的 `moc`/`uic`/`rcc`/`qmake` **本身就是能在鸿蒙 PC 上跑的二进制**——
自持工具链成立。

### 本机可行性实测（全部通过）

```
perl     5.42.0        ✅   /data/service/hnp/bin/perl
GNU Make 4.4.1         ✅   /data/service/hnp/bin/make
python3  3.12.9        ✅
xz / unxz              ✅   /data/service/hnp/bin/xz
clang(OHOS) 15.0.4     ✅   aarch64-unknown-linux-ohos-clang
NDK sysroot            ✅   .../ohos-sdk_26.0.0.18/ohos/native/sysroot
磁盘                    ✅   可用 442 GB
CPU                    ✅   20 核
```

源码包 254 MB，可直接 `curl` 下载（无需 git，本机没装 git）。

### 剩余风险

1. **Qt5 `configure` 的宿主平台检测**：`uname -s` 返回 `HarmonyOS`（不是 Linux），
   大概率需要强制 `-platform linux-clang` 并设 `CC/CXX` 为 ohos clang
2. **openssl 头文件**（可选）：`-openssl-runtime -I<头文件路径>`，
   可从 `gitee.com/openharmony/third_party_openssl` 取
3. Qt 5.12 较老，用 clang 15 编译可能有少量 `-Werror` 类报错（社区已有 FAQ）
4. 编译耗时：20 核，估计 1~2 小时（Qt5 比 Qt6 小很多）

---

## 六、建议的下一步

**换道到 Qt 5.12.12，并在本机自持构建。** 具体顺序：

1. **下载源码**（254 MB）→ `~/dev/qt5-ohos/`
2. **先跑一次 `configure` 探针**（不编译），看平台检测卡不卡——这是唯一的风险点，
   半小时内就能定生死
3. configure 通过 → `make -j20` 构建安装
4. 拿到 `moc/uic/rcc/qmake` + `libQt5*.so` + `plugins/platforms/libqohos.so`
5. 用社区的 `qt_ohos_template` 壳工程 + 我们的 `hap-sign-tool` 签名 → `hdc install`
6. 跑通最小 Qt Widgets demo 后，再碰 KLayout

> 第 5 步我们已经验证过一遍：`hap-sign-tool`（原生 ELF）+ `build_mini_hap.py`
> 已经成功签出并安装过 `official-mini-signed.hap`，签名和装机不是障碍。

**要不要现在开始下载源码并跑 configure 探针？**
