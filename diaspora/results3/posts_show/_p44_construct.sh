#!/bin/bash
# P44 — run _p31_construct.py (or a variant) over a gaps file. Round-11 knobs.
#   usage: bash _p44_construct.sh <TAG> <GAPSJSON> [CONSTRUCTOR]
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
TAG="${1:?tag}"; GJ="${2:?gaps json}"; CON="${3:-$B/_p31_construct.py}"
L="$B/_p44_construct_${TAG}.log"
env P15_GAPS="$GJ" P18_INDEX="${P44_INDEX:-$B/_p31_index_P35C.pkl}" \
    PARTS_IN="${P44_PARTS:-$B/_p31_parts_P35C.json}" \
    BASES_PER_GAP="${BASES_PER_GAP:-2}" \
    P23_GROUP="${P23_GROUP:-set}" P23_HARD_SPLIT="${P23_HARD_SPLIT:-1}" \
    P31_PIN_HARD="${P31_PIN_HARD:-1}" P31_GATE_HARD="${P31_GATE_HARD:-1}" \
    P31_OWN_FIRST="${P31_OWN_FIRST:-0}" P31_GROUP_GATES="${P31_GROUP_GATES:-1}" \
    P31_PINREPORT="$B/_p44_pins_${TAG}.json" \
    P15_PREFIX="_p15_seeds${TAG}_" P15_PREFIXB="_p15_seeds${TAG}B_" \
    P23_LABEL_A="${TAG}" P23_LABEL_B="${TAG}B" \
    P15_MANIFEST="_p15_manifest_${TAG}.json" \
    PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= \
    python3 -u "$CON" > "$L" 2>&1
echo "rc=$? -> $L"
