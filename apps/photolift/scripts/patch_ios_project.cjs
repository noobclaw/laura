// Wires PhotoLift's native pieces into ios/Runner.xcodeproj/project.pbxproj:
//   - Swift bridges + the Objective-C++ engine wrapper + the shared C++ core
//   - ncnn.framework / openmp.framework (downloaded by scripts/fetch_ncnn_ios.sh)
//   - a "Fetch ncnn" run-script phase that runs first, so a clean checkout builds
//   - en / zh-Hans InfoPlist.strings (localised display name + purpose strings)
//   - header/framework search paths and C++17 on the Runner target
// No Xcode on this machine, so the project file is edited as text with fixed
// 24-hex object ids (same approach as scripts/add_widget_target.cjs). Idempotent.
const fs = require('fs');
const path = require('path');

const proj = path.join(__dirname, '..', 'ios', 'Runner.xcodeproj', 'project.pbxproj');
let s = fs.readFileSync(proj, 'utf8');
if (s.includes('PhotoLiftEngine.mm')) {
  console.log('already patched');
  process.exit(0);
}

const id = (n) => 'PL' + '0'.repeat(20) + n.toString(16).toUpperCase().padStart(2, '0');
// file refs
const F_UPSCALE = id(1), F_MEDIA = id(2), F_ENGINE_H = id(3), F_ENGINE_MM = id(4);
const F_CORE_CPP = id(5), F_CORE_H = id(6), F_NCNN = id(7), F_OPENMP = id(8);
const F_STR_EN = id(9), F_STR_ZH = id(10), G_STRINGS = id(11);
// build files
const B_UPSCALE = id(21), B_MEDIA = id(22), B_ENGINE_MM = id(23), B_CORE_CPP = id(24);
const B_NCNN = id(25), B_OPENMP = id(26), B_STRINGS = id(27);
// groups / phases
const G_FRAMEWORKS = id(31), G_NATIVE = id(32), P_FETCH = id(33);

function insertBefore(marker, text) {
  if (!s.includes(marker)) throw new Error('marker missing: ' + marker);
  s = s.replace(marker, text + marker);
}
function replaceOnce(from, to) {
  if (!s.includes(from)) throw new Error('anchor missing: ' + from);
  s = s.replace(from, to);
}

// PBXBuildFile
insertBefore('/* End PBXBuildFile section */',
`\t\t${B_UPSCALE} /* UpscaleBridge.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${F_UPSCALE} /* UpscaleBridge.swift */; };
\t\t${B_MEDIA} /* MediaBridge.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${F_MEDIA} /* MediaBridge.swift */; };
\t\t${B_ENGINE_MM} /* PhotoLiftEngine.mm in Sources */ = {isa = PBXBuildFile; fileRef = ${F_ENGINE_MM} /* PhotoLiftEngine.mm */; };
\t\t${B_CORE_CPP} /* photolift_core.cpp in Sources */ = {isa = PBXBuildFile; fileRef = ${F_CORE_CPP} /* photolift_core.cpp */; };
\t\t${B_NCNN} /* ncnn.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${F_NCNN} /* ncnn.framework */; };
\t\t${B_OPENMP} /* openmp.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${F_OPENMP} /* openmp.framework */; };
\t\t${B_STRINGS} /* InfoPlist.strings in Resources */ = {isa = PBXBuildFile; fileRef = ${G_STRINGS} /* InfoPlist.strings */; };
`);

// PBXFileReference
insertBefore('/* End PBXFileReference section */',
`\t\t${F_UPSCALE} /* UpscaleBridge.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UpscaleBridge.swift; sourceTree = "<group>"; };
\t\t${F_MEDIA} /* MediaBridge.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MediaBridge.swift; sourceTree = "<group>"; };
\t\t${F_ENGINE_H} /* PhotoLiftEngine.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = PhotoLiftEngine.h; sourceTree = "<group>"; };
\t\t${F_ENGINE_MM} /* PhotoLiftEngine.mm */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.objcpp; path = PhotoLiftEngine.mm; sourceTree = "<group>"; };
\t\t${F_CORE_CPP} /* photolift_core.cpp */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.cpp; name = photolift_core.cpp; path = ../native/photolift_core.cpp; sourceTree = "<group>"; };
\t\t${F_CORE_H} /* photolift_core.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; name = photolift_core.h; path = ../native/photolift_core.h; sourceTree = "<group>"; };
\t\t${F_NCNN} /* ncnn.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = ncnn.framework; path = Frameworks/ncnn.framework; sourceTree = "<group>"; };
\t\t${F_OPENMP} /* openmp.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = openmp.framework; path = Frameworks/openmp.framework; sourceTree = "<group>"; };
\t\t${F_STR_EN} /* en */ = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = en; path = en.lproj/InfoPlist.strings; sourceTree = "<group>"; };
\t\t${F_STR_ZH} /* zh-Hans */ = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = "zh-Hans"; path = "zh-Hans.lproj/InfoPlist.strings"; sourceTree = "<group>"; };
`);

// PBXFrameworksBuildPhase: link ncnn + openmp into Runner
replaceOnce(
`\t\t\t\t78A318202AECB46A00862997 /* FlutterGeneratedPluginSwiftPackage in Frameworks */,
\t\t\t);`,
`\t\t\t\t78A318202AECB46A00862997 /* FlutterGeneratedPluginSwiftPackage in Frameworks */,
\t\t\t\t${B_NCNN} /* ncnn.framework in Frameworks */,
\t\t\t\t${B_OPENMP} /* openmp.framework in Frameworks */,
\t\t\t);`);

// PBXGroup: Frameworks + Native groups, hooked into the main group; sources into Runner
insertBefore('/* End PBXGroup section */',
`\t\t${G_FRAMEWORKS} /* Frameworks */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t${F_NCNN} /* ncnn.framework */,
\t\t\t\t${F_OPENMP} /* openmp.framework */,
\t\t\t);
\t\t\tname = Frameworks;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t${G_NATIVE} /* Native */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t${F_CORE_CPP} /* photolift_core.cpp */,
\t\t\t\t${F_CORE_H} /* photolift_core.h */,
\t\t\t);
\t\t\tname = Native;
\t\t\tsourceTree = "<group>";
\t\t};
`);
replaceOnce(
`\t\t\t\t331C8082294A63A400263BE5 /* RunnerTests */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t};`,
`\t\t\t\t331C8082294A63A400263BE5 /* RunnerTests */,
\t\t\t\t${G_NATIVE} /* Native */,
\t\t\t\t${G_FRAMEWORKS} /* Frameworks */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t};`);
replaceOnce(
`\t\t\t\t74858FAD1ED2DC5600515810 /* Runner-Bridging-Header.h */,
\t\t\t);
\t\t\tpath = Runner;`,
`\t\t\t\t74858FAD1ED2DC5600515810 /* Runner-Bridging-Header.h */,
\t\t\t\t${F_UPSCALE} /* UpscaleBridge.swift */,
\t\t\t\t${F_MEDIA} /* MediaBridge.swift */,
\t\t\t\t${F_ENGINE_H} /* PhotoLiftEngine.h */,
\t\t\t\t${F_ENGINE_MM} /* PhotoLiftEngine.mm */,
\t\t\t\t${G_STRINGS} /* InfoPlist.strings */,
\t\t\t);
\t\t\tpath = Runner;`);

// Runner build phases: fetch script first
replaceOnce(
`\t\t\tbuildPhases = (
\t\t\t\t9740EEB61CF901F6004384FC /* Run Script */,`,
`\t\t\tbuildPhases = (
\t\t\t\t${P_FETCH} /* Fetch ncnn */,
\t\t\t\t9740EEB61CF901F6004384FC /* Run Script */,`);

// knownRegions
replaceOnce(
`\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);`,
`\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t\t"zh-Hans",
\t\t\t);`);

// Resources: InfoPlist.strings
replaceOnce(
`\t\t\t\t97C146FC1CF9000F007C117D /* Main.storyboard in Resources */,
\t\t\t);`,
`\t\t\t\t97C146FC1CF9000F007C117D /* Main.storyboard in Resources */,
\t\t\t\t${B_STRINGS} /* InfoPlist.strings in Resources */,
\t\t\t);`);

// PBXShellScriptBuildPhase: fetch ncnn before anything compiles
insertBefore('/* End PBXShellScriptBuildPhase section */',
`\t\t${P_FETCH} /* Fetch ncnn */ = {
\t\t\tisa = PBXShellScriptBuildPhase;
\t\t\talwaysOutOfDate = 1;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\tinputPaths = (
\t\t\t);
\t\t\tname = "Fetch ncnn";
\t\t\toutputPaths = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t\tshellPath = /bin/sh;
\t\t\tshellScript = "bash \\"$SRCROOT/../scripts/fetch_ncnn_ios.sh\\"";
\t\t};
`);

// Sources
replaceOnce(
`\t\t\t\t7884E8682EC3CC0700C636F2 /* SceneDelegate.swift in Sources */,
\t\t\t);`,
`\t\t\t\t7884E8682EC3CC0700C636F2 /* SceneDelegate.swift in Sources */,
\t\t\t\t${B_UPSCALE} /* UpscaleBridge.swift in Sources */,
\t\t\t\t${B_MEDIA} /* MediaBridge.swift in Sources */,
\t\t\t\t${B_ENGINE_MM} /* PhotoLiftEngine.mm in Sources */,
\t\t\t\t${B_CORE_CPP} /* photolift_core.cpp in Sources */,
\t\t\t);`);

// PBXVariantGroup for InfoPlist.strings
insertBefore('/* End PBXVariantGroup section */',
`\t\t${G_STRINGS} /* InfoPlist.strings */ = {
\t\t\tisa = PBXVariantGroup;
\t\t\tchildren = (
\t\t\t\t${F_STR_EN} /* en */,
\t\t\t\t${F_STR_ZH} /* zh-Hans */,
\t\t\t);
\t\t\tname = InfoPlist.strings;
\t\t\tsourceTree = "<group>";
\t\t};
`);

// Runner target build settings (Debug / Release / Profile)
const extra =
`\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++17";
\t\t\t\tFRAMEWORK_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"$(PROJECT_DIR)/Frameworks",
\t\t\t\t);
\t\t\t\tHEADER_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"$(PROJECT_DIR)/Frameworks/ncnn.framework/Headers",
\t\t\t\t\t"$(PROJECT_DIR)/Frameworks/ncnn.framework/Headers/ncnn",
\t\t\t\t\t"$(PROJECT_DIR)/../native",
\t\t\t\t);
`;
for (const cfg of ['249021D4217E4FDB00AE95B9', '97C147061CF9000F007C117D', '97C147071CF9000F007C117D']) {
  const anchor = `\t\t${cfg} /* `;
  const idx = s.indexOf(anchor);
  if (idx < 0) throw new Error('config missing: ' + cfg);
  const settingsIdx = s.indexOf('buildSettings = {\n', idx);
  const insertAt = settingsIdx + 'buildSettings = {\n'.length;
  s = s.slice(0, insertAt) + extra + s.slice(insertAt);
}

fs.writeFileSync(proj, s);
console.log('patched', proj);
