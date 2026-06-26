# Claudius

Just because you have to use a coding agent at work doesn't mean you can't have a little extra whimsy in your life. This project gives Claude Code a randomly chosen personality at the start of each session.

## Setup

1. Clone or copy this repo to `~/.config/claudius/`:

   ```bash
   git clone <repo-url> ~/.config/claudius
   ```

2. Add a `SessionStart` hook to `~/.claude/settings.json`:

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
       ]
     }
   }
   ```

   If you already have a `hooks` block, merge the `SessionStart` entry into it.

   If you have `jq` installed, this command does it for you (safe to run more than once):

   ```bash
   jq '.hooks.SessionStart = ((.hooks.SessionStart // []) + [{"matcher":"","hooks":[{"type":"command","command":"~/.config/claudius/claudius.sh"}]}] | unique)' ~/.claude/settings.json > ~/.claude/settings.tmp && mv ~/.claude/settings.tmp ~/.claude/settings.json
   ```

That's it. At the start of each new session Claude will pick a random personality from the `personalities/` folder and adopt it for the entire session.

## Adding personalities

Drop any `.md` file into `personalities/`. Describe the persona in plain language — how Claude should speak, what it should emphasize, any quirks.

## Disabling a persona

Set its weight to `0` in `weights.txt` and it will be permanently skipped — never selected, and never incremented back into rotation.
