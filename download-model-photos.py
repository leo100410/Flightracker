"""Fetch a reviewed, bounded model-photo catalog from Wikimedia Commons. Not a build step."""
import html
import json
import pathlib
import re
import urllib.parse
import urllib.request
import time

ROOT = pathlib.Path(__file__).resolve().parent / "Sources/RadarCore/Resources"
FILES = [
    ("A320", "Airbus A320", "Airbus A320 and a seagull.jpg", "Benjamin Shaw", "CC BY-SA 4.0", "https://creativecommons.org/licenses/by-sa/4.0/"),
    ("A321", "Airbus A321", "Airbus A321-100.jpg", "MaxEddi", "Public domain", "https://commons.wikimedia.org/wiki/Template:PD-self"),
    ("B738", "Boeing 737-800", "B737-800.jpg", "Jo\u00e3o Pedro Wanzeller", "CC BY-SA 4.0", "https://creativecommons.org/licenses/by-sa/4.0/"),
    ("A20N", "Airbus A320neo", "Airbus A320neo CC-DBN.jpg", "Ziongarage", "CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/"),
    ("A319", "Airbus A319", "Airbus a319.jpg", "Leozengy", "CC BY-SA 4.0", "https://creativecommons.org/licenses/by-sa/4.0/"),
    ("A21N", "Airbus A321neo", "Airbus A321neo (35121128500).jpg", "Clemens Vasters", "CC BY 2.0", "https://creativecommons.org/licenses/by/2.0/"),
]

def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "SkyNear/1.2 (personal flight radar; model-photo catalog)"})
    with urllib.request.urlopen(request, timeout=25) as response:
        data = response.read(12_000_001)
        if len(data) > 12_000_000:
            raise ValueError("Download too large")
        return data

if __name__ == "__main__":
    catalog = []
    for code, title, filename, author, license_name, license_url in FILES:
        source = "https://commons.wikimedia.org/wiki/File:" + urllib.parse.quote(filename.replace(" ", "_"))
        name = "ModelPhoto-" + code
        if not (ROOT / (name + ".jpg")).exists():
            page = fetch(source).decode("utf-8")
            match = re.search(r'class="fullImageLink"[^>]*>\s*<a href="([^"]+)"', page)
            if not match:
                raise ValueError("Original image missing: " + code)
            url = html.unescape(match.group(1))
            if not url.startswith("https://upload.wikimedia.org/"):
                raise ValueError("Unexpected download host")
            time.sleep(2)
            (ROOT / (name + ".jpg")).write_bytes(fetch(url))
            time.sleep(2)
        catalog.append(dict(code=code, title=title, filename=name, author=author,
                            license=license_name, source=source, licenseURL=license_url))
        print(code, "saved")
    (ROOT / "ModelPhotos.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = ["Model reference photos (not the tracked aircraft). Resized JPEG derivatives; each retains its listed license."]
    for item in catalog:
        lines.extend(["", item["title"] + " - " + item["author"], item["license"], item["source"], item["licenseURL"]])
    (ROOT / "ModelPhotoCredits.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("Resize newly downloaded originals to at most 480x320 before packaging. Existing project resources are already resized.")
