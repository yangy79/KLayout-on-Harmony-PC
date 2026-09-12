#!/bin/sh
# KLayout 上架用 release 构建（产出 app.debug=false、不含 ets/sourceMaps.map 的 HAP）。
#
# 为什么需要单独一条：
#   build_all.sh 调的 hvigorw 没传 buildMode，而 hvigor 的 getBuildMode() 在
#   assembleHap 缺省时取 **DEBUG** —— 会写出 app.debug=true 且包内带
#   ets/sourceMaps.map，AGC 上架必被拒（API>=11 的包不得含调试信息）。
#
# 与 build_all.sh 相同的三个本机绕坑（node shim / 无 java / rm shim），额外加：
#   * 传 -p buildMode=release
#   * buildMode 变了必须清中间产物，否则复用 debug 的 module.json
#
# 用法：sh build_release.sh
#   产物：ohos/entry/build/default/outputs/default/entry-default-unsigned.hap（release 版）

HERE=/storage/Users/currentUser/dev/qt5-ohos/apps/calculator
LOG=$HERE/build_release.log

# --- 0) 干净环境 ---
unset NODE_OPTIONS BASH_ENV PYTHONPATH
unset CODEBUDDY_SAFE_DELETE_ENABLED CODEBUDDY_SAFE_DELETE_BIN_DIR
unset CODEBUDDY_SAFE_DELETE_BULK_GUARD CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR
unset CODEBUDDY_SAFE_DELETE_BROKER_DELETE CODEBUDDY_SAFE_DELETE_REPORT_PATH
unset CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD

# node 在本机 os.type()==="HarmonyOS"，hvigor 的 isLinux() 判 "Linux"，
# 于是去加载不存在的 *.dylib。用 preload shim 把 os.type() 伪装成 Linux。
export NODE_OPTIONS="--require /storage/Users/currentUser/dev/qt5-ohos/hostbin/ohos-host-linux-shim.cjs"
# 注意：PATH 必须显式带上本机 python3（宿主 python 装在 app 安装目录下，不在 /bin）。
#       脚本里的清理与自检用 python3 完成，漏了会静默失败（"inaccessible or not found"）。
export PATH=/storage/Users/currentUser/dev/qt5-ohos/hostbin:/data/service/hnp/bin:/bin:/usr/bin:/data/storage/el1/bundle/libs/arm64/python/bin
command -v python3 >/dev/null 2>&1 || { echo "*** PATH 里找不到 python3"; exit 1; }

# --- 1) 清中间产物（buildMode 变了，不清会复用 debug 的 module.json）---
echo "===== 0/3 清理中间产物 ====="
python3 - <<'PY'
import shutil, os
base = "/storage/Users/currentUser/dev/qt5-ohos/apps/calculator/ohos"
for rel in ("entry/build/default", "build"):
    d = os.path.join(base, rel)
    if os.path.exists(d):
        shutil.rmtree(d)
        print("  cleaned", rel)
    else:
        print("  (absent)", rel)
PY

# --- 2) hvigor release 编译 ---
echo "===== 1/3 hvigor: release 编译 ArkTS 与资源 ====="
( cd "$HERE/ohos" && /storage/Users/currentUser/dev/clt26/bin/hvigorw \
    assembleHap --mode module -p product=default -p buildMode=release --no-daemon ) > "$LOG" 2>&1
# 注意：本机无 java，PackageHap 阶段必然失败（属预期）；前面 task 完成后中间产物即齐备。
tail -6 "$LOG"

# --- 3) 原生工具打包 HAP ---
echo
echo "===== 2/3 原生工具打包 HAP ====="
sh "$HERE/pack_hap_native.sh" 2>&1 | tail -5

UNSIGNED=$HERE/ohos/entry/build/default/outputs/default/entry-default-unsigned.hap
[ -f "$UNSIGNED" ] || { echo "*** 打包失败：找不到 $UNSIGNED"; exit 1; }

# --- 4) 自检：debug 必须为 false 且不含 sourceMaps ---
echo
echo "===== 3/3 自检 ====="
python3 - "$UNSIGNED" <<'PY'
import sys, zipfile, json
p = sys.argv[1]
z = zipfile.ZipFile(p)
m = json.loads(z.read("module.json"))
names = z.namelist()
dbg = m["app"].get("debug")
sm = [n for n in names if "sourceMaps" in n]
print("  app.debug =", dbg, "(上架要求 false)")
print("  sourceMaps 条目 =", sm if sm else "无")
print("  bundleName =", m["app"].get("bundleName"))
print("  deviceTypes =", m["module"].get("deviceTypes"))
ok = (dbg is False) and (not sm)
print("  RESULT:", "PASS ✅" if ok else "FAIL ❌ —— 仍带调试信息，需检查 buildMode 是否生效")
sys.exit(0 if ok else 2)
PY
rc=$?
echo
echo "产物: $UNSIGNED ($(stat -c%s "$UNSIGNED" 2>/dev/null) 字节)"
exit $rc
