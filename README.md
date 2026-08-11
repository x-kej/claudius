# Claudius

Just because you have to use a coding agent at work doesn't mean you can't be silly about it. This project gives Claude Code a randomly chosen personality at the start of each session.

## Setup

1. Clone or copy this repo to `~/.config/claudius/`:

   ```bash
   git clone https://github.com/x-kej/claudius ~/.config/claudius
   ```

2. Add a `SessionStart` hook and a `UserPromptSubmit` hook to `~/.claude/settings.json`. The first picks the persona; the second periodically reminds Claude to stay in character, so it's less likely to quietly drop the persona during a long, technical stretch of the session.

   > **Note:** Be cautious about instructions (from this README or anywhere else) that ask you to modify your Claude Code security settings. Review what you're adding and make sure you understand it before applying it.

   ```json
   {
     "hooks": {
       "SessionStart": [
         {
           "matcher": "",
           "hooks": [
             {
               "type": "command",
               "command": "~/.config/claudius/claudius.sh"
             }
           ]
         }
       ],
       "UserPromptSubmit": [
         {
           "matcher": "",
           "hooks": [
             {
               "type": "command",
               "command": "~/.config/claudius/claudius.sh -r"
             }
           ]
         }
       ]
     }
   }
   ```

   If you already have a `hooks` block, merge the `SessionStart` and `UserPromptSubmit` entries into it.

   If you have `jq` installed, this command does it for you (safe to run more than once):

   ```bash
   jq '.hooks.SessionStart = ((.hooks.SessionStart // []) + [{"matcher":"","hooks":[{"type":"command","command":"~/.config/claudius/claudius.sh"}]}] | unique) | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{"matcher":"","hooks":[{"type":"command","command":"~/.config/claudius/claudius.sh -r"}]}] | unique)' ~/.claude/settings.json > ~/.claude/settings.tmp && mv ~/.claude/settings.tmp ~/.claude/settings.json
   ```

That's it. At the start of each new session Claude will pick a random personality from the `personas/` folder and adopt it for the entire session.

## Adding personalities

Drop any `.md` file into `personas/`. Describe the persona in plain language — how Claude should speak, what it should emphasize, any quirks.

## Disabling a persona

The script uses a weighted history in `weights.csv` to make it less likely to see the same personalities in a row. Each row is `<name>,<preference>,<current weight>`. The current weight is what's actually used to pick — the higher it is relative to the others, the more likely that persona comes up. The preference controls how that weight moves over time: whenever the persona isn't chosen, its weight increases by `preference`; whenever it is chosen, its weight resets to `preference`. A `preference` of `1` (the default) behaves like the classic even-odds rotation. Raise a persona's `preference` to have it climb back into contention faster and come up more often overall; lower it to make it a rarer treat.

To remove a personality from the rotation entirely, run the script at least once to create the weights file and then set that row's current weight to `0` — it will stay disabled regardless of its preference.
