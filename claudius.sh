#!/usr/bin/env bash
# Claudius: gives each Claude Code session a randomly chosen persona.
#
# SessionStart: print the session's persona as session context.
#   startup, clear: draw a new persona and record it for this session id.
#   resume, compact: re-print the persona already recorded for this session
#     id, so the voice survives a restart or a compaction. If none is
#     recorded (the state expired, or the session predates this version),
#     draw one.
# UserPromptSubmit (--remind): every Nth prompt, print a short voice cue for
#   the session's recorded persona.
#
# Each session's persona lives in its own state file, so concurrent sessions
# never see each other's draws.
#
# Runs the same way as a plugin (Claude Code sets CLAUDE_PLUGIN_ROOT and
# CLAUDE_PLUGIN_DATA) or wired up directly in settings.json, where state goes
# in .state/ next to this script.
#
# Environment:
#   CLAUDIUS_REMIND_EVERY  prompts between reminders (default 4, 0 disables)

set -u

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
PERSONAS="$ROOT/personas"
COMMON="$ROOT/common.md"

if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    PLUGIN=1
    DATA="$CLAUDE_PLUGIN_DATA"
else
    PLUGIN=0
    DATA="$ROOT/.state"
fi
WEIGHTS="$DATA/weights.csv"
SESSIONS="$DATA/sessions"
SESSION_TTL_DAYS=30

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

# One string field from the hook's JSON input.
json_field() {
    printf '%s' "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 |
        sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/'
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

# Session state file: line 1 is the persona filename, line 2 the prompt count
# since the last reminder.
write_state() {
    local tmp
    tmp="$(mktemp "$state.XXXXXX")" || return
    printf '%s\n%d\n' "$1" "$2" > "$tmp" && mv "$tmp" "$state"
}

# The persona recorded for this session, if it still exists, or "".
recorded_persona() {
    local name
    [[ -f "$state" ]] || return
    name="$(sed -n '1p' "$state")"
    [[ "$name" == *.md && -f "$PERSONAS/$name" ]] && echo "$name"
}

input="$(cat)"
session_id="$(json_field session_id | tr -cd 'A-Za-z0-9_-')"
session_id="${session_id:-unknown}"
session_source="$(json_field source)"

mkdir -p "$SESSIONS"
state="$SESSIONS/$session_id"

if [[ "${1:-}" == "-r" || "${1:-}" == "--remind" ]]; then
    ((REMIND_EVERY > 0)) || exit 0

    persona="$(recorded_persona)"
    count=0
    [[ -f "$state" ]] && count="$(sed -n '2p' "$state")"
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    count=$((count + 1))

    if ((count >= REMIND_EVERY)); then
        printf 'Claudius reminder: %s\n' "$(reminder_text "$persona")"
        count=0
    fi

    write_state "$persona" "$count"
    exit 0
fi

# Session start from here on.

# Carry over weights from the pre-plugin layout, which kept them in the repo.
if ((PLUGIN)) && [[ ! -f "$WEIGHTS" && -f "$ROOT/weights.csv" ]]; then
    cp "$ROOT/weights.csv" "$WEIGHTS"
fi

find "$SESSIONS" -type f -mtime +"$SESSION_TTL_DAYS" -delete 2>/dev/null

PICKED=""
case "$session_source" in
    resume|compact) PICKED="$(recorded_persona)" ;;
esac
drew=0
if [[ -z "$PICKED" ]]; then
    pick
    drew=1
fi

if [[ -z "$PICKED" ]]; then
    rm -f "$state"
    echo "claudius: No persona could be loaded this session (the personas/ folder is empty, or every persona is disabled in weights.csv). Tell the user this at the start of your first response, in plain language."
    exit 0
fi

write_state "$PICKED" 0
((drew)) && printf '%s %s %s %s\n' "$(date '+%F %T')" "$session_id" "${session_source:-unknown}" "${PICKED%.md}" >> "$DATA/picks.log"

if [[ "$session_source" == "resume" || "$session_source" == "compact" ]]; then
    echo "This is the persona for this session. If anything earlier in the conversation set a different persona or voice, this one replaces it."
    echo
fi
render "$PICKED"
