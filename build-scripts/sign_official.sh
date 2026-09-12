#!/bin/sh
# 鸿蒙本机 HAP 官方签名（原生 ELF 工具，无需 Java / DevEco / VM）
#
# 用法：
#   sh sign_official.sh <unsigned.hap> <out-signed.hap> [keyAlias]
#
# 前置材料（都在 signing/ 目录）：
#   key.pem            EC 私钥
#   yydev-leaf.pem     开发者证书（AGC 下发的 .cer 转 PEM 也行）
#   yydev-inter.pem    中间 CA
#   yydev-root.pem     根 CA
#   yydev.cer          -appCertFile 用（leaf 证书，PEM 或 DER 均可）
#   <profile>.p7b      调试 Profile（UDID 已加白名单）
#
# 关键前提：官方签名器是**原生 ELF**，不在 Java 里
#   /data/service/hnp/bin/hap-sign-tool
#   -> /data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/toolchains/lib/hap-sign-tool

set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

IN="${1:?用法: sh sign_official.sh <unsigned.hap> <out-signed.hap> [keyAlias]}"
OUT="${2:?用法: sh sign_official.sh <unsigned.hap> <out-signed.hap> [keyAlias]}"
ALIAS="${3:-yydev}"
PWD_="${HAP_KS_PWD:?set HAP_KS_PWD}"

KEY=key.pem
LEAF=yydev-leaf.pem
INTER=yydev-inter.pem
ROOT=yydev-root.pem
CERT=yydev.cer
PROFILE="${HAP_PROFILE:-KlayoutProfileDebug.p7b}"
KS=yydev.p12
SIGN_TOOL=/data/service/hnp/bin/hap-sign-tool

[ -f "$IN" ]      || { echo "缺输入包: $IN"; exit 1; }
[ -f "$KEY" ]     || { echo "缺私钥: $KEY"; exit 1; }
[ -f "$PROFILE" ] || { echo "缺 Profile: $PROFILE"; exit 1; }
[ -x "$SIGN_TOOL" ] || { echo "找不到官方签名器: $SIGN_TOOL"; exit 1; }

# 1) 证书链合并（leaf 必须在最前）
cat "$LEAF" "$INTER" "$ROOT" > yydev-fullchain.pem

# 2) 用 openssl 生成 p12 密钥库（官方工具要求 JKS 或 P12，不接受裸 PEM 私钥）
openssl pkcs12 -export \
  -out "$KS" -inkey "$KEY" -in "$LEAF" -certfile yydev-fullchain.pem \
  -name "$ALIAS" -password "pass:$PWD_"

echo "p12 生成: $KS ($(stat -c%s "$KS") 字节)"

# 3) 官方签名。-compatibleVersion 用 HAP 内 module.json 的 minAPIVersion 亦可，
#    这里取设备 API 版本，商用机实测 8 可过。
"$SIGN_TOOL" sign-app \
  -mode localSign \
  -keyAlias "$ALIAS" \
  -keyPwd "$PWD_" \
  -keystorePwd "$PWD_" \
  -keystoreFile "$KS" \
  -appCertFile "$CERT" \
  -profileFile "$PROFILE" \
  -profileSigned 1 \
  -inFile "$IN" \
  -signAlg SHA256withECDSA \
  -signCode 1 \
  -compatibleVersion "${HAP_COMPAT_VER:-8}" \
  -outFile "$OUT"

echo "签名完成: $OUT ($(stat -c%s "$OUT") 字节)"
echo "装机: hdc install $OUT"
