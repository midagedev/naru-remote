#!/usr/bin/env bash
#
# Every document this project points at should exist.
#
# The documentation here cross-references by name in prose — docs/BRANDING.md §7,
# `specs/034-pip-framing/spec.md` — rather than by markdown link, so nothing
# renders as a broken link when a file moves. It just quietly stops being true,
# which is the failure mode this catches: on 2026-08-27 the repository went
# public with ten root documents, four of them naming a file that had been
# superseded or a section that had moved.
#
# Historical records are excluded on purpose. `artifacts/` and `scratch/` are
# dated snapshots of what was measured or believed at a moment; rewriting a
# path inside one to keep this script quiet would be falsifying the record.
#
# Usage: scripts/check-doc-links.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# The living documentation: what a reader or an agent is told to trust.
# Built with a plain loop rather than `mapfile`, which macOS's bash 3.2 —
# the one every contributor on a Mac has by default — does not have.
documents_file="$(mktemp)"
trap 'rm -f "$documents_file"' EXIT
git ls-files '*.md' | grep -Ev '^(artifacts|scratch)/' > "$documents_file"

failures=0
checked=0

while IFS= read -r document; do
    [ -n "$document" ] || continue
    # Backticked references that look like a repository path ending in .md.
    # `-o` prints one per line; the sed strips the backticks.
    while IFS= read -r reference; do
        [ -n "$reference" ] || continue
        checked=$((checked + 1))

        # Resolve relative to the repository root first, then to the
        # referring document's own directory — both spellings appear.
        if [ -f "$reference" ]; then
            continue
        fi
        if [ -f "$(dirname "$document")/$reference" ]; then
            continue
        fi

        # A leading slash is repository-root-relative in this documentation.
        if [ -f "${reference#/}" ]; then
            continue
        fi

        case "$reference" in
            # `specs/<n>-<slug>/spec.md` written as a pattern rather than a
            # path is a description of a convention, not a reference to a file.
            *'<'*'>'*) continue ;;

            # A bare conventional name — `spec.md`, `tasks.md` — means "the one
            # belonging to the feature under discussion", which is a role and
            # not a path. Only the qualified spelling is checkable.
            spec.md|plan.md|tasks.md|data-model.md|research.md|quickstart.md|design.md|requirements.md)
                continue ;;

            # Absolute paths outside the working tree: a scratch file, a
            # reviewer's machine, an agent's memory store. Not ours to resolve.
            /tmp/*|/Users/*|/var/*|/etc/*|/private/*) continue ;;

            # `artifacts/` holds generated records, and a task that says
            # "record PASS/FAIL in artifacts/…" is naming where its output goes,
            # not claiming the output exists. Those are open tasks, and an open
            # task with no record yet is the correct state, not a broken link.
            artifacts/*) continue ;;
        esac

        printf '%s: references a document that does not exist: %s\n' \
            "$document" "$reference" >&2
        failures=$((failures + 1))
    done < <(
        grep -oE '`\.?/?[A-Za-z0-9_./<>-]+\.md`' "$document" 2>/dev/null \
        | sed -e 's/^`//' -e 's/`$//' -e 's#^\./##' \
        | sort -u
    )
done < "$documents_file"

if [ "$failures" -gt 0 ]; then
    printf '\n%d broken document reference(s) across %d checked.\n' \
        "$failures" "$checked" >&2
    exit 1
fi

printf 'All %d document references resolve.\n' "$checked"
