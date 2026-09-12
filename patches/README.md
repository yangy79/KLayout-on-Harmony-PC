# patches/ —— 相对上游源码的改动

本目录只放**统一的 diff 文件**。补丁的 baseline 是两个**精确指定**的上游源码包，
不含任何我们自己的文件（新增文件在 `../overlay/`）。

| 文件 | 目标 | 改动规模 |
|---|---|---|
| `klayout-0.30.10-ohos.patch` | KLayout 0.30.10 源码包 | 7 个文件，835 行 diff |
| `qt5-ohos-mkspec-no-werror.patch` | Qt 5.12.12 for OpenHarmony 的 qtbase 源码 | 1 行 |

## 打补丁

**KLayout 补丁** —— 在**源码包解出的根目录**下执行（该目录内含 `src/`、`build.sh`）：

```sh
patch -p1 < patches/klayout-0.30.10-ohos.patch
```

baseline 必须是官方源码包（顶层目录名 `klayout-0.30.10/`）：

- URL：`https://www.klayout.org/downloads/source/klayout-0.30.10.tar.gz`
- 大小：`103949878` 字节
- SHA-256：`96f7db5a744d9cd8ac913bb9186ce3b51e836321665d8f874336d0d43d2275c0`

> 不要用 GitHub 的 `archive/refs/tags/v0.30.10.tar.gz` 作为 baseline —— 两者的
> `src/version/version.h` 等内容不同，补丁可能不干净应用。用上面的官方源码包。

**Qt mkspec 补丁** —— 在 Qt 源码包根目录（含 `qtbase/`）下执行：

```sh
patch -p1 < patches/qt5-ohos-mkspec-no-werror.patch
```

## 补丁覆盖的文件

| # | 文件 | 改动摘要 |
|---|---|---|
| 1 | `src/klayout_main/klayout_main/klayout.cc` | 注入 `KLAYOUT_PATH`、导出 `main`、显式 `dlopen` 插件、About 版权段、hilog 诊断 |
| 2 | `src/klayout_main/klayout_main/klayout_main.pro` | QtCore 私有头路径、`--export-dynamic`、GDS2 源码并入主库 |
| 3 | `src/plugins/db_plugin.pri` | `-Wl,--no-gc-sections` |
| 4 | `src/plugins/lay_plugin.pri` | `-Wl,--no-gc-sections` |
| 5 | `src/laybasic/laybasic/layAbstractMenu.cc` | 菜单图标路径回退为 `:/` 形式 |
| 6 | `src/lay/lay/layMainWindow.cc` | 侧栏 dock 最小宽度 280 |
| 7 | `src/tl/tl/tlStream.cc` | `FileOpenErrorException` 附 hilog 诊断 |

每个 hunk 上方都有中文注释说明**为什么**要这样改。逐条动机汇总见
[`../docs/PORTING-NOTES.md`](../docs/PORTING-NOTES.md)。

## 校验

打完补丁后，可用补充源码包自带的脚本确认结果与本仓库声明一致：

```sh
sh ../scripts/setup-source.sh --out ./verify   # 脚本内部会校验 SHA-256 并打印结果
```
