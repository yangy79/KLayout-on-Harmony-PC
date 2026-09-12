#!/bin/sh
# 冒烟验证：release 模式构建的包能否正常运行。
#
# 为什么需要绕一圈：
#   上架用的 release 包必须用 AGC 的发布证书签，而发布证书是 app_gallery 分发类型的，
#   设备根本不信任、无法侧载（code:9568322）。所以想真机验证 release 构建，
#   只能用调试证书签一份"同样是 release 编译产物"的包。
#   又因为调试 Profile 是**按包名签发**的，而包名已改成 com.yangy79.klayout，
#   这里临时把包名改回 Ot6.based.Klayout，测完自动恢复并重建。
#
# 用法：sh smoke_test_release.sh
set -e

D=/storage/Users/currentUser/dev/qt5-ohos/apps/calculator
OHOS=$D/ohos
APPJ=$OHOS/AppScope/app.json5
SIGN=/storage/Users/currentUser/Documents/ohos-dev/signing
UNSIGNED=$OHOS/entry/build/default/outputs/default/entry-default-unsigned.hap
OUT=$D/klayout-releasebuild-dbgsigned.hap
NEW=com.yangy79.klayout
OLD=Ot6.based.Klayout

TGT=$(hdc list targets 2>/dev/null | head -1 | tr -d '\r')
[ -n "$TGT" ] || { echo "*** hdc 无设备，先 hdc tconn <IP:端口>"; exit 1; }
echo "设备: $TGT"

set_bundle() {
  python3 - "$APPJ" "$1" "$2" <<'PY'
import sys
p, new, old = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(p, encoding="utf-8").read()
if old not in t:
    sys.exit(f"[FAIL] {p} 里找不到 {old}")
open(p, "w", encoding="utf-8").write(t.replace(old, new))
print(f"  bundleName -> {new}")
PY
}

restore_and_rebuild() {
  echo
  echo "==================== 收尾：恢复包名并重建 release 包 ===================="
  set_bundle "$NEW" "$OLD"
  sh $D/build_release.sh 2>&1 | tail -8
}
trap restore_and_rebuild EXIT

echo
echo "==================== 1) 临时改回调试包名 ===================="
set_bundle "$OLD" "$NEW"

echo
echo "==================== 2) release 构建 ===================="
sh $D/build_release.sh 2>&1 | tail -10

echo
echo "==================== 3) 调试证书签名（仅为侧载验证） ===================="
( cd "$SIGN" && HAP_PROFILE=KlayoutProfileDebug.p7b HAP_COMPAT_VER=12 \
    sh sign_official.sh "$UNSIGNED" "$OUT" ) 2>&1 | tail -3

echo
echo "==================== 4) 侧载并启动 ===================="
hdc -t "$TGT" install -r "$OUT" 2>&1 | tail -2
hdc -t "$TGT" shell "aa force-stop Ot6.based.Klayout" >/dev/null 2>&1 || true
hdc -t "$TGT" shell "hilog -r" >/dev/null 2>&1 || true
hdc -t "$TGT" shell "aa start -a QAbility -b Ot6.based.Klayout" 2>&1 | tail -1
sleep 7

echo
echo "==================== 5) 日志判据 ===================="
hdc -t "$TGT" shell "hilog -x 2>&1 | grep -E 'KLAYOUT_OHOS' | grep -E 'CONT_ENTERED|PATCH_DONE|registered formats|preloaded|main window|icon\]|Stream has unknown' | head -n 25" 2>&1 | tail -28

echo
echo "（进程存活检查）"
hdc -t "$TGT" shell "ps -ef 2>/dev/null | grep -c 'Ot6.based.Klayout'" 2>&1 | tail -1

echo
echo "冒烟包: $OUT"
