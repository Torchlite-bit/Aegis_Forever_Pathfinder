"""
Uploads the release zip to CurseForge, for .github/workflows/release.yml. The Aegis: Forever
Instance Journal's own uploader, pointed at this addon.

    python Tools/curseforge_upload.py dist

Reads the zip and its notes from the folder (Tools/package.py writes both). Needs two
settings of the GitHub repository; without them it says so and does nothing:
  CF_API_KEY             a CurseForge API token (a repository secret)
  CURSEFORGE_PROJECT_ID  the project's id, from its CurseForge page (a repository variable)
Optional repository variables:
  CURSEFORGE_GAME_VERSION_IDS  game version ids, comma-separated, instead of looking them up
  CURSEFORGE_RELEASE_TYPE      release (the default), beta or alpha

The game version is WoW: Forever's: a version type or version named for Forever, the one
matching the TOC's ## Interface (16001 is 1.60.1) when there are several. On success it writes
<folder>/curseforge.txt with the new file's id, which the workflow keeps on the GitHub release
so a version is uploaded only once.
"""

import glob
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOC = os.path.join(ROOT, "Aegis_Forever_Pathfinder.toc")
API = "https://wow.curseforge.com/api"


def request(path, token, data=None, content_type=None):
    req = urllib.request.Request(API + path, data=data, headers={"X-Api-Token": token, "User-Agent": "aegis-release"})
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=300) as response:
            return json.loads(response.read().decode("utf-8") or "null")
    except urllib.error.HTTPError as error:
        sys.exit("CurseForge answered {} to {}: {}".format(error.code, path, error.read().decode("utf-8", "replace")))


def client_version():
    """The TOC's ## Interface as a game version: 16001 is 1.60.1."""
    with open(TOC, encoding="utf-8") as handle:
        interface = int(re.search(r"^## Interface:\s*(\d+)", handle.read(), re.M).group(1))
    return "{}.{}.{}".format(interface // 10000, interface // 100 % 100, interface % 100)


def forever_version_ids(token):
    chosen = os.environ.get("CURSEFORGE_GAME_VERSION_IDS", "").strip()
    if chosen:
        return [int(v) for v in chosen.split(",") if v.strip()]
    wanted = client_version()
    versions = request("/game/versions", token) or []
    try:
        types = request("/game/version-types", token) or []
    except SystemExit:
        types = []
    named = lambda entry: (str(entry.get("name", "")) + " " + str(entry.get("slug", ""))).lower()
    forever_types = {t["id"] for t in types if "forever" in named(t)}
    candidates = [v for v in versions if v.get("gameVersionTypeID") in forever_types]
    candidates = candidates or [v for v in versions if "forever" in named(v)]
    exact = [v for v in candidates if v.get("name") == wanted]
    if exact:
        return [exact[0]["id"]]
    if candidates:
        return [max(candidates, key=lambda v: v["id"])["id"]]
    exact = [v for v in versions if v.get("name") == wanted]
    if len(exact) == 1:
        return [exact[0]["id"]]
    print("No WoW: Forever game version found. Version types: "
          + ", ".join(sorted(str(t.get("name")) for t in types)))
    print("Versions named " + wanted + ": " + json.dumps(exact))
    sys.exit("Set the repository variable CURSEFORGE_GAME_VERSION_IDS to the right id.")


def multipart(fields, file_field, path):
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields.items():
        parts.append('--{}\r\nContent-Disposition: form-data; name="{}"\r\n\r\n{}\r\n'
                     .format(boundary, name, value).encode("utf-8"))
    with open(path, "rb") as handle:
        content = handle.read()
    parts.append('--{}\r\nContent-Disposition: form-data; name="{}"; filename="{}"\r\nContent-Type: application/zip\r\n\r\n'
                 .format(boundary, file_field, os.path.basename(path)).encode("utf-8") + content + b"\r\n")
    parts.append("--{}--\r\n".format(boundary).encode("utf-8"))
    return b"".join(parts), "multipart/form-data; boundary=" + boundary


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else "dist"
    token = os.environ.get("CF_API_KEY", "").strip()
    project = os.environ.get("CURSEFORGE_PROJECT_ID", "").strip()
    if not token or not project:
        print("CurseForge upload skipped: set the CF_API_KEY secret and the CURSEFORGE_PROJECT_ID variable to turn it on.")
        return 0
    zips = glob.glob(os.path.join(folder, "*.zip"))
    if len(zips) != 1:
        sys.exit("Expected one zip in {}, found {}.".format(folder, len(zips)))
    with open(os.path.join(folder, "notes.md"), encoding="utf-8") as handle:
        notes = handle.read()
    version = re.search(r"-v([^-]+)\.zip$", zips[0]).group(1)
    metadata = {
        "changelog": notes,
        "changelogType": "markdown",
        "displayName": "v" + version,
        "gameVersions": forever_version_ids(token),
        "releaseType": os.environ.get("CURSEFORGE_RELEASE_TYPE", "").strip() or "release",
    }
    body, content_type = multipart({"metadata": json.dumps(metadata)}, "file", zips[0])
    answer = request("/projects/{}/upload-file".format(project), token, body, content_type)
    file_id = answer.get("id") if isinstance(answer, dict) else answer
    with open(os.path.join(folder, "curseforge.txt"), "w", encoding="utf-8") as handle:
        handle.write("Uploaded to CurseForge as file {} (game versions {}).\n".format(file_id, metadata["gameVersions"]))
    print("Uploaded v{} to CurseForge: file {}.".format(version, file_id))
    return 0


if __name__ == "__main__":
    sys.exit(main())
