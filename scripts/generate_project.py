#!/usr/bin/env python3
"""Generate the checked-in Xcode project deterministically without Ruby dependencies."""
from pathlib import Path
import hashlib
import json
import plistlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / 'ios'
PROJECT = IOS / 'UniversalBookmarker.xcodeproj'
objects = {}

def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def obj(object_key, isa, **fields):
    key = identifier(object_key)
    objects[key] = {'isa': isa, **fields}
    return key

def serialize(value, depth=0):
    indent = '\t' * depth
    if isinstance(value, dict):
        return '{\n' + ''.join('\t' * (depth+1) + json.dumps(str(k)) + ' = ' + serialize(v, depth+1) + ';\n' for k,v in value.items()) + indent + '}'
    if isinstance(value, list):
        return '(\n' + ''.join('\t'*(depth+1) + serialize(v,depth+1) + ',\n' for v in value) + indent + ')'
    return str(value) if isinstance(value,int) else json.dumps(str(value))

config_ref = obj('configuration-file','PBXFileReference',lastKnownFileType='text.xcconfig',path='Configuration/Project.xcconfig',sourceTree='<group>')
core_ref = obj('core-package','XCLocalSwiftPackageReference',relativePath='../Packages/BookmarkCore')
cloud_ref = obj('cloud-package','XCLocalSwiftPackageReference',relativePath='../Packages/BookmarkCloud')
file_refs = [config_ref]
products = []
targets = []
target_ids = {name:identifier('target-'+name) for name in ['UniversalBookmarker','ShareExtension','UniversalBookmarkerTests','UniversalBookmarkerUITests']}

def configurations(name, extra):
    refs=[]
    for mode in ['Debug','Release']:
        settings = {'SWIFT_VERSION':'6.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','TARGETED_DEVICE_FAMILY':'1',
                    'SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator',
                    'CODE_SIGN_STYLE':'Automatic','SWIFT_STRICT_CONCURRENCY':'complete',
                    'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O',
                    'ENABLE_TESTABILITY':'YES' if mode=='Debug' else 'NO',**extra}
        refs.append(obj(name+'-'+mode,'XCBuildConfiguration',baseConfigurationReference=config_ref,name=mode,buildSettings=settings))
    return obj(name+'-configurations','XCConfigurationList',buildConfigurations=refs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

descriptions = [
 ('UniversalBookmarker','com.apple.product-type.application','app',sorted((IOS/'UniversalBookmarker').rglob('*.swift')),['BookmarkCore','BookmarkCloud'],{'INFOPLIST_FILE':'Configuration/App-Info.plist','CODE_SIGN_ENTITLEMENTS':'Configuration/App.entitlements','PRODUCT_BUNDLE_IDENTIFIER':'$(APP_BUNDLE_IDENTIFIER)','PRODUCT_NAME':'$(TARGET_NAME)','ENABLE_PREVIEWS':'YES'}),
 ('ShareExtension','com.apple.product-type.app-extension','appex',sorted((IOS/'ShareExtension').glob('*.swift')),['BookmarkCore'],{'INFOPLIST_FILE':'ShareExtension/Info.plist','CODE_SIGN_ENTITLEMENTS':'Configuration/Share.entitlements','PRODUCT_BUNDLE_IDENTIFIER':'$(APP_BUNDLE_IDENTIFIER).ShareExtension','PRODUCT_NAME':'$(TARGET_NAME)','APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES'}),
 ('UniversalBookmarkerTests','com.apple.product-type.bundle.unit-test','xctest',sorted((IOS/'UniversalBookmarkerTests').glob('*.swift'))+[IOS/'ShareExtension/CaptureStaging.swift']+sorted((IOS/'ShareExtension/Tests').glob('*.swift')),['BookmarkCore','BookmarkCloud'],{'GENERATE_INFOPLIST_FILE':'YES','PRODUCT_BUNDLE_IDENTIFIER':'$(APP_BUNDLE_IDENTIFIER).Tests','PRODUCT_NAME':'$(TARGET_NAME)','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/UniversalBookmarker.app/UniversalBookmarker','BUNDLE_LOADER':'$(TEST_HOST)'}),
 ('UniversalBookmarkerUITests','com.apple.product-type.bundle.ui-testing','xctest',sorted((IOS/'UniversalBookmarkerUITests').glob('*.swift')),[],{'GENERATE_INFOPLIST_FILE':'YES','PRODUCT_BUNDLE_IDENTIFIER':'$(APP_BUNDLE_IDENTIFIER).UITests','PRODUCT_NAME':'$(TARGET_NAME)','TEST_TARGET_NAME':'UniversalBookmarker'}),
]
for name, product_type, extension, sources, packages, settings in descriptions:
    builds=[]
    for path in sources:
        relative=str(path.relative_to(IOS))
        ref=obj('file-'+relative,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=relative,sourceTree='<group>')
        if ref not in file_refs: file_refs.append(ref)
        builds.append(obj('build-'+name+'-'+relative,'PBXBuildFile',fileRef=ref))
    source_phase=obj(name+'-sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=builds,runOnlyForDeploymentPostprocessing=0)
    deps=[]; package_products=[]; linked=[]
    for package in packages:
        product=obj(name+'-package-'+package,'XCSwiftPackageProductDependency',package=core_ref if package=='BookmarkCore' else cloud_ref,productName=package)
        package_products.append(product)
        linked.append(obj(name+'-link-'+package,'PBXBuildFile',productRef=product))
    framework_phase=obj(name+'-frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=linked,runOnlyForDeploymentPostprocessing=0)
    phases=[source_phase,framework_phase]
    if name in ['UniversalBookmarker','ShareExtension']:
        privacy=obj('privacy-file','PBXFileReference',lastKnownFileType='text.xml',path='Configuration/PrivacyInfo.xcprivacy',sourceTree='<group>')
        if privacy not in file_refs: file_refs.append(privacy)
        resource=obj(name+'-privacy','PBXBuildFile',fileRef=privacy)
        phases.append(obj(name+'-resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[resource],runOnlyForDeploymentPostprocessing=0))
    if name=='UniversalBookmarker':
        proxy=obj('extension-proxy','PBXContainerItemProxy',containerPortal=identifier('project'),proxyType=1,remoteGlobalIDString=target_ids['ShareExtension'],remoteInfo='ShareExtension')
        deps.append(obj('extension-dependency','PBXTargetDependency',target=target_ids['ShareExtension'],targetProxy=proxy))
        product_ref=identifier('product-ShareExtension')
        embed=obj('embed-extension','PBXBuildFile',fileRef=product_ref,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
        phases.append(obj('copy-extension','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embed],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0))
    if name.endswith('Tests'):
        proxy=obj(name+'-app-proxy','PBXContainerItemProxy',containerPortal=identifier('project'),proxyType=1,remoteGlobalIDString=target_ids['UniversalBookmarker'],remoteInfo='UniversalBookmarker')
        deps.append(obj(name+'-app-dependency','PBXTargetDependency',target=target_ids['UniversalBookmarker'],targetProxy=proxy))
    product=obj('product-'+name,'PBXFileReference',explicitFileType={'app':'wrapper.application','appex':'wrapper.app-extension','xctest':'wrapper.cfbundle'}[extension],includeInIndex=0,path=name+'.'+extension,sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product)
    target=obj('target-'+name,'PBXNativeTarget',buildConfigurationList=configurations(name,settings),buildPhases=phases,buildRules=[],dependencies=deps,name=name,productName=name,productReference=product,productType=product_type,packageProductDependencies=package_products)
    targets.append(target)

main_group=obj('main-group','PBXGroup',children=[obj('source-group','PBXGroup',children=file_refs,name='Sources',sourceTree='<group>'),obj('product-group','PBXGroup',children=products,name='Products',sourceTree='<group>')],sourceTree='<group>')
project=obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastSwiftUpdateCheck':'1600','LastUpgradeCheck':'1600'},buildConfigurationList=configurations('Project',{'CLANG_ENABLE_MODULES':'YES','DEFINES_MODULE':'YES'}),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main_group,productRefGroup=identifier('product-group'),projectDirPath='',projectRoot='',targets=targets,packageReferences=[core_ref,cloud_ref])
document={'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project}
PROJECT.mkdir(parents=True,exist_ok=True)
(PROJECT/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize(document)+'\n')

scheme=ET.Element('Scheme',LastUpgradeVersion='1600',version='1.3')
build=ET.SubElement(scheme,'BuildAction',parallelizeBuildables='YES',buildImplicitDependencies='YES')
entries=ET.SubElement(build,'BuildActionEntries')
entry=ET.SubElement(entries,'BuildActionEntry',buildForTesting='YES',buildForRunning='YES',buildForProfiling='YES',buildForArchiving='YES',buildForAnalyzing='YES')
def reference(parent,name):
    ET.SubElement(parent,'BuildableReference',BuildableIdentifier='primary',BlueprintIdentifier=target_ids[name],BuildableName=name+('.app' if name=='UniversalBookmarker' else '.xctest'),BlueprintName=name,ReferencedContainer='container:UniversalBookmarker.xcodeproj')
reference(entry,'UniversalBookmarker')
test=ET.SubElement(scheme,'TestAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',shouldUseLaunchSchemeArgsEnv='YES')
testables=ET.SubElement(test,'Testables')
for name in ['UniversalBookmarkerTests','UniversalBookmarkerUITests']:
    reference(ET.SubElement(testables,'TestableReference',skipped='NO'),name)
launch=ET.SubElement(scheme,'LaunchAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',launchStyle='0',useCustomWorkingDirectory='NO',ignoresPersistentStateOnLaunch='NO',debugDocumentVersioning='YES',debugServiceExtension='internal',allowLocationSimulation='YES')
reference(ET.SubElement(launch,'BuildableProductRunnable',runnableDebuggingMode='0'),'UniversalBookmarker')
profile=ET.SubElement(scheme,'ProfileAction',buildConfiguration='Release',shouldUseLaunchSchemeArgsEnv='YES',useCustomWorkingDirectory='NO',debugDocumentVersioning='YES')
reference(ET.SubElement(profile,'BuildableProductRunnable',runnableDebuggingMode='0'),'UniversalBookmarker')
ET.SubElement(scheme,'AnalyzeAction',buildConfiguration='Debug')
ET.SubElement(scheme,'ArchiveAction',buildConfiguration='Release',revealArchiveInOrganizer='YES')
scheme_dir=PROJECT/'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True,exist_ok=True)
ET.indent(scheme)
ET.ElementTree(scheme).write(scheme_dir/'UniversalBookmarker.xcscheme',encoding='UTF-8',xml_declaration=True)
print(f'Generated {PROJECT.relative_to(ROOT)} with {sum(len(d[3]) for d in descriptions)} source build entries.')
