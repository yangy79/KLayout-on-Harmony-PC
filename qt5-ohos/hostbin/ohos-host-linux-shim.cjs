// DevEco/hvigor 宿主平台 shim（HarmonyOS PC 专用）
//
// 问题：本机构建时 node 报告 os.type()==="HarmonyOS"、process.platform==="openharmony"，
// 而 hvigor 的平台判定是硬编码字符串比较：
//     @ohos/hvigor-common/src/util/system-util.js
//         isWindows(){ return "Windows_NT" === os.type() }
//         isLinux()  { return "Linux"      === os.type() }
//         isMac()    { return "Darwin"     === os.type() }
// 于是三支全 false，任何 "windows ? .dll : linux ? .so : .dylib" 的三元都会落到 darwin 分支。
// 典型症状（CompileResource 阶段）：
//     Failed to load the library '<sdk>/hms/toolchains/lib/libimage_transcoder_shared.dylib',
//     path invalid
// 而同目录下 libimage_transcoder_shared.so 是 ELF64/AArch64，正是本机可加载的。
//
// 用法：NODE_OPTIONS="--require /path/to/ohos-host-linux-shim.cjs"
// 该变量会被 hvigor fork 出来的 worker 子进程继承，因此全局生效。
//
// 只改 os.type()，不动 process.platform：
//   - 报错点用的正是 os.type()；
//   - 改 process.platform 会让 native addon 去 xxx-linux-arm64.node 目录找文件，
//     而这些 addon 实际是按 openharmony 命名/构建的，反而会加载失败。

const os = require('os');

const REAL_TYPE = (() => { try { return os.type(); } catch (e) { return ''; } })();

// 只在确实是鸿蒙宿主时才伪装，避免误伤真实 Linux/Windows 上的复用
if (REAL_TYPE === 'HarmonyOS' || REAL_TYPE === 'OpenHarmony' || process.platform === 'openharmony') {
    try {
        Object.defineProperty(os, 'type', {
            value: () => 'Linux',
            writable: true,
            configurable: true,
            enumerable: false
        });
    } catch (e) {
        // 兜底：直接赋值
        try { os.type = () => 'Linux'; } catch (e2) {}
    }
}
