#!/usr/bin/env bash
# Unit tests (tests/unit/test_*.gd). Exit 0 = all pass.
source "$(dirname "$0")/_godot.sh"
cd "$ROOT"
out="$(godot_q --headless --path . res://tests/run_tests.tscn)"
echo "$out"
echo "$out" | grep -q 'TEST_RESULT ok=true'
