#!/usr/bin/env python3
"""Record the real answers the real-flow test replays: an Apple Podcasts search and the first
show's real feed (its three newest episodes). Run again to refresh them:

    python3 tests/real-flow/record.py

Addresses that would leave the test (the feed, the audio) are rewritten to {FIXTURES}, which the
fixture server replaces with its own address. Podcast Index answers can't be recorded without an
API key, so the test searches Apple.
"""

import json
import pathlib
import re
import subprocess
import tempfile
import urllib.parse
import urllib.request

TERM = "99% Invisible"
SHOW = "99% Invisible"
EPISODES = 3
HERE = pathlib.Path(__file__).resolve().parent
ANSWERS = HERE / "answers"
UA = {"User-Agent": "Castaway-real-flow-recorder"}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
        return r.read()


def main():
    ANSWERS.mkdir(exist_ok=True)
    query = urllib.parse.urlencode({"term": TERM, "media": "podcast", "entity": "podcast", "limit": 5})
    search = json.loads(get(f"https://itunes.apple.com/search?{query}"))
    results = search["results"]
    show = next(r for r in results if r.get("collectionName") == SHOW)
    real_feed = show["feedUrl"]
    for r in results:
        if r.get("feedUrl"):
            r["feedUrl"] = "{FIXTURES}/feeds/%d.xml" % r["collectionId"]
    (ANSWERS / "apple-search.json").write_text(json.dumps(search, indent=1, ensure_ascii=False) + "\n")

    feed = get(real_feed).decode("utf-8")
    items = re.findall(r"<item>.*?</item>", feed, flags=re.S)
    head = feed[: feed.index(items[0])]
    tail = feed[feed.index(items[-1]) + len(items[-1]) :]
    kept = []
    for n, item in enumerate(items[:EPISODES], 1):
        item = re.sub(r'(<enclosure[^>]*\burl=")[^"]*(")', r"\g<1>{FIXTURES}/audio/%d.mp3\g<2>" % n, item)
        kept.append(item)
    # Nothing that would send the server to the real feed instead.
    head = re.sub(r"<itunes:new-feed-url>.*?</itunes:new-feed-url>\s*", "", head, flags=re.S)
    head = re.sub(r'<atom:link[^>]*rel="self"[^>]*/>\s*', "", head)
    (ANSWERS / f"{show['collectionId']}.xml").write_text(head + "\n".join(kept) + tail)

    # A real, playable second of silence for the enclosures.
    with tempfile.TemporaryDirectory() as tmp:
        out = pathlib.Path(tmp) / "a.mp3"
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "anullsrc=r=22050:cl=mono", "-t", "1",
             "-q:a", "9", str(out)],
            check=True,
        )
        (ANSWERS / "audio.mp3").write_bytes(out.read_bytes())

    print(f"Recorded: Apple search for {TERM!r} ({len(results)} shows) and {EPISODES} episodes of {SHOW}.")


if __name__ == "__main__":
    main()
