---
description: 查看或修改今天的 DayPlan 桌面日程卡片
---

用户在 /dayplan 后面输入的是：$ARGUMENTS

工具位置与数据位置：

- 命令行：`~/Applications/DayPlan.app/Contents/MacOS/DayPlan`
- 数据目录：`~/Library/Application Support/DayPlan/plans/`
- 当天文件：`<数据目录>/YYYY-MM-DD.json`

第一步永远先运行：

```sh
~/Applications/DayPlan.app/Contents/MacOS/DayPlan --today
```

如果输出「还没有计划文件」，说明今天还没排。按下面的格式写一份新的 JSON 到当天路径。

```json
{
  "date": "2026-11-24",
  "weekday": "周二",
  "title": "",
  "subtitle": "",
  "blocks": [
    {
      "id": "a1b2c3d4",
      "origin": "ai",
      "time": "09:00 – 10:30",
      "units": 3,
      "text": "写清楚这一段要做什么",
      "note": "一句补充，可以留空",
      "done": false
    }
  ],
  "footer": "一句收尾，不超过三十字",
  "updated_at": "2026-11-24T17:14:00Z"
}
```

如果已经有计划，按用户要求操作：

- 加一条：`DayPlan --add "内容" --time "14:00 – 15:00" --units 2 --note "备注"`
- 勾掉：`DayPlan --done 2`（序号从 1 开始）
- 取消勾选：`DayPlan --undone 2`
- 记实况：`DayPlan --outcome 2 "实际怎么走的"`

规则：

- `id` 用 8 位小写十六进制，写入后不再改，应用靠它定位
- `origin` 写 `ai`；用户自己在卡片里新增的会是 `user`，不要覆盖
- 覆盖当天文件前，先复制一份为 `<date>.prev.json`
- 正文中文不超过 18 字、备注不超过 26 字，窗口窄，超出会被截断
- 不要把 `latest.json` 当普通文件写，它是软链
- 不要碰其它工具的配置目录，本应用只认自己的数据目录

做完把今天的条目念一遍给用户确认。
