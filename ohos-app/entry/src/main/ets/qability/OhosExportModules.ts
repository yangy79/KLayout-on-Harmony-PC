// Qt 模板生成的文件。原始内容在此 lazy-import 了一批 HarmonyOS 商业版专有 kit：
//   @kit.CoreSpeechKit / @kit.FileManagerServiceKit / @kit.Penkit /
//   @kit.ShareKit / @kit.StatusBarExtensionKit
// 在公共 SDK 下这些模块不可用，且 es2abc 在 compatibleSdkVersion=5.0.0(12) 下不支持
// `import lazy` 语法，编译期直接报：
//   10705000 Syntax Error: Current configuration does not support using lazy import.
// calculator 不需要任何这些能力，返回空工厂表即可
// （QtUtils.getModulesFactoriesMapForQt 会再往里塞 LocalStorage / QEmbeddedComponentCreator）。
export function getOhosExportModulesFactories(): object {
  return {};
}
