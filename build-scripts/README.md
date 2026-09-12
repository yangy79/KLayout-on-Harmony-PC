# build-scripts/ —— 实际使用的打包与签名脚本

本目录是**实机使用过的原始脚本**，原样收录（仅把 keystore 口令换成环境变量占位符），
用于证明发布包的构建过程可复核，并让任何人都能重跑同一条链路。

> ⚠️ **与实机环境的差异**：这些脚本里含绝对路径（HarmonyOS PC 的构建机布局）。
> 换机器跑需要改脚本顶部的路径常量，见文末「移植到别的机器」。

## 1. 环境前提

| 项 | 说明 |
|---|---|
| 宿主 | HarmonyOS PC（aarch64 / musl），无 Java、无 g++ |
| DevEco CLI | `hvigorw`（脚本里为 `~/dev/clt26/bin/hvigorw`） |
| OHOS SDK | `~/dev/clt26/sdk/...`（原生 `ohos_packing_tool`）；`/data/service/hnp/bin/hap-sign-tool` |
| Qt | `~/dev/qt5-ohos/install/5.12.12/ohos-arm64-v8a-clang/` |
| KLayout 构建产物 | `~/dev/klayout-0.30.10/build-ohos/` |

## 2. 脚本清单与调用顺序

```
            ┌─────────────────────────────────────────────┐
            │ 1) build_klayout_hap.sh                     │
            │    注入 libklayout.so + 模块库 + stream 插件 │
            │    + 资源树 → ohos-app/                     │
            └────────────────────┬────────────────────────┘
                                 │
            ┌────────────────────▼────────────────────────┐
            │ 2) build_release.sh                         │
            │    清中间产物 → hvigor(DEBUG 复跑) →         │
            │    原生工具打 HAP → 自检 app.debug==false    │
            └────────────────────┬────────────────────────┘
                                 │
            ┌────────────────────▼────────────────────────┐
            │ 3) build_app_pack.sh                        │
            │    签 HAP → 打 .app → 签 .app → verify-app   │
            └─────────────────────────────────────────────┘

  辅助：build_all.sh（debug 全链路）· pack_hap_native.sh（原生打包）
        smoke_test_release.sh（真机冒烟）· sign_official.sh（通用签名）
```

| 脚本 | 作用 |
|---|---|
| `build_klayout_hap.sh` | 把编译产物注入壳工程的 `entry/libs/arm64-v8a/`，并把 `klayout-resources/` 部署到 `entry/src/main/resources/resfile/klayout`；改 `APP_LIBRARY_NAME` |
| `build_release.sh` | **上架用**。清 `ohos/entry/build/default` 后以 `-p buildMode=release` 跑 hvigor，再用原生工具打 HAP，最后自检 `app.debug==false` 且无 sourceMaps |
| `build_app_pack.sh` | AGC 只收 `.app`：签 HAP → `ohos_packing_tool pack --mode app` → 签 `.app` → `verify-app` 双验 |
| `build_all.sh` | debug 全链路（本地调试用），产物 `entry-calculator-signed.hap` |
| `build_hap.sh` / `build.sh` | 更早期的打包迭代（保留备查） |
| `pack_hap_native.sh` | 用 SDK 自带**原生** `ohos_packing_tool` 替代 `java -jar app_packing_tool.jar`（本机无 java） |
| `smoke_test_release.sh` | release 构建产物无法侧载（发布 Profile 是 `app_gallery` 分发型）。此脚本临时把包名改回调试包名、用调试证书签**同一份 release 产物**做真机冒烟，结束后自动恢复 |
| `sign_official.sh` | 通用签名脚本（原生 `hap-sign-tool`，支持 `HAP_PROFILE` / `HAP_COMPAT_VER` 环境变量切换 Profile） |

## 3. 三个绕不过去的本机坑（脚本里已处理）

### 3.1 release 与 debug 是两套产物

`hvigorw assembleHap` **不传 `buildMode` 时默认是 DEBUG**，产出包内 `app.debug=true`
且带 `ets/sourceMaps.map`。AGC 明令 API≥11 的包不得含调试信息 —— 这是**上架必拒项**。
所以上架必须走 `build_release.sh`，且它会在打包后**自检断言**，不通过就非零退出。
另外 `buildMode` 变了必须先清 `ohos/entry/build/default`，否则会复用 debug 的 `module.json`。

### 3.2 本机没有 java

hvigor 的 `PackageHap` 任务会 `spawn java -jar app_packing_tool.jar`，必然
`spawn java ENOENT (Error Code 00308018)`。**这一步失败是预期的** —— 只要它前面
所有编译任务已完成，中间产物就齐备，随后用 `pack_hap_native.sh` 里的原生工具
补上打包即可。

### 3.3 node / rm 的 shim

本机 `os.type()` 返回 `HarmonyOS`，hvigor 的 `isLinux()` 判定会落到 darwin 分支，
去找不存在的 `*.dylib` → 需用 `qt5-ohos/hostbin/ohos-host-linux-shim.cjs`
（`NODE_OPTIONS=--require ...`）把 `os.type()` 伪装成 Linux。
同时 `PATH` 必须显式重建（`qt5-ohos/hostbin` 提供干净的 `rm`），否则 `PATH` 里
被注入的坏 `rm` 会让所有 Makefile 的 `rm -f` 规则报错。

## 4. 密钥材料（不入库）

脚本需要以下文件存在，**但本仓库不包含它们**：

| 文件 | 来源 |
|---|---|
| `klayout-release.p12` | 自行用 openssl 生成的发布密钥库 |
| `klayout-release.cer` | 在 AGC「证书管理」用 CSR 申请后下载 |
| `klayout-release.p7b` | 在 AGC「Profile」为 `com.yangy79.klayout` 创建的发布 Profile |

口令一律通过环境变量传入：

```sh
export KLAYOUT_KS_PWD='<你的密钥库口令>'   # build_app_pack.sh / sign_official.sh
export HAP_KS_PWD='<你的密钥库口令>'        # sign_official.sh（调试证书链路）
```

> 仓库里出现的 `${KLAYOUT_KS_PWD:?set KLAYOUT_KS_PWD}` 样式即为此处占位符 ——
> 原始脚本里写的是明文口令，发布前已替换。

## 5. 移植到别的机器

脚本顶部这些常量需要按你的机器布局改：

```sh
HERE=/path/to/ohos-app          # 或原来的 <qt5-ohos>/apps/calculator
KLAYOUT_BUILD=/path/to/klayout-0.30.10/build-ohos
QT_LIB=/path/to/qt5-ohos/install/5.12.12/ohos-arm64-v8a-clang/lib
SIGNDIR=/path/to/signing
```

`pack_hap_native.sh` 里的 `TOOL=` 指向你本机 DevEco SDK 的
`openharmony/toolchains/lib/ohos_packing_tool`。
