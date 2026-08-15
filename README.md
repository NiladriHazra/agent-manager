# agents-view

A macOS menu bar app that answers two questions about your coding agents: which
ones are running right now and what each is working on, and how much weekly
quota is left before one of them stops mid-task.

Native Swift and SwiftUI, no Electron. Reads only local files, sends nothing
anywhere, and calls no undocumented vendor APIs.

<img src="docs/screenshot.png" width="360" alt="The agents-view dropdown">

## Why the rows differ

Agents are wildly inconsistent about what they write to disk, and the interface
is honest about that rather than inventing numbers:

| Agent | Running and activity | Quota |
| --- | --- | --- |
| Codex | yes | **real limit**, straight from its own session log |
| Claude Code | yes, with the session title | local usage only |
| OpenCode | yes, with the session title | local usage and spend |
| Cursor, Gemini, Antigravity, Grok, Hermes | yes | none published |

A quota bar with a reset countdown only ever appears when the vendor genuinely
wrote a limit to disk. Everything else is labelled `usage`, meaning tokens
counted from local transcripts, which is what you spent rather than what you
have left. The two are never mixed.

## Installing

Requires macOS 14 or later, and Command Line Tools for the build (no Xcode).

```sh
git clone https://github.com/NiladriHazra/agents-view
cd agents-view
./scripts/build.sh
open dist/agents-view.app
```

The build is ad-hoc signed, so if you move the app somewhere Gatekeeper is
suspicious of, right-click it and choose Open the first time.

The panel lists only agents that are running right now, since that is the
question it exists to answer. Idle ones are hidden until you turn them on.

## Settings

Open them from the dropdown footer:

- which agents appear, whether to show idle ones, and whether to hide ones that
  are not installed
- what the menu bar shows: count and quota, count only, quota only, or icon only
- refresh interval
- amber and red thresholds for a low quota
- whether cache reads count toward usage totals (off by default, see below)
- launch at login

## How it stays cheap

An always-on menu bar app has no business burning CPU, and the data here is
large: 2.2 GB of Codex sessions and 500 MB of Claude transcripts on the machine
this was built against, including one single 295 MB session file.

- **Codex quota** is the final `token_count` record in the newest session, found
  by reading the last 64 KB and widening only if needed. Measured at 8 ms.
- **Claude usage** is an incremental index keyed by `(device, inode)`, so a
  refresh reads only the bytes appended since last time and skips untouched
  files without opening them. A cold build takes about a second; a warm refresh
  measured 30 ms.
- **OpenCode** totals are already aggregated per session in its SQLite database,
  so one read-only query covers the week.
- **Process detection** reads the kernel process table directly instead of
  forking `ps`, and takes about 6 ms.

No code path can read an entire session file.

## Notes

- `agents-view --diagnose` prints exactly what each provider read, with timings.
  Use it when a number looks wrong.
- Claude's cache-read tokens run around a hundred times larger than everything
  else, so they are excluded from the headline figure by default. The setting is
  there if you want them.
- The Codex quota is per account. If you use more than one, you see one of them.
- Logos are the vendors' own marks, in their real brand colours.

## Licence

MIT.
