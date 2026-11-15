#!/usr/bin/env python3
"""Serves the recorded answers (answers/) in place of Apple Podcasts and the show's feed host.

    FIXTURE_BASE=http://rf-fixtures:8000 python3 fixture_server.py

Apple's /search and /lookup answer from the recorded search; /feeds/<id>.xml is a recorded feed;
/audio/<n>.mp3 is a second of silence. Every request is printed.
"""

import http.server
import json
import os
import pathlib
import re
import sys
import urllib.parse

ANSWERS = pathlib.Path(__file__).resolve().parent / "answers"
BASE = os.environ.get("FIXTURE_BASE", "http://127.0.0.1:8000").rstrip("/")


def text(name):
    return (ANSWERS / name).read_text().replace("{FIXTURES}", BASE)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        if url.path == "/search":
            return self.send(200, "application/json", text("apple-search.json"))
        if url.path == "/lookup":
            wanted = set(",".join(query.get("id", [""])).split(","))
            search = json.loads(text("apple-search.json"))
            found = [r for r in search["results"] if str(r.get("collectionId")) in wanted]
            return self.send(200, "application/json", json.dumps({"resultCount": len(found), "results": found}))
        m = re.fullmatch(r"/feeds/(\d+)\.xml", url.path)
        if m and (ANSWERS / f"{m.group(1)}.xml").exists():
            return self.send(200, "application/rss+xml; charset=utf-8", text(f"{m.group(1)}.xml"))
        if re.fullmatch(r"/audio/\d+\.mp3", url.path):
            return self.send(200, "audio/mpeg", (ANSWERS / "audio.mp3").read_bytes())
        self.send(404, "text/plain", f"no recorded answer for {url.path}")

    def send(self, status, content_type, body):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print("fixtures:", fmt % args, file=sys.stderr, flush=True)


if __name__ == "__main__":
    port = int(os.environ.get("FIXTURE_PORT", "8000"))
    http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
