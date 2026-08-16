<div align="center">
  <img src="docs/klipeo-mark.png" width="64" alt="">
  <h1>agent-manager</h1>
  <p><b>Every coding agent you're running, in one menu bar icon.</b></p>
  <p>
    Which ones are working · which are waiting on <i>you</i> · what each has spent
  </p>
  <p>
    <img src="https://img.shields.io/badge/macOS-14%2B-000?style=flat-square" alt="macOS 14+">
    <img src="https://img.shields.io/badge/Swift-99%25-F05138?style=flat-square" alt="Swift">
    <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT">
    <img src="https://img.shields.io/badge/network-none-2ea44f?style=flat-square" alt="No network">
  </p>
</div>

<div align="center">
  <img src="docs/demo.gif" width="820" alt="agent-manager in use">
  <p><sub><a href="https://github.com/NiladriHazra/agent-manager/releases/download/v0.1.0/demo.mp4">Watch the full 31-second walkthrough</a> — settings, model selector, sub-agents</sub></p>
</div>

---

You have Claude in one terminal, three Codex sessions in three more, OpenCode
somewhere behind them. Two finished ten minutes ago and are sitting there
waiting for your reply. One is about to hit its weekly limit mid-task.

There is no way to see any of that without checking every window.

This is a small menu bar app that answers it in one glance. Native Swift and
SwiftUI, no Electron, about 3 MB. It reads **only local files** on your own
machine, sends nothing anywhere, and calls no undocumented vendor APIs.

## Install

**Download** — [latest release](https://github.com/NiladriHazra/agent-manager/releases/latest), unzip, drag to Applications. Or paste this:

```sh
curl -L https://github.com/NiladriHazra/agent-manager/releases/latest/download/agent-manager.zip -o /tmp/am.zip \
  && unzip -oq /tmp/am.zip -d /Applications \
  && xattr -dr com.apple.quarantine /Applications/agent-manager.app \
  && open /Applications/agent-manager.app
```

The `xattr` line matters. The build is **ad-hoc signed**, not notarized — I
don't pay Apple's $99/year — so macOS quarantines it on download and refuses to
open it without that. If you'd rather not run it, right-click the app and
choose **Open** the first time instead, which does the same thing through the
GUI.

**Build from source** — needs Xcode Command Line Tools, nothing else:

```sh
git clone https://github.com/NiladriHazra/agent-manager
cd agent-manager && ./scripts/build.sh && open dist/agent-manager.app
```

There is no Dock icon by design. Look for the mark in your menu bar. Turn on
**Launch at login** in Settings so it survives a reboot.

## What you get

**Three tabs, each backed by something actually written to disk.**

| | meaning | how it is known |
| --- | --- | --- |
| **Working** | mid-task right now | transcript written in the last 3 minutes, and its last record is not an ended turn |
| **Waiting** | finished, wants your reply | the last record **is** an ended turn: `task_complete` for Codex, `stop_reason: end_turn` for Claude, a completed assistant message for OpenCode |
| **Open** | alive, but neither | a live process with no recent activity |

A live process is not the same as a working one. A session parked at a prompt
stays alive for hours — on the machine this was built against, that was the
difference between "9 running" and the honest answer, 2.

**Per agent** — quota or usage across today and the last 7 days, spend where
the vendor publishes a price, the model in use, and a model selector when an
agent has used more than one. Multiple terminals of the same tool stack into a
single row that expands sideways.

**Per session** — branch, working directory, pid, sub-agents, and for Claude a
**context bar** showing how close that chat is to compacting. Click a row to
raise its terminal; Terminal.app and iTerm2 select the exact tab.

## Why the rows differ

Agents are wildly inconsistent about what they record, and this is honest about
that rather than inventing numbers:

| agent | activity | tokens | limit |
| --- | --- | --- | --- |
| **Codex** | yes | yes | **real quota**, from its own session log, plus credit balance |
| **Claude Code** | yes, with session titles | yes, plus per-chat context | none published |
| **OpenCode** | yes, with session titles | yes, per session, with spend and model | none published |
| **Grok** | yes | yes, with spend | none published |
| Cursor, Gemini, Antigravity, Hermes | yes | nothing on disk | none published |

A quota bar with a reset countdown appears **only** where the vendor genuinely
wrote a limit to disk. Everything else is labelled as locally counted usage,
which is what you spent, not what you have left. The two are never mixed, and
nothing is invented to fill an empty column.

Codex is the only agent that publishes a limit. For the others you can set your
own weekly or daily budget in Settings, and the percentage is measured against
**your** figure — the app says so rather than implying it came from the vendor.

## Menu bar, your way

The mark is always there. Everything beside it is yours to choose: the count of
working agents, and a percentage for up to three agents. One agent shows its
number alone; two or more each carry their own logo, because bare percentages
side by side don't say which is which.

Per agent, choose what its percentage measures — vendor quota, a weekly or
daily budget you set, or live context — and whether it shows as icon, number,
or both. A live preview in Settings shows the combination before you commit.

## Settings

Right-click the menu bar icon for **Settings**, **Refresh** and **Quit**.

- **General** — menu bar composition, refresh interval, low-quota thresholds, launch at login
- **Agents** — which agents appear at all
- **Readings** — per agent, which readings a row may draw. Each agent is offered only what it genuinely writes to disk, so no switch here is decorative
- **About**

## If the icon disappears

macOS lays status items out right to left and **clips from the left** when the
bar overflows. Screen recording and dictation both add system indicators, and
those always win. The app is still running; there is no API to claim a slot.

- The app asks for the rightmost slot on first launch, so it is last in the eviction queue
- **⌥⌘A** opens the same panel in a floating window from anywhere, so you're never locked out
- ⌘-drag the icon to move it; the position sticks
- **Settings → Icon only, always** makes it the smallest possible target
- A menu bar manager like [Ice](https://github.com/jordanbaird/Ice) is the only thing that truly guarantees a slot

## How it stays cheap

An always-on menu bar app has no business burning CPU, and the data is large:
2.2 GB of Codex sessions and 500 MB of Claude transcripts on the machine this
was built against, including one 295 MB session file.

- **Codex quota** is the last `token_count` record in the newest session, found by reading the final 64 KB and widening only if needed — 8 ms
- **Claude usage** is an incremental index keyed by `(device, inode)`, so a refresh reads only bytes appended since last time and skips untouched files without opening them. Cold build ~1 s, warm refresh **~130 ms**
- **OpenCode** totals are already aggregated in SQLite, so one read-only query covers the week
- **Process detection** reads the kernel process table directly instead of forking `ps` — ~30 ms, on its own 2-second beat, so a new agent appears almost immediately
- Providers are probed concurrently, and unchanged files are never re-read

No code path reads an entire session file.

Process matching is on the exec path plus the first two arguments, because the
short name the kernel reports is useless: Claude runs from a version-named
binary and reports `2.1.233`, `cursor-agent` is a shell script that execs node,
and Hermes is `python3 …/bin/hermes`.

## Troubleshooting

`agent-manager --diagnose` prints exactly what each provider read, with
timings, session states, TTYs and per-model totals. Use it when a number looks
wrong — it is the same code path the app uses, so it cannot disagree.

## Notes

- Claude's cache-read tokens run about a hundred times larger than everything else, so they are excluded from headline figures by default. The setting is there if you want them
- The Codex quota is per account. If you use more than one, you see one of them
- Logos are the vendors' own marks

## Licence

MIT.
