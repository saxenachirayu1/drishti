#!/usr/bin/env bash
# Runs a command; if it fails, repeats the important part of its output as
# GitHub annotations, so the failure is readable from the PR's checks page.
#   tool/ci_annotate.sh "<title>" <pattern> -- <command...>
title="$1"; pattern="$2"; shift 3
"$@" 2>&1 | tee /tmp/ci_out.txt
code=${PIPESTATUS[0]}
emit() {
  local t="$1" body="$2"
  body=${body//'%'/'%25'}; body=${body//$'\r'/}; body=${body//$'\n'/'%0A'}
  echo "::error title=${t}::${body}"
}
if [ "$code" -ne 0 ]; then
  failed=$(grep -E "❌|\[E\]" /tmp/ci_out.txt | sed 's#.*/app/##' | awk '!seen[$0]++' | head -40)
  [ -n "$failed" ] && emit "$title: failing" "$failed"
  body=$(grep -E -A"${CONTEXT:-0}" "$pattern" /tmp/ci_out.txt | grep -v "^--$" | grep -v "hasSize\|When the exception was thrown\|was being processed" | cut -c1-300 | awk '!seen[$0]++' | head -${LINES_MAX:-120})
  [ -z "$body" ] && body=$(tail -80 /tmp/ci_out.txt | cut -c1-300)
  emit "$title" "$body"
fi
exit "$code"
