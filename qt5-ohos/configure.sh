#!/bin/sh
# Qt 5.12.12 for OpenHarmony/HarmonyOS —— 本机（HarmonyOS PC aarch64 musl）自持构建配置脚本
#
# 与官方 wiki 的差异（本机适配）：
#   1. -platform linux-clang-native  —— 本机 uname -s 返回 "HarmonyOS"，configure 无法自动识别宿主平台；
#      且本机无 g++，官方 linux-clang mkspec 含 "-ccc-gcc-name g++" 会失败，故自建无 g++ 依赖的 mkspec。
#   2. -extprefix 指向本机可写目录   —— NDK 目录 /data/service/hnp/... 只读，无法作为安装目标。
#   3. host 与 target 使用同一个 clang（本机 clang 即 ohos NDK clang），故 host tools 天然可在本机运行。

set -e

export NATIVE_OHOS_SDK=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native
export OHOS_SDK_ROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos
export LLVM_INSTALL_DIR="$NATIVE_OHOS_SDK/llvm"
# 与 build_qtbase.sh 一致：必须重建 PATH，绕开 WorkBuddy 注入的坏 rm shim
export PATH=/storage/Users/currentUser/dev/qt5-ohos/hostbin:/data/storage/el1/bundle/libs/arm64/python/bin:/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/bin:/data/service/hnp/bin:/bin:/usr/bin

QT_SRC=/storage/Users/currentUser/dev/qt5-ohos/src/qt-harmonyos-src-5.12.12
QT_BUILD=/storage/Users/currentUser/dev/qt5-ohos/build-arm64
QT_INSTALL=/storage/Users/currentUser/dev/qt5-ohos/install/5.12.12/ohos-arm64-v8a-clang

ARCH=arm64-v8a

mkdir -p "$QT_BUILD"
cd "$QT_BUILD"

"$QT_SRC/configure" \
    -v \
    -platform linux-clang-native \
    -xplatform ohos-clang \
    -prefix /data/storage/el1/bundle/libs/arm64 \
    -extprefix "$QT_INSTALL" \
    -opensource \
    -confirm-license \
    -release \
    -no-use-gold-linker \
    -no-gcc-sysroot \
    -ohos-arch "$ARCH" \
    -opengles3 \
    -skip qt3d -skip qtactiveqt -skip qtandroidextras -skip qtcanvas3d \
    -skip qtconnectivity -skip qtdatavis3d -skip qtdoc -skip qtdocgallery -skip qtfeedback \
    -skip qtgamepad -skip qtgraphicaleffects -skip qtlocation -skip qtmacextras -skip qtnetworkauth \
    -skip qtpim -skip qtpurchasing -skip qtqa -skip qtremoteobjects -skip qtrepotools \
    -skip qtscript -skip qtscxml -skip qtsensors -skip qtserialbus -skip qtserialport \
    -skip qtspeech -skip qtsystems -skip qttools -skip qttranslations -skip qtvirtualkeyboard \
    -skip qtwayland -skip qtwebchannel -skip qtwebengine -skip qtwebglplugin -skip qtwebsockets \
    -skip qtwebview -skip qtwinextras -skip qtx11extras -skip doc \
    -no-dbus \
    -c++std c++14 \
    -nomake examples \
    -nomake tests
