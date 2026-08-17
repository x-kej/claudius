#!/bin/bash
SCRIPT_DIR="$(dirname "$0")"
WEIGHTS="$SCRIPT_DIR/weights.csv"
PERSONAS="$SCRIPT_DIR/personas"
COMMON="$SCRIPT_DIR/common.md"
REMINDER_FREQUENCY=8
readonly SCRIPT_DIR WEIGHTS PERSONAS COMMON REMINDER_FREQUENCY

# Read stdin once — session_id is needed by both branches below.
input="$(cat)"
session_id="$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')"
state_file="/tmp/claudius-$session_id"

# UserPromptSubmit hook: read back the reminder seeded at SessionStart and
# fire it every REMINDER_FREQUENCY turns.
if [[ "$1" == "-r" || "$1" == "--remind" ]]; then
    [[ -f "$state_file" ]] || exit 0

    reminder=$(sed -n '1p' "$state_file")
    count=$(sed -n '2p' "$state_file")
    ((count++))

    if (( count >= REMINDER_FREQUENCY )); then
        echo "$reminder"
        count=0
    fi

    tmp=$(mktemp "$state_file.XXXXXX")
    printf '%s\n%d\n' "$reminder" "$count" > "$tmp" && mv "$tmp" "$state_file"
    exit 0
fi

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

if [[ -n "$chosen" ]]; then
    # Tagged rather than keyed by line number or wording, so a "(REMINDER)"
    # line still gets picked up even if it's reordered, reworded, or absent.
    blob="$(cat "$PERSONAS/$chosen" "$COMMON")"

    reminder_lines="$(grep -F '(REMINDER)' <<< "$blob" | sed -E 's/^- //; s/ \(REMINDER\)$//' | tr '\n' ' ' | sed -E 's/ +$//')"
    reminder="Reminder — ${reminder_lines}"
    printf '%s\n0\n' "$reminder" > "$state_file"

    sed -E 's/ \(REMINDER\)$//' <<< "$blob"
else
    echo "claudius: No persona could be loaded this session (personas/ directory is empty, or weights.csv is malformed). Alert the user to this at the start of your first response, in plain language — no persona voice, since none is active this session."
fi
