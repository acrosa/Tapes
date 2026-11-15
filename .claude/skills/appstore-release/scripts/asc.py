#!/usr/bin/env python3
"""App Store Connect API from the command line, with a team API key. Standard library and openssl only.

Set ASC_KEY_ID and ASC_ISSUER_ID. The key is read from ASC_KEY_PATH, or from
~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8. Never print the key or copy it into a project.

  asc.py GET  /v1/apps
  asc.py GET  "/v1/apps/<app>/appStoreVersions?limit=5"
  asc.py PATCH /v1/appStoreVersionLocalizations/<id> '{"data": {...}}'
  asc.py screenshots <appScreenshotSet id> 01.png 02.png ...     # upload, wait until accepted, print the new ids
  asc.py attach <appStoreVersion id> <build id>
  asc.py submit <app id> <appStoreVersion id>                    # sends the version to App Review: ask the user first

Also usable as a module: `from asc import call`.
"""
import base64, hashlib, json, os, subprocess, sys, time, urllib.error, urllib.request

HOST = "https://api.appstoreconnect.apple.com"


def token():
    kid, iss = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"]
    key = os.environ.get("ASC_KEY_PATH") or os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{kid}.p8")
    b64 = lambda x: base64.urlsafe_b64encode(x).rstrip(b"=")
    now = int(time.time())
    head = b64(json.dumps({"alg": "ES256", "kid": kid, "typ": "JWT"}).encode())
    body = b64(json.dumps({"iss": iss, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}).encode())
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key], input=head + b"." + body,
                         capture_output=True, check=True).stdout
    # openssl signs in DER; a JWT wants the two 32-byte numbers side by side.
    i = 3 if der[1] < 0x80 else 4
    rl = der[i]; r = der[i + 1:i + 1 + rl]
    j = i + 1 + rl + 1; sl = der[j]; s = der[j + 1:j + 1 + sl]
    raw = r.lstrip(b"\0").rjust(32, b"\0") + s.lstrip(b"\0").rjust(32, b"\0")
    return (head + b"." + body + b"." + b64(raw)).decode()


def call(method, path, body=None):
    """Returns the decoded response, or {"error": status, "body": text}."""
    url = path if path.startswith("http") else HOST + path
    request = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                     headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        data = urllib.request.urlopen(request).read()
        return json.loads(data) if data else {}
    except urllib.error.HTTPError as e:
        return {"error": e.code, "body": e.read().decode()}


def upload_screenshots(set_id, paths):
    """Adds the files to a screenshot set and waits for Apple to accept them. Existing ones are left alone."""
    ids = []
    for path in paths:
        data = open(path, "rb").read()
        made = call("POST", "/v1/appScreenshots", {"data": {
            "type": "appScreenshots",
            "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})
        if "error" in made:
            sys.exit(f"{path}: {made}")
        shot = made["data"]["id"]
        for op in made["data"]["attributes"]["uploadOperations"]:
            part = data[op["offset"]:op["offset"] + op["length"]]
            urllib.request.urlopen(urllib.request.Request(
                op["url"], method=op["method"], data=part,
                headers={h["name"]: h["value"] for h in op["requestHeaders"]})).read()
        done = call("PATCH", f"/v1/appScreenshots/{shot}", {"data": {
            "type": "appScreenshots", "id": shot,
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        if "error" in done:
            sys.exit(f"{path}: {done}")
        ids.append(shot)
    for _ in range(50):
        states = [call("GET", f"/v1/appScreenshots/{i}")["data"]["attributes"]["assetDeliveryState"] for i in ids]
        if any(s["state"] == "FAILED" for s in states):
            sys.exit(f"rejected: {states}")          # wrong dimensions show up here
        if all(s["state"] == "COMPLETE" for s in states):
            return ids
        time.sleep(6)
    sys.exit("still processing after five minutes")


def attach(version_id, build_id):
    return call("PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build", {"data": {"type": "builds", "id": build_id}})


def submit(app_id, version_id):
    made = call("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    if "error" in made:
        return made
    sub = made["data"]["id"]
    item = call("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub}},
                          "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
    if "error" in item:
        return item
    return call("PATCH", f"/v1/reviewSubmissions/{sub}", {"data": {
        "type": "reviewSubmissions", "id": sub, "attributes": {"submitted": True}}})


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    if a[0] == "screenshots":
        out = upload_screenshots(a[1], a[2:])
    elif a[0] == "attach":
        out = attach(a[1], a[2])
    elif a[0] == "submit":
        out = submit(a[1], a[2])
    else:
        out = call(a[0], a[1], json.loads(a[2]) if len(a) > 2 else None)
    print(json.dumps(out, indent=1))
