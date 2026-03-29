#!/usr/bin/env python3
"""
Generates a complete Xcode project (Cache Out.xcodeproj) for the Cache Out macOS app.
Includes a CacheOutTests unit-test target that @testable-imports the app module.
Run from the repo root: python3 generate_xcodeproj.py
"""
import os, hashlib

ROOT = "/Users/apoorv/Documents/GitHub/Cache Out"
PROJ_NAME = "Cache Out"
TARGET_NAME = "Cache Out"
BUNDLE_ID = "com.cacheout.CacheOut"
SOURCES_DIR = "CacheOut"
TEST_SOURCES_DIR = "CacheOutTests"
MACOS_VERSION = "26.0"
SWIFT_VERSION = "6.0"

# ── Deterministic fake UUIDs (24 hex chars, Xcode style) ─────────────────────
def pid(seed: str) -> str:
    return hashlib.md5(seed.encode()).hexdigest()[:24].upper()

# ── Collect app swift files ───────────────────────────────────────────────────
swift_files = []
for dirpath, _, filenames in os.walk(os.path.join(ROOT, SOURCES_DIR)):
    for f in sorted(filenames):
        if f.endswith(".swift"):
            full = os.path.join(dirpath, f)
            rel  = os.path.relpath(full, ROOT)
            swift_files.append((f, rel))
swift_files.sort(key=lambda x: x[1])

# ── Collect test swift files ──────────────────────────────────────────────────
test_files = []
test_dir = os.path.join(ROOT, TEST_SOURCES_DIR)
if os.path.isdir(test_dir):
    for dirpath, _, filenames in os.walk(test_dir):
        for f in sorted(filenames):
            if f.endswith(".swift"):
                full = os.path.join(dirpath, f)
                rel  = os.path.relpath(full, ROOT)
                test_files.append((f, rel))
test_files.sort(key=lambda x: x[1])

# ── Asset catalog ─────────────────────────────────────────────────────────────
ASSETS_REF_UUID = pid("ASSETS_XCASSETS_REF")
ASSETS_BLD_UUID = pid("ASSETS_XCASSETS_BLD")
ASSETS_REL      = "CacheOut/Assets.xcassets"

MOLE_SRC_REF_UUID = pid("MOLE_SRC_FOLDER_REF")
MOLE_SRC_BLD_UUID = pid("MOLE_SRC_FOLDER_BLD")
MOLE_SRC_REL      = "CacheOut/Resources/mole-src"

PRIVACY_REF_UUID = pid("PRIVACY_XCPRIVACY_REF")
PRIVACY_BLD_UUID = pid("PRIVACY_XCPRIVACY_BLD")
PRIVACY_REL      = "CacheOut/PrivacyInfo.xcprivacy"

ENTITLEMENTS_REF_UUID = pid("ENTITLEMENTS_REF")
ENTITLEMENTS_REL      = "CacheOut/CacheOut.entitlements"

# ── Project-level UUIDs ───────────────────────────────────────────────────────
PROJECT_UUID        = pid("PROJECT")
TARGET_UUID         = pid("TARGET")
BUILD_CONF_LIST_PRJ = pid("BUILD_CONF_LIST_PRJ")
BUILD_CONF_LIST_TGT = pid("BUILD_CONF_LIST_TGT")
DEBUG_PRJ_UUID      = pid("DEBUG_PRJ")
RELEASE_PRJ_UUID    = pid("RELEASE_PRJ")
DEBUG_TGT_UUID      = pid("DEBUG_TGT")
RELEASE_TGT_UUID    = pid("RELEASE_TGT")
SOURCES_PHASE_UUID  = pid("SOURCES_PHASE")
FWKS_PHASE_UUID     = pid("FWKS_PHASE")
RESOURCES_PHASE_UUID= pid("RESOURCES_PHASE")
MAIN_GROUP_UUID     = pid("MAIN_GROUP")
PRODUCTS_GROUP_UUID = pid("PRODUCTS_GROUP")
APP_PRODUCT_UUID    = pid("APP_PRODUCT")

IOKit_UUID     = pid("IOKit_REF")
IOKit_BLD_UUID = pid("IOKit_BLD")
SM_UUID        = pid("ServiceManagement_REF")
SM_BLD_UUID    = pid("ServiceManagement_BLD")

# ── Test-target UUIDs ─────────────────────────────────────────────────────────
TEST_TARGET_UUID         = pid("TEST_TARGET")
TEST_BUNDLE_UUID         = pid("TEST_BUNDLE_PRODUCT")
TEST_BUILD_CONF_LIST     = pid("TEST_BUILD_CONF_LIST")
TEST_DEBUG_UUID          = pid("TEST_DEBUG_CFG")
TEST_RELEASE_UUID        = pid("TEST_RELEASE_CFG")
TEST_SOURCES_PHASE_UUID  = pid("TEST_SOURCES_PHASE")
TEST_FWKS_PHASE_UUID     = pid("TEST_FWKS_PHASE")
TEST_GROUP_UUID          = pid("TEST_GROUP")
XCTEST_REF_UUID          = pid("XCTEST_REF")
XCTEST_BLD_UUID          = pid("XCTEST_BLD")
# Dependency: test target depends on app target
TEST_DEPENDENCY_UUID     = pid("TEST_DEPENDENCY")
TEST_CONTAINER_UUID      = pid("TEST_CONTAINER")

# Per-file UUIDs
file_ref_uuids   = {rel: pid("REF_"+rel)   for _, rel in swift_files}
build_file_uuids = {rel: pid("BLD_"+rel)   for _, rel in swift_files}
test_ref_uuids   = {rel: pid("TREF_"+rel)  for _, rel in test_files}
test_bld_uuids   = {rel: pid("TBLD_"+rel)  for _, rel in test_files}

# Group UUIDs
groups = {}
for _, rel in swift_files:
    parts = rel.split(os.sep)
    for i in range(1, len(parts)):
        grp_path = os.sep.join(parts[:i])
        if grp_path not in groups:
            groups[grp_path] = pid("GRP_"+grp_path)

# ── Section builder helpers ───────────────────────────────────────────────────
def pbx_file_refs():
    lines = []
    for name, rel in swift_files:
        uid = file_ref_uuids[rel]
        lines.append(f'\t\t{uid} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {name}; path = "{rel}"; sourceTree = "<group>"; }};')
    for name, rel in test_files:
        uid = test_ref_uuids[rel]
        lines.append(f'\t\t{uid} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {name}; path = "{rel}"; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{APP_PRODUCT_UUID} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "{TARGET_NAME}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')
    lines.append(f'\t\t{TEST_BUNDLE_UUID} = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = CacheOutTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')
    lines.append(f'\t\t{IOKit_UUID} = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = IOKit.framework; path = System/Library/Frameworks/IOKit.framework; sourceTree = SDKROOT; }};')
    lines.append(f'\t\t{SM_UUID} = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = ServiceManagement.framework; path = System/Library/Frameworks/ServiceManagement.framework; sourceTree = SDKROOT; }};')
    lines.append(f'\t\t{XCTEST_REF_UUID} = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = XCTest.framework; path = Library/Xcode/Products/Library/Frameworks/XCTest.framework; sourceTree = DEVELOPER_DIR; }};')
    lines.append(f'\t\t{ASSETS_REF_UUID} = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; name = "Assets.xcassets"; path = "{ASSETS_REL}"; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{MOLE_SRC_REF_UUID} = {{isa = PBXFileReference; lastKnownFileType = folder; name = "mole-src"; path = "{MOLE_SRC_REL}"; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{PRIVACY_REF_UUID} = {{isa = PBXFileReference; lastKnownFileType = text.xml; name = "PrivacyInfo.xcprivacy"; path = "{PRIVACY_REL}"; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{ENTITLEMENTS_REF_UUID} = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; name = "CacheOut.entitlements"; path = "{ENTITLEMENTS_REL}"; sourceTree = "<group>"; }};')
    return "\n".join(lines)

def pbx_build_files():
    lines = []
    for _, rel in swift_files:
        lines.append(f'\t\t{build_file_uuids[rel]} = {{isa = PBXBuildFile; fileRef = {file_ref_uuids[rel]}; }};')
    for _, rel in test_files:
        lines.append(f'\t\t{test_bld_uuids[rel]} = {{isa = PBXBuildFile; fileRef = {test_ref_uuids[rel]}; }};')
    lines.append(f'\t\t{IOKit_BLD_UUID} = {{isa = PBXBuildFile; fileRef = {IOKit_UUID}; }};')
    lines.append(f'\t\t{SM_BLD_UUID} = {{isa = PBXBuildFile; fileRef = {SM_UUID}; }};')
    lines.append(f'\t\t{XCTEST_BLD_UUID} = {{isa = PBXBuildFile; fileRef = {XCTEST_REF_UUID}; }};')
    lines.append(f'\t\t{ASSETS_BLD_UUID} = {{isa = PBXBuildFile; fileRef = {ASSETS_REF_UUID}; }};')
    lines.append(f'\t\t{MOLE_SRC_BLD_UUID} = {{isa = PBXBuildFile; fileRef = {MOLE_SRC_REF_UUID}; }};')
    lines.append(f'\t\t{PRIVACY_BLD_UUID} = {{isa = PBXBuildFile; fileRef = {PRIVACY_REF_UUID}; }};')
    return "\n".join(lines)

def app_sources_files():
    return "\n".join(f'\t\t\t\t{build_file_uuids[rel]},' for _, rel in swift_files)

def test_sources_files():
    return "\n".join(f'\t\t\t\t{test_bld_uuids[rel]},' for _, rel in test_files)

def build_group_tree():
    children_map = {}
    for grp_path in sorted(groups.keys()):
        parent = os.path.dirname(grp_path)
        if parent not in children_map:
            children_map[parent] = []
        children_map[parent].append((groups[grp_path], os.path.basename(grp_path)))
    for name, rel in swift_files:
        parent_dir = os.path.dirname(rel)
        if parent_dir not in children_map:
            children_map[parent_dir] = []
        children_map[parent_dir].append((file_ref_uuids[rel], name))

    lines = []
    main_children = children_map.get("", [])
    main_uuids = "\n".join(f'\t\t\t\t{u},' for u, _ in main_children)
    lines.append(f"""\t\t{MAIN_GROUP_UUID} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{main_uuids}
\t\t\t\t{ENTITLEMENTS_REF_UUID},
\t\t\t\t{TEST_GROUP_UUID},
\t\t\t\t{PRODUCTS_GROUP_UUID},
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};""")

    lines.append(f"""\t\t{PRODUCTS_GROUP_UUID} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{APP_PRODUCT_UUID},
\t\t\t\t{TEST_BUNDLE_UUID},
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};""")

    test_kids = "\n".join(f'\t\t\t\t{test_ref_uuids[rel]},' for _, rel in test_files)
    lines.append(f"""\t\t{TEST_GROUP_UUID} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{test_kids}
\t\t\t);
\t\t\tname = CacheOutTests;
\t\t\tsourceTree = "<group>";
\t\t}};""")

    for grp_path in sorted(groups.keys()):
        uid = groups[grp_path]
        name = os.path.basename(grp_path)
        kids = children_map.get(grp_path, [])
        kids_str = "\n".join(f'\t\t\t\t{u},' for u, _ in kids)
        lines.append(f"""\t\t{uid} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{kids_str}
\t\t\t);
\t\t\tname = {name};
\t\t\tsourceTree = "<group>";
\t\t}};""")
    return "\n".join(lines)


# ── Build configuration settings ─────────────────────────────────────────────
COMMON_SETTINGS = f"""
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = {MACOS_VERSION};
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};"""

TARGET_SETTINGS = f"""
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "CacheOut/CacheOut.entitlements";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tINFOPLIST_FILE = "CacheOut/Info.plist";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = {MACOS_VERSION};
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "{BUNDLE_ID}";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};"""

TEST_SETTINGS = f"""
\t\t\t\tBUNDLE_LOADER = "$(BUILT_PRODUCTS_DIR)/Cache Out.app/Contents/MacOS/Cache Out";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = {MACOS_VERSION};
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.cacheout.CacheOutTests";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};
\t\t\t\tTEST_HOST = "$(BUNDLE_LOADER)";"""


# ── PBXContainerItemProxy (test depends on app) ───────────────────────────────
CONTAINER_PROXY = f"""\t\t{TEST_CONTAINER_UUID} = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {PROJECT_UUID};
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {TARGET_UUID};
\t\t\tremoteInfo = "{TARGET_NAME}";
\t\t}};"""

TARGET_DEPENDENCY = f"""\t\t{TEST_DEPENDENCY_UUID} = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {TARGET_UUID};
\t\t\ttargetProxy = {TEST_CONTAINER_UUID};
\t\t}};"""

# ── Assemble pbxproj ──────────────────────────────────────────────────────────
pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXBuildFile section */
{pbx_build_files()}
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
{CONTAINER_PROXY}
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
{pbx_file_refs()}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{FWKS_PHASE_UUID} = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{IOKit_BLD_UUID},
\t\t\t\t{SM_BLD_UUID},
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{TEST_FWKS_PHASE_UUID} = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{XCTEST_BLD_UUID},
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{build_group_tree()}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{TARGET_UUID} = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {BUILD_CONF_LIST_TGT};
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES_PHASE_UUID},
\t\t\t\t{FWKS_PHASE_UUID},
\t\t\t\t{RESOURCES_PHASE_UUID},
\t\t\t);
\t\t\tbuildRules = ();
\t\t\tdependencies = ();
\t\t\tname = "{TARGET_NAME}";
\t\t\tpackageProductDependencies = ();
\t\t\tproductName = "{TARGET_NAME}";
\t\t\tproductReference = {APP_PRODUCT_UUID};
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{TEST_TARGET_UUID} = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {TEST_BUILD_CONF_LIST};
\t\t\tbuildPhases = (
\t\t\t\t{TEST_SOURCES_PHASE_UUID},
\t\t\t\t{TEST_FWKS_PHASE_UUID},
\t\t\t);
\t\t\tbuildRules = ();
\t\t\tdependencies = (
\t\t\t\t{TEST_DEPENDENCY_UUID},
\t\t\t);
\t\t\tname = CacheOutTests;
\t\t\tproductName = CacheOutTests;
\t\t\tproductReference = {TEST_BUNDLE_UUID};
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t}};
/* End PBXNativeTarget section */
"""

pbxproj += f"""
/* Begin PBXProject section */
\t\t{PROJECT_UUID} = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{TARGET_UUID} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t\t{TEST_TARGET_UUID} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t\tTestTargetID = {TARGET_UUID};
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {BUILD_CONF_LIST_PRJ};
\t\t\tcompatibilityVersion = "Xcode 15.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (en, Base);
\t\t\tmainGroup = {MAIN_GROUP_UUID};
\t\t\tminimumXcodeVersion = 16.0;
\t\t\tproductRefGroup = {PRODUCTS_GROUP_UUID};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{TARGET_UUID},
\t\t\t\t{TEST_TARGET_UUID},
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{RESOURCES_PHASE_UUID} = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{ASSETS_BLD_UUID},
\t\t\t\t{MOLE_SRC_BLD_UUID},
\t\t\t\t{PRIVACY_BLD_UUID},
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{SOURCES_PHASE_UUID} = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{app_sources_files()}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{TEST_SOURCES_PHASE_UUID} = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{test_sources_files()}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
{TARGET_DEPENDENCY}
/* End PBXTargetDependency section */
"""

pbxproj += f"""
/* Begin XCBuildConfiguration section */
\t\t{DEBUG_PRJ_UUID} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{COMMON_SETTINGS}
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{RELEASE_PRJ_UUID} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = {MACOS_VERSION};
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tSWIFT_VERSION = {SWIFT_VERSION};
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{DEBUG_TGT_UUID} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{TARGET_SETTINGS}
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{RELEASE_TGT_UUID} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{TARGET_SETTINGS}
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{TEST_DEBUG_UUID} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{TEST_SETTINGS}
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{TEST_RELEASE_UUID} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{TEST_SETTINGS}
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{BUILD_CONF_LIST_PRJ} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = ({DEBUG_PRJ_UUID}, {RELEASE_PRJ_UUID});
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{BUILD_CONF_LIST_TGT} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = ({DEBUG_TGT_UUID}, {RELEASE_TGT_UUID});
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{TEST_BUILD_CONF_LIST} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = ({TEST_DEBUG_UUID}, {TEST_RELEASE_UUID});
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {PROJECT_UUID};
}}
"""


# ── Write project.pbxproj ─────────────────────────────────────────────────────
proj_dir     = os.path.join(ROOT, f"{PROJ_NAME}.xcodeproj")
os.makedirs(proj_dir, exist_ok=True)
pbxproj_path = os.path.join(proj_dir, "project.pbxproj")
with open(pbxproj_path, "w") as f:
    f.write(pbxproj)

print(f"✅  Written:   {pbxproj_path}")
print(f"    App files: {len(swift_files)} Swift sources")
print(f"    Test files:{len(test_files)} Swift sources ({[name for name, _ in test_files]})")
print(f"    Groups:    {list(groups.keys())[:6]} …")
print()
print("Next steps:")
print("  1. Open 'Cache Out.xcodeproj' in Xcode — SPM will re-resolve Sparkle automatically.")
print("  2. Select scheme 'CacheOutTests' and press ⌘U to run all tests.")
print("  3. Product → Clean Build Folder (⌘⇧K) if you see stale DerivedData errors.")
