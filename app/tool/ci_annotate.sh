#!/usr/bin/env bash
# Runs a command; if it fails, repeats the important part of its output as a
# GitHub annotation, so the failure is readable from the PR's checks page.
#   tool/ci_annotate.sh "<title>" <pattern> -- <command...>
title="$1"; pattern="$2"; shift 3
"$@" 2>&1 | tee /tmp/ci_out.txt
code=${PIPESTATUS[0]}
if [ "$code" -ne 0 ]; then
  body=$(grep -E "$pattern" /tmp/ci_out.txt | head -150 | cut -c1-400)
  [ -z "$body" ] && body=$(tail -80 /tmp/ci_out.txt | cut -c1-400)
  body=${body//'%'/'%25'}; body=${body//$'\r'/}; body=${body//$'\n'/'%0A'}
  echo "::error title=${title}::${body}"
fi
exit "$code"
