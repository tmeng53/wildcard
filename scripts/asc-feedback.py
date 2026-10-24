#!/usr/bin/env python3
"""Prints the newest TestFlight crash reports from App Store Connect, without anything personal.

Testers send these from TestFlight (screenshot → Share Beta Feedback, or "Share" after a crash).
The repo is public, so this prints only an allowlist of a submission's fields (never the tester's
name, email or comment) and, from each crash log, the exception and the crashed thread's frames.

Needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_APP_ID and ASC_KEY_PATH (the Admin key's .p8), and PyJWT
with cryptography. Optional: ASC_LIMIT (default 3).
https://developer.apple.com/documentation/appstoreconnectapi/betafeedbackcrashsubmission
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
# Submission fields safe to print in a public log.
SAFE_FIELDS = [
    "createdDate",
    "buildBundleId",
    "appPlatform",
    "devicePlatform",
    "deviceFamily",
    "deviceModel",
    "osVersion",
    "architecture",
    "connectionType",
    "appUptimeInMilliseconds",
]


def token() -> str:
    with open(os.environ["ASC_KEY_PATH"], encoding="utf-8") as key:
        now = int(time.time())
        return jwt.encode(
            {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
            key.read(),
            algorithm="ES256",
            headers={"kid": os.environ["ASC_KEY_ID"]},
        )


def get(path: str, auth: str) -> dict:
    request = urllib.request.Request(API + path, headers={"Authorization": f"Bearer {auth}"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def ips_summary(text: str) -> str | None:
    """A readable summary of an .ips crash report (a JSON header line, then a JSON body)."""
    header_line, _, rest = text.partition("\n")
    try:
        header = json.loads(header_line)
        body = json.loads(rest)
    except json.JSONDecodeError:
        return None
    images = body.get("usedImages", [])
    lines = [
        f"app: {header.get('app_version')} ({header.get('build_version')}) on {header.get('os_version')}",
        f"exception: {json.dumps(body.get('exception'))}",
        f"termination: {json.dumps(body.get('termination'))}",
    ]
    if body.get("asi"):
        lines.append(f"asi: {json.dumps(body['asi'], ensure_ascii=False)}")
    for thread in body.get("threads", []):
        if not thread.get("triggered"):
            continue
        lines.append(f"crashed thread: {thread.get('name') or thread.get('queue') or ''}")
        for index, frame in enumerate(thread.get("frames", [])):
            image = images[frame["imageIndex"]] if frame.get("imageIndex", -1) < len(images) else {}
            symbol = frame.get("symbol", "?")
            location = f" ({frame['sourceFile']}:{frame.get('sourceLine')})" if frame.get("sourceFile") else ""
            offset = f" +{frame.get('symbolLocation', frame.get('imageOffset'))}"
            lines.append(f"  {index:2} {image.get('name', '?'):28} {symbol}{offset}{location}")
    return "\n".join(lines)


def text_summary(text: str) -> str:
    """The exception and backtraces of a classic text crash report, without its identifiers."""
    keep = []
    started = False
    for line in text.splitlines():
        if line.startswith(("Exception Type", "Exception Codes", "Termination", "Triggered by", "Crashed Thread")):
            keep.append(line)
        if line.startswith("Thread ") and "Crashed" in line:
            started = True
        elif started and not line.strip():
            break
        if started:
            keep.append(line)
    return "\n".join(keep) or "(no crashed thread found in the log)"


def main() -> int:
    auth = token()
    limit = os.environ.get("ASC_LIMIT", "3")
    submissions = get(
        f"/apps/{os.environ['ASC_APP_ID']}/betaFeedbackCrashSubmissions?sort=-createdDate&limit={limit}", auth
    )
    if not submissions.get("data"):
        print("No crash submissions.")
    for submission in submissions.get("data", []):
        attributes = submission.get("attributes", {})
        print("=" * 100)
        for field in SAFE_FIELDS:
            if field in attributes:
                print(f"{field}: {attributes[field]}")
        try:
            log = get(f"/betaFeedbackCrashSubmissions/{submission['id']}/crashLog", auth)
        except urllib.error.HTTPError as error:
            print(f"crash log: HTTP {error.code}")
            continue
        text = (log.get("data") or {}).get("attributes", {}).get("logText") or ""
        print(ips_summary(text) or text_summary(text))
    return 0


if __name__ == "__main__":
    sys.exit(main())
