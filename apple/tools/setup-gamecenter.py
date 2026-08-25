#!/usr/bin/env python3
"""Create Time Tiles' Game Center configuration in App Store Connect.

The plan (§12) wants this config reviewable in the repo rather than clicked
into a web form, and it has to stay in lockstep with the identifiers the app
submits against — `LeaderboardID`, `AchievementID` and
`Matchmaking.battleActivityID`. A drifted identifier doesn't fail loudly; the
score just silently never appears.

Idempotent: anything already present is left alone, so it's safe to re-run
after adding a leaderboard or an achievement.

    ./apple/tools/setup-gamecenter.py            # create what's missing
    ./apple/tools/setup-gamecenter.py --dry-run  # just report

Credentials come from apple/Local.env via asc.py, same as release.sh.
"""

import datetime
import sys

import asc
from asc import call

DRY = "--dry-run" in sys.argv

# --- The battle activity (Matchmaking.battleActivityID) ----------------------

ACTIVITY = {
    "id": "battle",
    "name": "Battle",
    "description": "Free-for-all. Last one standing wins.",
    "min": 2,   # BATTLE_MIN_PLAYERS
    "max": 8,   # BATTLE_MAX_PLAYERS
}

# --- Leaderboards (LeaderboardID) -------------------------------------------
#
# The Daily Deal board is RECURRING, and its start instant must agree with
# DailyRules.resetHourUTC. If they disagree, two players in different time
# zones can submit different puzzles into the same occurrence — the exact bug
# plan §8.2 says to pin rather than discover.

DAILY_RESET_HOUR_UTC = 8  # keep in step with DailyRules.resetHourUTC

LEADERBOARDS = [
    {"id": "solo.regular", "name": "Solo — Regular", "ref": "Solo Regular"},
    {"id": "solo.fast", "name": "Solo — Fast", "ref": "Solo Fast"},
    {
        "id": "daily.deal",
        "name": "Daily Deal",
        "ref": "Daily Deal",
        "recurring": True,
    },
    {"id": "battle.wins", "name": "Battle Wins", "ref": "Battle Wins"},
]

# --- Achievements (AchievementID) -------------------------------------------
#
# Points must total <= 1000 across at most 100 achievements. Fifteen at
# varying weights, leaning heavier on the ones that take a while.

ACHIEVEMENTS = [
    ("first.solo", "First Deal", "Finish your first Solo game.", 10),
    ("tutorial.done", "Shown the Ropes", "Finish the tutorial.", 10),
    ("gap.tile", "Borrowed Letter", "Play a word through a gap tile.", 20),
    ("word.eight", "Eight Across", "Place an eight-letter word.", 40),
    ("pile.clearer", "Clean Sweep", "Clear the board 3 times in one Solo game.", 50),
    ("comeback", "Dug Out", "Come back from over the limit in Solo.", 30),
    ("fast.500", "Quick Study", "Score 500 in Solo Fast.", 50),
    ("games.100", "Regular", "Finish 100 games.", 100),
    ("daily.week", "Seven Days", "Play 7 Daily Deals in a row.", 75),
    ("battle.first", "Last One Standing", "Win a battle.", 40),
    ("battle.backtoback", "Back to Back", "Win two battles in a row.", 60),
    ("battle.fullfield", "Full House", "Win a battle with a full field of 8.", 75),
    ("battle.finalround", "Down to Two", "Survive to a battle's final round.", 30),
    ("battle.clean", "Never Flustered", "Win a battle without ever passing 15 pile tiles.", 60),
    ("battle.attack", "Heavy Weather", "Send 25 attack tiles in one game.", 50),
]


def main():
    app_id = asc.app_id()
    if not app_id:
        sys.exit(f"no app record for {asc.BUNDLE_ID}")

    detail = call("GET", f"/v1/apps/{app_id}/gameCenterDetail")
    if not detail or not detail.get("data"):
        print("Game Center not enabled; enabling")
        if DRY:
            return
        detail = call("POST", "/v1/gameCenterDetails", {
            "data": {"type": "gameCenterDetails",
                     "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    gc = detail["data"]["id"]
    print(f"app {app_id} · gameCenterDetail {gc}")

    ensure_activity(gc)
    ensure_leaderboards(gc)
    ensure_achievements(gc)


def existing(gc, kind, key="vendorIdentifier"):
    found = {}
    for item in asc.pages(f"/v1/gameCenterDetails/{gc}/{kind}?limit=200"):
        found[item["attributes"][key]] = item["id"]
    return found


def ensure_activity(gc):
    print("\nActivity")
    have = existing(gc, "gameCenterActivities")
    if ACTIVITY["id"] in have:
        print(f"  = {ACTIVITY['id']}")
        return
    print(f"  + {ACTIVITY['id']}")
    if DRY:
        return
    made = call("POST", "/v1/gameCenterActivities", {
        "data": {"type": "gameCenterActivities",
                 "attributes": {
                     "referenceName": ACTIVITY["name"],
                     "vendorIdentifier": ACTIVITY["id"],
                     "playStyle": "SYNCHRONOUS",
                     "minimumPlayersCount": ACTIVITY["min"],
                     "maximumPlayersCount": ACTIVITY["max"],
                     "supportsPartyCode": True},
                 "relationships": {
                     "gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": gc}}}}})
    if not made:
        return
    version = call("POST", "/v1/gameCenterActivityVersions", {
        "data": {"type": "gameCenterActivityVersions",
                 "relationships": {"activity": {
                     "data": {"type": "gameCenterActivities", "id": made["data"]["id"]}}}}})
    if version:
        call("POST", "/v1/gameCenterActivityLocalizations", {
            "data": {"type": "gameCenterActivityLocalizations",
                     "attributes": {"locale": "en-US", "name": ACTIVITY["name"],
                                    "description": ACTIVITY["description"]},
                     "relationships": {"version": {
                         "data": {"type": "gameCenterActivityVersions",
                                  "id": version["data"]["id"]}}}}})


def ensure_leaderboards(gc):
    print("\nLeaderboards")
    have = existing(gc, "gameCenterLeaderboards")
    for board in LEADERBOARDS:
        if board["id"] in have:
            print(f"  = {board['id']}")
            continue
        print(f"  + {board['id']}" + ("  (recurring, 24h)" if board.get("recurring") else ""))
        if DRY:
            continue
        attributes = {
            "referenceName": board["ref"],
            "vendorIdentifier": board["id"],
            "submissionType": "BEST_SCORE",
            "scoreSortType": "DESC",
            "defaultFormatter": "INTEGER",
        }
        if board.get("recurring"):
            # Anchored to the same instant the seed rolls over on.
            # The start has to be in the future, so anchor on the *next* reset
            # rather than a fixed date. What matters for correctness is that
            # occurrences fall on the reset hour, which every future one does.
            now = datetime.datetime.now(datetime.timezone.utc)
            start = now.replace(
                hour=DAILY_RESET_HOUR_UTC, minute=0, second=0, microsecond=0)
            if start <= now:
                start += datetime.timedelta(days=1)
            attributes["recurrenceStartDate"] = start.strftime("%Y-%m-%dT%H:%M:%SZ")
            # Hours, not days: App Store Connect rejects "P1D" and wants an
            # ISO 8601 duration carrying time components.
            attributes["recurrenceDuration"] = "PT24H"
            # And the rule is an RRULE, not a duration.
            attributes["recurrenceRule"] = "FREQ=DAILY;INTERVAL=1"
        made = call("POST", "/v1/gameCenterLeaderboards", {
            "data": {"type": "gameCenterLeaderboards", "attributes": attributes,
                     "relationships": {"gameCenterDetail": {
                         "data": {"type": "gameCenterDetails", "id": gc}}}}})
        if made:
            call("POST", "/v1/gameCenterLeaderboardLocalizations", {
                "data": {"type": "gameCenterLeaderboardLocalizations",
                         "attributes": {"locale": "en-US", "name": board["name"]},
                         "relationships": {"gameCenterLeaderboard": {
                             "data": {"type": "gameCenterLeaderboards",
                                      "id": made["data"]["id"]}}}}})


def ensure_achievements(gc):
    total = sum(points for *_, points in ACHIEVEMENTS)
    print(f"\nAchievements ({len(ACHIEVEMENTS)}, {total} points)")
    assert total <= 1000, "Game Center caps achievement points at 1000"
    have = existing(gc, "gameCenterAchievements")
    for identifier, name, description, points in ACHIEVEMENTS:
        if identifier in have:
            print(f"  = {identifier}")
            continue
        print(f"  + {identifier}  ({points})")
        if DRY:
            continue
        made = call("POST", "/v1/gameCenterAchievements", {
            "data": {"type": "gameCenterAchievements",
                     "attributes": {"referenceName": name, "vendorIdentifier": identifier,
                                    "points": points, "showBeforeEarned": True,
                                    "repeatable": False},
                     "relationships": {"gameCenterDetail": {
                         "data": {"type": "gameCenterDetails", "id": gc}}}}})
        if made:
            call("POST", "/v1/gameCenterAchievementLocalizations", {
                "data": {"type": "gameCenterAchievementLocalizations",
                         "attributes": {"locale": "en-US", "name": name,
                                        "beforeEarnedDescription": description,
                                        "afterEarnedDescription": description},
                         "relationships": {"gameCenterAchievement": {
                             "data": {"type": "gameCenterAchievements",
                                      "id": made["data"]["id"]}}}}})


main()
