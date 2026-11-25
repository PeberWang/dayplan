# DayPlan（今日）

macOS 原生的小便签：一张贴在桌面上的纸卡，显示当天的日程。可勾选、可直接在窗口里改字、加条目、删条目；一个按钮切到近七天；`Cmd+3` 打开统计。

## 启动

```sh
open ~/Applications/DayPlan.app
```

- 固定 360 × 620 的无边框卡片，不能拖、不能缩放，可以被别的窗口完整遮住
- Dock 不占图标；菜单栏有一个小图标，点开可以「显示/隐藏窗口、统计、设置…、退出」
- `Cmd+Q` 退出，`Cmd+3` 统计，`Cmd+,` 设置，`Cmd+W` 关当前窗
- 默认随登录自动启动（设置 → 启动 → 登录时自动启动，可关）；关掉后不会再随登录拉起
- 语言三选一：跟随系统 / 中文 / English，在设置里点了立刻生效，不用重启
- 外观三选一：跟随系统 / 浅色 / 深色（v11），切换立刻生效，重启后保持上次选择

## 用法

- 单击条目：选中（按 Delete 删除，`Cmd+Z` 撤销最近一次删除）
- 双击主文 / 备注 / 时间 / 单位数：原地编辑；回车或点别处保存，Esc 取消
- 底部「+ 添加」：末尾加一条空条目，`origin` 记为 `user`
- 鼠标移到条目上，右侧浮出小铅笔：点开记录区，写下这条实际怎么做的、卡在哪；有记录时备注下方按行显示（最多 2 条 + …），点摘要可再展开
- 记录区里回车换行，点别处或 Esc 收起并保存；「清空」把这条记录清掉（`outcome` 置空）；选中条目按 `O` 也能展开
- 右键条目：编辑、记一笔实况、上移 / 下移、删除
- 右上角「本周 / 本周」按钮：今天 ⇄ 最近七天；一周视图里点任何一天都能回去改（今天和历史一样可编辑，写完不跳回今天）
- 主文最多两行、备注最多两行，超出省略；编辑时直接改全文

编辑即写盘，写前会把旧文件存成 `<date>.prev.json`。过了零点今天不会继承昨天的条目；当天还没有文件时是空白卡片，第一次勾选或「+ 添加」时按当天日期新建文件，并把 `latest.json` 指过去。历史上空着的日子点进去同样能写，第一次操作时补建那天的文件（不会改 `latest.json`）。

## 开机自启

默认开启：应用每次启动都会确认一份 LaunchAgent 在，登录时由 launchd 拉起，装在哪个目录都有效。

- 位置：`~/Library/LaunchAgents/io.github.peberwang.dayplan.plist`
- 内容：`/usr/bin/open -a ~/Applications/DayPlan.app`，`RunAtLoad`，只在 Aqua 会话加载
- 关掉：设置 → 启动 → 关掉「登录时自动启动」，应用会 `launchctl bootout` 并删掉这份 plist
- 再开：重新打开开关，立刻写回并 `bootstrap`；开关状态记在 `UserDefaults` 的 `launchAtLogin`（没写过就是开）
- 不用 `SMAppService`：本地 ad-hoc 签名的构建走那个 API 经常注册失败，LaunchAgent 不依赖签名和安装位置

## 数据

- 当天文件：`~/.openclaw/workspace/state/dayplan/YYYY-MM-DD.json`
- 当前显示：`~/.openclaw/workspace/state/dayplan/latest.json`（软链，指向当天）
- 勾选、编辑状态由应用写回同一个 JSON，并更新 `updated_at`
- 星期不读 JSON 的 `weekday`，按 `date` 现算
- 测试时可用 `DAYPLAN_DIR=/path/to/dir` 指向别的目录（仓库里的 `testdata/`、`testdata-en/` 是样例）
- 设置里也能改数据目录（写入 `UserDefaults` 的 `dataDir`），改完当场重读；`DAYPLAN_DIR` 存在时优先它

结构：

```json
{
  "date": "2026-11-24",
  "weekday": "周二",
  "title": "MPSA 形式模型",
  "subtitle": "9 单位 · 6.5 小时",
  "blocks": [
    {
      "id": "a1b2c3d4",
      "origin": "ai",
      "time": "11:00 – 12:00",
      "units": 2,
      "text": "事项",
      "note": "备注",
      "done": false,
      "outcome": "推到第二阶段就卡住了，晚上换了个顺序才通。",
      "outcome_at": "2026-11-24T23:10:00Z"
    }
  ],
  "footer": "一句收尾",
  "updated_at": "2026-11-24T17:14:00Z"
}
```

`title` / `subtitle` 仍可写，但 v5 界面不显示；`id` 是 8 位小写十六进制，缺了会在读入当天文件时补上并写回一次；`origin` 为 `ai` / `user`。

`outcome` / `outcome_at` 可选：`outcome` 缺失或空串表示没有记录，写入时同步 `outcome_at`，清空时写空串并删掉 `outcome_at`。它和 `reflection` 是两层数据（单条任务的实况 vs 全天感受），互不替代。

OpenClaw 还可能写 `reflection`（`text` / `mood` / `at`）或其他未知字段。应用不显示它们，但写回时基于原始 JSON 字典修改，所以会原样保留。`mood` 不做取值校验。

## 统计

- 独立窗口 800 × 520，`Cmd+3` 打开；最近 30 天，每天一根柱
- 数据：`~/Library/Application Support/DayPlan/stats.json`（`{"schema":1,"days":{"2026-11-24":{"total":9,"done":2}}}`），写前留 `stats.prev.json`
- 点评：`~/Library/Application Support/DayPlan/comment.txt`（48 小时内有效，标「OpenClaw · 昨天」；否则用本地规则，标「本地估算」）
- 首次启动/缺天时从日程目录只读回填；删日程文件不会删 stats
- 测试覆盖目录：`DAYPLAN_STATS_DIR=/path/to/dir`
- 仓库里的 `testdata-v4/` + `teststats-v4/` 是 30 天柱状图与点评来源的样例
- `reflection` 与所有不认识的字段在写回时原样保留，不会因为界面不显示而丢掉

## 用命令行（任何 agent 都能接）

同一个二进制带一个 CLI 入口。参数里出现 `--today`、`--json`、`--add` 等开关就不显示窗口，
执行完退出；读写走的是窗口同一套逻辑、同一份 JSON。

```sh
DayPlan --today                    # 时间、正文、备注、完成与否、outcome；行尾 #id
DayPlan --json                     # 同样的数据，machine-readable
DayPlan --add "读两篇审稿意见" --time "14:00 – 15:00" --units 2 --note "只看方法部分"
DayPlan --done 3                   # 序号从 1 开始
DayPlan --outcome 3 "卡在识别策略，换了个 IV"
```

安装到 `PATH`：`ln -sf ~/Applications/DayPlan.app/Contents/MacOS/DayPlan ~/.local/bin/DayPlan`。

接入方式：

- OpenCode：`integrations/opencode/dayplan.md` → `.opencode/commands/dayplan.md`（或全局 `~/.config/opencode/commands/`）
- Claude Code：`integrations/claude/dayplan.md` → `.claude/commands/dayplan.md`
- Codex：把 `integrations/codex/AGENTS-snippet.md` 粘进项目 `AGENTS.md`
- 其他读 `AGENTS.md` / `CLAUDE.md` 的工具：`integrations/generic/AGENTS-snippet.md`

调研结论、已验证与未验证的边界见 [`docs/integrations.md`](docs/integrations.md)。

## 用 git 安装与自动更新

```sh
git clone https://github.com/PeberWang/dayplan.git ~/dayplan
cd ~/dayplan && ./scripts/install.sh
```

`scripts/install.sh` 编译后把 `.app` 装到 `~/Applications/DayPlan.app`，并把仓库绝对路径写进
`UserDefaults` 的 `installRepo`。应用靠它判断「这是 git 安装」，并定时更新：

- 启动 30 秒后查一次，之后每 24 小时一次（也可在设置里点「立即检查」）
- 版本号：仓库根 `VERSION` 与 `Info.plist` 的 `CFBundleShortVersionString` 一起改；
  远程读 `raw.githubusercontent.com/PeberWang/dayplan/master/VERSION`，逐段按数字比较
- 有更新时：`git fetch` → 比 `HEAD` 与 `origin/master` → `pull --ff-only` → 重新跑 `scripts/install.sh`
- 只快进，不合并、不重置；本地有改动或网络失败就放弃本轮，不重试、不影响现有安装
- 编译失败保留旧二进制，错误写进 `~/Library/Logs/DayPlan-update.log`
- 替换成功后不强制重启：菜单栏 tooltip 与设置页显示「已更新，重启后生效」，
  菜单栏里另有「重启以应用更新」，重启与否由你决定
- 设置 → 更新：开关「自动检查并更新」（默认开）、当前版本与上次更新时间、「立即检查」
- 关掉开关只停自动检查；「立即检查」仍可用。下载 zip / 手动拖进 Applications 的安装没有
  `installRepo`，检查会静默跳过，需要手动更新

## 源码与重建

```sh
cd ~/dayplan
./scripts/install.sh     # 编译 + 装到 ~/Applications/DayPlan.app + ad-hoc 签名；./build.sh 是同一份
```

或手动：

```sh
swiftc -O -parse-as-library -o DayPlan DayPlanApp.swift
mkdir -p ~/Applications/DayPlan.app/Contents/MacOS
cp DayPlan ~/Applications/DayPlan.app/Contents/MacOS/DayPlan
cp Info.plist ~/Applications/DayPlan.app/Contents/Info.plist
codesign --force --deep --sign - ~/Applications/DayPlan.app
```

注意：CommandLineTools 的 SwiftUI 缺 SwiftUIMacros 插件，代码里不能用 `@State` / `@Binding` / `@Environment` / `@Observable` 一类宏；状态都放在 `Store` / `StatsStore`（ObservableObject）里。

改动明细见 `CHANGES-v13.md`（v12 见 `CHANGES-v12.md`，v11 见 `CHANGES-v11.md`）。
