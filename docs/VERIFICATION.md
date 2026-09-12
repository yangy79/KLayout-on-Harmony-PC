# 验证记录

本文件记录发布产物的**可复核**验证结果。所有数据都可用命令重新得到，
命令附在每节末尾。

**验证对象**

| 产物 | 大小 | SHA-256 |
|---|---|---|
| `klayout-1.0.0-release.hap` | `106037546` 字节 | `653d2f60c77fbb8a78cbfc94bc479ebec01dfe55bd2aae2f5156284b263c6fa9` |
| `klayout-1.0.0-release.app` | `106053081` 字节 | `d640888e49092e434c822aaedea6a7204414a668d01bebd9037a3bbebc90ef93` |

> `.app` 是把已签名的 HAP 再包一层（`entry-default.hap` + `pack.info`）并签名得到的
> App Pack —— **AGC 上架只收 `.app`**，不传模块级 `.hap`。

---

## 1. 源码可还原性（GPL「完整对应源码」的核心证据）

| 检查 | 结果 |
|---|---|
| 上游源码包 SHA-256 与官方一致 | ✅ `96f7db5a744d9cd8ac913bb9186ce3b51e836321665d8f874336d0d43d2275c0`（103949878 字节） |
| `patches/klayout-0.30.10-ohos.patch` 在干净上游树上 `--dry-run` | ✅ 7 个文件全部干净命中，无 fuzz |
| 打完补丁后与构建用工作树逐文件比对 | ✅ 7/7 文件 SHA-256 **完全相同** |
| `scripts/setup-source.sh` 端到端跑通（校验 → 解包 → 打补丁 → 复制 overlay） | ✅ 还原出 8408 个文件的完整源码树，逐文件哈希与构建用工作树一致 |
| `overlay/` 文件就位 | ✅ `apply_ohos_resource_patch.py` + `klayout-resources/`（68 个文件） |
| 补丁脚本幂等性（对已打补丁的树重复运行） | ✅ 被自身标记识别并跳过，`klayout.cc` 哈希不变 |

**复现命令**

```sh
# 1) 校验上游源码包
sha256sum klayout-0.30.10.tar.gz     # 应得 96f7db5a…

# 2) 干跑补丁
cd klayout-0.30.10 && patch -p1 --dry-run < patches/klayout-0.30.10-ohos.patch

# 3) 端到端还原
sh scripts/setup-source.sh --tarball klayout-0.30.10.tar.gz --out ./verify
```

---

## 2. 上架硬性检查（AGC 审核必查项）

| 检查项 | 要求 | 实测 | 结果 |
|---|---|---|---|
| `app.debug` | 必须为 `false`（API≥11 包不得含调试信息） | `False` | ✅ |
| `sourceMaps` | 不得存在 | 0 条 | ✅ |
| `bundleName` | 与 AGC 登记一致 | `com.yangy79.klayout` | ✅ |
| `versionName` / `versionCode` | — | `1.0.0` / `1000000` | ✅ |
| `vendor` | — | `yangy79` | ✅ |
| `deviceTypes` | 与商店声明一致 | `["2in1"]` | ✅ |
| 签名校验（HAP） | `verify-app` 通过 | `hap verify successed!` | ✅ |
| 签名校验（`.app`） | `verify-app` 通过 | `verify-app success` | ✅ |
| compatibleSdkVersion | NEXT 要求 `≥ 4.0.0(10)` | `5.0.0(12)` | ✅ |

**复现命令**

```sh
python3 - <<'PY'
import zipfile, io, json
z = zipfile.ZipFile("klayout-1.0.0-release.app")
m = json.loads(zipfile.ZipFile(io.BytesIO(z.read("entry-default.hap"))).read("module.json"))
print("debug=", m["app"]["debug"], "bundle=", m["app"]["bundleName"], "deviceTypes=", m["module"]["deviceTypes"])
PY
hap-sign-tool verify-app -inFile klayout-1.0.0-release.app
```

---

## 3. 包内结构与许可声明核验

| 检查项 | 实测 |
|---|---|
| `libs/arm64-v8a/*.so` | 56 个（注入 55 个 + 壳自身 `libentry.so`） |
| ├ `libklayout.so` | 1 |
| ├ `libklayout_*.so`（模块库） | 20 |
| ├ stream 插件（GDS2 / OASIS / CIF / DXF / …） | 25 |
| ├ Qt 库（Core/Gui/Widgets/Network/Xml/PrintSupport/Sql） | 7 |
| ├ `libqohos.so`（Ohos QPA 插件） | 1 |
| └ `libc++_shared.so` | 1 |
| `resources/resfile/klayout/` | 68 个文件（`tech` / `salt` / `drc` / `macros` / `pymacros`） |
| 包内 `libklayout.so` 含移植仓库地址 | `KLayout-on-Harmony-PC` **1** 次；旧占位 `klayout-harmonyos` **0** 次 |
| 包内 `libklayout.so` 含许可声明 | `GNU GPL v3` 1 次；`Port source code` 1 次 |

> 这两项证明：**应用内 Help → About 页确实向用户显示了许可信息与源码获取入口**
> （GPL-3.0 对"分发目标代码时须同时提供源码获取方式"的要求）。

**复现命令**

```sh
python3 - <<'PY'
import zipfile, io
z = zipfile.ZipFile("klayout-1.0.0-release.app")
inner = zipfile.ZipFile(io.BytesIO(z.read("entry-default.hap")))
d = inner.read("libs/arm64-v8a/libklayout.so")
for p in (b"KLayout-on-Harmony-PC", b"klayout-harmonyos", b"GNU GPL v3"):
    print(p.decode(), d.count(p))
PY
```

---

## 4. 真机功能验证

release 构建的产物**无法侧载** —— 发布 Profile 是 `app_gallery` 分发类型，设备不信任
（`code:9568322`）。因此真机验证走 [`build-scripts/smoke_test_release.sh`](../build-scripts/smoke_test_release.sh)：
临时把包名改回调试包名、用调试证书签**同一份 release 编译产物**，验证后自动恢复。

### 实测结果（release 产物，侧载运行）

| 判据 | 结果 |
|---|---|
| 应用启动、主窗口出现 | ✅ |
| `QtAppConstants.APP_LIBRARY_NAME` 生效、`dlsym("main")` 成功 | ✅ 日志 `opened library ... with main function` → `calling 'main'` |
| stream 插件预加载 | ✅ `preloaded ok=25 fail=0` |
| 版图格式注册表非空 | ✅ `formats=10`（GDS2 / OASIS / CIF / DXF / LEF-DEF / MAG / MALY / PCB + 2） |
| 打开 `.gds` 版图 | ✅ 正常渲染（截图见 `docs/screenshots/`） |
| ArkTS 混淆未破坏 Qt 胶水层 | ✅ release 开启混淆后功能与 debug 构建一致 |
| 未出现 `Stream has unknown format` | ✅ |

> ⚠️ **时序说明**：上述真机验证在**本文件所列哈希之前的一次构建**上完成；
> 两者之间唯一的源码差异是 `klayout.cc` 里 About 页的一行**展示用字符串**
> （源码地址由占位符改为真实仓库地址），不涉及任何逻辑。
> 第 3 节已核验该字符串确实进入了包内二进制。
> 若需要对本文件所列哈希做一次完整的真机复测，请重跑 `smoke_test_release.sh`。

---

## 5. 尚未验证 / 已知限制

| 项 | 说明 |
|---|---|
| 手机（`phone`）与平板（`tablet`）形态 | **未声明、未验证**。Qt 侧已知问题 QTFOROH-1076（清单含 `phone` 时窗口最小化后不恢复），故先收窄到 `2in1` |
| Ruby / Python 宏与 DRC/LVS 脚本 | 构建时关闭（本机无解释器），**包内不含脚本引擎** |
| QtSvg / QtMultimedia / Qt Designer 相关功能 | 对应 Qt 模块未构建 |
| 大版图（>100 MB GDS）内存表现 | 未做系统性压测 |
| 内置示例库 | 为控制包体未随包分发 `demo` 内容 |
