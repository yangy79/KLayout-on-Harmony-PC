#!/bin/sh
# setup-source.sh —— 还原「与已发布二进制对应的」完整可编译源码树
#
# 做的事：
#   1. 下载上游 KLayout 0.30.10 官方源码包（或使用 --tarball 指定的本地文件）
#   2. 校验 SHA-256（防止拿到被篡改 / 不同版本的上游）
#   3. 解包
#   4. 打上本仓库的全部移植补丁（patches/）
#   5. 复制本仓库的新增文件（overlay/）
#   6. 打印后续构建步骤
#
# 用法：
#   sh scripts/setup-source.sh                            # 下载并还原到 ./klayout-0.30.10
#   sh scripts/setup-source.sh --out /path/to/src         # 指定输出目录
#   sh scripts/setup-source.sh --tarball /path/to/klayout-0.30.10.tar.gz
#
# 依赖：sh、tar、patch；下载用 curl 或 wget；校验用 sha256sum / shasum / python3 / openssl 任一个。

set -e

# ---------- 上游源码包的精确标识 ----------
UPSTREAM_URL="https://www.klayout.org/downloads/source/klayout-0.30.10.tar.gz"
UPSTREAM_SIZE="103949878"
UPSTREAM_SHA256="96f7db5a744d9cd8ac913bb9186ce3b51e836321665d8f874336d0d43d2275c0"
TARBALL_NAME="klayout-0.30.10.tar.gz"
SRC_DIRNAME="klayout-0.30.10"

# ---------- 解析参数 ----------
TARBALL=""
URL="$UPSTREAM_URL"
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tarball) TARBALL="$2"; shift 2 ;;
    --url)     URL="$2";     shift 2 ;;
    --out)     OUT="$2";     shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "未知参数: $1（用 --help 查看用法）" >&2; exit 2 ;;
  esac
done

# 定位仓库根目录（本脚本位于 <repo>/scripts/）
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
[ -f "$REPO_DIR/patches/klayout-0.30.10-ohos.patch" ] || {
  echo "*** 找不到 $REPO_DIR/patches/klayout-0.30.10-ohos.patch" >&2
  echo "    本脚本必须放在仓库的 scripts/ 目录内运行。" >&2
  exit 1
}
[ -n "$OUT" ] || OUT="$PWD/$SRC_DIRNAME"

echo "=========================================================="
echo " KLayout 0.30.10 · HarmonyOS 移植 · 源码还原"
echo "=========================================================="
echo "  上游源码包 : ${TARBALL:-$URL}"
echo "  输出目录   : $OUT"
echo

# ---------- 工具检测 ----------
have() { command -v "$1" >/dev/null 2>&1; }

have patch || { echo "*** 缺少 patch 命令（Debian/Ubuntu: apt install patch；macOS 自带）" >&2; exit 1; }

sha256_of() {
  if have sha256sum;      then sha256sum "$1" | cut -d' ' -f1
  elif have shasum;       then shasum -a 256 "$1" | cut -d' ' -f1
  elif have openssl;      then openssl dgst -sha256 "$1" | sed 's/.*= *//'
  elif have python3;      then python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
  else echo "" ; fi
}

file_size() {
  if have stat; then
    stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null
  else
    wc -c < "$1" | tr -d ' '
  fi
}

# ---------- 1) 取得 tarball ----------
TMP_DL=""
if [ -z "$TARBALL" ]; then
  TARBALL="$PWD/$TARBALL_NAME"
  if [ -f "$TARBALL" ]; then
    echo "== 1/5 已存在本地文件，跳过下载: $TARBALL"
  else
    echo "== 1/5 下载上游源码包 =="
    if have curl; then
      curl -fL --retry 3 --connect-timeout 20 -o "$TARBALL" "$URL"
    elif have wget; then
      wget -c -O "$TARBALL" "$URL"
    else
      echo "*** 没有 curl / wget，无法下载。请手动下载后用 --tarball 指定：" >&2
      echo "    $URL" >&2
      exit 1
    fi
    echo "    -> $TARBALL"
  fi
else
  echo "== 1/5 使用指定的本地源码包 =="
  [ -f "$TARBALL" ] || { echo "*** 文件不存在: $TARBALL" >&2; exit 1; }
  echo "    -> $TARBALL"
fi

# ---------- 2) 校验 ----------
echo
echo "== 2/5 校验源码包 =="
SZ=$(file_size "$TARBALL")
HASH=$(sha256_of "$TARBALL")
echo "    大小    : $SZ 字节（期望 $UPSTREAM_SIZE）"
echo "    SHA-256 : $HASH"
echo "    期望值  : $UPSTREAM_SHA256"

if [ -n "$HASH" ] && [ "$HASH" != "$UPSTREAM_SHA256" ]; then
  echo
  echo "*** SHA-256 不匹配，拒绝继续。" >&2
  echo "    可能原因：上游重新打包、下载不完整、或该文件不是 0.30.10 官方源码包。" >&2
  echo "    请到 https://www.klayout.de/build.html 核对后重试。" >&2
  exit 1
fi
if [ -z "$HASH" ]; then
  echo "    [警告] 本机没有任何 sha256 工具，跳过哈希校验（仅比对了大小）。" >&2
  [ "$SZ" = "$UPSTREAM_SIZE" ] || { echo "*** 大小不匹配，拒绝继续。" >&2; exit 1; }
else
  echo "    ✓ 校验通过"
fi

# ---------- 3) 解包 ----------
echo
echo "== 3/5 解包 =="
if [ -e "$OUT" ]; then
  echo "*** 输出目录已存在: $OUT" >&2
  echo "    请先删除，或用 --out 指定其它目录。" >&2
  exit 1
fi
PARENT=$(dirname -- "$OUT")
mkdir -p "$PARENT"
TMPX="$PARENT/.klayout_extract_$$"
mkdir -p "$TMPX"
tar -xzf "$TARBALL" -C "$TMPX"
[ -d "$TMPX/$SRC_DIRNAME" ] || {
  echo "*** 解包后找不到 $SRC_DIRNAME/ —— 该 tarball 的结构与预期不符。" >&2
  rm -rf "$TMPX"
  exit 1
}
mv "$TMPX/$SRC_DIRNAME" "$OUT"
rm -rf "$TMPX"
echo "    -> $OUT（$(find "$OUT" -type f | wc -l | tr -d ' ') 个文件）"

# ---------- 4) 打补丁 ----------
echo
echo "== 4/5 打移植补丁 =="
( cd "$OUT" && patch -p1 < "$REPO_DIR/patches/klayout-0.30.10-ohos.patch" )
echo "    ✓ patches/klayout-0.30.10-ohos.patch 已应用"

# ---------- 5) 复制新增文件 ----------
echo
echo "== 5/5 复制本仓库新增文件（overlay/） =="
if [ -f "$REPO_DIR/overlay/apply_ohos_resource_patch.py" ]; then
  cp -f "$REPO_DIR/overlay/apply_ohos_resource_patch.py" "$OUT/"
  echo "    -> apply_ohos_resource_patch.py"
fi
if [ -d "$REPO_DIR/overlay/klayout-resources" ]; then
  cp -Rf "$REPO_DIR/overlay/klayout-resources" "$OUT/"
  echo "    -> klayout-resources/（$(find "$OUT/klayout-resources" -type f | wc -l | tr -d ' ') 个文件）"
fi

cat <<EOF

==========================================================
 完成。现在得到的是「与已发布二进制一一对应」的完整源码树。
==========================================================

  源码树 : $OUT

下一步（详见 docs/BUILD.md）：

  1) 准备 Qt 5.12.12 for OpenHarmony（只编 qtbase），见 qt5-ohos/README.md

  2) 配置并编译 KLayout（QMAKE 指向上面构建出的 qmake）：

       cd $OUT
       ./build.sh \\
         -qmake <qt5-ohos>/install/5.12.12/ohos-arm64-v8a-clang/bin/qmake \\
         -noruby -nopython -without-qtbinding \\
         -without-qt-svg -without-qt-multimedia \\
         -without-qt-designer -without-qt-uitools \\
         -nolibgit2 -nolstream \\
         -build $OUT/build-ohos -bin $OUT/bin-ohos

     产物：$OUT/build-ohos/libklayout.so 及各模块库、stream 插件。

  3) 注入 HAP 壳工程并打包签名，见 build-scripts/README.md

说明：资源路径注入逻辑（KLAYOUT_PATH / 插件预加载 / hilog 诊断）**已包含在上面的
      补丁里**，无需再运行 overlay/apply_ohos_resource_patch.py ——
      该脚本只是当初生成这些改动所用的工具，重复运行会被自身的
      "OHOS-KLAYOUT-PATCH-BEGIN" 标记识别为已应用并直接跳过。

许可：KLayout 为 GPL-3.0（见 LICENSE）。分发本源码树的任何修改版时，
      请同样以 GPL-3.0 提供完整对应源码。
EOF
