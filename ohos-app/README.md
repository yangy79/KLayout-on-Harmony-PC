# ohos-app/ —— KLayout 的 HAP 壳工程

这是一个 **DevEco Studio / hvigor 工程**（Stage 模型）。它的职责只有一件事：
**启动宿主进程，加载并运行 `libklayout.so`**。

Qt for OpenHarmony 的 QPA 插件 `libqohos.so` 会在 ArkTS 侧准备好 Qt 运行环境后，
`dlopen` 由 `APP_LIBRARY_NAME` 指定的库并 `dlsym("main")` 启动它。所以本应用真正的
"C++ 主程序"是 `libklayout.so`，而不是壳里的 `libentry.so`。

> 工程骨架源自 Qt 5.12.12 for OpenHarmony 随附的官方 DevEco 模板
> （`qtbase/src/harmonyos/templates`，LGPL-3.0）。模板原始说明保留在
> [`README.qt-template.md`](README.qt-template.md)。

---

## 1. 相对 Qt 官方模板的改动

用 `diff -rq` 对比模板可确认，全部差异只有下列几处：

| 文件 | 改动 |
|---|---|
| `AppScope/app.json5` | `bundleName` → `com.yangy79.klayout`；`vendor` → `yangy79`；`versionName`/`versionCode` → `1.0.0`/`1000000`；`icon` → `$media:layered_image` |
| `AppScope/resources/base/element/string.json` | 应用名 `KLayout` |
| `AppScope/resources/base/media/` | 换成本应用图标（分层图标：`background.png` / `foreground.png` / `layered_image.json`） |
| `build-profile.json5` | `compatibleSdkVersion` → `5.0.0(12)`；`runtimeOS` → `HarmonyOS` |
| `entry/build-profile.json5` | release 开启混淆（`obfuscation-rules.txt`）；`abiFilters` 收敛为 `arm64-v8a` |
| `entry/src/main/module.json5` | `deviceTypes` 收敛为 **仅 `["2in1"]`** |
| `entry/src/main/ets/common/QtAppConstants.ets` | `APP_LIBRARY_NAME` → `libklayout.so` |
| `entry/src/main/ets/qability/OhosExportModules.ts` | 与上述常量对应的导出项调整 |
| `entry/src/main/resources/**/element/string.json` | 模块名 / 描述文案 |
| `entry/src/main/resources/base/media/` | 启动图标 `startIcon.png`、分层图标前景/背景 |
| （删除）`qEmbeddedUiExtensionHost/` | 本应用不使用嵌套 UI 扩展，移除以减少模块数 |

`entry/src/main/ets/` 下其余文件（`QAbility.ets`、`QEmbeddedComponentCreator.ets`、
各 `NativeNode.ets`、`QChildProcess.ets` 等）以及 `entry/src/main/cpp/` 均为**模板原样**。

---

## 2. 目录要点

```
ohos-app/
├── AppScope/
│   ├── app.json5                     包名 / 版本 / 图标 / 厂商
│   └── resources/base/
│       ├── element/string.json       应用名
│       └── media/                    分层图标（background / foreground / layered_image）
├── entry/
│   ├── build-profile.json5           release 混淆、abiFilters=arm64-v8a
│   ├── obfuscation-rules.txt
│   └── src/
│       ├── main/
│       │   ├── module.json5          deviceTypes = ["2in1"]，abilities / extensionAbilities
│       │   ├── ets/common/QtAppConstants.ets   ★ APP_LIBRARY_NAME = 'libklayout.so'
│       │   ├── ets/qability/         QAbility 等（来自 Qt 模板）
│       │   ├── cpp/                  libentry.so 的 CMake 工程
│       │   ├── qt/                   libqohos 的 .d.ts 声明
│       │   └── resources/
│       │       ├── base/media/       分层图标、启动图标
│       │       └── resfile/          ← 构建时注入 KLayout 资源树（本仓库不含）
│       └── ohosTest/                 单元/集成测试骨架（模板自带）
├── build-profile.json5               compatibleSdkVersion 5.0.0(12)
├── hvigorfile.ts / oh-package.json5 / hvigor/
└── README.qt-template.md             Qt 官方模板原始说明
```

### ★ 两处构建期才会出现的目录

本仓库**不包含**这两个目录（它们是构建产物 / 体积大），由打包脚本注入：

| 目录 | 内容 | 注入者 |
|---|---|---|
| `entry/libs/arm64-v8a/` | 打包脚本注入的 **55 个 `.so`**：`libklayout.so` + 20 个 `libklayout_*.so` + 25 个 stream 插件 + 7 个 Qt 库 + `libqohos.so` + `libc++_shared.so`（最终 HAP 里共 56 个，多出的 1 个是壳自身编译出的 `libentry.so`） | [`../build-scripts/build_klayout_hap.sh`](../build-scripts/build_klayout_hap.sh) |
| `entry/src/main/resources/resfile/klayout/` | KLayout 运行时资源树（68 个文件：`tech` / `salt` / `drc` / `macros` / `pymacros`） | 同上（源在 [`../overlay/klayout-resources/`](../overlay/klayout-resources/)） |

> **为什么资源树放 `resfile/` 而不是 `rawfile/`**：
> `rawfile` 打包在 HAP 内**安装后不解压**，只能通过 `resourceManager` NDK 读取，
> KLayout 的 `std::ifstream` 完全够不着；`resfile` 安装后会**解压成真实磁盘文件**，
> 正是 Qt 的 `QOhosAppContext.resourceDir` 所指的
> `/data/storage/el1/bundle/entry/resources/resfile`。

> **为什么 stream 插件放 `libs/` 而不是资源目录**：
> OHOS 安全策略**禁止从用户可写分区 `dlopen`**。KLayout 默认从
> `KLAYOUT_PATH/db_plugins/` 加载插件，而该路径落在应用可写目录 → 25 个插件全部
> "Unable to load plugin"。故改放应用安装目录 `libs/arm64-v8a/`，由
> `klayout.cc` 的移植补丁在启动时显式 `dlopen`。

---

## 3. 设备形态为何只声明 2in1

`module.json5` 的 `deviceTypes` 只写 `["2in1"]`。这是**刻意的**：

- 实测通过并提交商店截图的形态只有 PC（2in1）；
- Qt for OpenHarmony 侧存在已知问题 **QTFOROH-1076** —— 清单包含 `phone` 时，
  窗口最小化后无法恢复。

声明了却未验证的形态会被审核质疑，因此先收窄到已验证形态。将来若要扩
`tablet` / `phone`，需先实测通过并补齐对应形态的商店截图。

---

## 4. 构建

见 [`../docs/BUILD.md`](../docs/BUILD.md)。本机要点：没有 java，hvigor 的
`PackageHap` 必然失败（属预期），用原生 `ohos_packing_tool` 补上打包步骤；
release 必须显式传 `-p buildMode=release`，否则默认产出 DEBUG 包（含
`sourceMaps`），AGC 上架必拒。
