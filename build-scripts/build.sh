#!/bin/sh
# 用 qmake 构建 calculator（Qt 5.12.12 for OpenHarmony）
#
# 注意：
#   - NATIVE_OHOS_SDK 必须设置，ohos-clang mkspec 会读取它并据此推导 sysroot / target triple。
#   - OHOS_TARGET_ARCH 默认为 arm64-v8a（configure 时确定）。
#   - PATH 必须完全重建，绕开 WorkBuddy 注入的坏 rm shim（bad interpreter → Error 127）。

export NATIVE_OHOS_SDK=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native
export OHOS_SDK_ROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos
export OHOS_TARGET_ARCH=arm64-v8a

export PATH=/storage/Users/currentUser/dev/qt5-ohos/hostbin:/data/storage/el1/bundle/libs/arm64/python/bin:/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/bin:/data/service/hnp/bin:/bin:/usr/bin

QT=/storage/Users/currentUser/dev/qt5-ohos/install/5.12.12/ohos-arm64-v8a-clang
APP=/storage/Users/currentUser/dev/qt5-ohos/apps/calculator
BUILD="$APP/build-arm64"

mkdir -p "$BUILD"
cd "$BUILD" || exit 1

"$QT/bin/qmake" "$APP/cpp/calculator.pro" -spec ohos-clang CONFIG+=release || exit 1
make -j20 || exit 1

# ohos-clang mkspec 带 unversioned_libname，产物是无前缀无后缀的 calculator；
# 而鸿蒙 HAP 的 libs/<arch>/ 与 QtAppConstants.ets 的 APP_LIBRARY_NAME 都用
# libXXX.so 惯例，这里统一重命名。（dlopen 按路径加载，与内部 SONAME 无关。）
if [ -f "$BUILD/calculator" ]; then
    cp -f "$BUILD/calculator" "$BUILD/libcalculator.so"
fi

echo "=== 产物 ==="
ls -la "$BUILD"/libcalculator.so 2>/dev/null

echo "=== 校验 main 符号导出 ==="
"$NATIVE_OHOS_SDK/llvm/bin/llvm-nm" -D --defined-only "$BUILD/libcalculator.so" 2>/dev/null | grep -w main

echo "=== 依赖的 Qt 库 ==="
"$NATIVE_OHOS_SDK/llvm/bin/llvm-readelf" -d "$BUILD/libcalculator.so" 2>/dev/null | grep -E "NEEDED.*Qt5|NEEDED.*c\\+\\+" | head -6
