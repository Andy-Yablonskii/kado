#!/usr/bin/env python3
"""Makes sure the personal build has an App Store Connect app and an internal
TestFlight group "Andy" that receives every build. Run by Scripts/ship-andy.sh,
which loads ASC_KEY_ID, ASC_ISSUER_ID and ASC_TESTER_ID from ~/.appstoreconnect/kado.env."""
import base64, json, subprocess, sys, time, urllib.request, os
KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
KEY = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b"=")
def der_to_raw(der):
    # parse ECDSA DER signature into R||S (32 bytes each)
    i = 2
    if der[1] & 0x80: i += der[1] & 0x7f
    assert der[i] == 2; rl = der[i+1]; r = der[i+2:i+2+rl]; i += 2 + rl
    assert der[i] == 2; sl = der[i+1]; s = der[i+2:i+2+sl]
    return r.lstrip(b"\0").rjust(32, b"\0") + s.lstrip(b"\0").rjust(32, b"\0")
def token():
    h = b64(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    now = int(time.time())
    p = b64(json.dumps({"iss": ISSUER, "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"}).encode())
    msg = h + b"." + p
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY], input=msg, capture_output=True, check=True).stdout
    return (msg + b"." + b64(der_to_raw(der))).decode()
BUNDLE_ID = "com.andyyablonskii.kado"
GROUP_NAME = "Andy"
# Andy's tester record, already in the "Andy" group of his other apps.
TESTER_ID = os.environ["ASC_TESTER_ID"]

def call(method, path, body=None):
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=json.dumps(body).encode() if body else None, method=method,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        text = r.read().decode()
        return json.loads(text) if text else {}

apps = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"]
if not apps:
    sys.exit(f"No App Store Connect app for {BUNDLE_ID} yet. Create it at appstoreconnect.apple.com "
             "(Apps > + > New App) and run this again.")
app_id = apps[0]["id"]
groups = call("GET", f"/v1/apps/{app_id}/betaGroups")["data"]
group = next((g for g in groups if g["attributes"]["name"] == GROUP_NAME), None)
if group is None:
    group = call("POST", "/v1/betaGroups", {"data": {
        "type": "betaGroups",
        "attributes": {"name": GROUP_NAME, "isInternalGroup": True, "hasAccessToAllBuilds": True},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    print(f"Created internal TestFlight group {GROUP_NAME}.")
testers = call("GET", f"/v1/betaGroups/{group['id']}/betaTesters")["data"]
if not any(t["id"] == TESTER_ID for t in testers):
    call("POST", f"/v1/betaGroups/{group['id']}/relationships/betaTesters",
         {"data": [{"type": "betaTesters", "id": TESTER_ID}]})
    print("Added Andy to the group.")
print(f"App {app_id} ready; group {GROUP_NAME} gets every build.")
