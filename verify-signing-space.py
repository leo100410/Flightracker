#!/usr/bin/env python3
import pathlib
import plistlib
import struct
import sys
import zipfile

ARM64 = 0x0100000C

def arm64_slice(blob):
    if len(blob) < 32:
        raise ValueError('Mach-O zu kurz')
    magic = blob[:4]
    if magic in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'):
        endian = '<' if magic == b'\xcf\xfa\xed\xfe' else '>'
        if struct.unpack_from(endian+'I', blob, 4)[0] != ARM64:
            raise ValueError('Kein arm64-Mach-O')
        return blob
    formats = {b'\xca\xfe\xba\xbe':('>',20), b'\xbe\xba\xfe\xca':('<',20),
               b'\xca\xfe\xba\xbf':('>',32), b'\xbf\xba\xfe\xca':('<',32)}
    if magic not in formats:
        raise ValueError('Nicht unterstütztes Mach-O-Format')
    endian, stride = formats[magic]
    count = struct.unpack_from(endian+'I',blob,4)[0]
    if count > 100 or 8+count*stride > len(blob):
        raise ValueError('Ungültiger FAT-Header')
    for index in range(count):
        pos=8+index*stride
        cpu=struct.unpack_from(endian+'I',blob,pos)[0]
        fmt='QQ' if stride==32 else 'II'
        offset,size=struct.unpack_from(endian+fmt,blob,pos+8)
        if cpu == ARM64:
            if offset+size > len(blob):
                raise ValueError('Ungültiger arm64-Slice')
            return arm64_slice(blob[offset:offset+size])
    raise ValueError('Kein arm64-Slice')

def inspect(blob):
    blob=arm64_slice(blob)
    endian='<' if blob[:4]==b'\xcf\xfa\xed\xfe' else '>'
    ncmds, sizeofcmds=struct.unpack_from(endian+'II',blob,16)
    end=32+sizeofcmds
    if end > len(blob) or ncmds > 10000:
        raise ValueError('Ungültige Load-Command-Tabelle')
    pos=32
    section_offsets=[]
    signature=None
    for _ in range(ncmds):
        if pos+8 > end:
            raise ValueError('Abgeschnittener Load-Command')
        cmd,size=struct.unpack_from(endian+'II',blob,pos)
        if size < 8 or size%8 != 0 or pos+size > end:
            raise ValueError('Ungültige Load-Command-Größe')
        if cmd==0x19:
            if size < 72:
                raise ValueError('Ungültiges LC_SEGMENT_64')
            nsects=struct.unpack_from(endian+'I',blob,pos+64)[0]
            if 72+nsects*80 > size:
                raise ValueError('Abgeschnittene Section-Tabelle')
            for index in range(nsects):
                sec=pos+72+index*80
                section_size=struct.unpack_from(endian+'Q',blob,sec+40)[0]
                file_offset=struct.unpack_from(endian+'I',blob,sec+48)[0]
                flags=struct.unpack_from(endian+'I',blob,sec+64)[0]
                if section_size and file_offset and flags&0xff not in (1,12,18):
                    if file_offset+section_size > len(blob):
                        raise ValueError('Section reicht über das Dateiende')
                    section_offsets.append(file_offset)
        if cmd==0x1d:
            if size != 16:
                raise ValueError('Ungültiges LC_CODE_SIGNATURE')
            signature=struct.unpack_from(endian+'II',blob,pos+8)
            if signature[0]+signature[1] > len(blob):
                raise ValueError('Signaturbereich reicht über das Dateiende')
        pos+=size
    if pos!=end:
        raise ValueError('sizeofcmds stimmt nicht mit den Load-Commands überein')
    first=min(section_offsets) if section_offsets else None
    if first is not None and first<end:
        raise ValueError('Load-Commands überlappen eine Section')
    if signature is not None:
        return True, 'LC_CODE_SIGNATURE vorhanden; kryptografische Gültigkeit nicht geprüft'
    if first is None:
        return False, 'Kein Signatur-Load-Command; freier Platz nicht zuverlässig bestimmbar'
    padding=first-end
    if padding>=16 and blob[end:end+16]==bytes(16):
        return True, f'Kein LC_CODE_SIGNATURE, aber {padding} Byte Headerplatz; 16 Nullbytes für den Load-Command vorhanden'
    return False, f'Kein LC_CODE_SIGNATURE und nicht genügend freier Headerplatz ({padding} Byte)'

def main():
    if len(sys.argv)!=2:
        raise SystemExit('Aufruf: python3 verify-signing-space.py Pfad/zur/App.ipa')
    path=pathlib.Path(sys.argv[1])
    if not path.is_file():
        raise SystemExit('IPA nicht gefunden: '+str(path))
    failures=[]
    with zipfile.ZipFile(path) as archive:
        names=set(archive.namelist())
        apps=[n for n in names if n.startswith('Payload/') and n.endswith('.app/Info.plist') and n.count('/')==2]
        if len(apps)!=1:
            raise SystemExit('Genau eine Haupt-App erwartet')
        app_root=apps[0].removesuffix('Info.plist')
        infos=[apps[0]]+sorted(n for n in names if n.startswith(app_root+'PlugIns/') and n.endswith('.appex/Info.plist'))
        if len(infos)<2:
            raise SystemExit('Widget-Extension fehlt; dieser Fix entfernt sie nicht')
        for info_path in infos:
            info=plistlib.loads(archive.read(info_path))
            executable=info.get('CFBundleExecutable')
            if not executable:
                failures.append(info_path+': CFBundleExecutable fehlt'); continue
            binary=info_path.removesuffix('Info.plist')+executable
            try:
                ok,message=inspect(archive.read(binary))
            except (ValueError,struct.error,KeyError) as error:
                ok,message=False,str(error)
            print(binary+'\n  '+('OK: ' if ok else 'FEHLER: ')+message)
            if not ok:
                failures.append(binary)
    if failures:
        raise SystemExit('Signatur-Headerprüfung fehlgeschlagen. Diese IPA nicht erneut als korrigiert importieren; Ausgabe und Linker-Log prüfen.')
    print('\nHeaderprüfung bestanden. Das ist keine Signierung, Zertifikatsprüfung oder Installationsgarantie.')
    print('Nächster Schritt: die neu gebaute IPA in KSign neu importieren und signieren. Auf Signed OK achten, nicht nur auf den Ordner Signed.')

if __name__=='__main__':
    main()
