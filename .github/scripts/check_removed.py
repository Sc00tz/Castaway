#!/usr/bin/env python3
"""Fail if something the owner decided to remove comes back.

Each rule names what was removed (with the decision), the patterns that mark it, where to look,
and what is allowed to keep them (credit lines, tests that check the removal, historical
migrations). Run from the repository root:

    python3 .github/scripts/check_removed.py
"""

import fnmatch
import re
import subprocess
import sys

APP_CODE = ["rust-api/src/**", "web/src/**", "web/src-tauri/**", "mobile/lib/**", "mobile/android/**", "mobile/ios/**"]
CODE_EXT = (".rs", ".dart", ".kt", ".java", ".swift", ".m", ".js", ".mjs", ".ts")

RULES = [
    {
        "what": "YouTube search (2026-11-12: \"Just drop the Youtube search\")",
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
        "where": APP_CODE + ["rust-api/tests/**", "mobile/test/**", "rust-api/openapi.json"],
        # The server test that checks YouTube search is refused.
        "allowed_files": ["rust-api/tests/integration/directory.rs"],
    },
    {
        "what": "Rewriting http:// addresses to https:// on the phone (2026-11-15: \"fix the forcehttps thing\")",
        "patterns": [r"forceHttps", r"replace\(scheme: 'https'\)"],
        "where": ["mobile/lib/**", "mobile/test/**"],
    },
    {
        "what": "MySQL, MariaDB or SQLite (2026-11-13: \"Lets go with Postgres only\" / \"GET IT THE FUCK OUT OF THERE\")",
        "patterns": [r"(?i)mysql", r"(?i)mariadb", r"(?i)sqlite"],
        "where": ["**"],
        "allowed_files": [
            "*.lock",
            "**/*.lock",
            ".github/scripts/check_removed.py",
            # On the cleanup list: the iOS project links the system SQLite library (from AnyTime).
            "mobile/ios/Runner.xcodeproj/project.pbxproj",
            # The README's comparison with PinePods says what Castaway dropped.
            "README.md",
        ],
    },
    {
        "what": "PinePods' online services (2026-11-13: \"WE'RE NOT USING PINEPODS' DATA/SITES\")",
        "patterns": [
            r"(?i)pinepods\.online",
            r"(?i)podping",
            r"(?i)podpeople",
            r"(?i)buymeacoffee",
            r"(?i)discord\.(gg|com)",
            r"(?i)docker\.io/madeofpendletonwool",
            r"(?i)madeofpendletonwool/(pinepods-|i18n)",
        ],
        "where": ["**"],
        "allowed_files": [
            ".github/scripts/check_removed.py",
            # Migrations that dropped them (they run on old databases and are never shown).
            "rust-api/migrations/*",
            # The README's comparison with PinePods says what Castaway doesn't use.
            "README.md",
            "rust-api/src/database/migrate.rs",
        ],
    },
    {
        "what": "The PinePods name where a user or admin can see it (2026-11-14: \"Pinepods should never, ever, "
        "EVER, show up in a place that a user or admin will see it. In the code is fine, but not in any "
        "interface, setting, config file, or url.\")",
        "patterns": [r"(?i)pinepods"],
        # Everything people can see: app code's text strings, translations, settings and config files,
        # the API description, the image's startup files and the GitHub workflows (release names).
        "where": APP_CODE
        + [
            "web/index.html",
            "web/*.toml",
            "web/*.json",
            "rust-api/openapi.json",
            "rust-api/Cargo.toml",
            "docker-compose.yml",
            "dockerfile",
            "startup/**",
            ".github/workflows/**",
        ],
        # In app code, only text strings count: names and comments in the code are fine.
        "code_strings_only": True,
        # "References to what we forked is fine." (2026-11-14)
        "allowed_lines": [r"(?i)based on (the )?(\[|\*\*)?pinepods", r"(?i)built on the pinepods"],
        "allowed_files": ["rust-api/src/database/migrate.rs"],
    },
]

STRING = re.compile(r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'")
# Rust format arguments name code, not text: "{PINEPODS_FINAL_VERSION}" prints a number.
FORMAT_ARG = re.compile(r"\{[A-Z0-9_]+\}")


def scoped(pattern):
    """A pattern as its own group; a leading (?i) applies to that pattern only."""
    return f"(?i:{pattern[4:]})" if pattern.startswith("(?i)") else f"(?:{pattern})"


def tracked_files():
    out = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True)
    return [f for f in out.stdout.splitlines() if f]


def matches(path, globs):
    return any(fnmatch.fnmatchcase(path, g) or (g.endswith("/**") and path.startswith(g[:-2])) for g in globs)


def main():
    files = tracked_files()
    failures = []
    for rule in RULES:
        regex = re.compile("|".join(scoped(p) for p in rule["patterns"]))
        allowed_lines = [re.compile(p) for p in rule.get("allowed_lines", [])]
        for path in files:
            if not matches(path, rule["where"]) or matches(path, rule.get("allowed_files", [])):
                continue
            try:
                text = open(path, encoding="utf-8").read()
            except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
                continue
            strings_only = rule.get("code_strings_only") and path.endswith(CODE_EXT)
            for n, line in enumerate(text.splitlines(), 1):
                if any(a.search(line) for a in allowed_lines):
                    continue
                haystack = " ".join(FORMAT_ARG.sub("", s) for s in STRING.findall(line)) if strings_only else line
                if regex.search(haystack):
                    failures.append(f"{path}:{n}: {rule['what']}\n    {line.strip()[:160]}")
    if failures:
        print("Something we removed is back:\n")
        print("\n".join(failures))
        return 1
    print(f"✓ Nothing we removed is back ({len(RULES)} rules, {len(files)} files checked).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
