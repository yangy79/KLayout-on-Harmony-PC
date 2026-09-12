# KLayout 在 HarmonyOS PC 上的工作总览

> 整理日期：2026-09-05 ｜ 设备：HUAWEI MateBook Pro（HAD-W32，aarch64，HarmonyOS 6.1.0.135，API 24，设备类型 `2in1`）
> 归档位置：`/storage/Users/currentUser/Documents/金融交易/workchain/klayout/`

---

## 一、我做这件事的目的

### 1.1 根本需求

我在搭一条跑在鸿蒙 PC 上的**光子/集成电路版图工作链**。这条链的上游已经打通：

| 环节 | 工具 | 状态 |
|---|---|---|
| 参数化版图生成 | **Nazca Design**（Python） | ✅ 本机可用 |
| 几何布尔运算 | shapely 2.0.6 / gdspy 1.6.13 | ✅ 本机可用 |
| 网格剖分 | gmsh 4.14 | ✅ 本机编译安装完成 |
| GDS 读写 / 几何查询 | **klayout.db** | ✅ 本机可用 |
| **看版图（可视化）** | KLayout GUI | ⚠️ **本次工作的目标** |

整条链缺的最后一块，是**把 Nazca 生成的 GDS 掩模版图真正"看到"**。版图不看图等于闭眼画——线宽对不对、层套没套准、文字有没有糊，全都得眼睛确认。

### 1.2 为什么这事不简单

HarmonyOS PC 有三条硬约束，把常规路子堵死了：

1. **无 C/C++ 编译器**（当时认为）——原生 GUI 应用编不了。
2. **OpenHarmony 安全策略**：只加载系统分区的已签名 `.so`，用户目录的 `.so` 一律拒绝 → 从源码装 KLayout GUI 无门。
3. **Qt 依赖重**——KLayout 是标准 Qt Widgets 应用，Qt 不在系统里。

所以「装个 KLayout」这句在 Linux 上一条 `apt install` 就能解决的事，在鸿蒙 PC 上变成了一个需要调研的工程项目。

### 1.3 目标分解

围绕"看图"这一个需求，实际探索了两条路：

- **路线 A（务实）**：不追求原生 GUI，用现成的纯 Python 能力等价实现看图 + DRC。
- **路线 B（理想）**：把 KLayout 原生 GUI 搬上鸿蒙，体验完整（图层面板、DRC 面板、编辑）。

**我真正需要的是"看到图"，不是"拥有 KLayout"。** 这个区分在复盘时很重要——见第六节。

---

## 二、路线 A：纯 Python 看图 + 无头 DRC（已完成，可用）

### 2.1 关键发现：装的是 Python 绑定，不是残缺的 GUI

我本机的 `klayout` 是 PyPI 包 **v0.30.10**（`~/.local/lib/python3.12/site-packages/klayout`），它是 KLayout 的 **standalone Python bindings**，不是被砍了一刀的 GUI 程序。实测能力边界：

| 模块 | 状态 | 能力 |
|---|---|---|
| `klayout.db` | ✅ 可用 | 无头几何内核：GDS 读写、图层/单元查询、`db.Region` 布尔、`width_check()` / `space_check()` / `enclosing_check()` 等 DRC 判定 |
| `klayout.lay` | ❌ 缺失 | `laycore.so` 不在，GUI 与 DRC 工具集成不在 |
| `pya` | ❌ 缺失 | `pyacore` 不在，完整 GUI 集成 API 不在 |

**结论**：几何内核是全的，只是没有界面。那就自己给界面——或者干脆不要界面。

### 2.2 无头 DRC：`headless_drc.py`

既然几何内核在，DRC 就能跑，不需要 GUI、也不需要 Windows 虚拟机。

```
$ python3 headless_drc.py demo_mask.gds
读入: demo_mask.gds  top_cell=demo_mask  1 DBU = 0.001 um
图层: [(1, 0), (2, 0)]
--- DRC (阈值 0.4 um, 单位已换算 DBU=1nm) ---
  waveguide+text L1/0: 线宽<0.4um 违规=72, 间距<0.4um 违规=28
  device       L2/0: 线宽<0.4um 违规=0,  间距<0.4um 违规=0
```

**这条链路的价值**：Nazca 出 GDS → klayout.db 无头 DRC，全程在鸿蒙本机一个 Python 环境里闭环，VMware、GUI、编译器一个都不需要。

**踩到的尺度坑**（值得记）：Nazca 的 GDS 是 **1 DBU = 1 nm**（`layout.dbu = 0.001` µm）。DRC 阈值必须换算：

```python
物理um ÷ dbu_um = DBU        # 0.4 um = 400 DBU
```

直接把 `0.4` 当阈值传进去，那是 0.4 nm，检查结果会全过——**假通过比报错更危险**。

另外 L1 层的 72 条线宽违规来自 Nazca 生成的**文字笔画**（比 0.4 µm 细），不是真缺陷。真实 PDK 里文字通常放在不参与 DRC 的标注层。

### 2.3 交互看图：`gds_viewer.py` → `gds_viewer.html`

`klayout.db` 解析几何 + `plotly` 出图，生成一个 **4.5 MB 的离线 HTML**（`include_plotlyjs="embedded"`，不联网也能开）：

```
$ python3 gds_viewer.py
顶层 cell: demo_mask | dbu: 0.001 nm
已生成 gds_viewer.html（浏览器打开即可缩放/平移/按层显隐）
```

能力：鼠标缩放 / 平移、按图层显隐、悬浮看坐标、配色沿用 `demo_mask.lyp` 的定义（L1 waveguide 绿、L2 device 橙、L3 text 蓝）。

**实现上的一个坑**：`klayout.db` 里 `Shape.polygon` 和 `Region.each()` 返回的是不同对象，取多边形顶点必须用 `poly.each_point_hull()`（不是 `each_point()`，`PolygonWithProperties` 没有这个方法）；而且 Box 形状也会混进 Region，得用 Region 统一归一化。

### 2.4 路线 A 小结

**零成本、零编译、纯 Python，绕开了鸿蒙所有的 .so 签名限制。** 看图和无头 DRC 两个需求都已满足。

---

## 三、路线 B 调研：原生 GUI 能不能上鸿蒙（结论：能，但代价大）

### 3.1 社区方案现状

调研结论整理在 `klayout_hmos_qt_port.md`。核心事实：

**Qt Group 官方 Qt for OpenHarmony 已经开源**
- 2026-03-31 发布 **Qt 5.12.12 LTS 适配版**，另有官方分支 `tqtc/harmonyos-5.15.16`。
- 核心模块 + 关键插件适配率约 **90%**，已支撑 WPS、剪映、钉钉等十余款生产力工具迁移到 HarmonyOS NEXT。

**第三方 Qt 应用的移植模式已经跑通**
- 形态：Qt Widgets 应用交叉编译为 `libApp.so`，由 DevEco 的 ArkTS 模板（`libqohos.so` 做 QPA 平台插件）加载，对接窗口与输入。
- 已有成功案例：calculator（Qt 示例）、**NotePad--（ndd）文本编辑器**完整移植到鸿蒙 PC。

**KLayout 本身的适配基础**
- 标准 Qt Widgets 应用，`build.sh -qmake <path>` 可指定 Qt 版本（Qt5 / Qt6 都行）。
- gitee 上有 **BigZebra/klayout** 的 OpenHarmony 移植分支可参考。

### 3.2 需要付的代价

| 环节 | 要求 | 现状 |
|---|---|---|
| 交叉编译 KLayout 本体 | OHOS Clang 工具链 + Qt for OHOS 库 + `libqohos.so` QPA | 工具链本机就有（见 3.3） |
| Qt6 for OHOS 预编译库 | 下载即可 | ❌ 未下载 |
| **依赖 OHOS 化** | zlib / expat / curl / **Ruby** / **Python** 都要 OHOS 构建版 | ❌ 一个都没做 |
| 打包 HAP | DevEco 模板工程 + `.so` 放 `entry/libs/arm64-v8a/` | ❌ 未开始 |
| 签名 + 装机 | 见第五节 | ✅ 已打通 |

**Qt5 vs Qt6 的取舍**：Qt5 for OHOS 虽是 LTS，但官方**不给预编译二进制**，得自己从 gerrit 克隆 qt5 源码交叉编译 Qt 库本身；Qt6 for HarmonyOS（6.12.0 Beta2）在线安装器直接带预编译包，省掉这一步，但仍是 Beta。

**注意：依赖里的 Ruby 和 Python 是最难啃的。** KLayout 用 Ruby/Python 做脚本扩展，这两个在 OHOS 上的构建版没有现成轮子，工作量比 calculator、NotePad 这类应用大一个量级。

### 3.3 一个重要纠正：本机 clang 就是 OHOS NDK

调研中期我一度认定"本机无编译器，编译必须去 Windows 虚拟机"。实测后发现**这个判断错了**：

```
/data/service/hnp/bin/clang          版本 15.0.4，默认 target = aarch64-unknown-linux-ohos
/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/
    ├── sysroot（musl libc++）
    ├── ohos.toolchain.cmake
    ├── build-tools/cmake + ninja
    └── llvm/bin/aarch64-unknown-linux-ohos-clang++
```

用它已成功编出 aarch64 OHOS ELF（`file` 显示 `arm64 ... /lib/ld-musl-aarch64.so.1`）。

**修正后的分工**：编译完全可在本机完成，**不需要虚拟机当编译器**。虚拟机的角色从"编译器"降级为"可选的开发机"。

---

## 四、路线 B 的最后一环：HAP 签名（已打通，但走过一大段弯路）

把 `.so` 变成能装的 HAP，需要签名。这一环上我犯了个代价不小的错误。

### 4.1 错误前提

我认定官方签名工具是 `hap-sign-tool.jar`，**必须装 JDK**，而本机没 Java 也不想装。于是决定自研一个纯 Python 签名器。

### 4.2 自研签名器 `sign_hap.py`（880 行）

逆向 OpenHarmony `developtools_hapsigner` 源码，实现了两层签名结构：
1. **内层 CodeSignBlock**（fs-verity，magic `0xE046C8C65389FCCD`）：merkle 树 + SignInfo 内嵌 CMS SignedData。
2. **外层 HAP Signing Block**：插在 ZIP 中央目录前，靠 32 字节 footer（`HAP Sig Block 42`）定位。

期间逐个踩过并修掉 7 个格式坑（CMS signed-attrs 的 DER 规范序、SET 0x31 与 [0] 0xa0 标签差异、`[0] EXPLICIT OCTET STRING`、body 相对偏移、原始 EOCD 还原、P-256/P-384 混合证书链等），以及一个隐蔽的 PEM 探测陷阱（裸 DER 的 p7b 内含 JSON，JSON 里嵌了 `-----BEGIN CERTIFICATE-----` 字符串，用 `b"-----BEGIN" in raw` 判断会被误判并 base64 解码，4101 字节缩成 871 字节）。

**结局**：本地自校验全过（用户态 HapVerify 的 CMS、证书链、Profile、merkle 全部 byte-perfect），但装机时卡在内核：

```
C05A06/installs/CODE_SIGN: [EnableCodeSignForFile]
  Enable fs-verity failed, errno = <129, Key was rejected by service>
```

我做了一个对照实验排除结构因素：把真实 DevEco 产物 `auto_installer.hap` 只改 bundleName，用同一套签名器签字，**同样卡在这一步**——确认问题在签名器产出的 fs-verity 度量，不在 HAP 结构。

### 4.3 真相：官方签名器就在设备上，而且是原生 ELF

复盘目标链时顺手核实，发现整个前提是错的：

```
/data/service/hnp/bin/hap-sign-tool
  → /data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/toolchains/lib/hap-sign-tool
```

`file` 一查——**`ELF aarch64`，673 KB，原生二进制，不是 jar，不需要 Java**。同目录还有 `binary-sign-tool`（原生二进制签名）、`ohos_packing_tool`（打包）。而本机 `/bin/openssl` 3.0.9 也一直在。

### 4.4 官方工具：3 步一次过

```bash
# 1. 合并证书链（leaf 必须在最前）
cat yydev-leaf.pem yydev-inter.pem yydev-root.pem > yydev-fullchain.pem

# 2. openssl 生成 p12（官方工具只认 JKS/P12，不认裸 PEM 私钥）
#    注：原文此处含调试证书密钥库的口令明文，公开前已替换为占位符
openssl pkcs12 -export -out yydev.p12 -inkey key.pem -in yydev-leaf.pem \
  -certfile yydev-fullchain.pem -name yydev -password "pass:$HAP_KS_PWD"

# 3. 签名
/data/service/hnp/bin/hap-sign-tool sign-app -mode localSign -keyAlias yydev \
  -keyPwd "$HAP_KS_PWD" -keystorePwd "$HAP_KS_PWD" -keystoreFile yydev.p12 \
  -appCertFile yydev.cer -profileFile KlayoutProfileDebug.p7b -profileSigned 1 \
  -inFile entry-mini-unsigned.hap -signAlg SHA256withECDSA -signCode 1 \
  -compatibleVersion 8 -outFile official-mini-signed.hap

# 4. 装机
hdc install official-mini-signed.hap
```

```
[Info]App install path:.../official-mini-signed.hap msg:install bundle successfully.
```

`bm dump -n Ot6.based.Klayout` 能查到完整信息（`appIdentifier: 6917615565877036017`）。**本机签名 → 侧载闭环首次打通。**

坑：`-compatibleVersion` 是必填项（输入为 hap 时），漏了直接报参数错；商用机填 8 可过。

现成脚本：`sign_official.sh`（支持 `HAP_KS_PWD` / `HAP_PROFILE` / `HAP_COMPAT_VER` 环境变量覆盖）。

### 4.5 装机过程中修掉的 HAP 结构问题

调试签名时顺带摸清了 BMS 对 HAP 结构的要求（每轮改一处、装一次、抓一次日志）：

| 内部码 | 报错 | 真因 |
|---|---|---|
| 8519744 | `ObtainOverlayType failed due to bad module.json` | **缺 `ets/modules.abc`**，报错文案完全误导 |
| 8519886 | `profile prop icon mission` | `module.json` 的 `app` 块缺 `icon` |
| 8519885 | `type error pages not string` | `module.pages` 必须是**字符串** `"$profile:main_pages"`，不能是数组 |

**定位方法**（比错误码有用得多，hilog 是流式不会自己退出，必须截断）：

```bash
hdc shell hilog -r >/dev/null 2>&1
hdc install xxx.hap
timeout 40 hdc shell "hilog | grep -E 'C011FE|C01120|C01121|C05A06' | head -60"
```

看 `ProcessBundleInstall:行号` 就知道卡在哪：**`:1533`=签名校验、`:1549`=解析 HAP、`:1719`=内核代码签名**。没有 `:1533` 报错就说明签名已被接受，别再回头改签名结构。

---

## 五、成果清单

### 5.1 可直接复用的产出（已归档到 `workchain/klayout/`）

| 文件 | 说明 |
|---|---|
| `headless_drc.py` | 无头 DRC，读 GDS 跑 width/space check，已实测通过 |
| `gds_viewer.py` | GDS → plotly 交互 HTML 生成器，已实测通过 |
| `gds_viewer.html` | 生成的离线看图页面（4.5 MB，浏览器直接打开） |
| `demo_mask.gds` / `.lyp` / `.csv` | Nazca 生成的示例掩模版图与图层配色定义 |
| `klayout_hmos_qt_port.md` | 原生 GUI 移植方案调研（社区现状 + 路线 + 对比 + 参考链接） |
| `sign_official.sh` | HAP 官方签名一键脚本 |

### 5.2 沉淀的技能

`ohos-hap-sign` —— 鸿蒙本机 HAP 签名与侧载，已整篇重写，**官方原生签名器路线置顶**，含：
- 官方工具 3 步签名法 + p12 生成
- 安装失败定位手册（错误码 ↔ 内部码 ↔ 根因对照表）
- 最小可安装 HAP 的结构要求
- hilog 抓取的正确姿势与进程清理（含"关终端 ≠ 进程结束"这个坑）
- 自研签名器降级为研究参考，附 7 个格式坑与 fs-verity errno 129 的排查方向

---

## 六、复盘与下一步建议

### 6.1 最大的教训：先验证工具在不在，别假设

自研 880 行签名器花掉的时间，本可以省下来——只要一开始跑一句：

```bash
ls /data/service/hnp/bin/ && which openssl
```

官方原生签名器、`binary-sign-tool`、`ohos_packing_tool`、openssl、OHOS NDK 全都摆在设备上。**这类"以为没有所以自己造"的错误，在这台机器上我犯了两次**（另一次是以为本机没编译器，实测 clang 就是 OHOS NDK）。

### 6.2 第二个教训：目的与手段要分清

我原本的需求是「**看到 GDS 版图**」，不是「**拥有 KLayout 原生 GUI**」。路线 A 用零成本已经满足了前者。而我在路线 A 交付之后，继续往下钻了交叉编译和签名两个大坑——**是在给一座还没开建的房子修车道**。

值得肯定的是，这一趟并非全无收获：签名闭环、HAP 结构要求、hilog 定位法，这些都是可复用的底层能力，将来移植任何应用到鸿蒙都用得上。

### 6.3 现状与目标的距离

| 环节 | 状态 |
|---|---|
| 看图（路线 A） | ✅ **已交付，够用** |
| 无头 DRC（路线 A） | ✅ **已交付，够用** |
| 交叉编译工具链 | ✅ 本机 OHOS NDK 就绪 |
| HAP 打包 + 签名 + 装机 | ✅ **已打通** |
| Qt6 for OHOS 预编译库 | ❌ 未下载 |
| KLayout 依赖 OHOS 化（zlib/expat/curl/Ruby/Python） | ❌ **零进展，最大工作量** |
| KLayout 本体编译 | ❌ 未开始 |

**HAP 签名这一环已经不再是阻塞项。** 路线 B 剩下的全部工作量集中在"依赖 OHOS 化 + 本体编译"，尤其是 Ruby 和 Python 的 OHOS 构建版。

### 6.4 建议

**先停一停，做一次价值判断再决定要不要继续。**

路线 A 已经能用，路线 B 的剩余工程量（五个依赖的 OHOS 化，其中 Ruby/Python 无现成轮子）很可能是路线 A 的几十倍。建议先回答：

1. 路线 A 的交互动画够不够用？缺的是缩放平移（已有），还是编辑、图层管理、DRC 面板这些？
2. 如果只缺编辑能力——值得为它付这个代价吗，还是可以在 Windows 虚拟机里做？
3. 如果确实要上原生 GUI，建议**先做一个小验证**：用现有的工具链移植一个 Qt 示例应用（比如 calculator），验证整条 `编译 → 打包 → 签名 → 装机` 链路，再决定要不要投入 KLayout 本体。这样风险最低。

**如果决定继续，我建议的第一步**是拿 Qt 示例应用跑通全链路验证，而不是直接啃 KLayout。
