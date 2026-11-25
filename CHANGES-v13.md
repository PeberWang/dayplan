# v13 — 默认随登录自动启动

版本：0.13.0（Info.plist CFBundleVersion 13）

## 新增

- 新增 `LoginItem`（DayPlanApp.swift）：写 / 删 `~/Library/LaunchAgents/io.github.peberwang.dayplan.plist`，
  并调用 `launchctl bootout / bootstrap` 立即生效。
- 设置面板新增「启动」一节：开关「登录时自动启动」，中英文文案齐备。
- `SettingsStore` 新增 `launchAtLogin`，存在 `UserDefaults` 的 `launchAtLogin`，**没写过就是开**。
- 应用启动时调用 `syncLaunchAtLogin()`：默认开的那份 plist 被删了会自动补回；用户显式关过就不再写。
- 设置窗口高度 470 → 560，容纳新的一节。

## 为什么用 LaunchAgent，不用 SMAppService

应用是本地 ad-hoc 签名的构建，也不在 `/Applications`。`SMAppService.mainApp.register()` 在这种情形下
经常抛错或注册成「未启用」。LaunchAgent 只依赖一份 plist，登录时由 launchd 拉起，与签名、安装位置无关，
卸载 / 停用也只是删文件加一次 `bootout`，行为可解释。

## 默认行为

- 新用户第一次运行应用后即生效，不需要去设置里手动打开。
- 想关：设置 → 启动 → 关掉「登录时自动启动」；`launchctl` 服务被 bootout，plist 被删除，
  `UserDefaults.launchAtLogin = false`，之后每次启动都不会再写回。
- 想再开：把开关打开即可，plist 立刻写回并 bootstrap。
- 直接跑二进制（CLI、测试）时不动系统状态，只有从 `.app` 里启动才写 plist。

## 验证过的路径

1. 首次启动 → plist 生成，`launchctl print gui/501/io.github.peberwang.dayplan` 可见，`launchctl kickstart` 成功。
2. 设置里关掉 → 文件消失、`defaults read ... launchAtLogin` 为 0、服务查不到。
3. 再打开 → 文件回来、值为 1、服务重新 bootstrap。

## 0.13.1 — 开关的「开」必须一眼看出来

系统 `.switch` 的打开色跟着系统强调色走。用户把强调色设成石墨灰时，开和关几乎一样；试过
`.tint(Palette.switchOn)`，首次渲染是蓝的，但设置里切一次浅色/深色就掉回系统灰。

所以换成自绘的 `DayPlanSwitchStyle`：

- 轨道 36 × 21 胶囊，开 → `Palette.switchOn`（浅色 #2F6FD0 / 深色 #4C8FE8），关 → `Palette.switchOn`
  的对位灰（#D8D4CC / #4A4741）
- 白色圆钮带一点投影，开在右、关在左，0.16 秒 easeOut
- 两种外观切换后颜色都正确刷新（动态色画在 Shape 里，不走 tint）

已验证：深色开/关、浅色开/关、浅→深来回切换后仍是蓝，四张截图逐一核对。
