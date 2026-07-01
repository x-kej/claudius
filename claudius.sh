#!/bin/bash
SCRIPT_DIR="$(dirname "$0")"
WEIGHTS="$SCRIPT_DIR/weights.txt"
PERSONAS="$SCRIPT_DIR/personas"
COMMON="$SCRIPT_DIR/common.md"

# Create weights.txt if it doesn't exist
if [[ ! -f "$WEIGHTS" ]]; then
    for f in "$PERSONAS"/*.md; do
        [[ -f "$f" ]] && echo "$(basename "$f"),1"
    done > "$WEIGHTS"
fi

# Sync: keep existing entries whose files still exist, add new files at weight 1
{
    while IFS=, read -r name weight; do
        [[ -f "$PERSONAS/$name" ]] && echo "$name,$weight"
    done < "$WEIGHTS"

    for f in "$PERSONAS"/*.md; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f")
        grep -q "^$name," "$WEIGHTS" || echo "$name,1"
    done
} > "$WEIGHTS.tmp" && mv "$WEIGHTS.tmp" "$WEIGHTS"

# Weighted random pick
chosen=$(while IFS=, read -r name weight; do
    for ((i=0; i<weight; i++)); do
        echo "$name"
    done
done < "$WEIGHTS" | shuf -n 1)

# Update weights: reset chosen to 1, increment all others
while IFS=, read -r name weight; do
    if [[ "$name" == "$chosen" ]]; then
        echo "$name,1"
    elif [[ "$weight" -eq 0 ]]; then
        echo "$name,0"
    else
        echo "$name,$((weight + 1))"
    fi
done < "$WEIGHTS" > "$WEIGHTS.tmp" && mv "$WEIGHTS.tmp" "$WEIGHTS"

cat "$COMMON"
cat "$PERSONAS/$chosen"
