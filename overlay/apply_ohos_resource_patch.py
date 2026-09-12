#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KLayout on HarmonyOS: 资源目录定位补丁（诊断走 hilog）。

API 调用方式（已与 qohosappcontext_p.h 核对）
-------------------------------------------
  namespace QOhosAppContext {
    enum class Type { ..., resourceDir, filesDir, ... };
    Q_CORE_EXPORT QString getProperty(Type prop);   // 自由函数，非成员
  }
  调用：QOhosAppContext::getProperty(QOhosAppContext::Type::resourceDir)

诊断通道（v2, 2026-09-11 改）
------------------------------
KLayout 的 Qt message handler 只写 stderr，OHOS 上 stderr 进不了 hilog；
文件落盘又在 app 沙箱内，hdc shell 读不到 —— 两条路都不通。故改为 hilog：

  ohos_dbg() 先 dlopen("libhilog_ndk.z.so") + dlsym("OH_LOG_Print") 动态调用，
  这样**不新增 DT_NEEDED**（避免把 SDK sysroot 的 libhilog_ndk 打进 HAP，
  那正是先前 Qt 初始化 SIGSEGV 的根因）；dlopen 失败才降级写文件。

  过滤：hilog | grep KLAYOUT_OHOS

两个注入点：
  A) klayout_main_cont 开头(qInstallMessageHandler 之前, QApplication 之前)
     -> CONT_ENTERED（确认 main 入口被调用）
  B) app->parse_cmd 之前(QApplication 创建之后)
     -> PATCH_ENTERED -> resourceDir/filesDir -> 候选路径 probe ->
        KLAYOUT_PATH / KLAYOUT_HOME -> PATCH_DONE
"""
import os, sys

ROOT = os.environ.get("KLAYOUT_PATCH_ROOT",
                      os.path.dirname(os.path.abspath(__file__)))
KL_CC  = os.path.join(ROOT, "src/klayout_main/klayout_main/klayout.cc")
KL_PRO = os.path.join(ROOT, "src/klayout_main/klayout_main/klayout_main.pro")

INCLUDE_BLOCK = '''#include "tlArch.h"

#if defined(Q_OS_OHOS)
# include <qohosappcontext_p.h>
# include "tlEnv.h"
# include <cstdlib>
# include <cstdio>
# include <string>
# include <dlfcn.h>
# include <QDir>
# include <QFileInfo>
# include <QStringList>

// OHOS 诊断：优先 hilog（dlopen 动态取 OH_LOG_Print，不新增 DT_NEEDED），
// 失败降级写文件（沙箱内路径，仅应用自查）。
static void ohos_dbg (const std::string &msg)
{
  typedef void (*ohlog_t) (int, int, unsigned int, const char *, const char *, ...);
  static ohlog_t s_log = 0;
  static int s_state = 0;
  if (s_state == 0) {
    s_state = 1;
    void *h = dlopen ("libhilog_ndk.z.so", RTLD_NOW | RTLD_GLOBAL);
    if (!h) h = dlopen ("/system/lib64/libhilog_ndk.z.so", RTLD_NOW | RTLD_GLOBAL);
    if (h) s_log = (ohlog_t) dlsym (h, "OH_LOG_Print");
  }
  if (s_log) {
    // LOG_APP=0, LOG_INFO=4, domain=0xD001400
    s_log (0, 4, 0xD001400u, "KLAYOUT_OHOS", "%{public}s", msg.c_str ());
    return;
  }
  const char *home = getenv ("HOME");
  std::string hp = home ? (std::string (home) + "/klayout_boot.log") : std::string ();
  const char *cands[] = {
    "/data/local/tmp/klayout_boot.log",
    "/data/storage/el1/tmp/klayout_boot.log",
    "/tmp/klayout_boot.log",
    hp.c_str ()
  };
  for (const char *p : cands) {
    if (!p || !*p) continue;
    FILE *f = fopen (p, "a");
    if (f) { fprintf (f, "%s\\n", msg.c_str ()); fclose (f); return; }
  }
}
#endif
'''

# 注入点 A: klayout_main_cont 开头, qInstallMessageHandler 之前
OHOS_BLOCK_A = '''#if defined(Q_OS_OHOS)
    //  >>> OHOS-KLAYOUT-DIAG-A-BEGIN >>>
    {
      const char *home = getenv ("HOME");
      ohos_dbg (std::string ("[boot] CONT_ENTERED @ ") + std::string (__TIME__)
                + std::string (" HOME=") + std::string (home ? home : "(null)"));
    }
    //  <<< OHOS-KLAYOUT-DIAG-A-END <<<
#endif
'''

# 注入点 B: app->parse_cmd 之前 (QApplication 创建之后)
OHOS_BLOCK_B = '''#if defined(Q_OS_OHOS)
    //  >>> OHOS-KLAYOUT-PATCH-BEGIN >>>
    ohos_dbg (std::string ("[boot] PATCH_ENTERED @ ") + std::string (__TIME__));

    {
      auto probe = [] (const QString &p) {
        QFileInfo fi (p);
        ohos_dbg (std::string ("[boot] probe '") + std::string (p.toUtf8 ().constData ())
                  + "' exists=" + (fi.exists () ? "1" : "0")
                  + " readable=" + (fi.isReadable () ? "1" : "0")
                  + " dir=" + (fi.isDir () ? "1" : "0"));
      };

      auto is_klayout_res = [] (const QString &d) -> bool {
        QDir dir (d);
        return dir.exists ()
            && (dir.exists (QString::fromUtf8 ("tech"))
                || dir.exists (QString::fromUtf8 ("macros"))
                || dir.exists (QString::fromUtf8 ("drc")));
      };

      QString rd = QOhosAppContext::getProperty (QOhosAppContext::Type::resourceDir);
      QString fd = QOhosAppContext::getProperty (QOhosAppContext::Type::filesDir);
      ohos_dbg (std::string ("[boot] resourceDir='")
                + std::string (rd.toUtf8 ().constData ()) + std::string ("'"));
      ohos_dbg (std::string ("[boot] filesDir='")
                + std::string (fd.toUtf8 ().constData ()) + std::string ("'"));

      QString chosen;
      if (!rd.isEmpty ()) {
        QStringList candidates;
        candidates << rd + QString::fromUtf8 ("/rawfile/klayout");
        candidates << rd + QString::fromUtf8 ("/resfile/klayout");
        candidates << rd + QString::fromUtf8 ("/klayout");
        candidates << rd;
        for (const QString &c : candidates) {
          probe (c);
          if (chosen.isEmpty () && is_klayout_res (c)) chosen = c;
        }
        if (chosen.isEmpty ()) {
          QList<QDir> stack; stack.push_back (QDir (rd));
          int depth = 0;
          while (!stack.isEmpty () && depth < 5) {
            QDir cur = stack.takeFirst ();
            if (is_klayout_res (cur.path ())) { chosen = cur.path (); break; }
            for (const QFileInfo &fi : cur.entryInfoList (QDir::Dirs | QDir::NoDotAndDotDot)) {
              stack.push_back (QDir (fi.filePath ()));
            }
            ++depth;
          }
        }
      }

      if (!chosen.isEmpty ()) {
        std::string new_path = std::string (chosen.toUtf8 ().constData ());
        const char *existing = getenv ("KLAYOUT_PATH");
        if (existing && *existing) {
          new_path += std::string (":") + std::string (existing);
        }
        tl::set_env ("KLAYOUT_PATH", new_path);
        ohos_dbg (std::string ("[boot] KLAYOUT_PATH='") + new_path + std::string ("'"));
      } else {
        ohos_dbg ("[boot] WARN: could not locate bundled resource tree");
      }

      if (!getenv ("KLAYOUT_HOME")) {
        if (!fd.isEmpty ()) {
          QString home = fd + QString::fromUtf8 ("/.klayout");
          QDir ().mkpath (home);
          tl::set_env ("KLAYOUT_HOME", std::string (home.toUtf8 ().constData ()));
          probe (home);
          ohos_dbg (std::string ("[boot] KLAYOUT_HOME='")
                    + std::string (home.toUtf8 ().constData ()) + std::string ("'"));
        }
      } else {
        ohos_dbg (std::string ("[boot] KLAYOUT_HOME already set='")
                  + std::string (getenv ("KLAYOUT_HOME")) + std::string ("'"));
      }
    }
    ohos_dbg ("[boot] PATCH_DONE");
    //  <<< OHOS-KLAYOUT-PATCH-END <<<
#endif
'''

PRO_ADD = ("# OHOS: QtCore private headers (QOhosAppContext::getProperty)\n"
           "INCLUDEPATH += $$[QT_INSTALL_HEADERS]/QtCore/$$QT_VERSION/QtCore/private\n"
           "# OHOS: keep klayout_main_cont (and the resource-path patch) reachable\n"
           "# (must use a non-empty 3rd arg: qmake's replace() rejects an empty one)\n"
           "QMAKE_LFLAGS = $$replace(QMAKE_LFLAGS, -Wl,--gc-sections, -Wl,--no-gc-sections)\n"
           "# OHOS: export 'main' so libqohos.so dlsym(\"main\") can start KLayout\n"
           "# (Qt OHOS mkspec compiles with -fvisibility=hidden, hiding main)\n"
           "QMAKE_LFLAGS += -Wl,--export-dynamic\n")

CC_INCLUDE_ANCHOR = '#include "tlArch.h"\n'
CC_INJECT_A_ANCHOR = '''#if QT_VERSION >= 0x050000
  qInstallMessageHandler (custom_message_handler);
'''
CC_INJECT_ANCHOR = '''    //  configures the application with the command line arguments
    app->parse_cmd (argc, argv);
'''
PRO_ANCHOR = "TARGET = klayout\n"


def _already(s):
    return ("OHOS-KLAYOUT-DIAG-A-BEGIN" in s) or ("OHOS-KLAYOUT-PATCH-BEGIN" in s)


def patch_cc():
    if not os.path.exists(KL_CC):
        raise SystemExit("ERROR: 找不到 " + KL_CC)
    with open(KL_CC, "r", encoding="utf-8") as f:
        s = f.read()
    if _already(s):
        print("  [skip] klayout.cc 已打补丁")
        return
    if CC_INCLUDE_ANCHOR not in s:
        raise SystemExit('ERROR: 未找到 #include "tlArch.h" 锚点')
    if CC_INJECT_A_ANCHOR not in s:
        raise SystemExit("ERROR: 未找到 qInstallMessageHandler 锚点(A)")
    if CC_INJECT_ANCHOR not in s:
        raise SystemExit("ERROR: 未找到 app->parse_cmd 锚点(B)")
    s = s.replace(CC_INCLUDE_ANCHOR, INCLUDE_BLOCK, 1)
    s = s.replace(CC_INJECT_A_ANCHOR, OHOS_BLOCK_A + CC_INJECT_A_ANCHOR, 1)
    s = s.replace(CC_INJECT_ANCHOR, OHOS_BLOCK_B + "\n" + CC_INJECT_ANCHOR, 1)
    with open(KL_CC, "w", encoding="utf-8") as f:
        f.write(s)
    print("  [ok] klayout.cc 已注入 A(CONT_ENTERED) + B(资源探测, hilog 输出)")


def patch_pro():
    if not os.path.exists(KL_PRO):
        raise SystemExit("ERROR: 找不到 " + KL_PRO)
    with open(KL_PRO, "r", encoding="utf-8") as f:
        s = f.read()
    if "OHOS: QtCore private headers" in s:
        print("  [skip] klayout_main.pro 已含 OHOS 改动")
        return
    if PRO_ANCHOR not in s:
        raise SystemExit("ERROR: 未找到 'TARGET = klayout' 锚点")
    s = s.replace(PRO_ANCHOR, PRO_ANCHOR + PRO_ADD, 1)
    with open(KL_PRO, "w", encoding="utf-8") as f:
        f.write(s)
    print("  [ok] klayout_main.pro 已加 QtCore 私有头目录 + 去 gc-sections + export-dynamic")


def revert_cc():
    with open(KL_CC, "r", encoding="utf-8") as f:
        s = f.read()
    s = s.replace(INCLUDE_BLOCK, CC_INCLUDE_ANCHOR, 1)
    for blk in (OHOS_BLOCK_A + "\n", OHOS_BLOCK_A, OHOS_BLOCK_B + "\n", OHOS_BLOCK_B):
        s = s.replace(blk, "", 1)
    with open(KL_CC, "w", encoding="utf-8") as f:
        f.write(s)
    print("  [ok] klayout.cc 已还原")


def revert_pro():
    with open(KL_PRO, "r", encoding="utf-8") as f:
        s = f.read()
    s = s.replace(PRO_ADD, "", 1)
    with open(KL_PRO, "w", encoding="utf-8") as f:
        f.write(s)
    print("  [ok] klayout_main.pro 已还原")


if __name__ == "__main__":
    if "--revert" in sys.argv:
        revert_cc(); revert_pro()
    else:
        print("应用 KLayout OHOS 资源定位+诊断补丁(v2, hilog)" +
              (" (到副本 " + ROOT + ")" if "KLAYOUT_PATCH_ROOT" in os.environ else "") + ":")
        patch_cc(); patch_pro()
        print("完成。请对 klayout_main 模块做增量重编(qmake+make)。")
