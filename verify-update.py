#!/usr/bin/env python3
"""Static resource/configuration checks; this is explicitly not a Swift/iOS build."""
import ast
import json
import pathlib
import plistlib
import re
import argparse
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent


def require(condition, message):
    if not condition:
        raise SystemExit("Static check failed: " + message)


translations = json.loads((ROOT / "Sources/RadarCore/Resources/Translations.json").read_text(encoding="utf-8-sig"))
used = set()
for path in (ROOT / "Sources").rglob("*.swift"):
    source = path.read_text(encoding="utf-8-sig")
    used.update(re.findall(r'\.text\("([^"\\]*)"\)', source))
    require("\ufffd" not in source, str(path.relative_to(ROOT)) + ": invalid Unicode")
for key in sorted(used):
    require(key in translations, "Missing localization key: " + key)
    require(all(translations[key].get(lang) for lang in ("en", "da")), "Missing translation: " + key)
for lang in ("", "-en", "-da"):
    path = ROOT / ("Sources/RadarCore/Resources/Sources" + lang + ".txt")
    text = path.read_text(encoding="utf-8-sig")
    require("https://adsb.fi/" in text and "ODbL" in text and "Apple" in text, "Source attribution incomplete: " + path.name)
for name in ("App-Info.plist", "Widget-Info.plist", "Resources/PrivacyInfo.xcprivacy"):
    with (ROOT / name).open("rb") as stream:
        info = plistlib.load(stream)
    if "Info.plist" in name:
        require("adsb.fi" in info["NSLocationWhenInUseUsageDescription"], "Location disclosure missing fallback")
app_info = plistlib.loads((ROOT / "App-Info.plist").read_bytes())
widget_info = plistlib.loads((ROOT / "Widget-Info.plist").read_bytes())
for key in ("CFBundleVersion", "CFBundleShortVersionString"):
    require(app_info[key] == widget_info[key], "App and extension versions differ: " + key)
package = (ROOT / "Package.swift").read_text(encoding="utf-8-sig")
require('resources: [.process("Resources")]' in package, "SwiftPM resources missing")
require("enable-cross-import-overlays" in package, "MapKit overlay fix missing")
require('"-headerpad", "-Xlinker", "0x4000"' in package, "Signing header padding missing")
require('"-u", "-Xlinker", "_main"' in package, "Widget entry-point link fix missing")
config = (ROOT / "xtool.yml").read_text(encoding="utf-8-sig")
require("bundleID: de.leola.skynear" in config, "Bundle ID changed")
for name in ("Sources/SkyNearWidgets/NearbyWidget.swift", "Sources/SkyNearWidgets/NearestAircraftWidget.swift"):
    source = (ROOT / name).read_text(encoding="utf-8-sig")
    require('supportedFamilies([.systemLarge])' in source, "Large widget missing")
    require("AppIntentConfiguration" not in source, "Widget requires unsupported App Intents metadata")
widget_source = (ROOT / "Sources/SkyNearWidgets/NearbyWidget.swift").read_text(encoding="utf-8-sig")
bundle = re.search(r'struct SkyNearWidgetBundle: WidgetBundle \{\s*var body: some Widget \{([^}]+)', widget_source)
require(bundle is not None, "WidgetBundle entry missing")
registrations = re.findall(r'^\s*(\w+)\(\)\s*$', bundle.group(1), flags=re.M)
require(registrations == ["NearbyWidget", "NearestAircraftWidget", "MediumAircraftWidget", "NearbyLiveActivity"], "Expected four direct widget registrations")
nearest_source = (ROOT / "Sources/SkyNearWidgets/NearestAircraftWidget.swift").read_text(encoding="utf-8-sig")
require('let kind = "SkyNear.Nearby.v1"' in widget_source, "Previous widget kind changed")
require('let kind = "SkyNear.Nearest.v1"' in nearest_source, "Nearest widget kind missing")
medium_source = (ROOT / "Sources/SkyNearWidgets/MediumAircraftWidget.swift").read_text(encoding="utf-8-sig")
require('supportedFamilies([.systemMedium])' in medium_source, "Medium widget family missing")
require('let kind = "SkyNear.NearestMedium.v1"' in medium_source, "Medium widget kind missing")
require(app_info.get('BGTaskSchedulerPermittedIdentifiers') == ['de.leola.skynear.refresh'], "Background refresh identifier missing")
require('fetch' in app_info.get('UIBackgroundModes', []), "Background fetch mode missing")
for path in (ROOT / "Sources/SkyNearWidgets").glob("*.swift"):
    for argument in re.findall(r'\.configurationDisplayName\(([^\n]+)\)', path.read_text(encoding="utf-8-sig")):
        require(argument.startswith('"') and '\\(' not in argument, "Interpolated widget gallery title risks a WidgetKit assertion")
photos = json.loads((ROOT / 'Sources/RadarCore/Resources/ModelPhotos.json').read_text(encoding='utf-8'))
require(len(photos) == 6, "Expected six bundled model references")
for photo in photos:
    image = ROOT / 'Sources/RadarCore/Resources' / (photo['filename'] + '.jpg')
    require(image.is_file() and image.stat().st_size < 100_000, "Missing or oversized model photo: " + photo['code'])
    require(photo['author'] and photo['license'] and photo['source'].startswith('https://commons.wikimedia.org/'), "Photo credit missing")
for path in (ROOT / "Sources/SkyNearWidgets").glob("*.swift"):
    require("AppIntentTimelineProvider" not in path.read_text(encoding="utf-8-sig"), "Unexpected App Intents provider")
for path in ROOT.glob("SkyNear_*_Fix/apply_fix.py"):
    text = path.read_text(encoding="utf-8-sig")
    ast.parse(text, filename=str(path))
    require("PositionCoordinator.swift" in text, "Old patch lacks update guard: " + path.parent.name)
for path in ROOT.glob("*.py"):
    ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--ipa", type=pathlib.Path, help="Also inspect the actual packaged app and widget extension")
args = parser.parse_args()
if args.ipa:
    with zipfile.ZipFile(args.ipa) as ipa:
        require(ipa.testzip() is None, "Corrupt IPA ZIP")
        names = ipa.namelist()
        apps = [n for n in names if n.endswith('.app/Info.plist') and n.count('/') == 2]
        extensions = [n for n in names if n.endswith('.appex/Info.plist')]
        require(len(apps) == 1 and len(extensions) == 1, "Expected one app and one widget extension")
        actual_app = plistlib.loads(ipa.read(apps[0]))
        actual_ext = plistlib.loads(ipa.read(extensions[0]))
        require(actual_app.get('NSSupportsLiveActivities') is True, "Packaged Live Activity permission missing")
        require(actual_app.get('BGTaskSchedulerPermittedIdentifiers') == ['de.leola.skynear.refresh'] and 'fetch' in actual_app.get('UIBackgroundModes', []), "Packaged background refresh configuration missing")
        require(actual_ext.get('NSWidgetWantsLocation') is True, "Packaged widget location configuration missing")
        require(actual_ext.get('NSExtension', {}).get('NSExtensionPointIdentifier') == 'com.apple.widgetkit-extension', "Wrong extension type")
        require(actual_app['CFBundleIdentifier'] == 'de.leola.skynear', "Packaged app ID changed")
        require(actual_ext['CFBundleIdentifier'] == 'de.leola.skynear.SkyNearWidgets', "Packaged extension ID changed")
        require(actual_app['CFBundleVersion'] == actual_ext['CFBundleVersion'] == app_info['CFBundleVersion'], "IPA is not the current build")
        ext_root = extensions[0].removesuffix('Info.plist')
        binary = ipa.read(ext_root + actual_ext['CFBundleExecutable'])
        for symbol in ['SkyNear.Nearby.v1', 'SkyNear.Nearest.v1', 'SkyNear.NearestMedium.v1', 'NearbyWidget', 'NearestAircraftWidget', 'MediumAircraftWidget', 'NearbyLiveActivity', 'SkyNearWidgetBundle']:
            require(symbol.encode() in binary, "Packaged widget symbol or kind absent: " + symbol)
        for target in [apps[0].removesuffix('Info.plist'), ext_root]:
            for resource in ['Translations.json', 'Sources.txt', 'Sources-en.txt', 'Sources-da.txt', 'ModelPhotos.json', 'ModelPhotoCredits.txt'] + [p.name for p in (ROOT / 'Sources/RadarCore/Resources').glob('ModelPhoto-*.jpg')]:
                location = target + 'SkyNear_RadarCore.bundle/' + resource
                require(location in names, "Packaged resource missing: " + location)
                require(ipa.read(location) == (ROOT / 'Sources/RadarCore/Resources' / resource).read_bytes(), "Packaged resource is stale: " + resource)
        print('Actual IPA checked: current app/extension IDs and build, three Home Screen widget kinds, four widget code types, location, Live Activities, background refresh, and resources.')
        print('App Intents metadata required: no (all Home Screen widgets use StaticConfiguration).')
print("Static checks passed: resources, localization, plists, preserved build fixes, patch guards.")
print("Swift/iOS compilation, XCTest execution, IPA generation and device tests were NOT performed by this check.")
