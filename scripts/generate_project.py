#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parent.parent

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def quote(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'

objects = []
def obj(key, value):
    objects.append(f'{uid(key)} = {{ {value} }};')

sources = sorted((root / 'StudyApp').rglob('*.swift'))
refs, builds = [], []
for file in sources:
    rel = str(file.relative_to(root))
    obj(rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(rel)}; sourceTree = SOURCE_ROOT;')
    obj('build:' + rel, f'isa = PBXBuildFile; fileRef = {uid(rel)};')
    refs.append(uid(rel)); builds.append(uid('build:' + rel))
for rel, kind in [('StudyApp/Configuration/Config.xcconfig', 'text.xcconfig'), ('StudyApp/Configuration/Info.plist', 'text.plist.xml')]:
    obj(rel, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(rel)}; sourceTree = SOURCE_ROOT;')
    refs.append(uid(rel))
obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = StudyApp.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('main', f'isa = PBXGroup; children = ({",".join(refs + [uid("products")])}); sourceTree = "<group>";')
obj('products', f'isa = PBXGroup; name = Products; children = ({uid("product")}); sourceTree = "<group>";')
obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)}); runOnlyForDeploymentPostprocessing = 0;')
obj('resources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("target-configs")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")}); buildRules = (); dependencies = (); name = StudyApp; productName = StudyApp; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2620; }}; buildConfigurationList = {uid("project-configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = de; hasScannedForEncodings = 0; knownRegions = (de,en,Base); mainGroup = {uid("main")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")});')
for kind in ['project', 'target']:
    config_ids = []
    for mode in ['Debug', 'Release']:
        key = f'{kind}-{mode}'
        config_ids.append(uid(key))
        settings = {
            'CLANG_ENABLE_MODULES': 'YES', 'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0',
            'SWIFT_VERSION': '5.0', 'SWIFT_STRICT_CONCURRENCY': 'complete',
            'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode == 'Debug' else '-O',
        } if kind == 'project' else {
            'PRODUCT_BUNDLE_IDENTIFIER': 'de.elian.studyapp', 'PRODUCT_NAME': '$(TARGET_NAME)',
            'INFOPLIST_FILE': 'StudyApp/Configuration/Info.plist', 'CODE_SIGN_STYLE': 'Automatic',
            'TARGETED_DEVICE_FAMILY': '1,2', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
            'SUPPORTS_MACCATALYST': 'NO', 'GENERATE_INFOPLIST_FILE': 'NO',
            'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
        }
        if kind == 'project' and mode == 'Debug': settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
        body = ' '.join(f'{k} = {quote(v)};' for k, v in settings.items())
        base = f'baseConfigurationReference = {uid("StudyApp/Configuration/Config.xcconfig")};' if kind == 'target' else ''
        obj(key, f'isa = XCBuildConfiguration; {base} buildSettings = {{ {body} }}; name = {mode};')
    obj(f'{kind}-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(config_ids)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
(root / 'StudyApp.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {uid("project")}; }}\n')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2620" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="StudyApp.app" BlueprintName="StudyApp" ReferencedContainer="container:StudyApp.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="StudyApp.app" BlueprintName="StudyApp" ReferencedContainer="container:StudyApp.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="StudyApp.app" BlueprintName="StudyApp" ReferencedContainer="container:StudyApp.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(root / 'StudyApp.xcodeproj/xcshareddata/xcschemes/StudyApp.xcscheme').write_text(scheme)
print('Generated StudyApp.xcodeproj')
