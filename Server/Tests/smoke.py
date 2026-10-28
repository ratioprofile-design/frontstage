"""Exercise authentication, permissions, revision conflicts, idempotency and durable storage."""
import copy
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

root = Path(__file__).resolve().parents[1]
binary = root / ".build/debug/FrontstageServer"
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
base = f"http://127.0.0.1:{port}"


def request(path, method="GET", body=None, token=None, expected=200):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(base + path, data=json.dumps(body).encode() if body is not None else None, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(req, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    data = response.read()
    assert response.code == expected, (path, response.code, expected, data[:300])
    return json.loads(data) if data else None


with tempfile.TemporaryDirectory(prefix="frontstage-sync-test-") as directory:
    env = os.environ.copy()
    env["FRONTSTAGE_DATA_DIR"] = directory
    env["FRONTSTAGE_ALLOW_SIGNUP"] = "1"
    env["FRONTSTAGE_WEB_ORIGIN"] = "https://frontstage-five.vercel.app"
    log = open(Path(directory) / "server.log", "wb")

    def start():
        process = subprocess.Popen([str(binary), "serve", "--hostname", "127.0.0.1", "--port", str(port)], cwd=root, env=env, stdout=log, stderr=log)
        for _ in range(100):
            if process.poll() is not None:
                raise RuntimeError("Server exited during startup")
            try:
                request("/health")
                return process
            except urllib.error.URLError:
                time.sleep(0.1)
        raise RuntimeError("Server did not become ready")

    process = start()
    try:
        preflight = urllib.request.Request(base + "/api/projects", method="OPTIONS", headers={
            "Origin": "https://frontstage-five.vercel.app", "Access-Control-Request-Method": "PUT",
            "Access-Control-Request-Headers": "authorization,content-type"})
        with urllib.request.urlopen(preflight, timeout=20) as response:
            assert response.headers["Access-Control-Allow-Origin"] == "https://frontstage-five.vercel.app"
            assert "PUT" in response.headers["Access-Control-Allow-Methods"]
            assert "authorization" in response.headers["Access-Control-Allow-Headers"].lower()
        preflight.add_header("Origin", "https://unrelated.invalid")
        with urllib.request.urlopen(preflight, timeout=20) as response:
            assert response.headers["Access-Control-Allow-Origin"] != "https://unrelated.invalid"
        assert set(request("/health")["supportedFeatures"]) == {"elementTypography", "productionBaselines", "dualDialogue"}
        accounts = {}
        for name in ("owner", "editor", "reader"):
            credentials = {"username": name, "password": secrets.token_urlsafe(20)}
            result = request("/api/signup", "POST", credentials)
            accounts[name] = result["token"]
            assert request("/api/login", "POST", credentials)["username"] == name
        request("/api/projects", expected=401)
        document = {"format": "frontstage", "version": 1, "name": "Shared test", "project": {"beats": [{"id": 1, "title": "Cause", "content": "<p>தமிழ்</p>"}], "nextId": 2}}
        project = request("/api/projects", "POST", {"document": document}, accounts["owner"])
        path = "/api/projects/" + project["id"]
        request(path, token=accounts["editor"], expected=404)
        for name in ("editor", "reader"):
            request(path + "/members", "POST", {"username": name, "access": name}, accounts["owner"], expected=204)
        assert request(path, token=accounts["reader"])["access"] == "reader"
        change_id = str(uuid.uuid4())
        updated = copy.deepcopy(document)
        updated["name"] = "Owner edit"
        body = {"expectedRevision": 1, "changeID": change_id, "document": updated}
        result = request(path, "PUT", body, accounts["owner"])
        assert result["snapshot"]["revision"] == 2
        assert request(path, "PUT", body, accounts["owner"])["snapshot"]["revision"] == 2
        body["changeID"] = str(uuid.uuid4())
        conflict = request(path, "PUT", body, accounts["editor"], expected=409)
        assert conflict["conflict"] and conflict["snapshot"]["document"]["name"] == "Owner edit"
        request(path, "PUT", body, accounts["reader"], expected=403)
        request(path + "/members", "POST", {"username": "reader", "access": "editor"}, accounts["editor"], expected=403)
        invalid = copy.deepcopy(document)
        invalid["version"] = 900
        request("/api/projects", "POST", {"document": invalid}, accounts["owner"], expected=400)
        process.terminate()
        process.wait(timeout=20)
        process = start()
        assert request(path, token=accounts["owner"])["revision"] == 2
        request(path + "/members", "POST", {"username": "editor", "access": None}, accounts["owner"], expected=204)
        request(path, token=accounts["editor"], expected=404)
        featured = copy.deepcopy(document)
        featured["project"]["frontstageScriptLayout"] = {"fontName": "Courier", "fontSize": 12, "lineHeight": 14, "paragraphSpacing": 10, "elements": {"character": {"fontSize": 16, "isTamil": True}}}
        feature_project = request("/api/projects", "POST", {"document": featured}, accounts["owner"])
        feature_path = "/api/projects/" + feature_project["id"]
        payload = {"expectedRevision": 1, "changeID": str(uuid.uuid4()), "document": featured}
        request(feature_path, "PUT", payload, accounts["owner"], expected=400)
        payload["document"] = copy.deepcopy(document)
        request(feature_path, "PUT", payload, accounts["owner"], expected=400)
        payload["document"] = featured
        payload["supportedFeatures"] = ["elementTypography", "productionBaselines", "dualDialogue"]
        assert request(feature_path, "PUT", payload, accounts["owner"])["snapshot"]["revision"] == 2
        request("/api/logout", "POST", token=accounts["owner"], expected=204)
        request(path, token=accounts["owner"], expected=401)
        print("PASS: restricted browser origin, authentication, permissions, revisions, conflict rejection, retry idempotency, restart durability and logout")
    finally:
        process.terminate()
        process.wait(timeout=20)
        log.close()
