"""
Reads a "Submit collected data" issue (.github/ISSUE_TEMPLATE/submit-data.yml)
and adds the data in it to the repository, through Tools/ingest.py.

The GitHub Action .github/workflows/ingest-data.yml runs it. Everything comes
in through the environment:

  ISSUE_NUMBER       the issue
  ISSUE_BODY_FILE    a file holding its text: the form's answers, as Markdown
                     (or ISSUE_BODY, the text itself)
  ISSUE_USER         the GitHub login of whoever opened it
  REPO_ROOT          the repository checkout to write into
  GITHUB_REPOSITORY  owner/repo, for the repository's own attachment links
  SUMMARY_PATH       where to write the answer for the issue, as Markdown
  GITHUB_OUTPUT      (set by Actions) gets stored=, changed= and credit=

It finds share codes and exports pasted in the issue, and files attached to it
(GitHub's own attachment links only), reads them, stores them and makes the
merged data and the credits again.

Exit status: 0 when at least one collection was taken in, 2 when nothing
usable was found (the answer says how to fix it), 1 when something went wrong
here.
"""

import os
import re
import sys
import traceback
import urllib.error
import urllib.parse
import urllib.request

TOOLS = os.path.dirname(os.path.abspath(__file__))
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)

import ingest  # noqa: E402

CREDIT_FIELD = "Credit me as"
NO_RESPONSE = "_No response_"
MAX_ATTACHMENTS = 10
DOWNLOAD_TIMEOUT = 30
# Downloads may only be sent on to these hosts (and their subdomains), over https.
ALLOWED_HOSTS = ("github.com", "githubusercontent.com")

_HEADING = re.compile(r"^###[ \t]+(.+?)[ \t]*$", re.M)
# A link in the text, up to where Markdown would end it.
_LINK = re.compile(r"https?://[^\s<>()\[\]\"'`]+")


##########################################################################################
# The issue's text
##########################################################################################

def parse_form(body):
    """The issue form's answers, { heading = answer }. An answer left empty
    ("_No response_") is "". When a heading appears twice, the first stands:
    that is the form's own, above anything typed into a later answer."""
    answers = {}
    headings = list(_HEADING.finditer(body or ""))
    for index, match in enumerate(headings):
        end = headings[index + 1].start() if index + 1 < len(headings) else len(body)
        answer = body[match.end():end].strip()
        answers.setdefault(match.group(1).strip().casefold(), "" if answer == NO_RESPONSE else answer)
    return answers


def credit_from_form(body):
    return ingest.clean_name(parse_form(body).get(CREDIT_FIELD.casefold(), ""))


def attachment_urls(body, repository=None):
    """The links to files attached to the issue: github.com/user-attachments/files/...,
    or the repository's own github.com/<owner>/<repo>/files/... Nothing else is fetched."""
    allowed = [re.compile(r"https://github\.com/user-attachments/files/\d+/[^\s)]+")]
    if repository and re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        owner, repo = repository.split("/")
        allowed.append(re.compile(r"https://github\.com/%s/%s/files/\d+/[^\s)]+" % (re.escape(owner), re.escape(repo))))
    urls = []
    for match in _LINK.finditer(body or ""):
        url = match.group(0)
        if any(pattern.fullmatch(url) for pattern in allowed) and url not in urls:
            urls.append(url)
    return urls[:MAX_ATTACHMENTS]


def file_name(url):
    return urllib.parse.unquote(urllib.parse.urlsplit(url).path.rsplit("/", 1)[-1]) or "attachment"


##########################################################################################
# Downloading an attachment
##########################################################################################

def allowed_host(url):
    parts = urllib.parse.urlsplit(url)
    host = (parts.hostname or "").lower().rstrip(".")
    return parts.scheme == "https" and any(host == name or host.endswith("." + name) for name in ALLOWED_HOSTS)


class _GitHubRedirectsOnly(urllib.request.HTTPRedirectHandler):
    """Follows a redirect only to GitHub's own hosts, over https: attachments
    are sent on to githubusercontent.com to download."""
    max_redirections = 5

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not allowed_host(newurl):
            raise urllib.error.HTTPError(newurl, code, "sent on to a host that isn't GitHub's", headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url):
    """The attachment's bytes, at most 25 MB. Raises ingest.IngestError."""
    if not allowed_host(url):
        raise ingest.IngestError("it isn't a GitHub attachment.")
    opener = urllib.request.build_opener(_GitHubRedirectsOnly)
    request = urllib.request.Request(url, headers={"User-Agent": "Aegis-Pathfinder-data-ingest"})
    try:
        with opener.open(request, timeout=DOWNLOAD_TIMEOUT) as response:
            if not allowed_host(response.geturl()):
                raise ingest.IngestError("it was sent on to a host that isn't GitHub's.")
            length = response.headers.get("Content-Length") or ""
            if re.fullmatch(r"[0-9]{1,15}", length) and int(length) > ingest.MAX_INPUT:
                raise ingest.IngestError("it is bigger than 25 MB.")
            content = response.read(ingest.MAX_INPUT + 1)
    except ingest.IngestError:
        raise
    except urllib.error.HTTPError as error:
        raise ingest.IngestError("it could not be downloaded (%s)." % error.code)
    except (urllib.error.URLError, OSError, ValueError) as error:
        raise ingest.IngestError("it could not be downloaded (%s)." % type(error).__name__)
    if len(content) > ingest.MAX_INPUT:
        raise ingest.IngestError("it is bigger than 25 MB.")
    return content


##########################################################################################
# Reading the issue and answering it
##########################################################################################

RESULT_WORDS = {
    "new": "Added",
    "replaced": "Added: a newer copy of a collection we had",
    "unchanged": "We already had this exact copy",
    "older": "We already have a newer copy of this collection, so kept that one",
    "taken": "Not added: this collection was first sent from another GitHub account",
}

HELP = """**How to send your data**

1. **Share code (easiest).** In game, click **Submit data** in the data
   collection window (or type `/apg submit`). Copy the share code it shows
   (Ctrl+C; if it isn't selected, click in the box and press Ctrl+A first) and
   paste it into the issue. It starts with `APF1:` and is one long line of letters.
2. **Or the data file.** After `/reload` (or logging out), it is at
   `WTF/Account/<your account>/SavedVariables/Aegis_Forever_Pathfinder.lua`.
   GitHub doesn't take `.lua` files: rename it to `.txt` (or zip it), then
   drag it into the issue.

**Edit this issue** (the ⋯ menu on your post, then *Edit*) to add the code or the file, and it is read again."""

INTERNAL_ERROR = """**Something went wrong on our side while reading this submission.**

Nothing is wrong with what you did; a maintainer will look at it. There's nothing more you need to do."""


def _summary(results, problems, credit_names):
    taken = [(submission, stored) for submission, stored in results if stored.status in ingest.ACCEPTED]
    lines = []
    if taken:
        changed = any(stored.status in ingest.CHANGED for _, stored in taken)
        lines.append("**Thanks for sending your data!**" if changed else "**Thanks! We already had this data.**")
        lines.append("")
        lines += ["| From | Collection | Quests | Levels | |", "|---|---|---:|---:|---|"]
        for submission, stored in results:
            origin = submission.kind if submission.origin == "text" else \
                "%s (%s)" % (ingest.markdown_escape(submission.origin), submission.kind)
            lines.append("| %s | `%s` | %d | %d | %s |" % (
                origin, stored.id[:12], stored.quests, stored.levels, RESULT_WORDS[stored.status]))
        lines.append("")
        if credit_names:
            lines.append("You are credited as **%s**." % ", ".join(ingest.markdown_escape(name)
                                                                  for name in credit_names))
        if changed:
            lines += ["", "It is now on the `data-submissions` branch and goes into the guides when that "
                          "branch's pull request is merged. Send your data again any time: the newest "
                          "copy of a collection replaces the old one, so nothing is counted twice."]
    else:
        lines.append("**We couldn't find any Pathfinder data we could use in this issue.**")
    if problems:
        lines += ["", "**Problems**", ""]
        lines += ["- " + _sentence(problem) for problem in problems]
    if not taken:
        lines += ["", HELP]
    return "\n".join(lines) + "\n"


def _sentence(problem):
    # File names in problems came from the player: escaped for Markdown.
    return ingest.markdown_escape(problem)


def run(environ):
    """(exit status, the answer for the issue, outputs for the workflow)."""
    body = environ.get("ISSUE_BODY") or ""
    if environ.get("ISSUE_BODY_FILE"):
        # The workflow fetches the issue into a file: an issue can be too long for one variable.
        with open(environ["ISSUE_BODY_FILE"], encoding="utf-8", errors="replace") as handle:
            body = handle.read(ingest.MAX_INPUT + 1)
    body = body.replace("\r\n", "\n")
    number = (environ.get("ISSUE_NUMBER") or "").strip()
    issue = int(number) if number.isdigit() else None
    login = ingest.clean_login(environ.get("ISSUE_USER"))
    root = environ.get("REPO_ROOT") or ingest.ROOT
    credit = credit_from_form(body)

    problems, found = [], []
    # Codes and exports pasted anywhere in the issue.
    found += ingest.decode(body, "The issue text", problems, report_empty=False)
    for url in attachment_urls(body, environ.get("GITHUB_REPOSITORY")):
        name = file_name(url)
        try:
            content = fetch(url)
        except ingest.IngestError as error:
            problems.append("%s: %s" % (name, error))
            continue
        found += ingest.decode(content, name, problems)
    if not found and not problems:
        problems.append("There is no share code, export or attached data file in the issue.")

    results = []
    for submission in found:
        label = submission.kind if submission.origin == "text" else submission.origin
        try:
            envelope = ingest.sanitize(submission.envelope)
            # Credit: the form's "Credit me as", else the name set in game, else the GitHub login.
            envelope["contributor"] = credit or envelope["contributor"] or ingest.clean_name(login)
            stored = ingest.store(envelope, root, {
                "kind": "github-issue", "via": submission.kind, "issue": issue, "github_login": login})
        except ingest.IngestError as error:
            problems.append("%s: %s" % (label, error))
            continue
        results.append((submission, stored))
        if stored.status == "taken":
            problems.append("%s: collection %s was first sent from another GitHub account, so it wasn't "
                            "replaced. If it is yours, say so here and a maintainer will sort it out."
                            % (label, stored.id[:12]))

    taken = [stored for _, stored in results if stored.status in ingest.ACCEPTED]
    changed = [stored for stored in taken if stored.status in ingest.CHANGED]
    if changed:
        ingest.rebuild(root)
    names = []
    for stored in taken:
        if stored.contributor and stored.contributor not in names:
            names.append(stored.contributor)
    outputs = {
        "stored": str(len(taken)),
        "changed": str(len(changed)),
        "credit": ", ".join(names)[:100] or (login or ""),
    }
    return (0 if taken else 2), _summary(results, problems, names), outputs


def _write_outputs(path, outputs):
    if not path:
        return
    with open(path, "a", encoding="utf-8") as handle:
        for key, value in outputs.items():
            # One line each: names are already free of line breaks; this makes sure.
            handle.write("%s=%s\n" % (key, re.sub(r"[\r\n]+", " ", value)))


def main(environ=None):
    environ = os.environ if environ is None else environ
    try:
        status, summary, outputs = run(environ)
    except Exception:  # noqa: BLE001 -- anything unexpected is reported, not hidden
        traceback.print_exc()
        status, summary, outputs = 1, INTERNAL_ERROR + "\n", {"stored": "0", "changed": "0", "credit": ""}
    if environ.get("SUMMARY_PATH"):
        with open(environ["SUMMARY_PATH"], "w", encoding="utf-8") as handle:
            handle.write(summary)
    _write_outputs(environ.get("GITHUB_OUTPUT"), outputs)
    print(summary)
    return status


if __name__ == "__main__":
    sys.exit(main())
