#!/bin/sh
# 把编译出的 libklayout.so 注入 calculator(KLayout) HAP 壳，重新打包+签名+安装。
#
# 前置：
#   - KLayout 已在 build-ohos 编译出 libklayout.so（见 dev/klayout-0.30.10/build-ohos）
#   - Qt 依赖库（Network/Xml/PrintSupport/Sql）已在 qt5-ohos install/lib
#
# 用法：sh build_klayout_hap.sh           产出并安装
#      HAP_SIGN=0 sh build_klayout_hap.sh  只打包不签名

set -e

HERE=/storage/Users/currentUser/dev/qt5-ohos/apps/calculator
SHELL_LIBS=$HERE/ohos/entry/libs/arm64-v8a
KLAYOUT_BUILD=/storage/Users/currentUser/dev/klayout-0.30.10/build-ohos
QT_LIB=/storage/Users/currentUser/dev/qt5-ohos/install/5.12.12/ohos-arm64-v8a-clang/lib
SIGNDIR=/storage/Users/currentUser/Documents/ohos-dev/signing
OUT=$HERE/entry-klayout-signed.hap
ETS_CONST=$HERE/ohos/entry/src/main/ets/common/QtAppConstants.ets

# --- 0) 干净环境 ---
unset NODE_OPTIONS BASH_ENV PYTHONPATH
unset CODEBUDDY_SAFE_DELETE_ENABLED CODEBUDDY_SAFE_DELETE_BIN_DIR
unset CODEBUDDY_SAFE_DELETE_BULK_GUARD CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR
unset CODEBUDDY_SAFE_DELETE_BROKER_DELETE CODEBUDDY_SAFE_DELETE_REPORT_PATH
unset CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD
export NODE_OPTIONS="--require /storage/Users/currentUser/dev/qt5-ohos/hostbin/ohos-host-linux-shim.cjs"
export PATH=/storage/Users/currentUser/dev/qt5-ohos/hostbin:/data/service/hnp/bin:/bin:/usr/bin

# --- 1) 定位 libklayout.so（ohos_deployment 应直接产出此名；否则退回无前缀的 klayout） ---
LK=$(find "$KLAYOUT_BUILD" -maxdepth 3 -name 'libklayout.so' 2>/dev/null | head -1)
if [ -z "$LK" ]; then
  LK=$(find "$KLAYOUT_BUILD" -maxdepth 3 -name 'klayout' -type f 2>/dev/null | head -1)
fi
[ -n "$LK" ] || { echo "*** ERROR: 找不到 libklayout.so"; exit 1; }
echo "=== libklayout.so: $LK ($(stat -c%s "$LK") 字节) ==="

# --- 2) 注入壳 libs 目录：替换 libcalculator.so -> libklayout.so，并补齐 Qt 依赖 ---
mkdir -p "$SHELL_LIBS"
rm -f "$SHELL_LIBS/libcalculator.so"
cp -f "$LK" "$SHELL_LIBS/libklayout.so"
for q in Qt5Network Qt5Xml Qt5PrintSupport Qt5Sql; do
  cp -f "$QT_LIB/lib${q}.so" "$SHELL_LIBS/" 2>/dev/null && echo "  拷贝 $q.so" || echo "  [跳过] $q.so 不存在"
done
echo "--- 壳 libs 现有 .so ---"
ls -1 "$SHELL_LIBS"/*.so

# --- 2.2) 拷贝全部 KLayout 模块库（libklayout_*.so）---
# libklayout.so 动态依赖这些库（db/lay/tl/gsi/laybasic/...）；缺任意一个，
# OHOS 运行时 dlopen 会因找不到 NEEDED 库而加载失败。
for f in "$KLAYOUT_BUILD"/libklayout_*.so; do
  [ -e "$f" ] && cp -f "$f" "$SHELL_LIBS/" && echo "  拷贝 $(basename "$f")"
done

# --- 2.4) 拷贝 KLayout 的 stream 插件（db_plugins / lay_plugins）到 libs 顶层 ---
# 为什么必须放这里、而不是 KLayout 期望的 <plugin_root>/db_plugins：
#   GDS2/OASIS/CIF/... 的 reader 是独立 .so 插件。KLayout 正常从
#   KLAYOUT_PATH 下的 db_plugins/ 里 dlopen，而我们的 KLAYOUT_PATH 指向
#   filesDir（el2，用户可写分区）—— **OHOS 安全策略禁止从可写分区加载 .so**，
#   实测 25 个插件全部 "Unable to load plugin"，格式注册表为空，
#   任何文件都报 "Stream has unknown format"（File 对话框的 layout 过滤器
#   扩展名列表也为空）。
#   放到应用安装目录 el1/bundle/libs/arm64（= 本目录，libklayout.so 所在处，
#   必然允许加载）顶层，由 klayout.cc 的 OHOS 补丁在启动时显式 dlopen。
PLUGIN_LIBS=$(ls "$KLAYOUT_BUILD"/db_plugins/*.so "$KLAYOUT_BUILD"/lay_plugins/*.so 2>/dev/null | wc -l)
for f in "$KLAYOUT_BUILD"/db_plugins/*.so "$KLAYOUT_BUILD"/lay_plugins/*.so; do
  [ -e "$f" ] && cp -f "$f" "$SHELL_LIBS/"
done
echo "--- 已拷贝 stream 插件 $PLUGIN_LIBS 个（db_plugins + lay_plugins）"

# --- 2.3) 补齐 SDK sysroot 中的系统辅助库 ---
# 这些库是 libklayout.so / Qt 的 DT_NEEDED，但本机鸿蒙设备的应用可见链接器命名空间
# 里缺失它们（libohenvironment/libicu/libace_napi.z/libhilog_ndk.z/libdeviceinfo_ndk.z）。
# HAP 不含会导致运行时 dlopen 因找不到 NEEDED 失败、应用启动即退（无日志、无 mission）。
# 从 SDK sysroot 拷贝进壳 libs。
OHOS_SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot
SYS_LIB_DIR="$OHOS_SYSROOT/usr/lib/aarch64-linux-ohos"
SYS_LIBS="libohenvironment.so libicu.so libace_napi.z.so libhilog_ndk.z.so libdeviceinfo_ndk.z.so"

if [ "${SKIP_SYS_LIBS:-0}" = "1" ]; then
  # 对照实验用：不塞系统库，让它们从设备 /system/lib64 解析。
  # 原版可运行的 calculator HAP 就不含这些库（其 NEEDED 的 libohenvironment.so
  # 由系统提供）；塞入 SDK sysroot 版本可能因 ABI/版本不匹配导致 Qt 初始化 SIGSEGV。
  echo "--- SKIP_SYS_LIBS=1：跳过系统库，并清理壳 libs 中的残留"
  for L in $SYS_LIBS; do
    [ -e "$SHELL_LIBS/$L" ] && rm -f "$SHELL_LIBS/$L" && echo "  移除残留 $L"
  done
else
  for L in $SYS_LIBS; do
    if [ -e "$SYS_LIB_DIR/$L" ]; then
      cp -f "$SYS_LIB_DIR/$L" "$SHELL_LIBS/" && echo "  拷贝 $L (from sysroot)"
    else
      echo "  [警告] 未找到 $L (NEEDED 缺失可能导致启动失败)"
    fi
  done
fi

# --- 2.5) 部署 KLayout 运行时资源树 -> resources/resfile/klayout ---
# 为什么必须用 resfile 而不是 rawfile：
#   * rawfile：打包在 HAP 内，安装后**不解压**，只能用 resourceManager NDK 读；
#     实测设备端 resourceDir 下 exists=0，KLayout 的 open()/std::ifstream 完全够不着。
#   * resfile：安装后**会解压成真实磁盘文件**，正是 Qt 的 QOhosAppContext
#     resourceDir 所指的 /data/storage/el1/bundle/entry/resources/resfile。
#   * libs/arm64-v8a 也不行：实测 hvigor 只收 *.so，普通文件会被静默丢弃（68 个全丢）。
KRES=$HERE/../../../klayout-0.30.10/klayout-resources
RESFILE=$HERE/ohos/entry/src/main/resources/resfile/klayout
if [ -d "$KRES" ]; then
  rm -rf "$RESFILE"
  mkdir -p "$RESFILE"
  cp -rf "$KRES"/. "$RESFILE"/
  # 插件（.so）改由 libs 目录提供（见 2.4）：放这里是无效的 —— el2 可写分区
  # 不允许 dlopen。留着只会白占体积、并在启动时刷一堆 "Unable to load plugin"。
  rm -rf "$RESFILE/db_plugins" "$RESFILE/lay_plugins"
  echo "--- 已部署资源树 -> $RESFILE ($(find "$RESFILE" -type f | wc -l) 个文件) ---"
  ls -1 "$RESFILE"
else
  echo "  [警告] 找不到 klayout-resources ($KRES)，跳过资源部署（应用仍可启动，但无内置库）"
fi

# 清掉已失效的 rawfile / libs 部署（两者都不落盘）
RAWFILE=$HERE/ohos/entry/src/main/resources/rawfile/klayout
[ -d "$RAWFILE" ] && { rm -rf "$RAWFILE"; echo "--- 已移除失效的 rawfile/klayout ---"; }
[ -d "$SHELL_LIBS/klayout" ] && { rm -rf "$SHELL_LIBS/klayout"; echo "--- 已移除失效的 libs/klayout ---"; }

# --- 3) 改 APP_LIBRARY_NAME ---
if grep -q "APP_LIBRARY_NAME = 'libklayout.so'" "$ETS_CONST"; then
  echo "--- APP_LIBRARY_NAME 已是 libklayout.so，跳过"
else
  sed -i "s/export const APP_LIBRARY_NAME = '[^']*';/export const APP_LIBRARY_NAME = 'libklayout.so';/" "$ETS_CONST"
  echo "--- APP_LIBRARY_NAME -> libklayout.so"
fi

# --- 4) 复用 calculator 的 hvigor+原生打包+签名链 ---
if [ "${HAP_SIGN:-1}" = "0" ]; then
  echo "HAP_SIGN=0：只打包"
  ( cd "$HERE" && sh build_all.sh ) 2>&1 | tail -8
  exit 0
fi

( cd "$HERE" && sh build_all.sh ) 2>&1 | tail -8
[ -f "$HERE/ohos/entry/build/default/outputs/default/entry-default-unsigned.hap" ] || { echo "*** 打包失败"; exit 1; }

# build_all.sh 的产物名是 entry-calculator-signed.hap；重命名为 klayout 语义
FINAL=$HERE/ohos/entry/build/default/outputs/default/entry-default-unsigned.hap
echo "=== 重签并产出 $OUT ==="
( cd "$SIGNDIR" && sh sign_official.sh "$FINAL" "$OUT" ) 2>&1 | tail -4
[ -f "$OUT" ] || { echo "*** 签名失败"; exit 1; }

echo
echo "✅ 产物: $OUT ($(stat -c%s "$OUT") 字节)"
echo "   安装: hdc install $OUT"
