#!/bin/sh
# KLayout 上架包全链路：签 hap -> 打 .app -> 签 .app -> 双验
#
# 前置（需你自行在 AGC 完成，见 README.md）：
#   $R/klayout-release.cer  —— AGC「证书管理」下载的发布证书（含全链，≥2 张）
#   $R/klayout-release.p7b  —— AGC「Profile」下载的发布 Profile（type=release）
# 两者缺一，本脚本会在第 1 步报错退出。
#
# 用法：sh build_app_pack.sh
#   产物：klayout-1.0.0-release.hap / klayout-1.0.0-release.app
#
# AGC 上架**只接受 .app（App Pack）**，不传模块级 .hap。
set -e

R=/storage/Users/currentUser/Documents/ohos-dev/signing/klayout-release
D=/storage/Users/currentUser/dev/qt5-ohos/apps/calculator
A=$D/appstage
PT=/data/service/hnp/bin/ohos_packing_tool
ST=/data/service/hnp/bin/hap-sign-tool

# release 构建产出的未签名 HAP（由 build_release.sh 生成）
U=$D/ohos/entry/build/default/outputs/default/entry-default-unsigned.hap
PACKINFO=$D/ohos/entry/build/default/outputs/default/pack.info
SIGNED_HAP=$D/klayout-1.0.0-release.hap
SIGNED_APP=$D/klayout-1.0.0-release.app

# pack.info 里 apiVersion.compatible = 12（与 build-profile.json5 的 compatibleSdkVersion 5.0.0(12) 一致）
COMPAT_VER=12

ALIAS=klayoutrelease
PWD_STORE=${KLAYOUT_KS_PWD:?set KLAYOUT_KS_PWD}

echo "==================== 前置检查 ===================="
for f in "$R/klayout-release.p12" "$R/klayout-release.cer" "$R/klayout-release.p7b"; do
  if [ ! -f "$f" ]; then
    echo "*** 缺少 $f"
    case "$f" in
      *.cer) echo "    -> 需在 AGC 用 $R/klayout-release.csr 申请【发布证书】并下载保存为此文件名" ;;
      *.p7b) echo "    -> 需在 AGC 为包名 com.yangy79.klayout 创建【发布 Profile】并下载保存为此文件名" ;;
    esac
    exit 1
  fi
done
[ -f "$U" ] || { echo "*** 找不到 release 未签名包：$U"; echo "    先执行：sh $D/build_release.sh"; exit 1; }
# 拒绝把 debug 包送去签名（上架必拒）
python3 - "$U" <<'PY' || exit 1
import sys, zipfile, json
m = json.loads(zipfile.ZipFile(sys.argv[1]).read("module.json"))
dbg = m["app"].get("debug")
sm  = [n for n in zipfile.ZipFile(sys.argv[1]).namelist() if "sourceMaps" in n]
if dbg is not False or sm:
    print(f"*** 该包仍是 debug 构建（app.debug={dbg}, sourceMaps={len(sm)} 条），拒绝签名。")
    print("    请改用 build_release.sh 产出的包。")
    sys.exit(1)
print("  ✓ 包的 app.debug=false 且无 sourceMaps")
PY

python3 -c "import shutil; shutil.rmtree('$A', ignore_errors=True)" 2>/dev/null || true
mkdir -p "$A" "$D/verify"

echo
echo "==================== 1/4 签 HAP ===================="
$ST sign-app -mode localSign \
  -keyAlias "$ALIAS" -keyPwd "$PWD_STORE" -keystorePwd "$PWD_STORE" \
  -keystoreFile "$R/klayout-release.p12" \
  -appCertFile  "$R/klayout-release.cer" \
  -profileFile  "$R/klayout-release.p7b" -profileSigned 1 \
  -inFile "$U" \
  -signAlg SHA256withECDSA -signCode 1 -compatibleVersion $COMPAT_VER \
  -outFile "$SIGNED_HAP" 2>&1 | tail -3

echo
echo "==================== 2/4 打 App Pack ===================="
cp "$SIGNED_HAP" "$A/entry-default.hap"
$PT pack --mode app --force true \
  --pack-info-path "$PACKINFO" \
  --hap-path "$A/entry-default.hap" \
  --hsp-path "" \
  --replace-pack-info false \
  --main-module-limit 2 --normal-module-limit 2 \
  --out-path "$A/klayout-default-unsigned.app" 2>&1 | tail -4

echo
echo "==================== 3/4 签 .app ===================="
# 与签 hap 同一条命令，差别：-inFile 换 .app，且不传 -compatibleVersion
$ST sign-app -mode localSign \
  -keyAlias "$ALIAS" -keyPwd "$PWD_STORE" -keystorePwd "$PWD_STORE" \
  -keystoreFile "$R/klayout-release.p12" \
  -appCertFile  "$R/klayout-release.cer" \
  -profileFile  "$R/klayout-release.p7b" -profileSigned 1 \
  -inFile "$A/klayout-default-unsigned.app" \
  -signAlg SHA256withECDSA -signCode 1 \
  -outFile "$SIGNED_APP" 2>&1 | tail -3

echo
echo "==================== 4/4 校验 ===================="
$ST verify-app -inFile "$SIGNED_HAP" \
  -outCertChain "$D/verify/hap-chain.cer" -outProfile "$D/verify/hap-profile.p7b" 2>&1 | tail -2
$ST verify-app -inFile "$SIGNED_APP" \
  -outCertChain "$D/verify/app-chain.cer" -outProfile "$D/verify/app-profile.p7b" 2>&1 | tail -2

echo
echo "==================== 产物 ===================="
ls -l "$SIGNED_HAP" "$SIGNED_APP"
echo
echo "上架：把 $SIGNED_APP 上传到 AGC（AppGallery Connect）"
