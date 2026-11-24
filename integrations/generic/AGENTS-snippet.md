## DayPlan (local CLI)

DayPlan is a small macOS card that shows today's plan. The same binary also has a
command-line mode that reads and writes the exact same JSON files. No network, no
API key, no MCP server, no vendor SDK — just a command that any agent able to run
a shell can use.

The CLI is at `~/Applications/DayPlan.app/Contents/MacOS/DayPlan`. If `DayPlan` is
not on `PATH`, call it by full path (or symlink it into a directory that is).

```sh
DayPlan --today                     # today's plan: time, text, note, done, outcome
DayPlan --json                      # same data as JSON
DayPlan --add "读两篇审稿意见" --time "14:00 – 15:00" --units 2 --note "只看方法部分"
DayPlan --done 3                    # mark item 3 done (index starts at 1)
DayPlan --undone 3
DayPlan --outcome 3 "卡在识别策略，换了个 IV"
DayPlan --date 2026-11-24 --today   # a specific date
```

Rules when using it:

- Always read with `--today` (or `--json`) before writing, so you quote the right item.
- Items are addressed by 1-based index in file order; each line ends with `#id`.
  Out-of-range indices fail with a clear message and the valid range.
- Never edit the JSON by hand and never write to the data directory directly.
  The data directory is whatever the app resolves: `$DAYPLAN_DIR` >
  `UserDefaults.dataDir` > `~/Library/Application Support/DayPlan/plans`.
- Every write leaves `<date>.prev.json` behind; that is the app's own backup.
- After writing, report back the item text and state so the user can confirm.
