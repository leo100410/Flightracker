"""Compare packaging configuration before/after signing without exposing profiles or credentials."""
import argparse
import json
import pathlib
import plistlib
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent
FIELDS = ("CFBundleIdentifier", "CFBundleVersion", "BGTaskSchedulerPermittedIdentifiers",
          "UIBackgroundModes", "SkyNearAppGroup", "NSWidgetWantsLocation", "NSSupportsLiveActivities")


def inspect(path):
    with zipfile.ZipFile(path) as ipa:
        entries = [name for name in ipa.namelist()
                   if name.startswith("Payload/") and name.endswith("/Info.plist")
                   and (name.count("/") == 2 or ("/PlugIns/" in name and name.count("/") == 4))]
        for entry in sorted(entries):
            info = plistlib.loads(ipa.read(entry))
            widget = "/PlugIns/" in entry
            expected = plistlib.loads((ROOT / ("Widget-Info.plist" if widget else "App-Info.plist")).read_bytes())
            values = {key: info.get(key) for key in FIELDS if key in info or key in expected}
            print(json.dumps({"file": entry, "installed_values": values,
                              "changes_from_source": {key: {"expected": expected.get(key), "actual": info.get(key)}
                                                      for key in FIELDS if key in expected and expected[key] != info.get(key)}},
                             ensure_ascii=False, indent=2))
            if not widget:
                allowed = info.get("BGTaskSchedulerPermittedIdentifiers", [])
                modes = info.get("UIBackgroundModes", [])
                print("Background config:", "fetch present" if "fetch" in modes else "FETCH MISSING",
                      "| permitted IDs:", len(allowed))
        if not entries:
            raise SystemExit("No app Info.plist found")
    print("Configuration inspection only. App Group access, signing validity and OS task execution require device checks.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=pathlib.Path)
    inspect(parser.parse_args().ipa)
