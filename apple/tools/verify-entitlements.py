#!/usr/bin/env python3
"""Check that what we are about to upload still carries its entitlements.

    ./apple/tools/verify-entitlements.py ios   apple/.release/ios
    ./apple/tools/verify-entitlements.py macos apple/.release/macos

Why this exists: on 2026-09-05 the archive was built with
CODE_SIGNING_ALLOWED=NO, to stop a bare CI keychain minting a development
certificate on every run. That does not merely skip a signature that
-exportArchive replaces moments later — it strips the entitlements out of the
binary, and the export re-signs from whatever the archive holds. The build
that shipped went to TestFlight without Game Center, without the iCloud
key-value store, and without the sandbox.

Nothing about the signature looks wrong when this happens: the authority is
right, the profile is embedded, `codesign --verify --strict --deep` passes.
iOS validation does not check for a sandbox either, so App Store Connect
accepted it without complaint. Only the entitlements say otherwise, so they
are what gets checked here.

The comparison is against Word/Word.entitlements, which XcodeGen generates
from the block in project.yml — the same file the build signs with. Keys are
compared, not values: the source uses build variables such as
$(TeamIdentifierPrefix) that are expanded by the time they are signed in.
"""

import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
APPLE_DIR = os.path.dirname(HERE)
ENTITLEMENTS = os.path.join(APPLE_DIR, "Word", "Word.entitlements")
SUFFIX = {"ios": ".ipa", "macos": ".pkg"}

# One entitlements file serves both platforms, but the App Sandbox keys are
# macOS-only: iOS apps are sandboxed unconditionally and Xcode drops them on
# the way in. Requiring them on iOS fails every correct build.
# com.apple.security.application-groups is the exception — it is real on both.
def macos_only(key):
    return (key.startswith("com.apple.security.")
            and key != "com.apple.security.application-groups")


def signed_entitlements(bundle):
    raw = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", bundle],
                         capture_output=True).stdout
    if not raw:
        return {}
    try:
        return plistlib.loads(raw)
    except Exception:
        return {}


def unpack(platform, export_dir, workdir):
    found = [f for f in sorted(os.listdir(export_dir)) if f.endswith(SUFFIX[platform])]
    if not found:
        sys.exit(f"No {SUFFIX[platform]} in {export_dir}.")
    artifact = os.path.join(export_dir, found[0])
    if platform == "ios":
        subprocess.run(["unzip", "-q", artifact, "-d", workdir], check=True)
        payload = os.path.join(workdir, "Payload")
        return os.path.join(payload, os.listdir(payload)[0]), found[0]
    out = os.path.join(workdir, "expanded")
    subprocess.run(["pkgutil", "--expand-full", artifact, out], check=True, capture_output=True)
    for root, dirs, _ in os.walk(out):
        for name in dirs:
            if name.endswith(".app"):
                return os.path.join(root, name), found[0]
    sys.exit(f"No .app inside {artifact}.")


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in SUFFIX:
        sys.exit("usage: verify-entitlements.py [ios|macos] <export-dir>")
    platform, export_dir = sys.argv[1], sys.argv[2]
    if not os.path.exists(ENTITLEMENTS):
        sys.exit(f"No {ENTITLEMENTS} — run `cd apple && xcodegen generate` first.")
    with open(ENTITLEMENTS, "rb") as handle:
        wanted = plistlib.load(handle)

    workdir = tempfile.mkdtemp(prefix="entitlements-")
    try:
        app, artifact = unpack(platform, export_dir, workdir)
        got = signed_entitlements(app)
        required = [k for k in wanted if not (platform == "ios" and macos_only(k))]
        missing = [key for key in required if key not in got]
        if missing:
            print(f"\n✗ {artifact} would ship without its capabilities:", file=sys.stderr)
            print(f"    {os.path.basename(app)}: missing {', '.join(sorted(missing))}",
                  file=sys.stderr)
            sys.exit(1)
        skipped = len(wanted) - len(required)
        note = f" ({skipped} macOS-only skipped)" if skipped else ""
        print(f"  ✓ {os.path.basename(app)}: {len(required)} entitlements present{note}")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
