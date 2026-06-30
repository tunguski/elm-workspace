#!/usr/bin/env bash
#
# build.sh — compile the elm-workspace demo (a workspace managing plain-text notes) to a
# standalone HTML file.
#
# The elm.sh wrapper chdirs to the elm-lang repo root before running, so every path passed to
# `make` must be absolute (computed here after we cd into the script's own dir). Like the other
# elm-lang example apps, it type-checks cleanly (no --no-check).
#
#   ELM=../../elm.sh ./build.sh
#
set -euo pipefail
cd "$(dirname "$0")"

ELM="${ELM:-elm}"
OUT="build"
P="$(pwd)"

mkdir -p "$OUT"
echo "Compiling elm-workspace with: $ELM"
$ELM make "$P/src/Main.elm" --project="$P/elm.json" -o "$P/$OUT/elm-workspace.html"

# The compiler owns the output's <head> (charset + a generic title); post-process it: a viewport
# meta, the page title, the Bootstrap Icons link, then the shared site chrome (assets/site.css) and
# the app stylesheet (src/workspace.css) inlined so the page stays self-contained. Order of the
# inserts puts site.css before the app css, so the app css can override. Idempotent on re-runs.
HTML="$P/$OUT/elm-workspace.html"
TITLE="elm-workspace" SITECSS="$P/assets/site.css" CSSFILE="$P/src/workspace.css" perl -0pi -e '
  if (index($_, q{name="viewport"}) < 0) {
    s#<meta charset="utf-8">#<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">#;
  }
  s#<title>.*?</title>#"<title>".$ENV{TITLE}."</title>"#e;
  if (index($_, q{bootstrap-icons}) < 0) {
    s#</head>#<link rel="stylesheet" href="bootstrap-icons-1.11.3.css"></head>#;
  }
  if (index($_, q{id="wsite-css"}) < 0) {
    open(my $f, "<", $ENV{SITECSS}) or die "no site.css: $!";
    local $/; my $css = <$f>; close($f);
    s#</head>#"<style id=\"wsite-css\">".$css."</style></head>"#e;
  }
  if (index($_, q{id="ws-app-css"}) < 0) {
    open(my $f, "<", $ENV{CSSFILE}) or die "no workspace.css: $!";
    local $/; my $css = <$f>; close($f);
    s#</head>#"<style id=\"ws-app-css\">".$css."</style></head>"#e;
  }
' "$HTML"

# Bootstrap Icons are vendored (no CDN); ship the versioned css + woff2 next to the page.
cp "$P/assets/bootstrap-icons-1.11.3.css" "$P/assets/bootstrap-icons-1.11.3.woff2" "$P/assets/logo.svg" "$P/$OUT/"
echo "Done -> $OUT/elm-workspace.html"
