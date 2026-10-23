#!/usr/bin/env python3
"""Generate ios/MelonThump.xcodeproj/project.pbxproj.

WARNING (2026-10-22): STALE — the live project has diverged from this
script (it also builds LocalAnalyzer.swift / VersionGate.swift /
AdsManager.swift / CreditWallet.swift, signs with the paid team, links
the GoogleMobileAds + GoogleUserMessagingPlatform SPM packages, and
uses Config.xcconfig as the target base configuration). Do NOT
regenerate without reconciling the script first, or the build breaks.

Modeled on the Retax.xcodeproj template (objectVersion 56, Swift 6,
SDKROOT=iphoneos, iOS 17 deployment target). Uses a hand-written Info.plist
(INFOPLIST_FILE) instead of a generated one so we can ship the microphone
usage description and the local-networking ATS exception.
"""
import os
import random
import sys

APP_NAME = "MelonThump"
BUNDLE_ID = "dev.xuyang.melonthump"
GROUP_PATH = "MelonThump"
SWIFT_FILES = [
    "MelonThumpApp.swift",
    "Models.swift",
    "APIClient.swift",
    "AudioRecorder.swift",
    "TapView.swift",
]
PLIST_FILE = "Info.plist"
ASSETS_FILE = "Assets.xcassets"


def uid() -> str:
    return "".join(random.choice("0123456789ABCDEF") for _ in range(24))


def main() -> None:
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "MelonThump.xcodeproj")
    os.makedirs(out_dir, exist_ok=True)

    ids = {name: uid() for name in SWIFT_FILES}
    plist_id = uid()
    assets_id = uid()
    assets_build_id = uid()
    app_ref = uid()
    build_ids = {name: uid() for name in SWIFT_FILES}
    main_group, products_group, app_group = uid(), uid(), uid()
    target = uid()
    frameworks_phase, resources_phase, sources_phase = uid(), uid(), uid()
    project = uid()
    proj_debug, proj_release = uid(), uid()
    tgt_debug, tgt_release = uid(), uid()
    proj_cfg_list, tgt_cfg_list = uid(), uid()

    build_files = "\n".join(
        f"\t\t{build_ids[n]} /* {n} in Sources */ = {{isa = PBXBuildFile; "
        f"fileRef = {ids[n]} /* {n} */; }};"
        for n in SWIFT_FILES
    )
    file_refs = "\n".join(
        f"\t\t{ids[n]} /* {n} */ = {{isa = PBXFileReference; "
        f'lastKnownFileType = sourcecode.swift; path = {n}; sourceTree = "<group>"; }};'
        for n in SWIFT_FILES
    )
    group_children = "\n".join(
        f"\t\t\t\t{ids[n]} /* {n} */," for n in SWIFT_FILES
    )
    sources_files = "\n".join(
        f"\t\t\t\t{build_ids[n]} /* {n} in Sources */," for n in SWIFT_FILES
    )

    def target_settings(name: str) -> str:
        return f"""\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;\n\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tINFOPLIST_FILE = {GROUP_PATH}/{PLIST_FILE};
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";"""

    pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{
/* Begin PBXBuildFile section */
{build_files}
\t\t{assets_build_id} /* {ASSETS_FILE} in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_id} /* {ASSETS_FILE} */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{file_refs}
\t\t{plist_id} /* {PLIST_FILE} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {PLIST_FILE}; sourceTree = "<group>"; }};
\t\t{assets_id} /* {ASSETS_FILE} */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {ASSETS_FILE}; sourceTree = "<group>"; }};
\t\t{app_ref} /* {APP_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{main_group} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{app_group} /* {APP_NAME} */,
\t\t\t\t{products_group} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{products_group} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{app_ref} /* {APP_NAME}.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{app_group} /* {APP_NAME} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{group_children}
\t\t\t\t{assets_id} /* {ASSETS_FILE} */,
\t\t\t\t{plist_id} /* {PLIST_FILE} */,
\t\t\t);
\t\t\tpath = {GROUP_PATH};
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target} /* {APP_NAME} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {tgt_cfg_list} /* Build configuration list for PBXNativeTarget "{APP_NAME}" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase} /* Sources */,
\t\t\t\t{frameworks_phase} /* Frameworks */,
\t\t\t\t{resources_phase} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = {APP_NAME};
\t\t\tpackageProductDependencies = (
\t\t\t);
\t\t\tproductName = {APP_NAME};
\t\t\tproductReference = {app_ref} /* {APP_NAME}.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t}};
\t\t\tbuildConfigurationList = {proj_cfg_list} /* Build configuration list for PBXProject "{APP_NAME}" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group};
\t\t\tproductRefGroup = {products_group} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target} /* {APP_NAME} */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{assets_build_id} /* {ASSETS_FILE} in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{sources_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{proj_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{proj_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = s;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{tgt_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{target_settings("Debug")}
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{tgt_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{target_settings("Release")}
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{proj_cfg_list} /* Build configuration list for PBXProject "{APP_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{proj_debug} /* Debug */,
\t\t\t\t{proj_release} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{tgt_cfg_list} /* Build configuration list for PBXNativeTarget "{APP_NAME}" */ = {{
\t\t\t\tisa = XCConfigurationList;
\t\t\t\tbuildConfigurations = (
\t\t\t\t{tgt_debug} /* Debug */,
\t\t\t\t{tgt_release} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

\t}};
\trootObject = {project} /* Project object */;
}}
"""

    with open(os.path.join(out_dir, "project.pbxproj"), "w") as f:
        f.write(pbxproj)
    print(f"wrote {out_dir}/project.pbxproj")


if __name__ == "__main__":
    main()
