#!/usr/bin/env python3
import pathlib
import plistlib
import struct
import sys
import zipfile

def require(value, message):
    if not value:
        raise SystemExit('IPA-Prüfung fehlgeschlagen: ' + message)

def is_arm64(blob):
    if len(blob) < 12:
        return False
    magic = blob[:4]
    if magic == b'\xcf\xfa\xed\xfe':
        return struct.unpack('<I', blob[4:8])[0] == 0x0100000C
    if magic == b'\xfe\xed\xfa\xcf':
        return struct.unpack('>I', blob[4:8])[0] == 0x0100000C
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf', b'\xbe\xba\xfe\xca', b'\xbf\xba\xfe\xca'):
        endian = '>' if magic[0] == 0xca else '<'
        count = struct.unpack(endian + 'I', blob[4:8])[0]
        stride = 32 if magic in (b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca') else 20
        return any(struct.unpack(endian + 'I', blob[8+i*stride:12+i*stride])[0] == 0x0100000C for i in range(count))
    return False

require(len(sys.argv) == 2, 'Aufruf: python3 verify-ipa.py Pfad/zur/App.ipa')
path = pathlib.Path(sys.argv[1])
require(path.is_file(), 'Datei nicht gefunden')
with zipfile.ZipFile(path) as ipa:
    require(ipa.testzip() is None, 'ZIP enthält beschädigte Einträge')
    names = set(ipa.namelist())
    apps = [n for n in names if n.startswith('Payload/') and n.endswith('.app/Info.plist') and n.count('/') == 2]
    require(len(apps) == 1, 'Genau ein Payload/<Name>.app erwartet')
    app_root = apps[0].removesuffix('Info.plist')
    info = plistlib.loads(ipa.read(apps[0]))
    require(info.get('NSLocationWhenInUseUsageDescription'), 'Standort-Berechtigungsbeschreibung fehlt')
    require(info.get('NSSupportsLiveActivities') is True, 'Live-Activity-Konfiguration fehlt')
    executable = app_root + info.get('CFBundleExecutable', '')
    require(executable in names, 'App-Executable fehlt')
    require(is_arm64(ipa.read(executable)), 'App-Executable enthält kein arm64')
    extensions = [n for n in names if n.startswith(app_root+'PlugIns/') and n.endswith('.appex/Info.plist')]
    require(extensions, 'Widget-Extension fehlt in PlugIns')
    valid_widget = False
    for name in extensions:
        widget = plistlib.loads(ipa.read(name))
        if widget.get('NSExtension', {}).get('NSExtensionPointIdentifier') != 'com.apple.widgetkit-extension':
            continue
        valid_widget = True
        require(widget.get('NSWidgetWantsLocation') is True, 'Widget-Standortkonfiguration fehlt')
        binary = name.removesuffix('Info.plist') + widget.get('CFBundleExecutable', '')
        require(binary in names and is_arm64(ipa.read(binary)), 'Widget-Executable fehlt oder enthält kein arm64')
        app_id = info.get('CFBundleIdentifier', '')
        widget_id = widget.get('CFBundleIdentifier', '')
        require(widget_id.startswith(app_id + '.'), 'Widget-Bundle-ID muss zur App-Bundle-ID passen')
    require(valid_widget, 'Keine WidgetKit-Extension gefunden')
    require(any(n.endswith('/Sources.txt') for n in names), 'SwiftPM-Quellenhinweise fehlen im App-Bundle')
    require(app_root+'PrivacyInfo.xcprivacy' in names, 'Datenschutzmanifest fehlt')
    print('IPA-Struktur OK: arm64-App, arm64-Widget, Standort, Live Activities, Ressourcen und Datenschutzmanifest.')
    print('Bundle-ID:', info.get('CFBundleIdentifier'))
    print('Diese Prüfung testet weder Apple-Signaturen noch Laufzeitverhalten.')
