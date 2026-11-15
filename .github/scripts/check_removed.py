#!/usr/bin/env python3
"""Fail if code for something the owner decided to remove comes back.

Each entry names what was removed, the patterns that mark its code, and the only files allowed to
contain them (tests that check the removal stays). Run from the repository root:

    python3 .github/scripts/check_removed.py
"""

import re
import subprocess
import sys

REMOVED = [
    {
        "what": "YouTube search (dropped 2026-11-12: \"Just drop the Youtube search\")",
        "patterns": [
            r"index=youtube",
            r"['\"]index['\"]\s*:\s*['\"]youtube['\"]",
            r"search_youtube",
            r"searchYouTube",
            r"youtube_search",
            r"YouTubeSearch",
            r"ytsearch",
            r"youtube_layout",
            r"YoutubeLayout",
            r"SearchProvider\.youtube",
            r"YouTubeChannelResult",
            r"YouTubeChannelPage",
            r'search_index\s*==\s*"youtube"',
            r'"youtube"\s*=>',
        ],
        # Tests that check the server refuses YouTube search.
        "allowed": {
            "rust-api/tests/integration/directory.rs",
        },
    },
]

# Where app code lives; everything a user or admin can reach is in here.
SCOPES = ["rust-api/src", "rust-api/tests", "web/src", "mobile/lib", "mobile/test", "rust-api/openapi.json"]


def tracked_files():
    out = subprocess.run(["git", "ls-files", "--", *SCOPES], capture_output=True, text=True, check=True)
    return [f for f in out.stdout.splitlines() if f]


def main():
    files = tracked_files()
    failures = []
    for item in REMOVED:
        regex = re.compile("|".join(f"(?:{p})" for p in item["patterns"]))
        for path in files:
            if path in item["allowed"]:
                continue
            try:
                text = open(path, encoding="utf-8").read()
            except (UnicodeDecodeError, FileNotFoundError):
                continue
            for n, line in enumerate(text.splitlines(), 1):
                if regex.search(line):
                    failures.append(f"{path}:{n}: {item['what']}\n    {line.strip()[:160]}")
    if failures:
        print("Code for something we removed is back:\n")
        print("\n".join(failures))
        return 1
    print(f"✓ Nothing we removed is back ({len(files)} files checked).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
