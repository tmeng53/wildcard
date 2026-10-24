#!/usr/bin/env python3
"""Revokes the Apple Development certificates a TestFlight build's cloud signing just created.

Every build runs on a fresh machine, so Xcode's cloud signing makes a new Apple Development
certificate each time and nothing reuses it; the account's limit then fills up and archiving
fails ("maximum number of certificates"). testflight.yml runs this after the upload.

It revokes only a certificate that is a development one, was created at or after ASC_SINCE (an
ISO time a few minutes before the build began) and is named "Created via API", which is how cloud
signing names its own. Distribution certificates and ones made in Xcode on someone's Mac are
never touched. It prints each certificate's type, name and time, never an id or a key.

Needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (the Admin key's .p8), ASC_SINCE, and PyJWT with
cryptography.
https://developer.apple.com/documentation/appstoreconnectapi/delete-a-certificate
"""

import json
import os
import time
import urllib.parse
import urllib.request
from datetime import datetime

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


def parse(time_text: str) -> datetime:
    return datetime.fromisoformat(time_text.replace("Z", "+00:00"))


def main() -> None:
    auth = token()
    since = parse(os.environ["ASC_SINCE"])
    query = urllib.parse.urlencode({"limit": 200, "fields[certificates]": "certificateType,displayName,name,createdDate"})
    certificates = call("GET", f"/certificates?{query}", auth)["data"]
    print(f"{len(certificates)} certificates in the account; revoking only new cloud-signing ones.")
    revoked = 0
    for certificate in certificates:
        attributes = certificate["attributes"]
        name = attributes.get("displayName") or attributes.get("name") or ""
        created = attributes.get("createdDate")
        kind = attributes.get("certificateType", "?")
        mine = (
            kind in DEVELOPMENT_TYPES
            and CLOUD_SIGNING_NAME in name
            and created is not None
            and parse(created) >= since
        )
        print(f"{'revoke' if mine else 'keep  '} {kind} | {name} | {created}")
        if mine:
            call("DELETE", f"/certificates/{certificate['id']}", auth)
            revoked += 1
    print(f"Revoked {revoked}.")


if __name__ == "__main__":
    main()
