#!/bin/bash
SCRIPT_DIR="$(dirname "$0")"
WEIGHTS="$SCRIPT_DIR/weights.csv"
PERSONAS="$SCRIPT_DIR/personas"
COMMON="$SCRIPT_DIR/common.md"

# Create weights.csv if it doesn't exist
if [[ ! -f "$WEIGHTS" ]]; then
    for f in "$PERSONAS"/*.md; do
        [[ -f "$f" ]] && echo "$(basename "$f"),1,1"
    done > "$WEIGHTS"
fi

# Sync: keep existing entries whose files still exist, add new files at preference 1, weight 1
{
    while IFS=, read -r name preference weight; do
        [[ -f "$PERSONAS/$name" ]] && echo "$name,$preference,$weight"
    done < "$WEIGHTS"

    for f in "$PERSONAS"/*.md; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f")
        grep -q "^$name," "$WEIGHTS" || echo "$name,1,1"
    done
} > "$WEIGHTS.tmp" && mv "$WEIGHTS.tmp" "$WEIGHTS"

# Weighted random pick
chosen=$(while IFS=, read -r name preference weight; do
    for ((i=0; i<weight; i++)); do
        echo "$name"
    done
done < "$WEIGHTS" | shuf -n 1)

# Update weights: reset chosen to its preference, increment all others by their preference
while IFS=, read -r name preference weight; do
    if [[ "$name" == "$chosen" ]]; then
        echo "$name,$preference,$preference"
    elif [[ "$weight" -eq 0 ]]; then
        echo "$name,$preference,0"
    else
        echo "$name,$preference,$((weight + preference))"
    fi
done < "$WEIGHTS" > "$WEIGHTS.tmp" && mv "$WEIGHTS.tmp" "$WEIGHTS"

cat "$COMMON"
cat "$PERSONAS/$chosen"
