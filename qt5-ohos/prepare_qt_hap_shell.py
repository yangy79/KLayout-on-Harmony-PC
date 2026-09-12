#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 Qt 官方 DevEco 壳工程模板（qtbase/src/harmonyos/templates）改造成指定应用的工程。

用法：
  python3 prepare_qt_hap_shell.py --template <模板目录> --out <工程目录> \
      --bundle-name com.example.app --app-lib libfoo.so [--app-label Foo] [--no-embedded]

做的事：
  1. 复制模板到 --out
  2. 可选删除 qEmbeddedUiExtensionHost 模块（--no-embedded，并从 build-profile.json5 的 modules 里移除）
  3. AppScope/app.json5 的 bundleName / vendor / label
  4. entry/src/main/ets/common/QtAppConstants.ets 的 APP_LIBRARY_NAME（必须与 HAP 内
     libs/<arch>/ 下的 .so 文件名逐字一致，libqohos.so 会 dlopen 它并 dlsym("main")）
  5. entry/build-profile.json5 的 abiFilters 收敛为 --abi（默认 arm64-v8a）
"""

import argparse
import json
import os
import re
import shutil
import sys


def read_text(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def write_text(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--template", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--bundle-name", required=True)
    ap.add_argument("--app-lib", required=True, help="应用 .so 文件名，如 libcalculator.so")
    ap.add_argument("--app-label", default=None)
    ap.add_argument("--vendor", default="yydev")
    ap.add_argument("--abi", default="arm64-v8a")
    ap.add_argument("--no-embedded", action="store_true",
                    help="删除 qEmbeddedUiExtensionHost 模块（不需要嵌入式 UI 扩展时用）")
    args = ap.parse_args()

    src = os.path.abspath(args.template)
    dst = os.path.abspath(args.out)
    if not os.path.isdir(src):
        sys.exit("模板目录不存在: %s" % src)
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst, symlinks=True)
    print("1) 已复制模板 -> %s" % dst)

    # --- AppScope/app.json5 ---
    p = os.path.join(dst, "AppScope", "app.json5")
    s = read_text(p)
    s = re.sub(r'"bundleName"\s*:\s*"[^"]*"', '"bundleName": "%s"' % args.bundle_name, s)
    s = re.sub(r'"vendor"\s*:\s*"[^"]*"', '"vendor": "%s"' % args.vendor, s)
    write_text(p, s)
    print("2) app.json5 bundleName -> %s" % args.bundle_name)

    # --- QtAppConstants.ets ---
    p = os.path.join(dst, "entry", "src", "main", "ets", "common", "QtAppConstants.ets")
    s = read_text(p)
    s2 = re.sub(r"export const APP_LIBRARY_NAME = '[^']*';",
                "export const APP_LIBRARY_NAME = '%s';" % args.app_lib, s)
    if s2 == s:
        sys.exit("未能替换 APP_LIBRARY_NAME，检查文件格式")
    write_text(p, s2)
    print("3) APP_LIBRARY_NAME -> %s" % args.app_lib)

    # --- entry/build-profile.json5: abiFilters ---
    p = os.path.join(dst, "entry", "build-profile.json5")
    s = read_text(p)
    s = re.sub(r'"abiFilters"\s*:\s*\[[^\]]*\]', '"abiFilters": [\n        "%s"\n      ]' % args.abi, s)
    write_text(p, s)
    print("4) abiFilters -> [%s]" % args.abi)

    # --- 可选：移除 qEmbeddedUiExtensionHost ---
    if args.no_embedded:
        d = os.path.join(dst, "qEmbeddedUiExtensionHost")
        if os.path.isdir(d):
            shutil.rmtree(d)
        p = os.path.join(dst, "build-profile.json5")
        s = read_text(p)
        # 删除该 module 的整个对象块（含前导逗号）
        s2 = re.sub(r',?\s*\{\s*"name"\s*:\s*"qEmbeddedUiExtensionHost".*?\n    \}',
                    "", s, flags=re.S)
        if s2 != s:
            write_text(p, s2)
        print("5) 已移除 qEmbeddedUiExtensionHost 模块")

    # --- 资源字符串（可选）---
    if args.app_label:
        for rel in ("AppScope/resources/base/element/string.json",
                    "entry/src/main/resources/base/element/string.json",
                    "entry/src/main/resources/zh_CN/element/string.json",
                    "entry/src/main/resources/en_US/element/string.json"):
            p = os.path.join(dst, rel)
            if not os.path.exists(p):
                continue
            try:
                data = json.loads(read_text(p))
            except Exception:
                continue
            changed = False
            for item in data.get("string", []):
                if item.get("name") in ("app_name", "QAbility_label"):
                    item["value"] = args.app_label
                    changed = True
            if changed:
                write_text(p, json.dumps(data, ensure_ascii=False, indent=2))
        print("6) 应用名 -> %s" % args.app_label)

    print("\n完成。接下来：")
    print("  - 把应用 .so 与依赖的 Qt 库、libqohos.so 放进 %s" %
          os.path.join(dst, "entry", "libs", args.abi))
    print("  - 用 hvigorw 构建 HAP，再用 hap-sign-tool 签名")


if __name__ == "__main__":
    main()
