#!/usr/bin/env bash
#
# build.sh — compile the elm-workspace demo (a workspace managing plain-text notes) to a
# standalone HTML file.
#
# The elm.sh wrapper chdirs to the elm-lang repo root before running, so every path passed to
# `make` must be absolute (computed here after we cd into the script's own dir). Like the other
# elm-lang example apps we compile with --no-check.
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
$ELM make "$P/src/Main.elm" --project="$P/elm.json" -o "$P/$OUT/elm-workspace.html" --no-check

# The compiler owns the output's <head>; add a viewport meta and inline src/workspace.css as a
# <style> so the page stays a single self-contained file (idempotent on re-runs).
HTML="$P/$OUT/elm-workspace.html"
CSSFILE="$P/src/workspace.css" perl -0pi -e '
  if (index($_, q{name="viewport"}) < 0) {
    s#<meta charset="utf-8">#<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">#;
  }
  if (index($_, q{bootstrap-icons}) < 0) {
    s#</head>#<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons\@1.11.3/font/bootstrap-icons.css"></head>#;
  }
  if (index($_, q{id="ws-app-css"}) < 0) {
    open(my $f, "<", $ENV{CSSFILE}) or die "no workspace.css: $!";
    local $/; my $css = <$f>; close($f);
    s#</head>#"<style id=\"ws-app-css\">".$css."</style></head>"#e;
  }
' "$HTML"
echo "Done -> $OUT/elm-workspace.html"
