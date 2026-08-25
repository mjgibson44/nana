"""A small App Store Connect client, shared by the tools in this directory.

Two scripts here talk to the same API with the same credentials —
setup-gamecenter.py and next-build-number.py — and minting a JWT through altool
has enough sharp edges (the token comes back on stderr about half the time) to
be worth writing once.

Credentials come from the environment, falling back to apple/Local.env — the
gitignored file release.sh reads, so a shell that can upload can also run these.
"""

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "dev.nana.TimeTiles"

_TOKEN = None


def credentials():
    """(key id, issuer id), or (None, None) if they aren't configured."""
    here = os.path.dirname(os.path.abspath(__file__))
    local = os.path.join(os.path.dirname(here), "Local.env")
    env = {}
    if os.path.exists(local):
        with open(local) as handle:
            for line in handle:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    key, _, value = line.partition("=")
                    env[key.strip()] = value.strip()
    # An exported value wins over the file, so a one-off shell can override it.
    key_id = os.environ.get("ASC_KEY_ID") or env.get("ASC_KEY_ID")
    issuer = os.environ.get("ASC_ISSUER_ID") or env.get("ASC_ISSUER_ID")
    return (key_id or None, issuer or None)


def token():
    """A bearer token, or None if there are no credentials to mint one from."""
    global _TOKEN
    if _TOKEN:
        return _TOKEN
    key_id, issuer = credentials()
    if not key_id or not issuer:
        return None
    result = subprocess.run(
        ["xcrun", "altool", "--generate-jwt", "--apiKey", key_id, "--apiIssuer", issuer],
        capture_output=True, text=True)
    # altool writes the token to stdout or stderr depending on its mood.
    match = re.search(r"eyJ[A-Za-z0-9_.-]+", result.stdout + result.stderr)
    _TOKEN = match.group(0) if match else None
    return _TOKEN


def call(method, path, body=None):
    """Returns the decoded response, or None if the request was rejected."""
    bearer = token()
    if not bearer:
        sys.exit("could not mint an App Store Connect token — see apple/Local.env")
    request = urllib.request.Request(
        API + path, method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + bearer,
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = json.loads(error.read() or b"{}")
        for e in detail.get("errors", []):
            print(f"    ! {e.get('status')} {e.get('title')} — {e.get('detail')}")
        return None


def pages(path):
    """Yield every item across a paginated collection."""
    while path:
        result = call("GET", path)
        if not result:
            return
        for item in result.get("data", []):
            yield item
        path = (result.get("links") or {}).get("next", "").replace(API, "") or None


def app_id():
    """The App Store Connect id for BUNDLE_ID, or None if there's no record."""
    apps = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    if not apps or not apps.get("data"):
        return None
    return apps["data"][0]["id"]
