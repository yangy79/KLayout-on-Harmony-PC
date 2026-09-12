#!/bin/sh
# 用 SDK 自带的【原生】打包工具替代 java -jar app_packing_tool.jar。
#
# 背景：hvigor 的 PackageHap 任务 spawn `java -jar app_packing_tool.jar`，
# 本机（HarmonyOS PC）没有 java，直接 `spawn java ENOENT`（Error Code 00308018）。
# 好在 SDK 里同时提供了一个原生 ELF 版：openharmony/toolchains/lib/ohos_packing_tool
# （1.1MB，AArch64），参数与 jar 版一致，直接替换即可。
#
# 命令行参数抄自 hvigor 自己的 debug 日志
# （.hvigor/outputs/build-logs/build.log 里 "Use tool [.../app_packing_tool.jar] [...]"），
# 保证与官方打包完全同源。

export PATH=/storage/Users/currentUser/dev/qt5-ohos/hostbin:/data/service/hnp/bin:/bin:/usr/bin
unset NODE_OPTIONS
unset BASH_ENV

TOOL=/storage/Users/currentUser/dev/clt26/sdk/default/openharmony/toolchains/lib/ohos_packing_tool
B=/storage/Users/currentUser/dev/qt5-ohos/apps/calculator/ohos/entry/build/default

# 注意：jar 版是 `java -jar tool.jar --mode hap ...`，原生版是子命令式，
# 必须在前面加 `pack`：`ohos_packing_tool pack --mode hap ...`，漏了会报
# "not support command: --mode"。
"$TOOL" pack \
  --mode hap \
  --force true \
  --lib-path        "$B/intermediates/stripped_native_libs/default" \
  --json-path       "$B/intermediates/package/default/module.json" \
  --resources-path  "$B/intermediates/res/default/resources" \
  --index-path      "$B/intermediates/res/default/resources.index" \
  --pack-info-path  "$B/outputs/default/pack.info" \
  --ets-path        "$B/intermediates/loader_out/default/ets" \
  --pkg-sdk-info-path "$B/intermediates/loader/default/pkgSdkInfo.json" \
  --out-path        "$B/outputs/default/entry-default-unsigned.hap"

echo "EXIT=$?"
ls -l "$B/outputs/default/" 2>/dev/null
