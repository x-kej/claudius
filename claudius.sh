#!/bin/bash
SCRIPT_DIR="$(dirname "$0")"
WEIGHTS="$SCRIPT_DIR/weights.csv"
PERSONAS="$SCRIPT_DIR/personas"
COMMON="$SCRIPT_DIR/common.md"
readonly SCRIPT_DIR WEIGHTS PERSONAS COMMON

# Load existing weights, dropping entries whose persona file no longer exists
names=()
prefs=()
weights=()
if [[ -f "$WEIGHTS" ]]; then
    while IFS=, read -r name preference weight; do
        [[ -n "$name" && -f "$PERSONAS/$name" ]] || continue
        names+=("$name")
        prefs+=("$preference")
        weights+=("$weight")
    done < "$WEIGHTS"
fi

# Add any new persona files not already tracked, at preference 1, weight 1
for f in "$PERSONAS"/*.md; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f")
    found=0
    for existing in "${names[@]}"; do
        [[ "$existing" == "$name" ]] && { found=1; break; }
    done
    if [[ "$found" -eq 0 ]]; then
        names+=("$name")
        prefs+=(1)
        weights+=(1)
    fi
done

# Weighted random pick
total=0
for w in "${weights[@]}"; do
    total=$((total + w))
done

chosen=""
if ((total > 0)); then
    r=$(((RANDOM * 32768 + RANDOM) % total))
    running=0
    for i in "${!names[@]}"; do
        running=$((running + weights[i]))
        if ((running > r)); then
            chosen="${names[i]}"
            break
        fi
    done
fi

# Write weights.csv once: reset chosen to its preference, increment all others by their preference
tmp=$(mktemp "$WEIGHTS.XXXXXX")
{
    for i in "${!names[@]}"; do
        name="${names[i]}"
        preference="${prefs[i]}"
        weight="${weights[i]}"
        if [[ "$name" == "$chosen" ]]; then
            echo "$name,$preference,$preference"
        elif [[ "$weight" -eq 0 ]]; then
            echo "$name,$preference,0"
        else
            echo "$name,$preference,$((weight + preference))"
        fi
    done
} > "$tmp" && mv "$tmp" "$WEIGHTS"

cat "$COMMON"
if [[ -n "$chosen" ]]; then
    cat "$PERSONAS/$chosen"
else
    echo "claudius: no persona available (personas/ directory empty, or weights.csv malformed?)" >&2
fi
