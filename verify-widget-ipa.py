#!/usr/bin/env python3
import pathlib
import plistlib
import struct
import sys
import zipfile

ARM64=0x0100000C

def arm64_slice(data):
    if len(data)<32: raise ValueError('Mach-O zu kurz')
    magic=data[:4]
    if magic==b'\xcf\xfa\xed\xfe':
        if struct.unpack_from('<I',data,4)[0]!=ARM64: raise ValueError('Nicht arm64')
        return data
    formats={b'\xca\xfe\xba\xbe':('>',20),b'\xbe\xba\xfe\xca':('<',20),
             b'\xca\xfe\xba\xbf':('>',32),b'\xbf\xba\xfe\xca':('<',32)}
    if magic not in formats: raise ValueError('Nicht unterstütztes Mach-O-Format')
    endian,stride=formats[magic]
    count=struct.unpack_from(endian+'I',data,4)[0]
    if count>100 or 8+count*stride>len(data): raise ValueError('Ungültiger FAT-Header')
    for i in range(count):
        pos=8+i*stride
        cpu=struct.unpack_from(endian+'I',data,pos)[0]
        offset,length=struct.unpack_from(endian+('QQ' if stride==32 else 'II'),data,pos+8)
        if cpu==ARM64:
            if offset+length>len(data): raise ValueError('Ungültiger arm64-Slice')
            return arm64_slice(data[offset:offset+length])
    raise ValueError('Kein arm64-Slice')

def inspect_macho(data,widget=False):
    data=arm64_slice(data)
    ncmds,sizeofcmds=struct.unpack_from('<II',data,16)
    end=32+sizeofcmds
    if ncmds>10000 or end>len(data): raise ValueError('Ungültige Load-Commands')
    pos=32; sections=[]; signature=None; symbol_table=None
    for _ in range(ncmds):
        if pos+8>end: raise ValueError('Abgeschnittene Load-Commands')
        cmd,size=struct.unpack_from('<II',data,pos)
        if size<8 or size%8 or pos+size>end: raise ValueError('Ungültige Load-Command-Größe')
        if cmd==0x19:
            if size<72: raise ValueError('Ungültiges Segment')
            count=struct.unpack_from('<I',data,pos+64)[0]
            if 72+count*80>size: raise ValueError('Ungültige Section-Tabelle')
            for i in range(count):
                sec=pos+72+i*80
                name=data[sec:sec+16].split(b'\0')[0].decode('ascii',errors='replace')
                segment=data[sec+16:sec+32].split(b'\0')[0].decode('ascii',errors='replace')
                length=struct.unpack_from('<Q',data,sec+40)[0]
                offset=struct.unpack_from('<I',data,sec+48)[0]
                flags=struct.unpack_from('<I',data,sec+64)[0]
                if length and offset and (flags&0xff) not in (1,12,18) and offset+length>len(data):
                    raise ValueError('Section außerhalb der Datei')
                address=struct.unpack_from('<Q',data,sec+32)[0]
                sections.append((segment,name,offset,length,flags,address))
        elif cmd==0x2:
            if size!=24: raise ValueError('Ungültige Symboltabelle')
            symbol_table=struct.unpack_from('<IIII',data,pos+8)
        elif cmd==0x1d:
            if size!=16: raise ValueError('Ungültiger Signatur-Load-Command')
            signature=struct.unpack_from('<II',data,pos+8)
            if sum(signature)>len(data): raise ValueError('Signaturbereich außerhalb der Datei')
        pos+=size
    if pos!=end: raise ValueError('sizeofcmds inkonsistent')
    text=next((s for s in sections if s[0]=='__TEXT' and s[1]=='__text' and s[3]>0),None)
    entry=next((s for s in sections if s[0]=='__TEXT' and s[1]=='__swift5_entry' and s[3]>=8),None)
    main_defined=False; main_address=None
    if symbol_table:
        symoff,count,stroff,strsize=symbol_table
        if symoff+count*16>len(data) or stroff+strsize>len(data): raise ValueError('Symboltabelle außerhalb der Datei')
        strings=data[stroff:stroff+strsize]
        for i in range(count):
            strx,typ,sect,desc,value=struct.unpack_from('<IBBHQ',data,symoff+i*16)
            if strx>=len(strings): continue
            name=strings[strx:].split(b'\0')[0]
            if name==b'_main' and (typ&0x0e)==0x0e and sect>0:
                main_defined=True
                main_address=value
    occupied=[s[2] for s in sections if s[2]>0 and s[3]>0 and (s[4]&0xff) not in (1,12,18)]
    first=min(occupied) if occupied else None
    if first is not None and first<end: raise ValueError('Load-Commands überlappen Dateiinhalt')
    padding=first-end if first is not None else None
    errors=[]
    if not text: errors.append('__TEXT/__text fehlt oder ist leer')
    if widget and not entry: errors.append('__swift5_entry fehlt oder ist zu klein')
    if widget and not main_defined: errors.append('Definiertes _main fehlt; Swift-Widget-Einstieg nicht eingebunden')
    entry_matches_main=False
    if entry and main_address is not None:
        for displacement in range(0,entry[3]-7,8):
            target=entry[5]+displacement+struct.unpack_from('<i',data,entry[2]+displacement)[0]
            if target==main_address: entry_matches_main=True
    if widget and not entry_matches_main: errors.append('__swift5_entry verweist nicht auf das definierte _main')
    if signature is None:
        if padding is None or padding<16 or data[end:end+16]!=bytes(16):
            errors.append('Kein LC_CODE_SIGNATURE und kein nutzbarer Platz für den Load-Command')
    result={'bytes':len(data),'text_bytes':text[3] if text else 0,
            'swift_entry':entry is not None,'main_defined':main_defined,'entry_matches_main':entry_matches_main,
            'header_padding':padding,'signature_command':signature is not None,'errors':errors}
    return result

def main():
    if len(sys.argv)!=2: raise SystemExit('Aufruf: python3 verify-widget-ipa.py Pfad/zur/App.ipa')
    path=pathlib.Path(sys.argv[1])
    if not path.is_file(): raise SystemExit('IPA nicht gefunden: '+str(path))
    errors=[]
    with zipfile.ZipFile(path) as archive:
        names=set(archive.namelist())
        app_infos=[n for n in names if n.startswith('Payload/') and n.endswith('.app/Info.plist') and n.count('/')==2]
        if len(app_infos)!=1: raise SystemExit('Genau eine Haupt-App erwartet')
        app_root=app_infos[0].removesuffix('Info.plist')
        ext_infos=sorted(n for n in names if n.startswith(app_root+'PlugIns/') and n.endswith('.appex/Info.plist'))
        widgets=0
        for info_path in app_infos+ext_infos:
            info=plistlib.loads(archive.read(info_path))
            is_widget=info.get('NSExtension',{}).get('NSExtensionPointIdentifier')=='com.apple.widgetkit-extension'
            if info_path not in app_infos and not is_widget: continue
            widgets+=int(is_widget)
            binary=info_path.removesuffix('Info.plist')+info.get('CFBundleExecutable','')
            print(binary)
            try:
                result=inspect_macho(archive.read(binary),widget=is_widget)
                print('  Code-Section:',result['text_bytes'],'Byte')
                print('  _main definiert:',result['main_defined'],'| Swift-Einstieg:',result['swift_entry'])
                if is_widget: print('  Swift-Einstieg zeigt auf _main:',result['entry_matches_main'])
                print('  Headerplatz:',result['header_padding'],'Byte | Signatur-Load-Command:',result['signature_command'])
                for error in result['errors']: print('  FEHLER:',error)
                errors.extend(result['errors'])
            except (ValueError,struct.error,KeyError) as error:
                print('  FEHLER:',error); errors.append(str(error))
        if widgets!=1: errors.append('Genau eine SkyNear-Widget-Extension erwartet')
    if errors:
        raise SystemExit('Widget-/Mach-O-Prüfung fehlgeschlagen. Diese IPA nicht als korrigiert signieren/installieren.')
    print('\nWidget-Code, Swift-Einstieg und Headerstruktur vorhanden.')
    print('Keine kryptografische Signaturprüfung und kein iPhone-Laufzeittest. Jetzt neu in KSign importieren und auf Signed OK achten.')

if __name__=='__main__': main()
