#!/usr/bin/env python3
"""
Generates a clean, ready-to-open `IslandPup.xcodeproj` (project.pbxproj + shared scheme)
matching `project.yml` so macOS users can open `IslandPup.xcodeproj` directly in Xcode
without needing to install XcodeGen first.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
XCODEPROJ = ROOT / "IslandPup.xcodeproj"


def oid(key: str) -> str:
    """Deterministic 24-char uppercase hex Xcode object ID."""
    return hashlib.sha1(f"islandpup-pbx:{key}".encode("utf-8")).hexdigest()[:24].upper()


def generate_pbxproj() -> str:
    shared_swift = [
        ("PetModels.swift", "Shared/Models/PetModels.swift"),
        ("PetActivityAttributes.swift", "Shared/Models/PetActivityAttributes.swift"),
        ("AnimatedPetSpriteView.swift", "Shared/Views/AnimatedPetSpriteView.swift"),
        ("SharedStorage.swift", "Shared/Sync/SharedStorage.swift"),
        ("PairSyncService.swift", "Shared/Sync/PairSyncService.swift"),
        ("PetLiveActivityIntents.swift", "Shared/Intents/PetLiveActivityIntents.swift"),
    ]
    shared_resources = [
        ("Assets.xcassets", "Shared/Assets.xcassets", "folder.assetcatalog"),
        ("PetTimerGate.ttf", "Shared/Resources/PetTimerGate.ttf", "file"),
    ]
    app_swift = [
        ("IslandPupApp.swift", "IslandPup/IslandPupApp.swift"),
        ("LiveActivityController.swift", "IslandPup/Controllers/LiveActivityController.swift"),
        ("ContentView.swift", "IslandPup/Views/ContentView.swift"),
        ("DynamicIslandPreviewBar.swift", "IslandPup/Views/DynamicIslandPreviewBar.swift"),
        ("PairSetupSheet.swift", "IslandPup/Views/PairSetupSheet.swift"),
    ]
    widget_swift = [
        ("IslandPupWidgetBundle.swift", "IslandPupWidget/IslandPupWidgetBundle.swift"),
        ("IslandPupLiveActivity.swift", "IslandPupWidget/IslandPupLiveActivity.swift"),
    ]
    config_files = [
        ("AppInfo.plist", "IslandPup/Info.plist", "text.plist.xml"),
        ("IslandPup.entitlements", "IslandPup/IslandPup.entitlements", "text.plist.entitlements"),
        ("WidgetInfo.plist", "IslandPupWidget/Info.plist", "text.plist.xml"),
        ("IslandPupWidget.entitlements", "IslandPupWidget/IslandPupWidget.entitlements", "text.plist.entitlements"),
    ]

    app_product_id = oid("product:IslandPup.app")
    widget_product_id = oid("product:IslandPupWidgetExtension.appex")

    build_files: list[str] = []
    file_refs: list[str] = []

    app_source_bf_ids: list[str] = []
    widget_source_bf_ids: list[str] = []
    app_res_bf_ids: list[str] = []
    widget_res_bf_ids: list[str] = []

    all_file_ref_ids_shared: list[str] = []
    all_file_ref_ids_app: list[str] = []
    all_file_ref_ids_widget: list[str] = []

    for name, rel_path in shared_swift:
        fref = oid(f"fileref:{rel_path}")
        all_file_ref_ids_shared.append(fref)
        file_refs.append(
            f'\t\t{fref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "{name}"; path = "{rel_path}"; sourceTree = "<group>"; }};'
        )
        bf_app = oid(f"bf:app:{rel_path}")
        bf_wid = oid(f"bf:wid:{rel_path}")
        app_source_bf_ids.append(bf_app)
        widget_source_bf_ids.append(bf_wid)
        build_files.append(f"\t\t{bf_app} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};")
        build_files.append(f"\t\t{bf_wid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};")

    for name, rel_path, ftype in shared_resources:
        fref = oid(f"fileref:{rel_path}")
        all_file_ref_ids_shared.append(fref)
        file_refs.append(
            f'\t\t{fref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; name = "{name}"; path = "{rel_path}"; sourceTree = "<group>"; }};'
        )
        bf_app = oid(f"bf:app:res:{rel_path}")
        bf_wid = oid(f"bf:wid:res:{rel_path}")
        app_res_bf_ids.append(bf_app)
        widget_res_bf_ids.append(bf_wid)
        build_files.append(f"\t\t{bf_app} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};")
        build_files.append(f"\t\t{bf_wid} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};")

    for name, rel_path in app_swift:
        fref = oid(f"fileref:{rel_path}")
        all_file_ref_ids_app.append(fref)
        file_refs.append(
            f'\t\t{fref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "{name}"; path = "{rel_path}"; sourceTree = "<group>"; }};'
        )
        bf_app = oid(f"bf:app:{rel_path}")
        app_source_bf_ids.append(bf_app)
        build_files.append(f"\t\t{bf_app} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};")

    for name, rel_path in widget_swift:
        fref = oid(f"fileref:{rel_path}")
        all_file_ref_ids_widget.append(fref)
        file_refs.append(
            f'\t\t{fref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "{name}"; path = "{rel_path}"; sourceTree = "<group>"; }};'
        )
        bf_wid = oid(f"bf:wid:{rel_path}")
        widget_source_bf_ids.append(bf_wid)
        build_files.append(f"\t\t{bf_wid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};")

    for label, rel_path, ftype in config_files:
        fref = oid(f"fileref:{rel_path}")
        if rel_path.startswith("IslandPup/"):
            all_file_ref_ids_app.append(fref)
        else:
            all_file_ref_ids_widget.append(fref)
        fname = Path(rel_path).name
        file_refs.append(
            f'\t\t{fref} /* {label} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; name = "{fname}"; path = "{rel_path}"; sourceTree = "<group>"; }};'
        )

    file_refs.append(
        f'\t\t{app_product_id} /* IslandPup.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = IslandPup.app; sourceTree = BUILT_PRODUCTS_DIR; }};'
    )
    file_refs.append(
        f'\t\t{widget_product_id} /* IslandPupWidgetExtension.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = IslandPupWidgetExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};'
    )

    embed_bf_id = oid("bf:embed:widget")
    build_files.append(
        f"\t\t{embed_bf_id} /* IslandPupWidgetExtension.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {widget_product_id} /* IslandPupWidgetExtension.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )

    # Groups
    main_group = oid("group:main")
    shared_group = oid("group:shared")
    app_group = oid("group:app")
    widget_group = oid("group:widget")
    products_group = oid("group:products")

    # Targets & Phases
    app_target = oid("target:IslandPup")
    widget_target = oid("target:IslandPupWidgetExtension")
    project_obj = oid("project:IslandPup")

    app_sources_phase = oid("phase:app:sources")
    app_frameworks_phase = oid("phase:app:frameworks")
    app_resources_phase = oid("phase:app:resources")
    app_embed_phase = oid("phase:app:embed")

    wid_sources_phase = oid("phase:wid:sources")
    wid_frameworks_phase = oid("phase:wid:frameworks")
    wid_resources_phase = oid("phase:wid:resources")

    target_dep = oid("dep:widget")
    proxy_id = oid("proxy:widget")

    # Configurations
    proj_cfg_list = oid("cfglist:proj")
    app_cfg_list = oid("cfglist:app")
    wid_cfg_list = oid("cfglist:wid")

    proj_debug = oid("cfg:proj:debug")
    proj_release = oid("cfg:proj:release")
    app_debug = oid("cfg:app:debug")
    app_release = oid("cfg:app:release")
    wid_debug = oid("cfg:wid:debug")
    wid_release = oid("cfg:wid:release")

    def fmt_list(items: list[str]) -> str:
        return "\n".join(f"\t\t\t\t{i}," for i in items)

    return f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{proxy_id} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {project_obj} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {widget_target};
			remoteInfo = IslandPupWidgetExtension;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		{app_embed_phase} /* Embed Foundation Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{embed_bf_id} /* IslandPupWidgetExtension.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
{chr(10).join(file_refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{app_frameworks_phase} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{wid_frameworks_phase} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{main_group} = {{
			isa = PBXGroup;
			children = (
				{shared_group} /* Shared */,
				{app_group} /* IslandPup */,
				{widget_group} /* IslandPupWidget */,
				{products_group} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{shared_group} /* Shared */ = {{
			isa = PBXGroup;
			children = (
{fmt_list(all_file_ref_ids_shared)}
			);
			name = Shared;
			sourceTree = "<group>";
		}};
		{app_group} /* IslandPup */ = {{
			isa = PBXGroup;
			children = (
{fmt_list(all_file_ref_ids_app)}
			);
			name = IslandPup;
			sourceTree = "<group>";
		}};
		{widget_group} /* IslandPupWidget */ = {{
			isa = PBXGroup;
			children = (
{fmt_list(all_file_ref_ids_widget)}
			);
			name = IslandPupWidget;
			sourceTree = "<group>";
		}};
		{products_group} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{app_product_id} /* IslandPup.app */,
				{widget_product_id} /* IslandPupWidgetExtension.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{app_target} /* IslandPup */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {app_cfg_list} /* Build configuration list for PBXNativeTarget "IslandPup" */;
			buildPhases = (
				{app_sources_phase} /* Sources */,
				{app_frameworks_phase} /* Frameworks */,
				{app_resources_phase} /* Resources */,
				{app_embed_phase} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				{target_dep} /* PBXTargetDependency */,
			);
			name = IslandPup;
			productName = IslandPup;
			productReference = {app_product_id} /* IslandPup.app */;
			productType = "com.apple.product-type.application";
		}};
		{widget_target} /* IslandPupWidgetExtension */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {wid_cfg_list} /* Build configuration list for PBXNativeTarget "IslandPupWidgetExtension" */;
			buildPhases = (
				{wid_sources_phase} /* Sources */,
				{wid_frameworks_phase} /* Frameworks */,
				{wid_resources_phase} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = IslandPupWidgetExtension;
			productName = IslandPupWidgetExtension;
			productReference = {widget_product_id} /* IslandPupWidgetExtension.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{project_obj} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{app_target} = {{
						CreatedOnToolsVersion = 16.0;
					}};
					{widget_target} = {{
						CreatedOnToolsVersion = 16.0;
					}};
				}};
			}};
			buildConfigurationList = {proj_cfg_list} /* Build configuration list for PBXProject "IslandPup" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {main_group};
			productRefGroup = {products_group} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{app_target} /* IslandPup */,
				{widget_target} /* IslandPupWidgetExtension */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{app_resources_phase} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{fmt_list(app_res_bf_ids)}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{wid_resources_phase} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{fmt_list(widget_res_bf_ids)}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{app_sources_phase} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{fmt_list(app_source_bf_ids)}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{wid_sources_phase} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{fmt_list(widget_source_bf_ids)}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{target_dep} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {widget_target} /* IslandPupWidgetExtension */;
			targetProxy = {proxy_id} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		{proj_debug} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				CURRENT_PROJECT_VERSION = 1;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MARKETING_VERSION = 1.0.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			}};
			name = Debug;
		}};
		{proj_release} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				CURRENT_PROJECT_VERSION = 1;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MARKETING_VERSION = 1.0.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{app_debug} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = IslandPup/IslandPup.entitlements;
				CODE_SIGN_STYLE = Automatic;
				INFOPLIST_FILE = IslandPup/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = com.islandpup.app;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTS_MACCATALYST = NO;
				TARGETED_DEVICE_FAMILY = 1;
			}};
			name = Debug;
		}};
		{app_release} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = IslandPup/IslandPup.entitlements;
				CODE_SIGN_STYLE = Automatic;
				INFOPLIST_FILE = IslandPup/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = com.islandpup.app;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTS_MACCATALYST = NO;
				TARGETED_DEVICE_FAMILY = 1;
			}};
			name = Release;
		}};
		{wid_debug} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_ENTITLEMENTS = IslandPupWidget/IslandPupWidget.entitlements;
				CODE_SIGN_STYLE = Automatic;
				INFOPLIST_FILE = IslandPupWidget/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = com.islandpup.app.widget;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				TARGETED_DEVICE_FAMILY = 1;
			}};
			name = Debug;
		}};
		{wid_release} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_ENTITLEMENTS = IslandPupWidget/IslandPupWidget.entitlements;
				CODE_SIGN_STYLE = Automatic;
				INFOPLIST_FILE = IslandPupWidget/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = com.islandpup.app.widget;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				TARGETED_DEVICE_FAMILY = 1;
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{proj_cfg_list} /* Build configuration list for PBXProject "IslandPup" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{proj_debug} /* Debug */,
				{proj_release} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{app_cfg_list} /* Build configuration list for PBXNativeTarget "IslandPup" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{app_debug} /* Debug */,
				{app_release} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{wid_cfg_list} /* Build configuration list for PBXNativeTarget "IslandPupWidgetExtension" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{wid_debug} /* Debug */,
				{wid_release} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {project_obj} /* Project object */;
}}
"""


def generate_scheme() -> str:
    app_target = oid("target:IslandPup")
    wid_target = oid("target:IslandPupWidgetExtension")
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{wid_target}"
               BuildableName = "IslandPupWidgetExtension.appex"
               BlueprintName = "IslandPupWidgetExtension"
               ReferencedContainer = "container:IslandPup.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "IslandPup.app"
               BlueprintName = "IslandPup"
               ReferencedContainer = "container:IslandPup.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "IslandPup.app"
            BlueprintName = "IslandPup"
            ReferencedContainer = "container:IslandPup.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


if __name__ == "__main__":
    XCODEPROJ.mkdir(parents=True, exist_ok=True)
    pbx_path = XCODEPROJ / "project.pbxproj"
    pbx_path.write_text(generate_pbxproj(), encoding="utf-8")

    schemes_dir = XCODEPROJ / "xcshareddata" / "xcschemes"
    schemes_dir.mkdir(parents=True, exist_ok=True)
    (schemes_dir / "IslandPup.xcscheme").write_text(generate_scheme(), encoding="utf-8")
    print(f"[OK] Generated {pbx_path} and shared IslandPup.xcscheme")
