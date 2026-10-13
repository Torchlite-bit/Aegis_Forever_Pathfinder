"""
Builds the release GitHub publishes on every push to main (.github/workflows/release.yml), and
CurseForge gets: the addon folder alone in a zip, as the game loads it and addon managers
expect, and the release notes, from the CHANGELOG. Made after the Aegis: Forever Instance
Journal's own.

    python Tools/package.py dist

Writes dist/Aegis_Forever_Pathfinder-v<version>.zip, named with the TOC's version, and
dist/notes.md. The addon goes in without Tools/, docs/, data/ (the data players sent) or dist/,
and without dot-files. Every file the TOC lists must be there, or nothing is written.
"""

import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = "Aegis_Forever_Pathfinder"
TOC = os.path.join(ROOT, ADDON + ".toc")
REPOSITORY = "https://github.com/Torchlite-bit/Aegis_Pathfinder_Forever"
# Kept in the repository, not in the addon: the tools, the docs, the collected data, and
# built releases. (The same list as .gitattributes's export-ignore.)
LEFT_OUT = {"Tools", "docs", "data", "dist"}


def toc_version_and_files():
    version, files = None, []
    with open(TOC, encoding="utf-8") as toc:
        for line in toc:
            line = line.strip()
            match = re.match(r"##\s*Version:\s*(\S+)", line)
            if match:
                version = match.group(1)
            elif line and not line.startswith("#"):
                files.append(line.replace("\\", "/"))
    return version, files


def addon_files():
    """Every file of the addon as it is installed: relative paths, the folders above left out."""
    found = []
    for folder, subfolders, names in os.walk(ROOT):
        relative = os.path.relpath(folder, ROOT)
        if relative == ".":
            subfolders[:] = [name for name in subfolders if name not in LEFT_OUT and not name.startswith(".")]
        else:
            subfolders[:] = [name for name in subfolders if not name.startswith((".", "__"))]
        for name in names:
            if name.startswith(".") or name.endswith((".pyc", ".zip")):
                continue
            path = os.path.normpath(os.path.join(relative, name)).replace("\\", "/")
            found.append(path)
    return sorted(found)


def changelog_section(version):
    """The CHANGELOG's entry for a version, without its heading, or "" when it has none.
    Headings are "## 0.2.0 — a title" or "## [0.2.0]"."""
    path = os.path.join(ROOT, "CHANGELOG.md")
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    match = re.search(r"^## \[?" + re.escape(version) + r"(?![\w.])[^\n]*\n(.*?)(?=^---$|^## |\Z)",
                      text, re.M | re.S)
    return match.group(1).strip() if match else ""


def release(out, version, files):
    """The addon folder alone in the zip (what addon managers expect), and the release notes,
    from the CHANGELOG."""
    os.makedirs(out, exist_ok=True)
    target = os.path.join(out, "{}-v{}.zip".format(ADDON, version))
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as package:
        for path in files:
            package.write(os.path.join(ROOT, path), ADDON + "/" + path)
    notes = changelog_section(version) or "See the CHANGELOG."
    notes += ("\n\n### Install\nDownload `{0}-v{2}.zip` below (not *Source code*), unzip it, put the `{0}` folder in "
              "`World of Warcraft/_classic_beta_/Interface/AddOns/`, then restart the game fully.\n\n"
              "[Full changelog]({1}/blob/main/CHANGELOG.md) · "
              "[Send your data]({1}/blob/main/docs/data-submission.md) · [Discord](https://discord.gg/Hr66t25vE7)\n"
              ).format(ADDON, REPOSITORY, version)
    with open(os.path.join(out, "notes.md"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(notes)
    # For the release workflow (.github/workflows/release.yml): the version, as a step output.
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as handle:
            handle.write("version={}\n".format(version))
    print("Wrote {} ({} addon files, {:.1f} MB) and its notes".format(target, len(files), os.path.getsize(target) / 1024 / 1024))


def main():
    version, listed = toc_version_and_files()
    if not version:
        sys.exit("No ## Version in the TOC.")
    files = addon_files()
    missing = [path for path in listed if path not in files]
    if missing:
        sys.exit("The TOC lists files that are not there: " + ", ".join(missing))
    folders = [arg for arg in sys.argv[1:] if not arg.startswith("-")]
    release(folders[0] if folders else "dist", version, files)


if __name__ == "__main__":
    main()
