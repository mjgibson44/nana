#!/usr/bin/env python3
"""Make sure an App Store provisioning profile exists for the app, paired with
the distribution certificate in this machine's keychain, and install it where
Xcode looks. Prints the profile's name, for release.sh's ExportOptions.

    ./apple/tools/ensure-profile.py ios

Why this exists: `xcodebuild -exportArchive` under *automatic* signing with an
App Store Connect API key reaches for Apple's cloud-managed distribution
certificate, and gives up — "Cloud signing permission error" — when the key
isn't allowed one. It then looks for an App Store profile to fall back on,
finds none (Xcode never made one, because it was busy failing at cloud
signing), and the export dies. That is how the first CI release died.

Manual signing sidesteps cloud signing altogether: the certificate is the one
release.yml imports into the runner's keychain, and this script finds — or
creates — the profile that pairs it with the app's bundle id, downloads it, and
hands its name over. Re-runnable: a valid profile carrying the right
certificate is reused, and a stale or invalid one is replaced.
"""

import base64
import hashlib
import os
import subprocess
import sys
import urllib.parse

import asc

PROFILE_NAME = "Time Tiles App Store (CI)"
PROFILE_TYPES = {"ios": "IOS_APP_STORE", "macos": "MAC_APP_STORE"}
# Xcode 16 reads the second; older tooling (and altool) the first. Both are
# cheap to write.
INSTALL_DIRS = [
    os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles"),
    os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles"),
]


def keychain_fingerprints():
    """SHA-1s of every signing identity in the keychain, as `security` prints
    them — the only handle we have on which certificate the runner can use."""
    result = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True, text=True)
    found = set()
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0].endswith(")") and len(parts[1]) == 40:
            found.add(parts[1].upper())
    return found


def distribution_certificate():
    """The App Store Connect id of the distribution certificate whose private
    key is in this keychain. There may be up to three in the team; only the
    one we can sign with is any use."""
    local = keychain_fingerprints()
    seen = []
    for item in asc.pages("/v1/certificates?filter[certificateType]=DISTRIBUTION&limit=200"):
        der = base64.b64decode(item["attributes"]["certificateContent"])
        fingerprint = hashlib.sha1(der).hexdigest().upper()
        seen.append((item["attributes"].get("displayName", "?"), fingerprint))
        if fingerprint in local:
            return item["id"]
    print("No distribution certificate in the keychain matches one in the team.", file=sys.stderr)
    print(f"  keychain: {sorted(local) or 'none'}", file=sys.stderr)
    for name, fingerprint in seen:
        print(f"  team:     {name} {fingerprint}", file=sys.stderr)
    sys.exit(1)


def bundle_identifier():
    found = asc.call(
        "GET", f"/v1/bundleIds?filter[identifier]={urllib.parse.quote(asc.BUNDLE_ID)}")
    for item in (found or {}).get("data", []):
        if item["attributes"].get("identifier") == asc.BUNDLE_ID:
            return item["id"]
    sys.exit(f"No bundle id {asc.BUNDLE_ID} is registered in the team.")


def related_ids(profile_id, relationship):
    found = asc.call("GET", f"/v1/profiles/{profile_id}/relationships/{relationship}")
    data = (found or {}).get("data")
    if isinstance(data, list):
        return {item["id"] for item in data}
    return {data["id"]} if data else set()


def usable(profile, certificate_id, bundle_id):
    attributes = profile["attributes"]
    if attributes.get("profileState") != "ACTIVE":
        return False
    return (certificate_id in related_ids(profile["id"], "certificates")
            and bundle_id in related_ids(profile["id"], "bundleId"))


def ensure(platform):
    profile_type = PROFILE_TYPES[platform]
    certificate_id = distribution_certificate()
    bundle_id = bundle_identifier()

    query = (f"/v1/profiles?filter[profileType]={profile_type}"
             f"&filter[name]={urllib.parse.quote(PROFILE_NAME)}&limit=200")
    for candidate in list(asc.pages(query)):
        if usable(candidate, certificate_id, bundle_id):
            return candidate
        # Expired, revoked, or bound to a certificate we can't sign with.
        print(f"  - replacing profile {candidate['id']} ({candidate['attributes'].get('profileState')})",
              file=sys.stderr)
        asc.call("DELETE", f"/v1/profiles/{candidate['id']}")

    made = asc.call("POST", "/v1/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": profile_type},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
            },
        }
    })
    if not made:
        sys.exit("Apple refused to create the provisioning profile.")
    print(f"  + created profile {made['data']['id']}", file=sys.stderr)
    return made["data"]


def install(profile):
    content = base64.b64decode(profile["attributes"]["profileContent"])
    name = f"{profile['attributes']['uuid']}.mobileprovision"
    for directory in INSTALL_DIRS:
        os.makedirs(directory, exist_ok=True)
        path = os.path.join(directory, name)
        with open(path, "wb") as handle:
            handle.write(content)
        os.chmod(path, 0o600)


def main():
    platform = sys.argv[1] if len(sys.argv) > 1 else "ios"
    if platform not in PROFILE_TYPES:
        sys.exit("usage: ensure-profile.py [ios|macos]")
    profile = ensure(platform)
    install(profile)
    print(profile["attributes"]["name"])


if __name__ == "__main__":
    main()
