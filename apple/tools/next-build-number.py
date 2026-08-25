#!/usr/bin/env python3
"""Print the build number the next upload should carry.

The commit count is the base — it needs no maintenance and rises on its own.
What it isn't is *monotonic across history rewrites*: a squash merge collapses a
branch's commits into one, so the count on main can be lower than the count the
last build was archived at. #49 went up as build 60 from a 64-commit branch that
merged as main's 56th commit, which would have made the next four uploads
collide with builds already on App Store Connect.

So the count is a floor, not the answer: ask App Store Connect what it has
already seen and take whichever is higher. That is the number the rule is
actually about, it needs no constant to hand-maintain, and it is equally right
when building from a branch, after a rebase, or twice from the same commit.

    ./apple/tools/next-build-number.py             # the number, on stdout
    ./apple/tools/next-build-number.py --explain   # ...and how it got there

Without credentials it falls back to the commit count and says so — enough for
an export you're going to look at locally, and the upload would have failed on
the missing credentials anyway.
"""

import os
import subprocess
import sys

import asc

EXPLAIN = "--explain" in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))


def note(message):
    """Diagnostics go to stderr; stdout is the number and nothing else."""
    print(message, file=sys.stderr)


def commit_count():
    result = subprocess.run(
        ["git", "-C", HERE, "rev-list", "--count", "HEAD"],
        capture_output=True, text=True, check=True)
    return int(result.stdout.strip())


def highest_uploaded():
    """The largest build number App Store Connect holds, or None if unknown."""
    key_id, _ = asc.credentials()
    if not key_id:
        note("note: no App Store Connect credentials, so the build number is the")
        note("      commit count alone — see apple/Local.env.")
        return None
    apps = asc.call("GET", f"/v1/apps?filter[bundleId]={asc.BUNDLE_ID}")
    if apps is None:
        # Credentials that don't work is a different thing from credentials that
        # aren't there: falling back here would hand back a number we have every
        # reason to think is already taken.
        sys.exit("App Store Connect rejected the request, so the build number "
                 "can't be checked against it.")
    if not apps.get("data"):
        note(f"note: no app record for {asc.BUNDLE_ID} yet, so nothing to collide with.")
        return None
    app = apps["data"][0]["id"]
    highest = None
    for build in asc.pages(f"/v1/builds?filter[app]={app}&limit=200&fields[builds]=version"):
        version = (build.get("attributes") or {}).get("version") or ""
        # Ours are plain integers. Anything else predates this scheme or came
        # from Xcode's UI; it can't be incremented, so it doesn't set the floor.
        if version.isdigit():
            highest = max(highest or 0, int(version))
        else:
            note(f"note: ignoring non-numeric build number {version!r}.")
    return highest


def main():
    count = commit_count()
    highest = highest_uploaded()
    build = count if highest is None else max(count, highest + 1)
    if EXPLAIN:
        note(f"commit count: {count}")
        note(f"highest on App Store Connect: {highest if highest is not None else 'unknown'}")
        note(f"next build: {build}")
    elif highest is not None and build != count:
        note(f"note: commit count is {count}, but build {highest} is already uploaded — "
             f"using {build}.")
    print(build)


main()
