#!/bin/sh
# 构建 Qt 5.12.12 for OpenHarmony 的 qtbase 模块（本机宿主 = HarmonyOS PC）
#
# 两个本机专有的坑：
#   1. PATH 必须完全重建，不能继承 $PATH —— WorkBuddy 注入的 shim 目录排在 PATH 首位，
#      其中的 rm 是坏脚本（bad interpreter），会让 Makefile 里所有 `rm -f` 规则 Error 127。
#      故用干净 PATH + hostbin/rm（转发给 /bin/rm）。
#   2. 其余与 configure.sh 相同（NATIVE_OHOS_SDK 等）。

export NATIVE_OHOS_SDK=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native
export OHOS_SDK_ROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos

export PATH=/storage/Users/currentUser/dev/qt5-ohos/hostbin:/data/storage/el1/bundle/libs/arm64/python/bin:/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/bin:/data/service/hnp/bin:/bin:/usr/bin

cd /storage/Users/currentUser/dev/qt5-ohos/build-arm64
exec make -j20 module-qtbase
