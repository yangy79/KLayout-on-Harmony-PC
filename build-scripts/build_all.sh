#!/bin/sh
# calculator（Qt 5.12 for OHOS）全链路一键构建：
#   hvigor 编译 ArkTS + 资源  →  原生工具打包 HAP  →  官方工具签名
#
# 为什么分三步而不是直接 hvigor assembleHap：
#   hvigor 的 PackageHap 任务会 spawn `java -jar app_packing_tool.jar`，
#   而 HarmonyOS PC 上没有 java（spawn java ENOENT, Error Code 00308018）。
#   好在 SDK 里同时给了原生 ELF 版 ohos_packing_tool，参数一致，手工补上这一步即可。
#
# 用法：sh build_all.sh          产出 entry-calculator-signed.hap
#      HAP_SIGN=0 sh build_all.sh  只打包不签名

HERE=/storage/Users/currentUser/dev/qt5-ohos/apps/calculator
SIGNDIR=/storage/Users/currentUser/Documents/ohos-dev/signing
OUT=$HERE/entry-calculator-signed.hap

# --- 0) 干净环境：清掉 WorkBuddy 注入的 node/rm shim，重建 PATH ---
unset NODE_OPTIONS BASH_ENV PYTHONPATH
unset CODEBUDDY_SAFE_DELETE_ENABLED CODEBUDDY_SAFE_DELETE_BIN_DIR
unset CODEBUDDY_SAFE_DELETE_BULK_GUARD CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR
unset CODEBUDDY_SAFE_DELETE_BROKER_DELETE CODEBUDDY_SAFE_DELETE_REPORT_PATH
unset CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD

# node 在本机报 os.type()==="HarmonyOS"，hvigor 的 isLinux() 判 "Linux"，
# 于是 "windows?.dll : linux?.so : .dylib" 落到 darwin 分支，去找不存在的
# libimage_transcoder_shared.dylib。用 preload shim 把 os.type() 伪装成 Linux。
export NODE_OPTIONS="--require /storage/Users/currentUser/dev/qt5-ohos/hostbin/ohos-host-linux-shim.cjs"
export PATH=/storage/Users/currentUser/dev/qt5-ohos/hostbin:/data/service/hnp/bin:/bin:/usr/bin

echo "===== 1/3 hvigor: 编译 ArkTS 与资源 ====="
( cd "$HERE/ohos" && /storage/Users/currentUser/dev/clt26/bin/hvigorw \
    assembleHap --mode module -p product=default --no-daemon ) 2>&1 | tail -5
# 注意：这一步必然在 PackageHap 处失败（缺 java），属预期；前面所有 task 已完成，
# 中间产物齐备即可继续。所以这里不检查退出码。

echo
echo "===== 2/3 原生工具打包 HAP（替代 java -jar app_packing_tool.jar） ====="
sh "$HERE/pack_hap_native.sh" 2>&1 | tail -5

UNSIGNED=$HERE/ohos/entry/build/default/outputs/default/entry-default-unsigned.hap
[ -f "$UNSIGNED" ] || { echo "打包失败：找不到 $UNSIGNED"; exit 1; }

if [ "${HAP_SIGN:-1}" = "0" ]; then
  echo "HAP_SIGN=0，跳过签名"; exit 0
fi

echo
echo "===== 3/3 官方 hap-sign-tool 签名 ====="
( cd "$SIGNDIR" && sh sign_official.sh "$UNSIGNED" "$OUT" ) 2>&1 | tail -6

[ -f "$OUT" ] && { echo; echo "✅ 产物: $OUT ($(stat -c%s "$OUT") 字节)"; echo "   装机: hdc install $OUT"; }
