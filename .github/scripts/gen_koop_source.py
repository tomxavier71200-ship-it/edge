#!/usr/bin/env python3
"""Generate the SideStore/AltStore source (apps.json) for Koop's rolling
iPhone build.

Like gen_altstore_source.py, it reads the real Info.plist baked into the .ipa,
so the bundle id and version can never drift from what was built. The
difference is the channel: one fixed release tag that every push to the work
branch overwrites, so the subscribe URL never changes and SideStore offers an
"Update" whenever the version moves.

Usage: gen_koop_source.py <path-to-ipa> <output-path> <owner/repo> <tag>
"""
import datetime
import json
import os
import plistlib
import sys
import zipfile


def read_info_plist(ipa_path: str) -> dict:
    with zipfile.ZipFile(ipa_path) as z:
        names = [
            n for n in z.namelist()
            if n.startswith("Payload/") and n.endswith(".app/Info.plist")
            and n.count("/") == 2
        ]
        if not names:
            raise SystemExit(f"no app Info.plist found inside {ipa_path}")
        with z.open(names[0]) as f:
            return plistlib.load(f)


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(f"usage: {sys.argv[0]} <ipa> <out.json> <owner/repo> <tag>")
    ipa_path, out_path, repo, tag = sys.argv[1:5]

    info = read_info_plist(ipa_path)
    bundle_id = info["CFBundleIdentifier"]
    version = info["CFBundleShortVersionString"]
    build = str(info.get("CFBundleVersion", ""))
    min_os = info.get("MinimumOSVersion", "15.0")
    size = os.path.getsize(ipa_path)
    url = (f"https://github.com/{repo}/releases/download/{tag}/"
           f"{os.path.basename(ipa_path)}")
    now = datetime.datetime.now(datetime.timezone.utc)

    source = {
        "name": "Koop",
        "identifier": f"{bundle_id}.koop-source",
        "apps": [{
            "name": "Koop",
            "bundleIdentifier": bundle_id,
            "developerName": "Koop",
            "subtitle": "Your WHOOP band, no subscription",
            "localizedDescription": (
                "Local-first companion for your WHOOP band. Not affiliated "
                "with WHOOP, Inc."
            ),
            "size": size,
            "versions": [{
                "version": version,
                "buildVersion": build,
                "date": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "localizedDescription": f"Koop {version} (build {build}).",
                "downloadURL": url,
                "size": size,
                "minOSVersion": min_os,
            }],
        }],
    }
    with open(out_path, "w") as f:
        json.dump(source, f, indent=2)
        f.write("\n")
    print(f"wrote {out_path}: {bundle_id} {version} ({build}), {size} bytes")


if __name__ == "__main__":
    main()
