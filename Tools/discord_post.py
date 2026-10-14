"""
Posts a new version's changelog to Discord, for .github/workflows/release.yml: one message,
with a link to the GitHub release, in this addon's post in the releases forum (or in the
channel the webhook belongs to). The same script serves every Aegis addon: only the four
settings below differ.

    python Tools/discord_post.py dist

Reads the zip and its notes from the folder (Tools/package.py writes both). Needs the
DISCORD_WEBHOOK_URL repository secret (the channel's Integrations → Webhooks → Copy Webhook
URL); without it, it says so and does nothing. The address is a password for that channel: it
is never printed. Optional:
  DISCORD_THREAD_ID     this addon's post in the releases forum (right-click the post, Copy Link:
                        the last number). A forum webhook needs it.
  DISCORD_PING_ROLE_ID  a role to mention with the post (the addon's ping role); none by default
  RELEASE_URL           the release page to link (the workflow sets it)

On success it writes <folder>/discord.txt with the message's id, which the workflow keeps on the
GitHub release so a version is announced only once.
"""

import glob
import json
import os
import re
import sys
import urllib.error
import urllib.request

# This addon's settings.
TITLE = "Aegis: Pathfinder (Forever)"
USERNAME = "Aegis: Pathfinder"
REPOSITORY = "https://github.com/Torchlite-bit/Aegis_Pathfinder_Forever"
COLOUR = 0x2D7A18                 # Pathfinder green
DESCRIPTION_MAX = 4000            # Discord allows 4096 in an embed's description
WEBHOOK = re.compile(r"https://(?:ptb\.|canary\.)?discord(?:app)?\.com/api/(?:v\d+/)?webhooks/\d+/[\w-]+")


def message(version, notes, release_url=None, role_id=None):
    """The webhook's JSON: an embed with the changelog, and a role mention only when asked for."""
    url = release_url or "{}/releases/tag/v{}".format(REPOSITORY, version)
    text = notes.strip()
    if len(text) > DESCRIPTION_MAX:
        more = "\n\n… [Read the rest]({})".format(url)
        text = text[:DESCRIPTION_MAX - len(more)].rstrip() + more
    body = {
        "username": USERNAME,
        "embeds": [{
            "title": "{} v{}".format(TITLE, version),
            "url": url,
            "description": text,
            "color": COLOUR,
        }],
        # Nobody is mentioned unless a role is named: a changelog that says "@everyone" stays text.
        "allowed_mentions": {"parse": []},
    }
    if role_id:
        body["content"] = "<@&{}>".format(role_id)
        body["allowed_mentions"] = {"parse": [], "roles": [role_id]}
    return body


def post(webhook, body, thread_id=None):
    """Sends it (into the thread, when given: Discord reopens an archived one) and returns the
    new message's id. Errors never include the address."""
    target = webhook + "?wait=true" + ("&thread_id=" + thread_id if thread_id else "")
    req = urllib.request.Request(target, data=json.dumps(body).encode("utf-8"), headers={
        "Content-Type": "application/json",
        # Discord turns away requests without a User-Agent of this form.
        "User-Agent": "DiscordBot ({}, 1.0)".format(REPOSITORY),
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            answer = json.loads(response.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as error:
        answer = error.read().decode("utf-8", "replace")[:500]
        if error.code == 400 and not thread_id and "thread" in answer.lower():
            sys.exit("This webhook belongs to a forum: set the DISCORD_THREAD_ID variable to this addon's post.")
        sys.exit("Discord answered {}: {}".format(error.code, answer))
    except urllib.error.URLError as error:
        sys.exit("Discord couldn't be reached: {}".format(error.reason))
    return answer.get("id")


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else "dist"
    webhook = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
    if not webhook:
        print("Discord post skipped: no DISCORD_WEBHOOK_URL secret. (Settings, Secrets and variables, Actions.)")
        return 0
    if not WEBHOOK.fullmatch(webhook):
        sys.exit("DISCORD_WEBHOOK_URL doesn't look like a Discord webhook address (it isn't shown here). "
                 "Copy it again from the channel's Integrations, Webhooks.")
    thread_id = os.environ.get("DISCORD_THREAD_ID", "").strip() or None
    if thread_id and not thread_id.isdigit():
        sys.exit("DISCORD_THREAD_ID should be the post's number (right-click the post, Copy Link: the last number).")
    role_id = os.environ.get("DISCORD_PING_ROLE_ID", "").strip() or None
    if role_id and not role_id.isdigit():
        sys.exit("DISCORD_PING_ROLE_ID should be the role's number (right-click the role, Copy Role ID).")
    zips = glob.glob(os.path.join(folder, "*.zip"))
    if len(zips) != 1:
        sys.exit("Expected one zip in {}, found {}.".format(folder, len(zips)))
    version = re.search(r"-v([^-]+)\.zip$", zips[0]).group(1)
    with open(os.path.join(folder, "notes.md"), encoding="utf-8") as handle:
        notes = handle.read()
    message_id = post(webhook, message(version, notes, os.environ.get("RELEASE_URL") or None, role_id), thread_id)
    with open(os.path.join(folder, "discord.txt"), "w", encoding="utf-8") as handle:
        handle.write("Posted to Discord as message {}.\n".format(message_id))
    print("Posted v{} to Discord: message {}.".format(version, message_id))
    return 0


if __name__ == "__main__":
    sys.exit(main())
