"""
Tests for the release tools that talk to other sites: Tools/discord_post.py. Nothing is sent:
the network call is replaced.

    python Tools/test_release.py
"""

import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import discord_post  # noqa: E402

HOOK = "https://discord.com/api/webhooks/123456789012345678/abcDEF-ghi_JKL"


class DiscordPost(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp(prefix="release-test-")
        open(os.path.join(self.folder, "Aegis_Forever_Pathfinder-v0.3.0.zip"), "wb").close()
        with open(os.path.join(self.folder, "notes.md"), "w", encoding="utf-8") as handle:
            handle.write("- **New installs start in Default.** @everyone look!\n")

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def run_main(self, env):
        out = io.StringIO()
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(sys, "argv", ["x", self.folder]), \
                contextlib.redirect_stdout(out):
            code = discord_post.main()
        return code, out.getvalue()

    def test_no_secret_posts_nothing(self):
        with mock.patch.object(discord_post, "post") as post:
            code, out = self.run_main({})
        self.assertEqual(code, 0)
        post.assert_not_called()
        self.assertIn("skipped", out)
        self.assertFalse(os.path.exists(os.path.join(self.folder, "discord.txt")))

    def test_posts_once_and_leaves_a_marker(self):
        with mock.patch.object(discord_post, "post", return_value="999") as post:
            code, out = self.run_main({"DISCORD_WEBHOOK_URL": HOOK})
        self.assertEqual(code, 0)
        webhook, body = post.call_args[0]
        self.assertEqual(webhook, HOOK)
        embed = body["embeds"][0]
        self.assertEqual(embed["title"], "Aegis: Pathfinder (Forever) v0.3.0")
        self.assertTrue(embed["url"].endswith("/releases/tag/v0.3.0"))
        self.assertIn("New installs start in Default", embed["description"])
        self.assertEqual(body["allowed_mentions"], {"parse": []}, "an @everyone in the notes pings no one")
        self.assertNotIn("content", body)
        with open(os.path.join(self.folder, "discord.txt"), encoding="utf-8") as handle:
            self.assertIn("999", handle.read())
        self.assertNotIn(HOOK, out, "the address is never printed")

    def test_a_role_is_mentioned_only_when_named(self):
        body = discord_post.message("0.3.0", "notes", role_id="4242")
        self.assertEqual(body["content"], "<@&4242>")
        self.assertEqual(body["allowed_mentions"], {"parse": [], "roles": ["4242"]})

    def test_long_notes_are_cut_with_a_link(self):
        body = discord_post.message("0.3.0", "x" * 6000)
        text = body["embeds"][0]["description"]
        self.assertLessEqual(len(text), discord_post.DESCRIPTION_MAX)
        self.assertIn("Read the rest", text)

    def test_a_wrong_address_is_refused_without_showing_it(self):
        secret = "https://example.com/not-a-hook/secret-part"
        with mock.patch.object(discord_post, "post") as post:
            with self.assertRaises(SystemExit) as stop:
                self.run_main({"DISCORD_WEBHOOK_URL": secret})
        post.assert_not_called()
        self.assertNotIn("secret-part", str(stop.exception.code))

    def test_the_request_has_the_user_agent_discord_wants(self):
        seen = {}

        class Answer(io.BytesIO):
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

        def fake_urlopen(req, timeout):
            seen["url"], seen["agent"] = req.full_url, req.get_header("User-agent")
            seen["body"] = json.loads(req.data.decode("utf-8"))
            return Answer(b'{"id": "77"}')

        with mock.patch("urllib.request.urlopen", fake_urlopen):
            self.assertEqual(discord_post.post(HOOK, {"embeds": []}), "77")
        self.assertTrue(seen["url"].endswith("?wait=true"))
        self.assertTrue(seen["agent"].startswith("DiscordBot ("))


if __name__ == "__main__":
    unittest.main(verbosity=1)
