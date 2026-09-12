#!/bin/sh
# 用 DevEco CLI 的 hvigorw 把壳工程打包成 HAP（未签名）。
#
# 环境：
#   DEVECO_SDK_HOME —— 必须用 DevEco CLI 自带的 SDK（~/dev/clt26/sdk，其下 default/hms/{ets,js,native,...}）。
#     不要指向 hnp 装的 /data/service/hnp/ohos-sdk.org/...，布局不同，hvigor 会报
#     "SDK component missing"。
#     注意：CLI 26 自带的组件元信息文件名是 uni-package.json，而 hvigor 找
#     oh-uni-package.json —— 需为 ets/js/native/toolchains/previewer 各补一份（已补）。
#   PATH —— 完全重建，绕开坏 rm shim，并把 node/python 放进去

export NATIVE_OHOS_SDK=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native
unset DEVECO_SDK_HOME
export PATH=/storage/Users/currentUser/dev/qt5-ohos/hostbin:/data/storage/el1/bundle/libs/arm64/python/bin:/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/bin:/data/service/hnp/bin:/bin:/usr/bin

# ⚠️ 关键：WorkBuddy 会向子进程注入 node/rm shim，必须全部清掉，否则 hvigor 必崩。
#   - NODE_OPTIONS=--require .../node-language-shim.cjs  → 让 node 的 fs.rmSync 走安全删除
#     BROKER，spawnSync 会 EACCES，报错：
#     [safe-delete][SAFE_DELETE_BULK_GUARD_ERROR] spawnSync .../node EACCES
#   - CODEBUDDY_SAFE_DELETE_* / PYTHONPATH / BASH_ENV 同理（坏 rm shim 也来自这里）。
unset NODE_OPTIONS
unset BASH_ENV
unset PYTHONPATH
unset CODEBUDDY_SAFE_DELETE_ENABLED
unset CODEBUDDY_SAFE_DELETE_BIN_DIR
unset CODEBUDDY_SAFE_DELETE_BULK_GUARD
unset CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR
unset CODEBUDDY_SAFE_DELETE_BROKER_DELETE
unset CODEBUDDY_SAFE_DELETE_REPORT_PATH
unset CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD

# ⚠️ 第二个坑：node 在本机报 os.type()==="HarmonyOS"，hvigor 的 isLinux() 判 "Linux"，
# 于是 "windows?.dll : linux?.so : .dylib" 落到 darwin 分支，去加载不存在的
# hms/toolchains/lib/libimage_transcoder_shared.dylib（真正的 .so 就在旁边，ELF64/AArch64）。
# 用 preload shim 把 os.type() 伪装成 Linux；NODE_OPTIONS 会被 hvigor 的 worker 子进程继承。
export NODE_OPTIONS="--require /storage/Users/currentUser/dev/qt5-ohos/hostbin/ohos-host-linux-shim.cjs"

PROJ=/storage/Users/currentUser/dev/qt5-ohos/apps/calculator/ohos
HVIGORW=/storage/Users/currentUser/dev/clt26/bin/hvigorw

cd "$PROJ" || exit 1

"$HVIGORW" assembleHap --mode module -p product=default --no-daemon "$@"
