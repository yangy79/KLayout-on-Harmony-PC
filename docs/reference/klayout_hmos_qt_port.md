# 在鸿蒙 PC 上跑 KLayout 原生 GUI —— 社区 Qt 方案调研与路线

> 调研日期：2026-09-05。结论：社区 Qt 方案**存在且已较成熟**，但不在本机一键装，需交叉编译 + 签名打包成 HAP。

## 一、社区现状（已核实）
1. **Qt Group 官方 Qt for OpenHarmony**
   - 2026-03-31 开源发布 **Qt 5.12.12 LTS 适配版**（完整保留核心能力：界面渲染、信号槽、I/O、网络、数据库）。
   - 另有官方分支 **tqtc/harmonyos-5.15.16**（持续周更）。
   - 官方文档：https://wiki.qt.io/Qt_for_HarmonyOS ；开源发布说明：wiki.qt.io/Qt5.12.12_Open_Source_Release_for_HarmonyOS_zh
   - 适配率：核心模块 + 关键插件约 90%，已支撑 WPS、剪映、钉钉等十余款生产力工具迁移到 HarmonyOS NEXT。
2. **第三方 Qt 应用移植模式（已验证可行）**
   - 形态：把 Qt Widgets/Quick 应用交叉编译为 **libApp.so**，由 DevEco 的 ArkTS 模板（含 `libqohos.so` QPA 平台插件）在 Ability 生命周期内加载、对接窗口与输入。
   - 打包：用 DevEco Studio 模板工程 → 拷贝 .so 到 `entry/libs/arm64-v8a/` → 签名 → 生成 HAP → 装到鸿蒙 PC/平板运行。
   - 成功案例：calculator（Qt 示例）、**NotePad--(ndd) 文本编辑器**已完整移植到鸿蒙 PC（CSDN 有详细实践）。
3. **KLayout 本身的适配基础**
   - KLayout 是标准 **Qt Widgets 应用**，`build.sh` 支持 `-qmake <path>` 指定 Qt 版本，可用 Qt5 或 Qt6。
   - gitee 上已有 **BigZebra/klayout** 的 OpenHarmony 移植分支（含针对 OHOS 的 `build.sh -qmake` 适配），可作为起点参考。

## 二、对 KLayout 的含义：可移植，但工程量大
要把 KLayout 原生 GUI 搬到鸿蒙 PC，需要：
1. **编译可在本机完成**（实测本机自带 OHOS NDK，`/data/service/hnp/bin/clang` 即 `aarch64-unknown-linux-ohos` 工具链，无需 Windows VM 当编译器）。但需要：(a) 下载 Qt6 for OHOS 预编译库；(b) 用本机 NDK 编译 KLayout 依赖(zlib/expat/curl/Ruby/Python)的 OHOS 构建版；(c) 本机装 JDK + 下载 Command Line Tools for HarmonyOS（含 hvigorw / hap-sign-tool.jar / hdc，其中 hdc 已就绪）。
2. **OHOS 版本的依赖**：Qt5/6（OHOS 构建）、以及 KLayout 的第三方依赖 zlib / expat / curl / Ruby / Python 都要有 OpenHarmony 构建——KLayout 依赖面比 NotePad 宽，这是主要工作量。
3. **交叉编译 KLayout 源码**：`./build.sh -qmake <OHOS_qmake>`（或参考 BigZebra 的 OHOS build 脚本），产出 `libklayout.so`。
4. **对接 DevEco 模板**：把 `libklayout.so` + Qt 运行库（`libQt5*.so`、`libqohos.so` 等）放进 `entry/libs/arm64-v8a`，改 `QtAppConstants.ets` 的 `APP_LIBRARY_NAME`。
5. **签名打包 HAP → 安装到鸿蒙 PC 运行**。

> 注意（2026-09-05 实测修正）：本机实际**自带完整 OHOS NDK 编译器**（`/data/service/hnp/...`，实测能编出合法 aarch64 OHOS ELF），**签名是纯命令行 Java 操作**（hap-sign-tool.jar，`java -jar ... sign-app -mode localSign`），也不需 DevEco GUI。因此**编译、打包(hvigorw)、签名、安装(hdc) 均可本机闭环**。仅两处可能仍要外部：① 下载 Qt6 for OHOS 预编译库 / Command Line Tools（纯文件下载）；② 若目标为商用 HarmonyOS 且要侧载，需在 AGC 账号申请一次绑定 UDID 的调试证书(.cer/.p7b)（任意联网机器/网页即可，文件拷回本机后本地签名）。OpenHarmony 社区自签证书则完全离线、连账号都不需。

## 三、与本机纯 Python 路线 A 的对比
| 维度 | 路线 A：`klayout.db` + plotly HTML（已做原型） | 路线 B：Qt 原生 GUI（社区方案） |
|---|---|---|
| 运行位置 | 本机即开即用 | 本机运行（HAP），本机交叉编译 |
| 编译/签名 | 无 | 本机 NDK 交叉编译 + 本机 java 签名（hap-sign-tool.jar），无需 DevEco GUI |
| 能力 | 看版图、缩放/平移/按层、基础 DRC（headless） | 完整 KLayout：编辑、DRC/LVS 面板、2.5D、LVS 浏览器 |
| 工程量 | 极小（已跑通） | 大（依赖 OHOS 构建 + 移植调试） |
| 风险 | 低 | 中（KLayout 依赖多，OHOS 构建缺件需补） |

## 四、建议
- **仅"看图 / 量测 / 基础 DRC"** → 路线 A 已够用且零成本，继续完善原型即可。
- **必须要完整 KLayout 原生 GUI 体验**（编辑、DRC/LVS 图形面板、2.5D）→ 走路线 B，**整条链路本机可闭环**（本机 NDK 编 + 本机 java 签名 + hdc 装），无需 VM/DevEco GUI；参考 **BigZebra/klayout** 与 **Qt for OpenHarmony** 官方文档；商用机侧载若需华为调试证书，先在 AGC 账号拿一次 .cer/.p7b 拷回本机。

## 五、参考链接
- Qt for OpenHarmony 官方文档：https://wiki.qt.io/Qt_for_HarmonyOS
- Qt 5.12.12 OHOS 开源发布：https://wiki.qt.io/Qt5.12.12_Open_Source_Release_for_HarmonyOS_zh
- Qt for OpenHarmony 构建指南：https://wiki.qt.io/Building_Qt_for_OpenHarmony
- KLayout OpenHarmony 移植（gitee）：https://openharmony.gitee.com/BigZebra/klayout
- NotePad-- 鸿蒙 PC 移植实践（CSDN，可作模板参考）：https://blog.csdn.net/qq8864/article/details/160382276
- 鸿蒙 PC Qt 第三方应用移植指南：https://harmonypc.csdn.net/69d8fdb654b52172bc6892a9.html
