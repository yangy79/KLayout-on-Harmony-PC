#!/bin/sh
# 安装已构建好的 qtbase（Qt 5.12.12 for OpenHarmony）到 -extprefix 指定的目录。
#
# 说明：
#   - 我们只构建了 module-qtbase，所以安装目标用 module-qtbase-install_subtargets，
#     而不是顶层 `make install`（后者会尝试安装所有模块，包含被 -skip 的，容易报错）。
#   - PATH 必须完全重建：WorkBuddy 注入的 shim/rm 是坏脚本（bad interpreter），
#     会让 install 阶段的 `rm -f` 规则 Error 127。

export NATIVE_OHOS_SDK=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native
export OHOS_SDK_ROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos

export PATH=/storage/Users/currentUser/dev/qt5-ohos/hostbin:/data/storage/el1/bundle/libs/arm64/python/bin:/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/bin:/data/service/hnp/bin:/bin:/usr/bin

cd /storage/Users/currentUser/dev/qt5-ohos/build-arm64
exec make -j20 module-qtbase-install_subtargets
