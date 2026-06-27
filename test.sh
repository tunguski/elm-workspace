#!/usr/bin/env bash
#
# test.sh — run the elm-workspace headless test suite. Everything the library does that matters
# (permissions, comment threading, the SQL query builder, the Table CSV/JSON codecs, JSON
# serialisation round-trips) is pure, so it is all checked headlessly.
#
# The elm.sh wrapper chdirs to the elm-lang repo root before running, so every path passed to
# the runner must be absolute (computed here after we cd into the script's own dir).
#
#   ELM=../../elm.sh ./test.sh
#
set -euo pipefail
cd "$(dirname "$0")"

ELM="${ELM:-elm}"
P="$(pwd)"

$ELM test "$P/test/WorkspaceTest.elm" \
  "$P/src/Workspace/Types.elm" "$P/src/Workspace/Permissions.elm" \
  "$P/src/Workspace/Comment.elm" "$P/src/Workspace/Db.elm" \
  "$P/src/Workspace/Table.elm" "$P/src/Workspace/Serialize.elm"
