#!/usr/bin/env python3
"""Revokes the Apple Development certificates a TestFlight build's cloud signing just created.

Every build runs on a fresh machine, so Xcode's cloud signing makes a new Apple Development
certificate each time and nothing reuses it; the account's limit then fills up and archiving
fails ("maximum number of certificates"). testflight.yml runs this after the upload.

Run it twice. `snapshot FILE` writes the ids of the certificates that exist before the build.
`revoke FILE` revokes the certificates that are not in that file, and only those that are
development ones named "Created via API", which is how cloud signing names its own. The API gives
a certificate no creation time, so the snapshot is how "made by this build" is known.
Distribution certificates and ones made in Xcode are never touched. It prints each certificate's
type and name, never an id or a key.

Needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (the Admin key's .p8), and PyJWT with cryptography.
https://developer.apple.com/documentation/appstoreconnectapi/delete-a-certificate
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
DEVELOPMENT_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT"}
CLOUD_SIGNING_NAME = "Created via API"


def token() -> str:
    with open(os.environ["ASC_KEY_PATH"], encoding="utf-8") as key:
        now = int(time.time())
        return jwt.encode(
            {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
            key.read(),
            algorithm="ES256",
            headers={"kid": os.environ["ASC_KEY_ID"]},
        )


def call(method: str, path: str, auth: str) -> dict:
    request = urllib.request.Request(API + path, method=method, headers={"Authorization": f"Bearer {auth}"})
    with urllib.request.urlopen(request, timeout=60) as response:
        body = response.read()
        return json.loads(body) if body else {}


def certificates(auth: str) -> list[dict]:
    query = urllib.parse.urlencode({"limit": 200, "fields[certificates]": "certificateType,displayName,name"})
    return call("GET", f"/certificates?{query}", auth)["data"]


def snapshot(path: str) -> None:
    ids = [certificate["id"] for certificate in certificates(token())]
    with open(path, "w", encoding="utf-8") as file:
        json.dump(ids, file)
    print(f"{len(ids)} certificates exist before the build.")


def revoke(path: str) -> None:
    auth = token()
    with open(path, encoding="utf-8") as file:
        before = set(json.load(file))
    revoked = 0
    for certificate in certificates(auth):
        attributes = certificate["attributes"]
        name = attributes.get("displayName") or attributes.get("name") or ""
        kind = attributes.get("certificateType", "?")
        mine = certificate["id"] not in before and kind in DEVELOPMENT_TYPES and CLOUD_SIGNING_NAME in name
        print(f"{'revoke' if mine else 'keep  '} {kind} | {name}")
        if mine:
            call("DELETE", f"/certificates/{certificate['id']}", auth)
            revoked += 1
    print(f"Revoked {revoked}.")


if __name__ == "__main__":
    command, file_path = sys.argv[1], sys.argv[2]
    {"snapshot": snapshot, "revoke": revoke}[command](file_path)
