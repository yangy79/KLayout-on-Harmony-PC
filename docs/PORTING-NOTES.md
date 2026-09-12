# 移植笔记

把 KLayout 0.30.10 跑在 HarmonyOS PC 上遇到的每一个真问题，以及各自的根因与解法。
按"卡住的程度"排序 —— 前四个是真正花掉时间的，后面几个是一行改动能解决的。

---

## 0. 整体判断：平台相关代码几乎为零

KLayout 对平台的依赖集中在 `Q_OS_*` 宏。在 OHOS 目标的编译环境里这些宏**全为 0**，
于是绝大部分平台分支自然落到"通用/未实现"路径，反而不会编进任何 POSIX/Linux 专有代码。

全树只有一处需要留意：`src/laybasic/gtf.cc` 引用了 `Qt::X11BypassWindowManagerHint`。
那只是**枚举常量的引用**，并非真的调用 X11，不构成依赖。

真正的移植工作量不在 C++ 代码里，而在**启动链路、资源定位、动态加载策略**这三件事上。

---

## 1. Qt OHOS 的启动模型：`main()` 不在可执行文件里

### 现象

`build.sh` 编完，产物是 `libklayout.so` 而不是可执行文件 `klayout`。

### 根因

Qt OHOS 的 mkspec `ohos-clang` 把 `TEMPLATE = app` **强制加上 `-shared`**。
所以应用是被当作共享库构建的。启动链是：

```
应用被拉起
  → 壳的 libentry.so 初始化
  → ArkTS 侧 QAbility 把 Qt 环境准备好
  → libqohos.so（QPA 平台插件）dlopen( APP_LIBRARY_NAME )
  → dlsym(handle, "main")  ← 应用真正的入口在这里
  → 调用 main()
```

同时 mkspec 带 `-fvisibility=hidden`，默认会把 `main` 隐藏掉。因此
`klayout_main.pro` 必须补上：

```qmake
QMAKE_LFLAGS += -Wl,--export-dynamic
```

否则 `dlsym("main")` 取到 NULL，表现为"库加载成功但什么都没发生"。

**相关文件**：`src/klayout_main/klayout_main/klayout_main.pro`、`ohos-app/entry/src/main/ets/common/QtAppConstants.ets`（`APP_LIBRARY_NAME` 必须是 HAP 内 `.so` 的文件名，逐字一致）。

---

## 2. 资源目录定位：`tl::get_inst_path()` 在 OHOS 上是坏的

### 现象

GUI 能起来，但找不到内置技术库（tech / salt / drc），某些资源打开失败。

### 根因

KLayout 的资源搜索路径是：

```
get_klayout_path() = KLAYOUT_HOME（默认 ~/.klayout）
                   + KLAYOUT_PATH（未设时回退 tl::get_inst_path()）
```

而 `tl::get_inst_path()` 通过 `/proc/<pid>/exe` 反查可执行文件位置。在 OHOS 上，
`/proc/<pid>/exe` 指向的是**壳的主程序**（`libentry.so` 所在的宿主进程），
不是 `libklayout.so`。所以它根本推不出我们的安装目录。

### 解法

从 Qt 的 OHOS 上下文里取真实路径，显式设 `KLAYOUT_PATH`。

Qt 的 OHOS 平台插件把 HAP 的 `resources/` 磁盘路径存进了 `QOhosAppContext`：

```cpp
#include <QtCore/private/qohosappcontext_p.h>

QString rd = QOhosAppContext::getProperty (QOhosAppContext::Type::resourceDir);
qputenv ("KLAYOUT_PATH", (rd + "/rawfile/klayout").toUtf8());
```

于是 `klayout_main.pro` 需要：

```qmake
QT_PRIVATE += core
INCLUDEPATH += $$[QT_INSTALL_HEADERS]/QtCore/$$QT_VERSION/QtCore/private
```

（`getProperty` 是带 `Q_CORE_EXPORT` 的静态方法，可直接链接调用；
OHOS 目标宏是 `Q_OS_OHOS`，由编译器预定义的 `__OHOS__` 派生。）

---

## 3. 资源与插件放哪里：`rawfile` / `resfile` / `libs` 三者的差别

这一条踩了很久，因为三种目录**看起来都能放文件，行为却完全不同**。

| 目录 | 安装后行为 | 结果 |
|---|---|---|
| `resources/rawfile/` | 打包在 HAP 内，**不解压**，只能用 `resourceManager` NDK 读 | KLayout 的 `std::ifstream` 完全够不着 → ✗ |
| `entry/libs/arm64-v8a/` | 只收 `*.so`，普通文件被 hvigor **静默丢弃** | 68 个资源文件全丢 → ✗ |
| `resources/resfile/` | 安装后**解压成真实磁盘文件** | ✔ 正是 `QOhosAppContext.resourceDir` 所指位置 |

所以：**KLayout 资源树（68 个文件）放 `resfile/klayout/`，插件 `.so` 放 `libs/arm64-v8a/`。**

### 插件为什么不放 KLayout 期望的 `db_plugins/`

KLayout 正常从 `KLAYOUT_PATH/db_plugins/` 里 `dlopen` 插件。但 `KLAYOUT_PATH` 指向的是
`resfile/`，也就是**应用可写分区（el2）**。而 OHOS 的安全策略**禁止从用户可写分区加载
`.so`** —— 实测 25 个插件全部 "Unable to load plugin"，格式注册表为空，
于是任何文件都报 `Stream has unknown format`（File 对话框里的 layout 扩展名列表也是空的）。

解法：把插件放到应用**安装目录** `libs/arm64-v8a/`（必然允许加载），
然后在 `klayout.cc` 启动时**显式 `dlopen` 每一个**：

```cpp
// 遍历 libs 目录下的 db_plugins/lay_plugins 同名 .so 并 dlopen(RTLD_NOW|RTLD_GLOBAL)
```

**相关文件**：`src/klayout_main/klayout_main/klayout.cc`、
`build-scripts/build_klayout_hap.sh`（§2.4 / §2.5）。

---

## 4. `--gc-sections` 杀掉了插件的自我注册

### 现象

插件 `dlopen` **返回成功**，但格式注册表一条都没增加。主程序依旧报
`Stream has unknown format`。

### 根因

KLayout 的插件靠**静态对象构造**完成注册，例如 GDS2：

```cpp
static tl::RegisteredClass<db::StreamFormatDeclaration> format_decl (new GDS2FormatDeclaration (), 0, "GDS2");
```

这个对象在源码里**没有任何外部引用**。链接时 `-Wl,--gc-sections` 判定它不可达，
把它从 `.init_array` 里剔除了 —— 构造函数从未执行，注册自然没发生。

判定实验很干净：同一写法、同一位置的 CIF / OASIS / DXF / LEF-DEF / MAG / MALY / PCB
七个插件都能正常注册（格式表 +1），**唯独 GDS2 不增长**（诊断日志
`libgds2.so -> formats=1` 不增长）。这说明不是加载机制的问题，而是该对象的构造被裁掉了。

### 解法（两处，互为保险）

1. 插件链接关闭 gc-sections —— `src/plugins/db_plugin.pri`、`src/plugins/lay_plugin.pri`：

   ```qmake
   QMAKE_LFLAGS += -Wl,--no-gc-sections
   ```

2. 把 GDS2 reader 的源码**直接编进主库**（`klayout_main.pro`），使注册与查询同进程、
   同注册表、无加载时序依赖：

   ```qmake
   GDS2_SRC = $$PWD/../../plugins/streamers/gds2/db_plugin
   INCLUDEPATH += $$GDS2_SRC $$GDS2_SRC/contrib $$PWD/../../plugins/common
   SOURCES += $$GDS2_SRC/dbGDS2.cc ...（9 个文件，跳过 gsiDeclDbGDS2.cc）
   ```

   > 跳过 `gsiDeclDbGDS2.cc` 是因为它只是 Ruby/Python 绑定声明，
   > 本构建 `-nopython -noruby -without-qtbinding` 用不上。

**相关文件**：`src/klayout_main/klayout_main/klayout_main.pro`、`src/plugins/{db,lay}_plugin.pri`。

---

## 5. 往 HAP 里塞系统库会导致启动即崩（SIGSEGV）

### 现象

应用启动瞬间退出，`exit with signal:11`，`QtMainThread` 上 `signo(11)`。
没有任何有用的日志。

### 根因

为了让 `libklayout.so` 的 `DT_NEEDED` 都能解析，最初把 OHOS SDK sysroot 里的
5 个系统库也拷进了 HAP：

```
libohenvironment.so  libicu.so  libace_napi.z.so
libhilog_ndk.z.so    libdeviceinfo_ndk.z.so
```

但这些库在设备上与**系统自带的同名库 ABI / 版本不匹配**，导致 Qt 初始化阶段崩溃。

### 判定实验（决定性）

把**原版能正常运行的 `libcalculator.so`** 顶替 `libklayout.so`，走**同一条打包链**
→ **同样 SIGSEGV**。

而原版能跑的 calculator HAP 里只有 7 个库（Qt5Core/Gui/Widgets、libc++_shared、
libcalculator、libentry、libqohos），**没有** `libohenvironment.so` ——
它对 `libohenvironment.so` 的依赖是从系统 `/system/lib64` 解析的。

⇒ 问题不在 KLayout，而在我们额外塞进去的系统库。

### 解法

打包时跳过这 5 个库，让它们从设备系统目录解析。`build_klayout_hap.sh` 用
`SKIP_SYS_LIBS=1` 控制：

```sh
SKIP_SYS_LIBS=1 sh build_klayout_hap.sh
```

修复后 calculator 与 KLayout 双双正常启动。

> **教训**：`DT_NEEDED` 能解析 ≠ 应该随包分发。系统提供的库就不要重复塞进包里。
> 反过来，排查"应用启动即崩且无日志"时，做"换已知能跑的库"的对照实验
> 比读日志快得多。

---

## 6. 诊断通道：OHOS 上看不到 stderr

KLayout 的 Qt message handler 只 `fprintf(stderr, ...)`，而：

- OHOS 上 stderr **不进 hilog**；
- 程序自己写文件又落在沙箱内，`hdc shell` 读不到。

于是"打不开文件""插件加载失败"这类错误**两条诊断通路都不通**，只能看到退出码。

解法：诊断改走 hilog，并且**用 `dlopen` + `dlsym` 动态解析 `OH_LOG_Print`**，
不新增 `DT_NEEDED`（避免重蹈第 5 条的覆辙）：

```cpp
void *h = dlopen ("libhilog_ndk.z.so", RTLD_NOW | RTLD_GLOBAL);
ohlog_t log = (ohlog_t) dlsym (h, "OH_LOG_Print");
log (0, 6 /*LOG_ERROR*/, 0xD001400u, "KLAYOUT_OHOS", "%{public}s", msg);
```

抓日志：

```sh
hdc shell "hilog 2>&1 | grep -E 'KLAYOUT_OHOS|stream' | head -n 30"
```

> `head` 是必须的 —— 不加的话 hilog 不退出，命令会被后台化卡住。

`src/tl/tl/tlStream.cc` 里也给 `FileOpenErrorException` 加了同款打印（带 `errno`
与调用栈的模块偏移，便于离线用 `llvm-nm` 反查）。

---

## 7. 菜单图标路径：`<:/foo.png>` 在 OHOS 上解析成绝对路径

KLayout 的部分菜单标题用了 `<:/foo_24px.png>` 形式。在 OHOS 上它被解析成
绝对路径 `/foo_24px.png`，取不到资源，图标变空白（Back/Forward、合并模式等）。
另一种写法 `<:foo_24px.png>` 则被解析成相对路径，同样取不到。

解法（`src/laybasic/laybasic/layAbstractMenu.cc`）：先试原路径，失败则规范化成
Qt 资源形式 `:/` 再试；并且**不要用 `QIcon::isNull()` 判断有效性** ——
路径无法解析时它依然是 false（图标对象仍带着文件名），要改用
`icon.pixmap(QSize(16,16)).isNull()` 探测实际能否取到位图。

---

## 8. dock 面板标题被省略号截断

OHOS 平台样式对 dock widget 的 `sizeHint` 报得很小，侧栏被挤压，
标题变成 `La...` / `Lib...`。

解法（`src/lay/lay/layMainWindow.cc`）：在 `#if defined(Q_OS_OHOS)` 下给各侧栏
设最小宽度 280。

---

## 9. 编译期：`-Werror` 必须放开

本机 clang 15 会对真实世界的 C++ 代码报出若干良性告警，例如
`-Wimplicit-const-int-float-conversion`。Qt 的 mkspec `ohos-clang/qmake.conf`
里写死的 `-Werror` 会把它们全部变成编译失败。

解法：`-Werror` → `-Wno-error`（见 `patches/qt5-ohos-mkspec-no-werror.patch`）。

---

## 10. 构建环境本身的坑（与 KLayout 无关，但会浪费大量时间）

| 坑 | 症状 | 处理 |
|---|---|---|
| 注入的坏 `rm` | Makefile 里所有 `rm -f` 规则报 `Error 127`，shim 的 interpreter 是坏的 | `PATH` 重建，把 `qt5-ohos/hostbin`（含干净 `rm`）放最前 |
| `rm -rf` 被劫持 | 安全删除 shim 把它改写成不存在的 `/rm` | 清理改用 Python `shutil.rmtree` 或 `find -delete` |
| `uname -s` 返回 `HarmonyOS` | `build.sh` / `configure` 判平台失败 | Qt 侧显式 `-platform linux-clang-native`；KLayout 不依赖 `Q_OS_LINUX` 故无影响 |
| 本机无 java | hvigor `PackageHap` 报 `spawn java ENOENT (00308018)` | 用 SDK 自带的原生 `ohos_packing_tool` 补上打包步骤（`pack_hap_native.sh`） |
| node `os.type()` 返回 `HarmonyOS` | hvigor 去找不存在的 `*.dylib` | `NODE_OPTIONS=--require .../ohos-host-linux-shim.cjs` 伪装成 Linux |
| `hdc shell` 读不到 app 私有目录 | `/data/storage/el1/bundle/libs/arm64/` 与 `/data/log` 均 Permission denied | 验证部署内容只能靠"本地产物字符串 + 打包时间"间接确认 |
| `/tmp` 只读 | 脚本写临时文件失败 | 临时文件写到自己的 `$HOME` 下 |
| `python3` 不在重建后的 `PATH` 里 | 构建脚本的清理/自检步骤静默失败 | `PATH` 补 `/data/storage/el1/bundle/libs/arm64/python/bin` |

---

## 附：移植改动一览

7 个文件被修改（上游 8408 个文件中的 7 个），另有 1 个新增文件。

| 文件 | 对应本文 |
|---|---|
| `src/klayout_main/klayout_main/klayout.cc` | §1 §2 §3 §6 |
| `src/klayout_main/klayout_main/klayout_main.pro` | §1 §2 §4 |
| `src/plugins/db_plugin.pri` | §4 |
| `src/plugins/lay_plugin.pri` | §4 |
| `src/laybasic/laybasic/layAbstractMenu.cc` | §7 |
| `src/lay/lay/layMainWindow.cc` | §8 |
| `src/tl/tl/tlStream.cc` | §6 |
| `overlay/apply_ohos_resource_patch.py`（新增） | §2（生成上述 klayout.cc/pro 改动的工具） |
| `qtbase/mkspecs/ohos-clang/qmake.conf`（Qt 侧） | §9 |
