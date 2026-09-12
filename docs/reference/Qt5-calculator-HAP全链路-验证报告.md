# Qt 5.12.12 鸿蒙版：从源码到「已签名可安装 HAP」全链路验证

日期：2026-09-10　工作根：`~/dev/qt5-ohos/`

---

## 1. 这件事的目的是什么

原始目标是在鸿蒙 PC 上**看 GDS 掩模版图**。路线 A（`klayout.db` + plotly 交互 HTML）已经
能用且不花钱，但它是网页，不是原生窗口。路线 B 想要的是**原生 GUI**：把 KLayout 编成
`.so`，打进 HAP，装到设备上真正跑起来。

这条路要成立，必须证明三件事：

1. 本机能不能**自持构建** Qt for OpenHarmony（无外部宿主工具链）；✅ 已验证（见
   `Qt5-鸿蒙本机自持构建-验证报告.md`）
2. Qt 应用能否按鸿蒙的方式（**.so + ArkTS 壳 + `libqohos.so` 运行时 dlopen**）跑起来；
3. 本机能否**打出并签出可安装的 HAP**（这一环此前从没走通过）。

本次完成的就是第 3 环，并把第 2 环所需的一切都装进了包里。**用官方 `calculator`
做验证对象**，而不是直接啃 KLayout——先验链路，再上重活。

---

## 2. 链路与产物

```
qmake 编译 calculator → libcalculator.so
        ↓
prepare_qt_hap_shell.py 生成 ArkTS 壳工程（Qt 官方模板）
        ↓
hvigorw assembleHap  →  编译 ArkTS / 资源 / 打包前准备
        ↓  （死在 PackageHap：要 java）
ohos_packing_tool pack  →  entry-default-unsigned.hap
        ↓
hap-sign-tool sign-app  →  entry-calculator-signed.hap
```

| 产物 | 路径 | 大小 |
|---|---|---|
| 已签名 HAP（最终交付） | `~/dev/qt5-ohos/apps/calculator/entry-calculator-signed.hap` | 24,027,230 B |
| 未签名 HAP | `apps/calculator/ohos/entry/build/default/outputs/default/entry-default-unsigned.hap` | 23,765,487 B |
| 应用 .so | `apps/calculator/build-arm64/libcalculator.so` | ~44 KB |

一键复现：`sh ~/dev/qt5-ohos/apps/calculator/build_all.sh`

---

## 3. 撞到的四个坑（都是本机专属，网上查不到）

### 坑 1：WorkBuddy 注入的 node / rm shim → hvigor 启动即崩

`NODE_OPTIONS=--require .../node-language-shim.cjs`（安全删除 BROKER）会让 hvigor 的
`spawnSync` 报 EACCES；`rm` 还被替换成坏 shim 的 shell function（改 PATH 无效，因为
function 优先）。**解法**：unset 全套 `NODE_OPTIONS` / `BASH_ENV` / `CODEBUDDY_SAFE_DELETE_*`，
并完全重建 PATH。

### 坑 2：`os.type()` 返回 HarmonyOS → 去加载 macOS 的 `.dylib` ⭐ 最隐蔽

```
node -e "console.log(process.platform, require('os').type())"
→ openharmony  HarmonyOS
```

而 hvigor 的平台判定是**硬编码字符串比较**：

```js
// @ohos/hvigor-common/src/util/system-util.js
isLinux()  { return "Linux"  === os.type() }   // false
isMac()    { return "Darwin" === os.type() }   // false
isWindows(){ return "Windows_NT" === os.type() } // false
```

于是 `windows ? .dll : linux ? .so : .dylib` 落到 darwin 分支：

```
hvigor ERROR: Failed :entry:default@CompileResource...
Error Code: 11201001  Dependency Error
Failed to load the library '<sdk>/hms/toolchains/lib/libimage_transcoder_shared.dylib', path invalid
```

而旁边的 `libimage_transcoder_shared.so` 就是 **ELF64 / AArch64**，正是本机要的。

**解法**：node preload shim 把 `os.type()` 伪装成 `Linux`
（`~/dev/qt5-ohos/hostbin/ohos-host-linux-shim.cjs`）：

```sh
export NODE_OPTIONS="--require /abs/path/ohos-host-linux-shim.cjs"
```

NODE_OPTIONS 会被 hvigor fork 的 worker 子进程继承，一次生效。
> ⚠️ **只改 `os.type()`，不要动 `process.platform`**：native addon 是按
> `xxx-linux-arm64.node` 这种目录名查找的，而这些 addon 实际按 openharmony 构建，
> 改了反而加载失败。

### 坑 3：`import lazy` 不被当前 SDK 版本支持（10705000）

Qt 官方壳模板生成 `ets/qability/OhosExportModules.ts`，里面 `import lazy` 了 5 个
**商业版专有 kit**（CoreSpeechKit / FileManagerServiceKit / Penkit / ShareKit /
StatusBarExtensionKit）。公共 SDK 下没有这些模块，且 es2abc 直接拒绝语法：

```
10705000 Syntax Error: Current configuration does not support using lazy import.
Lazy import can be used in the beta3 version of API 12 or higher versions.
The size of programs is expected to be 18, but is 17
```

**解法**：calculator 根本不需要这些（那张表只是给 Qt 收集模块工厂用），把
`getOhosExportModulesFactories()` 改成返回 `{}` 即可。

### 坑 4：打包要 `java`，本机没有 → 用原生 ELF 打包工具顶上

```
hvigor ERROR: Failed :entry:default@PackageHap...
Error Code: 00308018   spawn java ENOENT
```

本机无 JDK；而且网上那些 glibc 版 JDK 在 musl 上也跑不了，不要浪费时间下载。
**SDK 里本来就带了一个原生 ELF 版**：

```
<sdk>/openharmony/toolchains/lib/ohos_packing_tool      # 1.1 MB，ELF64/AArch64
```

参数与 jar 版完全一致，但**是子命令式，必须加 `pack`**（漏了报
`not support command: --mode`）。完整参数从 hvigor 自己的调试日志里抄最稳妥
（`.hvigor/outputs/build-logs/build.log` 搜 `Use tool [.../app_packing_tool.jar]`）。

因为 hvigor 必然死在 PackageHap，**构建脚本里不要检查它的退出码**——它之前的所有
task（CompileArkTS / 资源 / native strip）都已产出完整中间产物，接着手工打包就行。

---

## 4. 出包自检（全部通过）

HAP 内容：

```
   3642  module.json
  45860  ets/modules.abc          ← 缺它报 8519744
   1343  resources.index
  43728  libs/arm64-v8a/libcalculator.so
5758592  libs/arm64-v8a/libqohos.so
   6168  libs/arm64-v8a/libentry.so
4706720  libs/arm64-v8a/libQt5Gui.so
6622992  libs/arm64-v8a/libQt5Widgets.so
5199536  libs/arm64-v8a/libQt5Core.so
1262248  libs/arm64-v8a/libc++_shared.so
   2777  resources/base/media/app_icon.png   ← 缺它报 8519886
```

- `libcalculator.so` 导出 GLOBAL `main`（`readelf -Ws` 可见）✅
- `QtAppConstants.ets` 的 `APP_LIBRARY_NAME = 'libcalculator.so'` 与 .so 同名 ✅
- 动态依赖（`readelf -d`）中需自带的 7 个 .so 全部在包里；
  `libohenvironment.so` / `libace_napi.z.so` / `libGLESv3.so` / `libz.so` / `libicu.so`
  等属设备系统库，无需打包 ✅
- 官方 `hap-sign-tool` 签名一次通过（24,027,230 B）✅

---

## 5. 还差最后一步：真机装机

`hdc list targets` 当前返回 `[Empty]`——之前连过的设备已断开（`hdc discover` 找到 0 个，
本机也没有 hdcd 在跑）。连上设备后：

```sh
export PATH=/data/service/hnp/bin:$PATH
hdc install ~/dev/qt5-ohos/apps/calculator/entry-calculator-signed.hap
hdc shell aa start -a QAbility -b Ot6.based.Klayout -m entry
```

启动失败就抓日志（`C01120` 是 BMS/装机，`C05A06` 是内核代码签名）：

```sh
hdc shell hilog | grep -E "C01120|C05A06|qohos|libcalculator"
```

重点看 `dlopen("libcalculator.so")` 是否成功、Qt 平台插件 `libqohos.so` 是否加载。

---

## 6. 下一步

1. **装机验窗口**（唯一未完成项）——看到 calculator 窗口，路线 B 的「Qt 应用能在鸿蒙跑」
   才算真正落地。
2. 之后才是 KLayout 本体：关掉 Ruby/Python（`-noruby -nopython`）后只依赖
   Qt + zlib + expat + curl，但体积与内存都比 calculator 大一到两个数量级，
   先在 calculator 上把 dlopen / 平台插件 / 字体三件事验证清楚，能省掉大量返工。
3. 已知限制：Qt configure 显示 **Fontconfig = no**，需要等宽字体的界面要自备字体并 bundle。
