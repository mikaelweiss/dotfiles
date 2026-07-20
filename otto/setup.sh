#!/bin/bash
# Provisions a repo with the labels otto uses as its state machine.
# Usage: setup.sh <owner/repo>
# Safe to re-run: labels that already exist are left untouched.
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <owner/repo>" >&2
    exit 1
fi
repo=$1

create_label() {
    local name=$1
    shift
    local out
    if out=$(gh label create "$name" --repo "$repo" "$@" 2>&1); then
        echo "created: $name"
    elif [[ $out == *"already exists"* ]]; then
        echo "exists:  $name"
    else
        echo "$out" >&2
        exit 1
    fi
}

create_label "AI Ready" --color 4cb782
create_label "status:ideating"
create_label "status:awaiting-answers"
create_label "status:spec-ready"
create_label "status:in-progress"
create_label "status:in-review"
create_label "status:needs-human"
create_label "priority:1"
create_label "priority:2"
create_label "priority:3"
create_label "priority:4"
