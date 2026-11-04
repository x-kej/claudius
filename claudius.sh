#!/usr/bin/env bash
# Claudius: gives each Claude Code session a randomly chosen persona.
#
# As a plugin (Claude Code sets CLAUDE_PLUGIN_ROOT and CLAUDE_PLUGIN_DATA):
#   SessionStart / startup: draw this session's persona and write it to
#     output-styles/persona.md. Claude Code reads the plugin's output style
#     after SessionStart hooks run (observed: the style arrives with the first
#     prompt), so the session picks up the persona written here. Each draw is
#     logged to $CLAUDE_PLUGIN_DATA/picks.log for checking that ordering.
#   UserPromptSubmit (--remind): every Nth prompt, print a short voice cue.
#
# Standalone (wired up directly in settings.json, no plugin environment):
#   every session start draws a persona and prints it as session context.
#
# Environment:
#   CLAUDIUS_REMIND_EVERY  prompts between reminders (default 4, 0 disables)

set -u

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
PERSONAS="$ROOT/personas"
COMMON="$ROOT/common.md"
STYLE_DIR="$ROOT/output-styles"
STYLE="$STYLE_DIR/persona.md"

if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    PLUGIN=1
    DATA="$CLAUDE_PLUGIN_DATA"
else
    PLUGIN=0
    DATA="$ROOT/.state"
fi
WEIGHTS="$DATA/weights.csv"
SESSIONS="$DATA/sessions"

REMIND_EVERY="${CLAUDIUS_REMIND_EVERY:-4}"
[[ "$REMIND_EVERY" =~ ^[0-9]+$ ]] || REMIND_EVERY=4
GENERIC_REMINDER="Keep your persona's voice in this reply, technical parts included: its vocabulary, sentence shapes, and framing, not just its emoji."

# A persona file's body, without its frontmatter.
persona_body() {
    awk 'NR == 1 && $0 == "---" { fm = 1; next }
         fm && $0 == "---"      { fm = 0; next }
         !fm' "$1"
}

# One value from a persona file's frontmatter.
frontmatter() {
    awk -v key="$2" 'NR == 1 && $0 == "---" { fm = 1; next }
                     fm && $0 == "---"      { exit }
                     fm && index($0, key ":") == 1 {
                         sub("^" key ":[ \t]*", ""); print; exit
                     }' "$1"
}

# The full persona text: the persona itself, then the shared rules.
render() {
    persona_body "$PERSONAS/$1"
    printf '\n'
    cat "$COMMON"
}

# Weighted draw that favors personas not seen in a while. Sets PICKED to a
# persona filename, or "" if nothing is eligible.
#
# weights.csv rows are <name>,<preference>,<weight>. Each draw resets the
# chosen persona's weight to its preference and raises every other nonzero
# weight by its preference. A weight of 0 stays 0: that persona is disabled.
pick() {
    local names=() prefs=() weights=()
    local name pref weight f known i total=0 r running=0 tmp

    if [[ -f "$WEIGHTS" ]]; then
        while IFS=, read -r name pref weight; do
            [[ -n "$name" && -f "$PERSONAS/$name" ]] || continue
            [[ "$pref" =~ ^[0-9]+$ && "$weight" =~ ^[0-9]+$ ]] || continue
            names+=("$name"); prefs+=("$pref"); weights+=("$weight")
        done < "$WEIGHTS"
    fi

    for f in "$PERSONAS"/*.md; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f")"
        known=0
        for i in "${names[@]}"; do
            [[ "$i" == "$name" ]] && { known=1; break; }
        done
        ((known)) || { names+=("$name"); prefs+=(1); weights+=(1); }
    done

    for weight in "${weights[@]}"; do
        total=$((total + weight))
    done

    PICKED=""
    if ((total > 0)); then
        r=$(((RANDOM * 32768 + RANDOM) % total))
        for i in "${!names[@]}"; do
            running=$((running + weights[i]))
            if ((running > r)); then
                PICKED="${names[i]}"
                break
            fi
        done
    fi

    tmp="$(mktemp "$WEIGHTS.XXXXXX")" || return
    for i in "${!names[@]}"; do
        if [[ "${names[i]}" == "$PICKED" ]]; then
            echo "${names[i]},${prefs[i]},${prefs[i]}"
        elif ((weights[i] == 0)); then
            echo "${names[i]},${prefs[i]},0"
        else
            echo "${names[i]},${prefs[i]},$((weights[i] + prefs[i]))"
        fi
    done > "$tmp" && mv "$tmp" "$WEIGHTS"
}

# Write a persona as the plugin's output style.
write_style() {
    local tmp
    mkdir -p "$STYLE_DIR"
    tmp="$(mktemp "$STYLE.XXXXXX")" || return
    {
        printf -- '---\n'
        printf 'name: persona\n'
        printf 'description: Claudius persona: %s\n' "${1%.md}"
        printf 'keep-coding-instructions: true\n'
        printf 'force-for-plugin: true\n'
        printf -- '---\n\n'
        render "$1"
    } > "$tmp" && mv "$tmp" "$STYLE"
}

# The reminder text for a persona, or the generic one if it has no cue.
reminder_text() {
    local cue=""
    [[ -n "${1:-}" && -f "$PERSONAS/$1" ]] && cue="$(frontmatter "$PERSONAS/$1" reminder)"
    if [[ -n "$cue" ]]; then
        echo "$cue Keep it up through the technical parts too."
    else
        echo "$GENERIC_REMINDER"
    fi
}

# Session state file: line 1 is the reminder text, line 2 the prompt count,
# line 3 is set once the reminder has been synced to the loaded style.
seed_reminder() {
    printf '%s\n0\n\n' "$(reminder_text "$2")" > "$SESSIONS/$1"
}

# The persona the style file currently holds, or "".
style_persona() {
    local name
    [[ -f "$STYLE" ]] || return
    name="$(sed -n 's/^description: Claudius persona: \(.*\)$/\1/p' "$STYLE" | head -n 1)"
    [[ -n "$name" && -f "$PERSONAS/$name.md" ]] && echo "$name.md"
}

input="$(cat)"
session_id="$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/' | tr -cd 'A-Za-z0-9_-')"
session_id="${session_id:-unknown}"

mkdir -p "$SESSIONS"

if [[ "${1:-}" == "-r" || "${1:-}" == "--remind" ]]; then
    ((REMIND_EVERY > 0)) || exit 0

    state="$SESSIONS/$session_id"
    reminder=""
    count=0
    synced=""
    if [[ -f "$state" ]]; then
        reminder="$(sed -n '1p' "$state")"
        count="$(sed -n '2p' "$state")"
        synced="$(sed -n '3p' "$state")"
    fi

    # Claude Code reads the output style on a session's first prompt. If
    # another session started in the meantime, the style file now holds that
    # session's persona, and so does this session. Re-point the reminder at
    # whatever the file holds right now, once, so it matches the actual voice.
    if ((PLUGIN)) && [[ -z "$synced" ]]; then
        loaded="$(style_persona)"
        [[ -n "$loaded" ]] && reminder="$(reminder_text "$loaded")"
        synced=1
    fi

    reminder="${reminder:-$GENERIC_REMINDER}"
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    count=$((count + 1))

    if ((count >= REMIND_EVERY)); then
        printf 'Claudius reminder: %s\n' "$reminder"
        count=0
    fi

    tmp="$(mktemp "$state.XXXXXX")" || exit 0
    printf '%s\n%d\n%s\n' "$reminder" "$count" "$synced" > "$tmp" && mv "$tmp" "$state"
    exit 0
fi

# Session start from here on.

# Carry over weights from the pre-plugin layout, which kept them in the repo.
if ((PLUGIN)) && [[ ! -f "$WEIGHTS" && -f "$ROOT/weights.csv" ]]; then
    cp "$ROOT/weights.csv" "$WEIGHTS"
fi

find "$SESSIONS" -type f -mtime +7 -delete 2>/dev/null

pick
seed_reminder "$session_id" "$PICKED"

if [[ -z "$PICKED" ]]; then
    ((PLUGIN)) && rm -f "$STYLE"
    echo "claudius: No persona could be loaded this session (the personas/ folder is empty, or every persona is disabled in weights.csv). Tell the user this at the start of your first response, in plain language."
elif ((PLUGIN)); then
    write_style "$PICKED"
    printf '%s %s %s\n' "$(date '+%F %T')" "$session_id" "${PICKED%.md}" >> "$DATA/picks.log"
else
    render "$PICKED"
fi
