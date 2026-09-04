// Adds the CountdownWidget WidgetKit extension target to daycount's
// ios/Runner.xcodeproj/project.pbxproj. Idempotent: re-running on a project
// that already has the target is a no-op.
//
// No Xcode on this machine, so the project file is edited as text. Every
// object id is a fixed 24-hex string so the diff is reviewable.
const fs = require('fs');
const path = require('path');

const proj = path.join(__dirname, '..', 'apps', 'daycount', 'ios', 'Runner.xcodeproj', 'project.pbxproj');
let s = fs.readFileSync(proj, 'utf8');
if (s.includes('CountdownWidgetExtension')) {
  console.log('already present');
  process.exit(0);
}

const id = (n) => 'DC' + '0'.repeat(20) + n.toString(16).toUpperCase().padStart(2, '0');
const F_SWIFT = id(1), F_PLIST = id(2), F_ENT = id(3), F_RUNNER_ENT = id(4), F_APPEX = id(5), F_PRIVACY = id(21), B_PRIVACY = id(22);
const B_SWIFT = id(6), B_APPEX = id(7);
const G_WIDGET = id(8);
const T_WIDGET = id(9);
const P_SOURCES = id(10), P_FRAMEWORKS = id(11), P_RESOURCES = id(12), P_EMBED = id(13);
const PROXY = id(14), DEP = id(15);
const C_DEBUG = id(16), C_RELEASE = id(17), C_PROFILE = id(18), C_LIST = id(19);

const RUNNER_TARGET = '97C146ED1CF9000F007C117D';
const GENERATED_XCCONFIG = '9740EEB31CF90195004384FC';

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
`\t\t${B_SWIFT} /* CountdownWidget.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${F_SWIFT} /* CountdownWidget.swift */; };
\t\t${B_PRIVACY} /* PrivacyInfo.xcprivacy in Resources */ = {isa = PBXBuildFile; fileRef = ${F_PRIVACY} /* PrivacyInfo.xcprivacy */; };
\t\t${B_APPEX} /* CountdownWidgetExtension.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = ${F_APPEX} /* CountdownWidgetExtension.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
`);

// PBXContainerItemProxy
insertBefore('/* End PBXContainerItemProxy section */',
`\t\t${PROXY} /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = 97C146E61CF9000F007C117D /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = ${T_WIDGET};
\t\t\tremoteInfo = CountdownWidgetExtension;
\t\t};
`);

// PBXCopyFilesBuildPhase (Embed Foundation Extensions on Runner)
insertBefore('/* End PBXCopyFilesBuildPhase section */',
`\t\t${P_EMBED} /* Embed Foundation Extensions */ = {
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t${B_APPEX} /* CountdownWidgetExtension.appex in Embed Foundation Extensions */,
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
`);

// PBXFileReference
insertBefore('/* End PBXFileReference section */',
`\t\t${F_SWIFT} /* CountdownWidget.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CountdownWidget.swift; sourceTree = "<group>"; };
\t\t${F_PRIVACY} /* PrivacyInfo.xcprivacy */ = {isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; };
\t\t${F_PLIST} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
\t\t${F_ENT} /* CountdownWidget.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = CountdownWidget.entitlements; sourceTree = "<group>"; };
\t\t${F_RUNNER_ENT} /* Runner.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Runner.entitlements; sourceTree = "<group>"; };
\t\t${F_APPEX} /* CountdownWidgetExtension.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = CountdownWidgetExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; };
`);

// PBXFrameworksBuildPhase
insertBefore('/* End PBXFrameworksBuildPhase section */',
`\t\t${P_FRAMEWORKS} /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
`);

// PBXGroup: widget group + hook into main group, Products, Runner (entitlements)
insertBefore('/* End PBXGroup section */',
`\t\t${G_WIDGET} /* CountdownWidget */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t${F_SWIFT} /* CountdownWidget.swift */,
\t\t\t\t${F_PLIST} /* Info.plist */,
\t\t\t\t${F_ENT} /* CountdownWidget.entitlements */,
\t\t\t\t${F_PRIVACY} /* PrivacyInfo.xcprivacy */,
\t\t\t);
\t\t\tpath = CountdownWidget;
\t\t\tsourceTree = "<group>";
\t\t};
`);
replaceOnce(
`\t\t\t\t331C8082294A63A400263BE5 /* RunnerTests */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t};
\t\t97C146EF1CF9000F007C117D /* Products */ = {`,
`\t\t\t\t331C8082294A63A400263BE5 /* RunnerTests */,
\t\t\t\t${G_WIDGET} /* CountdownWidget */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t};
\t\t97C146EF1CF9000F007C117D /* Products */ = {`);
replaceOnce(
`\t\t\t\t331C8081294A63A400263BE5 /* RunnerTests.xctest */,
\t\t\t);
\t\t\tname = Products;`,
`\t\t\t\t331C8081294A63A400263BE5 /* RunnerTests.xctest */,
\t\t\t\t${F_APPEX} /* CountdownWidgetExtension.appex */,
\t\t\t);
\t\t\tname = Products;`);
replaceOnce(
`\t\t\t\t74858FAD1ED2DC5600515810 /* Runner-Bridging-Header.h */,
\t\t\t);
\t\t\tpath = Runner;`,
`\t\t\t\t74858FAD1ED2DC5600515810 /* Runner-Bridging-Header.h */,
\t\t\t\t${F_RUNNER_ENT} /* Runner.entitlements */,
\t\t\t);
\t\t\tpath = Runner;`);

// PBXNativeTarget: the extension, plus Runner gets the embed phase + dependency
insertBefore('/* End PBXNativeTarget section */',
`\t\t${T_WIDGET} /* CountdownWidgetExtension */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = ${C_LIST} /* Build configuration list for PBXNativeTarget "CountdownWidgetExtension" */;
\t\t\tbuildPhases = (
\t\t\t\t${P_SOURCES} /* Sources */,
\t\t\t\t${P_FRAMEWORKS} /* Frameworks */,
\t\t\t\t${P_RESOURCES} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = CountdownWidgetExtension;
\t\t\tproductName = CountdownWidgetExtension;
\t\t\tproductReference = ${F_APPEX} /* CountdownWidgetExtension.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t};
`);
replaceOnce(
`\t\t\t\t9705A1C41CF9048500538489 /* Embed Frameworks */,
\t\t\t\t3B06AD1E1E4923F5004D2608 /* Thin Binary */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = Runner;`,
`\t\t\t\t9705A1C41CF9048500538489 /* Embed Frameworks */,
\t\t\t\t${P_EMBED} /* Embed Foundation Extensions */,
\t\t\t\t3B06AD1E1E4923F5004D2608 /* Thin Binary */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t${DEP} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = Runner;`);

// PBXProject: target attributes + targets list
replaceOnce(
`\t\t\t\t\t97C146ED1CF9000F007C117D = {
\t\t\t\t\t\tCreatedOnToolsVersion = 7.3.1;
\t\t\t\t\t\tLastSwiftMigration = 1100;
\t\t\t\t\t};`,
`\t\t\t\t\t97C146ED1CF9000F007C117D = {
\t\t\t\t\t\tCreatedOnToolsVersion = 7.3.1;
\t\t\t\t\t\tLastSwiftMigration = 1100;
\t\t\t\t\t};
\t\t\t\t\t${T_WIDGET} = {
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t};`);
replaceOnce(
`\t\t\t\t331C8080294A63A400263BE5 /* RunnerTests */,
\t\t\t);
\t\t};
/* End PBXProject section */`,
`\t\t\t\t331C8080294A63A400263BE5 /* RunnerTests */,
\t\t\t\t${T_WIDGET} /* CountdownWidgetExtension */,
\t\t\t);
\t\t};
/* End PBXProject section */`);

// PBXResourcesBuildPhase
insertBefore('/* End PBXResourcesBuildPhase section */',
`\t\t${P_RESOURCES} /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t${B_PRIVACY} /* PrivacyInfo.xcprivacy in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
`);

// PBXSourcesBuildPhase
insertBefore('/* End PBXSourcesBuildPhase section */',
`\t\t${P_SOURCES} /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t${B_SWIFT} /* CountdownWidget.swift in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
`);

// PBXTargetDependency
insertBefore('/* End PBXTargetDependency section */',
`\t\t${DEP} /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = ${T_WIDGET} /* CountdownWidgetExtension */;
\t\t\ttargetProxy = ${PROXY} /* PBXContainerItemProxy */;
\t\t};
`);

// XCBuildConfiguration for the extension. Generated.xcconfig supplies
// FLUTTER_BUILD_NAME / FLUTTER_BUILD_NUMBER so the extension's version
// always equals the app's (App Store rejects a mismatch). It deliberately
// does NOT include Debug/Release.xcconfig: those pull in the CocoaPods
// xcconfig, which would try to link the Runner-only plugin frameworks.
function config(idc, name, extra) {
  return `\t\t${idc} /* ${name} */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = ${GENERATED_XCCONFIG} /* Generated.xcconfig */;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = CountdownWidget/CountdownWidget.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = CountdownWidget/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = "$(FLUTTER_BUILD_NAME)";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.noobclaw.daycount.CountdownWidget;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
${extra}\t\t\t};
\t\t\tname = ${name};
\t\t};
`;
}
insertBefore('/* End XCBuildConfiguration section */',
  config(C_DEBUG, 'Debug', '\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";\n') +
  config(C_RELEASE, 'Release', '') +
  config(C_PROFILE, 'Profile', ''));

// Runner: sign with the App Group entitlement in every configuration.
for (const cfg of ['249021D4217E4FDB00AE95B9', '97C147061CF9000F007C117D', '97C147071CF9000F007C117D']) {
  const anchor = `\t\t${cfg} /* `;
  const i = s.indexOf(anchor);
  if (i < 0) throw new Error('runner config missing ' + cfg);
  const j = s.indexOf('ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;', i);
  s = s.slice(0, j) + 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;' + s.slice(j + 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;'.length);
}

// XCConfigurationList
insertBefore('/* End XCConfigurationList section */',
`\t\t${C_LIST} /* Build configuration list for PBXNativeTarget "CountdownWidgetExtension" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t${C_DEBUG} /* Debug */,
\t\t\t\t${C_RELEASE} /* Release */,
\t\t\t\t${C_PROFILE} /* Profile */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
`);

fs.writeFileSync(proj, s);
console.log('widget target added');
