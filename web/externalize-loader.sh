#!/bin/sh
# Moves the module loader Trunk writes inline into dist/index.html into its own file, so the page
# needs no inline script and the server's Content-Security-Policy can say script-src 'self'.
# Run after `trunk build`:  sh externalize-loader.sh <dist folder>
set -eu
dist="${1:?usage: externalize-loader.sh <dist folder>}"
index="$dist/index.html"
loader="$dist/app-loader.tmp.js"
page="$dist/index.html.tmp"

awk -v loader="$loader" '
  function finish(text,   i) {
    i = index(text, "</script>")
    if (i == 0) { print text > loader; return 0 }
    printf "%s", substr(text, 1, i - 1) > loader
    printf "%s", "<script type=\"module\" src=\"__CASTAWAY_LOADER__\"></script>" substr(text, i + 9) "\n"
    found = 1
    return 1
  }
  inside { if (finish($0)) inside = 0; next }
  !found && (start = index($0, "<script type=\"module\">")) {
    printf "%s", substr($0, 1, start - 1)
    if (!finish(substr($0, start + 22))) inside = 1
    next
  }
  { print }
  END { if (!found) exit 3 }
' "$index" > "$page" || { echo "externalize-loader: no inline module loader found in $index" >&2; exit 1; }

name="app-loader-$(cksum < "$loader" | cut -d' ' -f1).js"
mv "$loader" "$dist/$name"
sed "s|__CASTAWAY_LOADER__|/$name|" "$page" > "$index"
rm -f "$page"
if grep -q '<script[^>]*>[^<[:space:]]' "$index"; then
  echo "externalize-loader: $index still has an inline script" >&2
  exit 1
fi
echo "externalize-loader: moved the loader to $name"
