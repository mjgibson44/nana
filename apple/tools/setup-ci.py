#!/usr/bin/env python3
"""Give the release workflow everything it needs to sign and upload a build.

Releasing from a laptop needs three things a GitHub runner doesn't have: an
Apple distribution certificate *with its private key*, an App Store Connect API
key, and the team id. This puts all of them into the repository's Actions
secrets, so `.github/workflows/release.yml` can archive and upload without a
human at a keyboard.

    ./apple/tools/setup-ci.py --dry-run   # report what exists, change nothing
    ./apple/tools/setup-ci.py             # create what's missing, set secrets

The certificate is created through the API rather than Xcode's UI, for the same
reason setup-gamecenter.py exists: a thing you click once is a thing nobody can
review or repeat. The private key is generated here and never leaves this
machine except as an encrypted secret — Apple only ever sees the CSR.

Re-runnable. An existing certificate is reused only if its private key is still
in apple/.release/ci, because a certificate without its key can't sign anything
and Apple will not hand the key back.
"""

import base64
import os
import secrets as randomness
import subprocess
import sys

import asc

DRY = "--dry-run" in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
APPLE_DIR = os.path.dirname(HERE)
ROOT = os.path.dirname(APPLE_DIR)
# Under .release, which is already gitignored as build output.
OUT = os.path.join(APPLE_DIR, ".release", "ci")
# LibreSSL, deliberately: its PKCS#12 defaults are what `security import` on a
# runner accepts without the -legacy dance OpenSSL 3 needs.
OPENSSL = "/usr/bin/openssl"
PASSWORD_FILE = os.path.join(OUT, "distribution.password")


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout


def flag(name, default=None):
    """--name value, off the command line."""
    if name in sys.argv:
        return sys.argv[sys.argv.index(name) + 1]
    return default


def team_id():
    """The team the app signs under: --team, or apple/Local.xcconfig."""
    given = flag("--team")
    if given:
        return given
    config = os.path.join(APPLE_DIR, "Local.xcconfig")
    if os.path.exists(config):
        for line in open(config):
            if line.strip().startswith("WORD_DEVELOPMENT_TEAM"):
                value = line.partition("=")[2].strip()
                if value:
                    return value
    sys.exit("No team id. Put it in apple/Local.xcconfig or pass --team YP8F3MJ2Y3.")


def repository():
    try:
        return run("gh", "repo", "view", "--json", "nameWithOwner",
                   "--jq", ".nameWithOwner", cwd=ROOT).strip()
    except subprocess.CalledProcessError:
        sys.exit("`gh repo view` failed — run `gh auth login` first.")


def certificates():
    found = []
    for item in asc.pages("/v1/certificates?filter[certificateType]=DISTRIBUTION&limit=200"):
        attributes = item["attributes"]
        found.append((item["id"], attributes.get("displayName", "?"),
                      attributes.get("expirationDate", "?")[:10]))
    return found


def make_certificate():
    """A fresh key pair, a CSR Apple signs, and the .p12 the runner imports."""
    os.makedirs(OUT, exist_ok=True)
    key = os.path.join(OUT, "distribution.key.pem")
    csr = os.path.join(OUT, "distribution.csr.pem")
    crt = os.path.join(OUT, "distribution.cer.pem")
    p12 = os.path.join(OUT, "distribution.p12")

    run(OPENSSL, "req", "-new", "-newkey", "rsa:2048", "-nodes",
        "-keyout", key, "-out", csr, "-subj", "/CN=Time Tiles release/C=US")
    made = asc.call("POST", "/v1/certificates", {
        "data": {"type": "certificates",
                 "attributes": {"certificateType": "DISTRIBUTION",
                                "csrContent": open(csr).read()}}})
    if not made:
        print("\nApple refused the certificate. The usual reason is the limit of "
              "three\ndistribution certificates — revoke an unused one in App Store "
              "Connect\n(Certificates, Identifiers & Profiles) and run this again. "
              "Existing:")
        for identifier, name, expires in certificates():
            print(f"    {name}  expires {expires}  ({identifier})")
        sys.exit(1)

    der = base64.b64decode(made["data"]["attributes"]["certificateContent"])
    with open(crt + ".der", "wb") as handle:
        handle.write(der)
    run(OPENSSL, "x509", "-inform", "DER", "-in", crt + ".der", "-out", crt)
    password = randomness.token_urlsafe(18)
    run(OPENSSL, "pkcs12", "-export", "-inkey", key, "-in", crt,
        "-name", "Time Tiles release", "-out", p12, "-passout", f"pass:{password}")
    # Kept beside the .p12 so a re-run can set the secrets again without
    # issuing a second certificate against the limit of three.
    with open(PASSWORD_FILE, "w") as handle:
        handle.write(password)
    for path in (p12, key, PASSWORD_FILE):
        os.chmod(path, 0o600)
    print(f"  + created a distribution certificate; key and .p12 kept in {OUT}")
    return p12, password


def secret(name, value):
    print(f"  → {name}")
    if DRY:
        return
    subprocess.run(["gh", "secret", "set", name], cwd=ROOT, input=value,
                   text=True, check=True, capture_output=True)


def main():
    key_id, issuer = asc.credentials()
    if not key_id or not issuer:
        sys.exit("No App Store Connect credentials — see apple/Local.env.")
    key_file = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8")
    if not os.path.exists(key_file):
        sys.exit(f"No {key_file}. The .p8 downloads exactly once; if it's lost, "
                 "revoke the key and issue another.")

    team = team_id()
    repo = repository()
    print(f"{repo} · team {team} · key {key_id}")

    print("\nDistribution certificate")
    have = certificates()
    for identifier, name, expires in have:
        print(f"  = {name}  expires {expires}  ({identifier})")
    kept = os.path.join(OUT, "distribution.p12")
    if os.path.exists(kept):
        password = flag("--p12-password")
        if not password and os.path.exists(PASSWORD_FILE):
            password = open(PASSWORD_FILE).read().strip()
        if not password:
            sys.exit(f"Found {kept} but not its password. Pass --p12-password, "
                     f"or delete {OUT} to issue a fresh certificate.")
        print(f"  = reusing {kept}")
        p12 = kept
    elif DRY:
        print("  + would create one (a key pair here, a CSR Apple signs)")
        p12, password = None, None
    else:
        p12, password = make_certificate()

    print("\nSecrets")
    secret("APPLE_TEAM_ID", team)
    secret("ASC_KEY_ID", key_id)
    secret("ASC_ISSUER_ID", issuer)
    secret("ASC_KEY_P8", base64.b64encode(open(key_file, "rb").read()).decode())
    if p12:
        secret("APPLE_DIST_CERT_P12", base64.b64encode(open(p12, "rb").read()).decode())
        secret("APPLE_DIST_CERT_PASSWORD", password)
    elif DRY:
        print("  → APPLE_DIST_CERT_P12\n  → APPLE_DIST_CERT_PASSWORD")

    print("\nDone." if not DRY else "\nDry run — nothing created, nothing set.")
    print("Merges to main that touch apple/ now build and upload to TestFlight.")


main()
