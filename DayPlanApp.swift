import AppKit
import Combine
import SwiftUI

// DayPlan v5：便签式竖窗 360×620，今天/本周，行内编辑，中英双语，独立统计窗口。
// 本机 CommandLineTools 缺 SwiftUIMacros，不能用 @State / @Binding / @Environment / @Observable；
// 所有状态放在 Store（ObservableObject + @Published），视图用 @ObservedObject。

// MARK: - 配色

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// v11：颜色随外观动态切换。浅色值保持改造前不变；深色值不是反转，而是把纸底
// 换成偏暖的近黑、文字换成偏暖的白，暖棕提亮成琥珀，否则在深底上会糊成一片。
enum Palette {
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func dynNS(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(hex: isDark(appearance) ? dark : light)
        }
    }

    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: dynNS(light, dark))
    }

    // 半透明的 ink：深底上浅色的低透明度更看不见，暗色要浓一档。
    static func inkAlpha(_ light: CGFloat, _ dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let darkMode = isDark(appearance)
            return NSColor(hex: darkMode ? 0xEDE9E2 : 0x1C1C1C)
                .withAlphaComponent(darkMode ? dark : light)
        })
    }

    static let paper = dyn(0xF7F5F0, 0x1B1A18)
    static let ink = dyn(0x1C1C1C, 0xEDE9E2)
    static let secondary = dyn(0x6B6B6B, 0x9C968C)
    static let time = dyn(0x8A6A3A, 0xC9A46B)
    static let nowDot = dyn(0x5E93C0, 0x7FB3DC)   // 当前时段的圆点：淡蓝，压一层灰，不抢眼
    static let timeDeep = dyn(0x6B4E28, 0xE4C493) // 统计里「今天」那根柱，比普通柱亮一档
    static let done = dyn(0xA8A29A, 0x6E6960)
    static let rule = inkAlpha(0.08, 0.12)

    // 纸色蒙版：暗色下玻璃本身偏暗，蒙版太厚会变成实心，所以减薄。
    static let paperVeil = Color(nsColor: NSColor(name: nil) { appearance in
        let darkMode = isDark(appearance)
        return NSColor(hex: darkMode ? 0x1B1A18 : 0xF7F5F0)
            .withAlphaComponent(darkMode ? 0.55 : 0.62)
    })

    // 统计柱：浅色沿用暖棕 60%，深色直接用琥珀，不加透明度。
    static let bar = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance)
            ? NSColor(hex: 0xC9A46B)
            : NSColor(hex: 0x8A6A3A).withAlphaComponent(0.6)
    })

    static let paperNS = dynNS(0xF7F5F0, 0x1B1A18)
    static let inkNS = dynNS(0x1C1C1C, 0xEDE9E2)
    static let secondaryNS = dynNS(0x6B6B6B, 0x9C968C)
    static let timeNS = dynNS(0x8A6A3A, 0xC9A46B)
    static let doneNS = dynNS(0xA8A29A, 0x6E6960)
}

// MARK: - 文案（简中 / 英文，跟随系统语言）

struct L10n {
    let isZH: Bool

    // v7：语言由设置决定，不再只看系统。
    static func from(_ source: LangSource) -> L10n {
        switch source {
        case .zh: return L10n(isZH: true)
        case .en: return L10n(isZH: false)
        case .system:
            // 跟随系统/本应用的偏好语言；测试时可用 -AppleLanguages "(zh-Hans)" 覆盖。
            let first = (Locale.preferredLanguages.first ?? "en").lowercased()
            return L10n(isZH: first.hasPrefix("zh"))
        }
    }

    static var current: L10n { from(SettingsStore.shared.language) }

    // 菜单
    var about: String { isZH ? "关于 DayPlan" : "About DayPlan" }
    var hideApp: String { isZH ? "隐藏 DayPlan" : "Hide DayPlan" }
    var quit: String { isZH ? "退出 DayPlan" : "Quit DayPlan" }
    var editMenu: String { isZH ? "编辑" : "Edit" }
    var windowMenu: String { isZH ? "窗口" : "Window" }
    var undo: String { isZH ? "撤销" : "Undo" }
    var redo: String { isZH ? "重做" : "Redo" }
    var cut: String { isZH ? "剪切" : "Cut" }
    var copy: String { isZH ? "拷贝" : "Copy" }
    var paste: String { isZH ? "粘贴" : "Paste" }
    var selectAll: String { isZH ? "全选" : "Select All" }
    var close: String { isZH ? "关闭" : "Close" }
    var showWindow: String { isZH ? "显示窗口" : "Show Window" }
    var hideWindow: String { isZH ? "隐藏窗口" : "Hide Window" }
    var statsMenu: String { isZH ? "统计" : "Stats" }

    // 主窗口
    var today: String { isZH ? "今天" : "Today" }
    var week: String { isZH ? "本周" : "Week" }
    var lastSeven: String { isZH ? "近七天" : "Last 7 days" }
    var switchToWeek: String { isZH ? "看本周" : "Week view" }
    var switchToToday: String { isZH ? "回到今天" : "Today view" }
    var backToToday: String { isZH ? "回到今天" : "Back to today" }
    var todayMarker: String { isZH ? "今天" : "Today" }
    var add: String { isZH ? "添加" : "Add" }
    var emptyBlock: String { isZH ? "（空）" : "(empty)" }
    var noPlan: String { isZH ? "还没有今天的计划" : "No plan for today" }
    var reload: String { isZH ? "重新读取" : "Reload" }
    var readOnlyHistory: String { isZH ? "这条记录读取失败，暂时不能改" : "Couldn't read this record" }
    var noDayPlan: String { isZH ? "这一天还没有计划，写下第一条即可"
                                 : "No plan for this day yet — write the first item." }
    var weekHint: String { isZH ? "点某一天回去看当天详情；任何一天的条目都能直接改"
                              : "Click a day to open it; items are editable for any day." }

    func parseFailed(_ file: String) -> String {
        isZH ? "今日文件解析失败：\(file)" : "Couldn't read today's file: \(file)"
    }
    func writeFailed(_ msg: String) -> String {
        isZH ? "写入失败：\(msg)" : "Couldn't save: \(msg)"
    }
    func footerDone(_ done: String, _ total: String) -> String {
        isZH ? "完成 \(done) / \(total) 项" : "\(done) / \(total) done"
    }
    func units(_ n: Double) -> String {
        let v = Fmt.units(n)
        if isZH { return "\(v) 单位" }
        return "\(v) \(n == 1 ? "unit" : "units")"
    }
    func unitsPair(_ done: String, _ total: String) -> String {
        isZH ? "\(done) / \(total) 单位" : "\(done) / \(total) units"
    }
    func weekSummary(_ done: String, _ total: String, _ pct: String) -> String {
        isZH ? "本周完成 \(done) 项，共 \(total) 项 · \(pct)"
             : "\(done) of \(total) done this week · \(pct)"
    }

    // 菜单项
    var editText: String { isZH ? "编辑文字" : "Edit text" }
    var editNote: String { isZH ? "编辑备注" : "Edit note" }
    var editTime: String { isZH ? "编辑时间" : "Edit time" }
    var editUnits: String { isZH ? "编辑单位数" : "Edit units" }
    var moveUp: String { isZH ? "上移" : "Move up" }
    var moveDown: String { isZH ? "下移" : "Move down" }
    var delete: String { isZH ? "删除" : "Delete" }
    var phTask: String { isZH ? "事项" : "Task" }
    var phNote: String { isZH ? "备注" : "Note" }
    var editOutcome: String { isZH ? "记一笔实况" : "Add outcome" }
    var collapseOutcome: String { isZH ? "收起" : "Collapse" }
    var clearOutcome: String { isZH ? "清空" : "Clear" }
    var phTime: String { isZH ? "11:00 – 12:00" : "11:00 – 12:00" }
    var phUnits: String { "0" }

    // 统计窗口
    var statsTitle: String { isZH ? "统计" : "Stats" }
    var statsRange: String { isZH ? "最近 30 天" : "Last 30 days" }
    var statsEmpty: String { isZH ? "还没有数据" : "No data yet" }
    var badgeAssistant: String { isZH ? "来自 AI · 昨天" : "From AI · yesterday" }
    var badgeLocal: String { isZH ? "本地估算" : "Local estimate" }
    var localLoosen: String { isZH ? "排得偏松，可以试着加一点量。"
                                   : "Light load — try adding a bit more." }
    var localTight: String { isZH ? "排得偏紧，先砍一半，把能做完的写进去。"
                                  : "Tight plan — cut it in half, keep what you can finish." }
    var localSteady: String { isZH ? "节奏稳，保持这个量。"
                                   : "Steady pace — keep this volume." }
    func localBestWorst(_ best: String, _ bestPct: String, _ worst: String, _ worstPct: String) -> String {
        isZH ? "最高的是 \(best)（\(bestPct)），最低是 \(worst)（\(worstPct)）。"
             : "Highest: \(best) (\(bestPct)); lowest: \(worst) (\(worstPct))."
    }
    func statsSummary(_ done: String, _ total: String, _ pct: String) -> String {
        isZH ? "近 30 天完成 \(done) 项，共 \(total) 项，平均完成率 \(pct)"
             : "\(done) of \(total) done in 30 days, \(pct) average"
    }
    func pickedDay(_ date: String, _ done: String, _ total: String) -> String {
        isZH ? "\(date) 完成 \(done) / \(total)" : "\(date): \(done) of \(total) done"
    }

    // 设置面板
    var settingsMenu: String { isZH ? "设置…" : "Settings…" }
    var settingsTitle: String { isZH ? "设置" : "Settings" }
    var languageLabel: String { isZH ? "语言" : "Language" }
    var followSystem: String { isZH ? "跟随系统" : "System" }
    var themeLabel: String { isZH ? "外观" : "Appearance" }
    var themeLight: String { isZH ? "浅色" : "Light" }
    var themeDark: String { isZH ? "深色" : "Dark" }
    var dataDirLabel: String { isZH ? "数据目录" : "Data folder" }
    var openFolder: String { isZH ? "打开" : "Open" }
    var changeFolder: String { isZH ? "更改…" : "Change…" }
    var envHint: String {
        isZH ? "环境变量 DAYPLAN_DIR 存在时会覆盖这里的设置"
             : "The DAYPLAN_DIR environment variable overrides this setting."
    }
    var chooseFolder: String { isZH ? "选择" : "Choose" }
    var aboutLabel: String { isZH ? "关于" : "About" }

    // 启动（v13）
    var startupLabel: String { isZH ? "启动" : "Startup" }
    var launchAtLoginLabel: String { isZH ? "登录时自动启动" : "Open at login" }
    var launchAtLoginHint: String {
        isZH ? "关掉后不再随登录启动，下次登录想用请自己打开" 
             : "Turn off to stop opening at login."
    }

    // 更新
    var updateLabel: String { isZH ? "更新" : "Updates" }
    var autoUpdateLabel: String { isZH ? "自动检查并更新" : "Check and update automatically" }
    var checkNow: String { isZH ? "立即检查" : "Check now" }
    var checking: String { isZH ? "正在检查…" : "Checking…" }
    var neverUpdated: String { isZH ? "尚未更新" : "never" }
    var restartToApply: String { isZH ? "已更新，重启后生效" : "Updated — restart to apply" }
    var updateHint: String {
        isZH ? "自动更新只对 git 安装生效，其他安装方式请手动更新"
             : "Automatic updates work for git installs; update other installs by hand."
    }
    var restartNow: String { isZH ? "重启以应用更新" : "Restart to apply update" }
    func versionLine(_ v: String, _ last: String) -> String {
        isZH ? "当前版本 \(v) · 上次更新 \(last)"
             : "Version \(v) · last update \(last)"
    }
    func updateOutcome(_ o: UpdateStore.Outcome) -> String {
        switch o {
        case .upToDate: return isZH ? "已是最新" : "Already up to date"
        case .updating: return isZH ? "发现新版，正在更新" : "New version found — updating"
        case .updated: return restartToApply
        case .failed: return isZH ? "检查或更新失败，详见日志" : "Check or update failed — see the log"
        case .noGit: return isZH ? "未通过 git 安装，请手动更新" : "Not a git install — update manually"
        }
    }
    func langName(_ s: LangSource) -> String {
        switch s {
        case .system: return followSystem
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    func themeName(_ t: ThemeSource) -> String {
        switch t {
        case .system: return followSystem
        case .light: return themeLight
        case .dark: return themeDark
        }
    }
}

// MARK: - 设置（语言 / 数据目录）

enum LangSource: String, CaseIterable, Identifiable {
    case system, zh, en
    var id: String { rawValue }

    // UserDefaults 里没写过就是「跟随系统」。
    static func stored() -> LangSource {
        let defaults = UserDefaults.standard
        var raw = defaults.string(forKey: "language")
        if raw == nil {
            let id = Bundle.main.bundleIdentifier ?? "io.github.peberwang.dayplan"
            raw = UserDefaults(suiteName: id)?.string(forKey: "language")
        }
        return LangSource(rawValue: raw ?? "") ?? .system
    }
}

// v11：外观三态。system 不覆盖 SwiftUI 的色彩环境与窗口 appearance，交给系统；
// light / dark 强制。存 UserDefaults 的 theme。
enum ThemeSource: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    static func stored() -> ThemeSource {
        let defaults = UserDefaults.standard
        var raw = defaults.string(forKey: "theme")
        if raw == nil {
            let id = Bundle.main.bundleIdentifier ?? "io.github.peberwang.dayplan"
            raw = UserDefaults(suiteName: id)?.string(forKey: "theme")
        }
        return ThemeSource(rawValue: raw ?? "") ?? .system
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

// 语言与数据目录的唯一来源。视图用 @ObservedObject 观察它，切换语言时 SwiftUI
// 会重算 body，所以不需要重建 NSHostingView。
// MARK: - 登录时自动启动（v13）

// 用 LaunchAgent 而不是 SMAppService。本应用是本地 ad-hoc 签名的构建，
// SMAppService 对未签名 / 不在 /Applications 的 app 经常 register 失败；
// LaunchAgent 只依赖一份 plist，登录时由 launchd 拉起，装在哪里都稳定。
// 默认开启；设置里显式关掉才会移除 plist。
enum LoginItem {
    static let label = "io.github.peberwang.dayplan"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    // 只有从 .app 里跑才有可靠的路径；裸二进制（CLI、测试）不动系统状态。
    static var appURL: URL? {
        let u = Bundle.main.bundleURL
        return u.pathExtension.lowercased() == "app" ? u : nil
    }

    private static var domain: String { "gui/\(getuid())" }

    // 返回错误描述；成功返回 nil。
    @discardableResult
    static func apply(_ on: Bool) -> String? {
        on ? install() : uninstall()
    }

    @discardableResult
    static func install() -> String? {
        guard let app = appURL else { return nil }
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-a</string>
                <string>\(app.path)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
        </dict>
        </plist>

        """
        do {
            try body.write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            return error.localizedDescription
        }
        // 先卸再装，保证 launchd 里是最新内容；没装过时 bootout 失败，忽略。
        launchctl(["bootout", "\(domain)/\(label)"])
        launchctl(["bootstrap", domain, plistURL.path])
        return nil
    }

    @discardableResult
    static func uninstall() -> String? {
        launchctl(["bootout", "\(domain)/\(label)"])
        guard isInstalled else { return nil }
        do {
            try FileManager.default.removeItem(at: plistURL)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var language: LangSource
    @Published private(set) var theme: ThemeSource          // v11：外观三态
    @Published private(set) var dataDirText: String     // 当前生效的目录
    @Published private(set) var envDirActive: Bool      // DAYPLAN_DIR 是否在生效
    @Published private(set) var autoUpdate: Bool        // v9：自动检查并更新，默认开
    @Published private(set) var launchAtLogin: Bool     // v13：登录时自动启动，默认开

    private init() {
        language = LangSource.stored()
        theme = ThemeSource.stored()
        let env = ProcessInfo.processInfo.environment
        envDirActive = !(env["DAYPLAN_DIR"] ?? "").isEmpty
        dataDirText = PlanIO.resolveDir().path
        // 没写过就是开。显式写 false 才算关。
        autoUpdate = SettingsStore.storedBool("autoUpdate", default: true)
        launchAtLogin = SettingsStore.storedBool("launchAtLogin", default: true)
    }

    var l10n: L10n { L10n.from(language) }

    func setLanguage(_ s: LangSource) {
        guard s != language else { return }
        language = s
        UserDefaults.standard.set(s.rawValue, forKey: "language")
    }

    func setTheme(_ t: ThemeSource) {
        guard t != theme else { return }
        theme = t
        UserDefaults.standard.set(t.rawValue, forKey: "theme")
    }

    // 环境变量优先；它存在时也照样记下选择，等环境变量撤掉就生效。
    func setDataDir(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: "dataDir")
        let id = Bundle.main.bundleIdentifier ?? "io.github.peberwang.dayplan"
        UserDefaults(suiteName: id)?.set(url.path, forKey: "dataDir")
        refreshDir()
    }

    func refreshDir() {
        let env = ProcessInfo.processInfo.environment
        envDirActive = !(env["DAYPLAN_DIR"] ?? "").isEmpty
        dataDirText = PlanIO.resolveDir().path
    }

    func setAutoUpdate(_ on: Bool) {
        guard on != autoUpdate else { return }
        autoUpdate = on
        UpdateStore.setPref("autoUpdate", on)
    }

    func setLaunchAtLogin(_ on: Bool) {
        guard on != launchAtLogin else { return }
        launchAtLogin = on
        UserDefaults.standard.set(on, forKey: "launchAtLogin")
        let id = Bundle.main.bundleIdentifier ?? "io.github.peberwang.dayplan"
        UserDefaults(suiteName: id)?.set(on, forKey: "launchAtLogin")
        LoginItem.apply(on)
    }

    // 每次启动对齐一次：默认开的那份 plist 丢了会自动补回来；用户显式关了就不再写。
    func syncLaunchAtLogin() {
        LoginItem.apply(launchAtLogin)
    }

    // 直接跑二进制（不在 .app 里）时 standard 可能读不到应用自己的 domain，再按 bundle id 读一次。
    static func storedBool(_ key: String, default def: Bool) -> Bool {
        if let v = UserDefaults.standard.object(forKey: key) as? Bool { return v }
        let id = Bundle.main.bundleIdentifier ?? "io.github.peberwang.dayplan"
        if let v = UserDefaults(suiteName: id)?.object(forKey: key) as? Bool { return v }
        return def
    }
}

// 全局只留一个「取当前语言」的入口给非视图代码（写入错误、日期格式、字体、菜单）。
// 视图不再直接用它：各自从 SettingsStore 取，才能跟着切换刷新。
var L: L10n { SettingsStore.shared.l10n }

// MARK: - 版本与自动更新

enum AppVersion {
    // 构建时写入：Info.plist 缺 CFBundleShortVersionString 时用它。发布时与 VERSION 一起改。
    static let fallback = "0.13.0"

    static var current: String {
        if let s = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return fallback
    }

    // 语义化比较：逐段转 Int，缺段补 0，非数字段按 0；返回 1 / 0 / -1。
    // 不能用字符串比较——"0.10.0" 会排在 "0.9.0" 前面。
    static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { seg in
                Int(seg.prefix { $0.isNumber }) ?? 0
            }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let vx = i < x.count ? x[i] : 0
            let vy = i < y.count ? y[i] : 0
            if vx != vy { return vx > vy ? 1 : -1 }
        }
        return 0
    }

    static func isNewer(_ a: String, than b: String) -> Bool { compare(a, b) > 0 }
}

extension Notification.Name {
    static let dayplanUpdateStateChanged = Notification.Name("io.github.peberwang.dayplan.updateStateChanged")
}

// v9：自动更新。只认「git 克隆后跑 scripts/install.sh」装上的那一份——install.sh 把仓库
// 绝对路径写进 UserDefaults 的 installRepo。流程：fetch → 比 origin/master → pull --ff-only
// → scripts/install.sh；任何一步失败都只写 ~/Library/Logs/DayPlan-update.log，不动现有安装、
// 不弹窗、不重试。替换成功后只置 pendingRestart，重启与否交给用户。
final class UpdateStore: ObservableObject {
    static let shared = UpdateStore()

    static let remoteVersionURL = URL(string: "https://raw.githubusercontent.com/PeberWang/dayplan/master/VERSION")!
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "io.github.peberwang.dayplan" }

    enum Phase: Equatable { case idle, checking, upToDate, updating, updated, failed, noGit }
    enum Outcome: Equatable { case upToDate, updating, updated, failed, noGit }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastOutcome: Outcome?
    @Published private(set) var pendingRestart: Bool = false
    @Published private(set) var lastUpdatedAt: Date?

    private let queue = DispatchQueue(label: "io.github.peberwang.dayplan.updater", qos: .utility)
    private var running = false
    private var timer: Timer?
    private let launchedAt = Date()

    private init() {
        let stamp = Self.pref("lastUpdatedAt") as? Double
        lastUpdatedAt = stamp.map { Date(timeIntervalSince1970: $0) }
        var pending = Self.pref("pendingRestart") as? Bool ?? false
        // 更新是在上一个进程里完成的：这次启动已经在跑新二进制，提示可以撤掉了。
        if pending, let t = lastUpdatedAt, t < launchedAt {
            pending = false
            Self.setPref("pendingRestart", false)
        }
        pendingRestart = pending
    }

    var installRepo: String? {
        guard let s = Self.pref("installRepo") as? String else { return nil }
        let t = (s as NSString).expandingTildeInPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    var lastUpdatedText: String? {
        guard let d = lastUpdatedAt else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    // MARK: 时机

    // 启动 30 秒后一次，之后每 24 小时一次。DAYPLAN_UPDATE_DELAY 可缩短首检（测试用）。
    func startScheduling() {
        guard timer == nil else { return }
        let delay = ProcessInfo.processInfo.environment["DAYPLAN_UPDATE_DELAY"].flatMap(Double.init) ?? 30
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.autoCheck()
        }
        let t = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.autoCheck()
        }
        t.tolerance = 300
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func checkNow() {
        guard !running else { return }
        running = true
        begin(manual: true)
    }

    private func autoCheck() {
        guard SettingsStore.shared.autoUpdate, !running else { return }
        running = true
        Self.appendLog("check: auto, version \(AppVersion.current)")
        begin(manual: false)
    }

    private func begin(manual: Bool) {
        if manual {
            lastOutcome = nil
            phase = .checking
        }
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.performCheck(manual: manual)
            DispatchQueue.main.async {
                self.phase = result.phase
                self.lastOutcome = result.outcome
                self.lastUpdatedAt = (Self.pref("lastUpdatedAt") as? Double)
                    .map { Date(timeIntervalSince1970: $0) }
                self.pendingRestart = Self.pref("pendingRestart") as? Bool ?? false
                self.running = false
                NotificationCenter.default.post(name: .dayplanUpdateStateChanged, object: nil)
            }
        }
    }

    // MARK: 流程（后台队列）

    private func performCheck(manual: Bool) -> (phase: Phase, outcome: Outcome?) {
        let version = AppVersion.current
        let failPhase: Phase = manual ? .failed : .idle

        guard let repo = installRepo else {
            Self.appendLog("skip: installRepo 未设置（不是 git 安装），version \(version)")
            return (manual ? .noGit : .idle, manual ? .noGit : nil)
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repo, isDirectory: &isDir),
              isDir.boolValue,
              FileManager.default.fileExists(atPath: repo + "/.git"),
              let git = Self.gitPath()
        else {
            Self.appendLog("skip: 仓库不存在或不是 git 仓库（不是 git 安装）→ \(repo)")
            return (manual ? .noGit : .idle, manual ? .noGit : nil)
        }

        // 1. fetch（只抓 origin，不碰用户配置的其他 remote）
        let fetch = run(git, ["-C", repo, "fetch", "--quiet", "origin"], timeout: 90)
        guard fetch.code == 0 else {
            Self.appendLog("fetch failed (\(fetch.code)): \(oneLine(fetch.out))")
            return (failPhase, manual ? .failed : nil)
        }

        // 2. 版本：本地 Info.plist vs 仓库里的 VERSION
        let remoteVersion = fetchRemoteVersion()
        let newer = remoteVersion.map { AppVersion.isNewer($0, than: version) } ?? false

        // 3. 提交：HEAD vs origin/master（仓库用 main 时退回 origin/main）
        var branch = "origin/master"
        if run(git, ["-C", repo, "rev-parse", "--verify", "--quiet", branch]).code != 0 {
            if run(git, ["-C", repo, "rev-parse", "--verify", "--quiet", "origin/main"]).code == 0 {
                branch = "origin/main"
            }
        }
        let head = run(git, ["-C", repo, "rev-parse", "HEAD"]).out.trimmed
        let remoteHead = run(git, ["-C", repo, "rev-parse", branch]).out.trimmed
        var behind = 0
        let count = run(git, ["-C", repo, "rev-list", "--count", "HEAD..\(branch)"])
        if count.code == 0 { behind = Int(count.out.trimmed) ?? 0 }

        Self.appendLog("check: version \(version) remote \(remoteVersion ?? "?") head \(short(head)) \(branch) \(short(remoteHead)) behind \(behind) newer \(newer)")

        guard behind > 0 || newer else {
            return (manual ? .upToDate : .idle, manual ? .upToDate : nil)
        }

        if manual {
            DispatchQueue.main.async { self.phase = .updating }
        }

        // 4. 只快进；本地有改动或网络有问题就放弃本轮
        let pull = run(git, ["-C", repo, "pull", "--ff-only", "--quiet"], timeout: 180)
        guard pull.code == 0 else {
            Self.appendLog("pull failed (\(pull.code)), 保留现有安装: \(oneLine(pull.out))")
            return (failPhase, manual ? .failed : nil)
        }

        // 5. 重新编译安装；脚本自己保证编译失败时不动旧二进制
        let script = repo + "/scripts/install.sh"
        guard FileManager.default.fileExists(atPath: script) else {
            Self.appendLog("install.sh 不存在: \(script)")
            return (failPhase, manual ? .failed : nil)
        }
        let install = run("/bin/zsh", [script], cwd: URL(fileURLWithPath: repo), timeout: 900)
        guard install.code == 0 else {
            Self.appendLog("install failed (\(install.code)), 旧二进制保留:\n\(tail(install.out))")
            return (failPhase, manual ? .failed : nil)
        }

        Self.appendLog("updated ok: \(oneLine(install.out))")

        // 版本号可能先于代码更新（VERSION 推了、代码没推），此时重装不会带来任何变化，
        // 不谎报「已更新」：提交没前进、装好的版本也和当前一样，就当已是最新。
        let headAfter = run(git, ["-C", repo, "rev-parse", "HEAD"]).out.trimmed
        let installed = Self.installedVersion()
        if headAfter == head, let installed, installed == version {
            Self.appendLog("install 完成但提交与版本都没变，不提示重启")
            return (manual ? .upToDate : .idle, manual ? .upToDate : nil)
        }

        Self.setPref("lastUpdatedAt", Date().timeIntervalSince1970)
        Self.setPref("pendingRestart", true)
        return (.updated, manual ? .updated : nil)
    }

    private static func installedVersion() -> String? {
        let app = ("~/Applications/DayPlan.app" as NSString).expandingTildeInPath
        guard let b = Bundle(path: app) else { return nil }
        return b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private func fetchRemoteVersion() -> String? {
        var req = URLRequest(url: Self.remoteVersionURL)
        req.timeoutInterval = 20
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let sem = DispatchSemaphore(value: 0)
        var text: String?
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard let data,
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let s = String(data: data, encoding: .utf8)
            else { return }
            text = s.split(separator: "\n").first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.resume()
        _ = sem.wait(timeout: .now() + 25)
        return (text?.isEmpty ?? true) ? nil : text
    }

    // MARK: 进程与日志

    private struct RunResult { let code: Int32; let out: String }

    private func run(_ executable: String, _ args: [String],
                     cwd: URL? = nil, timeout: TimeInterval = 120) -> RunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return RunResult(code: -1, out: "launch failed: \(error.localizedDescription)")
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            if p.isRunning { p.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return RunResult(code: p.terminationStatus, out: String(data: data, encoding: .utf8) ?? "")
    }

    private static func gitPath() -> String? {
        for p in ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }

    private func oneLine(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ⏎ ")
        return t.count > 600 ? String(t.prefix(600)) + "…" : t
    }

    private func tail(_ s: String, _ n: Int = 2000) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > n ? "…" + String(t.suffix(n)) : t
    }

    private func short(_ sha: String) -> String {
        sha.isEmpty ? "?" : String(sha.prefix(7))
    }

    private static func appendLog(_ text: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(ts) \(text)\n".data(using: .utf8) else { return }
        let fm = FileManager.default
        let dir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let url = dir.appendingPathComponent("DayPlan-update.log")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    // 只跑二进制（不在 .app 里）时 standard 可能读不到应用自己的 domain，再按 bundle id 读一次。
    static func pref(_ key: String) -> Any? {
        if let v = UserDefaults.standard.object(forKey: key) { return v }
        return UserDefaults(suiteName: bundleID)?.object(forKey: key)
    }

    static func setPref(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
        UserDefaults(suiteName: bundleID)?.set(value, forKey: key)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - 日期与数字

enum DateText {
    static let calendar = Calendar(identifier: .gregorian)
    static var locale: Locale { Locale(identifier: L.isZH ? "zh_CN" : "en_US") }

    static func date(from key: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    private static func format(_ key: String, _ fmt: String) -> String {
        guard let d = date(from: key) else { return key }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = .current
        f.dateFormat = fmt
        return f.string(from: d)
    }

    // 11月24日 / Nov 24,（英文的逗号留给后面的星期）
    static func label(_ key: String) -> String { format(key, L.isZH ? "M月d日" : "MMM d,") }
    // 周二 / Tue
    static func weekday(_ key: String) -> String { format(key, "EEE") }
    // 11-24：本周列表用的窄日期
    static func short(_ key: String) -> String {
        key.count >= 10 ? String(key.dropFirst(5)) : key
    }
    // 11月21日 / Nov 21
    static func monthDay(_ key: String) -> String { format(key, L.isZH ? "M月d日" : "MMM d") }

    static func num(_ v: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    static func pct(_ rate: Double) -> String {
        "\(Int((rate * 100).rounded()))%"
    }
}

// MARK: - 字体

enum Typo {
    // 中文 Songti SC 没有 semibold，日期取 Bold；英文用系统 New York（serif design）。
    static var date: Font {
        L.isZH ? Font.custom("STSongti-SC-Bold", fixedSize: 25)
               : .system(size: 25, weight: .bold, design: .serif)
    }
    static var weekday: Font {
        L.isZH ? Font.custom("STSongti-SC-Regular", fixedSize: 15)
               : .system(size: 15, design: .serif)
    }
    static var item: Font {
        L.isZH ? Font.custom("PingFangSC-Medium", fixedSize: 15)
               : .system(size: 15, weight: .medium)
    }
    static var note: Font {
        L.isZH ? Font.custom("PingFangSC-Regular", fixedSize: 11.5)
               : .system(size: 11.5)
    }
    static var time: Font { .system(size: 12.5, design: .monospaced).monospacedDigit() }
    static var timeNow: Font {
        .system(size: 12.5, weight: .medium, design: .monospaced).monospacedDigit()
    }
    static var units: Font { .system(size: 11, design: .monospaced).monospacedDigit() }
    static var summary: Font {
        L.isZH ? Font.custom("PingFangSC-Regular", fixedSize: 11) : .system(size: 11)
    }
    static var footer: Font {
        L.isZH ? Font.custom("PingFangSC-Regular", fixedSize: 11) : .system(size: 11)
    }
    static var weekDate: Font { .system(size: 13, design: .monospaced).monospacedDigit() }
    static var weekCount: Font { .system(size: 14, design: .monospaced).monospacedDigit() }
    static var statsTitle: Font {
        L.isZH ? Font.custom("STSongti-SC-Bold", fixedSize: 22)
               : .system(size: 22, weight: .bold, design: .serif)
    }
    static var statsBody: Font {
        L.isZH ? Font.custom("PingFangSC-Regular", fixedSize: 15) : .system(size: 15)
    }
    static var statsAxis: Font { .system(size: 10, design: .monospaced) }
}

// 行内编辑框用 AppKit 字体，字号与 Typo 一一对应。
enum EditFont {
    static var item: NSFont {
        L.isZH ? (NSFont(name: "PingFangSC-Medium", size: 15) ?? .systemFont(ofSize: 15, weight: .medium))
               : .systemFont(ofSize: 15, weight: .medium)
    }
    static var note: NSFont {
        L.isZH ? (NSFont(name: "PingFangSC-Regular", size: 11.5) ?? .systemFont(ofSize: 11.5))
               : .systemFont(ofSize: 11.5)
    }
    static var time: NSFont { .monospacedSystemFont(ofSize: 12.5, weight: .regular) }
    static var units: NSFont { .monospacedSystemFont(ofSize: 11, weight: .regular) }
    static var outcome: NSFont {
        L.isZH ? (NSFont(name: "PingFangSC-Regular", size: 12.5) ?? .systemFont(ofSize: 12.5))
               : .systemFont(ofSize: 12.5)
    }
}

enum Layout {
    static let width: CGFloat = 360
    static let height: CGFloat = 620
    static let timeColumn: CGFloat = 96
    static let hPad: CGFloat = 18
    static let topPad: CGFloat = 18
    static let bottomPad: CGFloat = 14
    static let rowVPad: CGFloat = 14
    static let timeGap: CGFloat = 14
    static let corner: CGFloat = 12
    static let margin: CGFloat = 24

    static let statsWidth: CGFloat = 800
    static let statsHeight: CGFloat = 520
    static let statsPad: CGFloat = 24
    static let statsGap: CGFloat = 28
    static let statsChartWidth: CGFloat = 420

    // 结果记录区：12.5pt × 1.45 行高，最少 2 行、最多 6 行，超出内部滚动。
    static let outcomeLineHeight: CGFloat = 12.5 * 1.45
    static let outcomeInset: CGFloat = 10
    static let outcomeMinHeight: CGFloat = 2 * outcomeLineHeight + outcomeInset
    static let outcomeMaxHeight: CGFloat = 6 * outcomeLineHeight + outcomeInset
}

// MARK: - 数据

// 只读的显示模型。写回不经过它，直接改原始 JSON 字典，未知字段原样保留。

struct Block: Identifiable {
    let id: String
    let origin: String
    var time: String
    var units: Double?
    var text: String
    var note: String
    var done: Bool
    var outcome: String   // 这条任务实际怎么完成的；空字符串 = 没有记录

    var isUser: Bool { origin == "user" }
    var hasOutcome: Bool {
        !outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DayData {
    let key: String
    let url: URL          // 已解析软链后的真实文件
    var raw: [String: Any]
    var weekday: String   // 按 date 用系统 Locale 自己算，不读 JSON 的 weekday
    var footer: String
    var blocks: [Block]

    var doneCount: Int { blocks.filter { $0.done }.count }
    var unitsTotal: Double { blocks.reduce(0) { $0 + ($1.units ?? 0) } }
    var unitsDone: Double { blocks.filter { $0.done }.reduce(0) { $0 + ($1.units ?? 0) } }
    var rate: Double { blocks.isEmpty ? 0 : Double(doneCount) / Double(blocks.count) }
}

struct DayDigest: Identifiable {
    let key: String
    let weekday: String
    let isToday: Bool
    let day: DayData?
    let broken: Bool  // 文件在但解析失败
    var id: String { key }
}

enum Raw {
    static func string(_ o: [String: Any], _ k: String) -> String {
        if let s = o[k] as? String { return s }
        if let n = o[k] as? NSNumber { return n.stringValue }
        return ""
    }

    static func number(_ o: [String: Any], _ k: String) -> Double? {
        let v: Double?
        if let n = o[k] as? NSNumber { v = n.doubleValue }
        else if let s = o[k] as? String { v = Double(s) }
        else { v = nil }
        guard let d = v, d.isFinite else { return nil }
        return d
    }

    static func bool(_ o: [String: Any], _ k: String) -> Bool {
        if let n = o[k] as? NSNumber { return n.boolValue }
        if let s = o[k] as? String { return s == "true" || s == "1" }
        return false
    }

    static func block(_ o: [String: Any]) -> Block {
        Block(id: string(o, "id"),
              origin: string(o, "origin").isEmpty ? "ai" : string(o, "origin"),
              time: string(o, "time"),
              units: number(o, "units"),
              text: string(o, "text"),
              note: string(o, "note"),
              done: bool(o, "done"),
              outcome: string(o, "outcome"))
    }
}

// MARK: - 日程文件读写（窗口与 CLI 共用）

// 目录解析、读取、id 规整、备份与写入只有这一份实现。
// 窗口从 Store 调，命令行从 CLI 调，两边看到的是同一套规则、同一批文件。

enum PlanError: LocalizedError {
    case missing(String)
    case badJSON(String)
    case rename(String)

    var errorDescription: String? {
        switch self {
        case .missing(let key): return "\(key).json 不存在"
        case .badJSON(let key): return "\(key).json 解析失败"
        case .rename(let name): return "写入 \(name) 失败"
        }
    }
}

enum PlanIO {
    static let fm = FileManager.default

    struct Loaded {
        var root: [String: Any]
        var url: URL
        var changed: Bool   // 读取时规整过 id / origin
    }

    // DAYPLAN_DIR > UserDefaults.dataDir > ~/Library/Application Support/DayPlan/plans
    static func resolveDir() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let p = env["DAYPLAN_DIR"], !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        if let p = prefDir() {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("DayPlan/plans")
    }

    // 直接跑二进制（不在 .app 里）时 UserDefaults.standard 可能读不到应用自己的 domain，
    // 再按 bundle id 读一次，保证 CLI 与窗口解析出同一个目录。
    private static func prefDir() -> String? {
        if let s = UserDefaults.standard.string(forKey: "dataDir"), !s.isEmpty { return s }
        let id = Bundle.main.bundleIdentifier ?? "io.github.peberwang.dayplan"
        if let s = UserDefaults(suiteName: id)?.string(forKey: "dataDir"), !s.isEmpty { return s }
        return nil
    }

    static func fileURL(_ key: String, in dir: URL) -> URL {
        dir.appendingPathComponent("\(key).json")
    }

    static func exists(_ key: String, in dir: URL) -> Bool {
        fm.fileExists(atPath: fileURL(key, in: dir).path)
    }

    // 读失败重试一次：外部可能正在写（rename 之前的瞬间）。
    static func read(_ key: String, in dir: URL) throws -> Loaded {
        let url = fileURL(key, in: dir).resolvingSymlinksInPath()
        guard fm.fileExists(atPath: url.path) else { throw PlanError.missing(key) }
        var lastError: Error = PlanError.missing(key)
        for attempt in 0..<2 {
            do {
                let data = try Data(contentsOf: url)
                guard var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    throw PlanError.badJSON(key)
                }
                let changed = normalize(&obj)
                return Loaded(root: obj, url: url, changed: changed)
            } catch {
                lastError = error
                if attempt == 0 { usleep(20_000) }
            }
        }
        throw lastError
    }

    // 缺 id / id 不合法 / id 重复就补一个 8 位十六进制；缺 origin 记 ai。
    private static func normalize(_ obj: inout [String: Any]) -> Bool {
        guard var blocks = obj["blocks"] as? [[String: Any]] else { return false }
        var changed = false
        var seen = Set<String>()
        for i in blocks.indices {
            let rawID = Raw.string(blocks[i], "id")
            var id = rawID.lowercased()
            if !Store.validID(id) || seen.contains(id) {
                repeat { id = Store.newID() } while seen.contains(id)
                blocks[i]["id"] = id
                changed = true
            } else if id != rawID {
                blocks[i]["id"] = id
                changed = true
            }
            seen.insert(id)
            if Raw.string(blocks[i], "origin").isEmpty {
                blocks[i]["origin"] = "ai"
                changed = true
            }
        }
        if changed { obj["blocks"] = blocks }
        return changed
    }

    static func newDayRoot(_ key: String) -> [String: Any] {
        ["date": key, "title": "", "subtitle": "", "blocks": [[String: Any]](),
         "footer": "", "updated_at": Store.stamp()]
    }

    // 新建当天文件后把 latest.json 重新指过去（相对软链，和已有安装一致）。
    static func touchLatest(_ key: String, in dir: URL) {
        let link = dir.appendingPathComponent("latest.json")
        try? fm.removeItem(at: link)
        try? fm.createSymbolicLink(atPath: link.path, withDestinationPath: "\(key).json")
    }

    // 写前留一份 <date>.prev.json，再写同目录临时文件后 rename 覆盖：
    // 读到的一定是完整的旧版或新版，不会看到半截。
    static func write(_ root: [String: Any], to url: URL, backup: Bool = true) throws {
        let prev = url.deletingPathExtension().appendingPathExtension("prev.json")
        if backup, fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: prev)
            try? fm.copyItem(at: url, to: prev)
        }
        var out = try JSONSerialization.data(withJSONObject: root,
                                             options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        out.append(0x0A)
        let perms = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions]
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(getpid())-\(Store.newID())")
        try out.write(to: tmp)
        // 沿用原文件权限；新建文件按 600，和目录里已有文件一致。
        try? fm.setAttributes([.posixPermissions: perms ?? 0o600], ofItemAtPath: tmp.path)
        if rename(tmp.path, url.path) != 0 {
            try? fm.removeItem(at: tmp)
            throw PlanError.rename(url.lastPathComponent)
        }
    }
}

// MARK: - Store

final class Store: ObservableObject {
    enum Mode: String { case day, week }
    enum Field: String { case time, units, text, note }
    struct EditTarget: Equatable {
        let blockID: String
        let field: Field
    }

    @Published private(set) var days: [DayDigest] = []
    @Published private(set) var todayKey = ""
    @Published private(set) var todayDay: DayData?      // 仅当 todayKey 那天有文件
    @Published private(set) var weekDone = 0
    @Published private(set) var weekTotal = 0
    @Published var mode: Mode = .day
    @Published var viewingKey: String?                  // 一周视图点进来的历史日期；nil 表示今天
    @Published var selectedID: String?
    @Published var editing: EditTarget?
    @Published var scrollTarget: String?   // 新增条目后滚到它
    @Published var errorText: String?
    @Published var writeError: String?
    @Published var hoveredID: String?           // 鼠标停在哪条上（只用来浮现写记录的小图标）
    @Published var expandedOutcome: String?     // 哪一条的记录区正展开
    @Published var outcomeEditorHeight: CGFloat = Layout.outcomeMinHeight
    @Published private(set) var nowStates: [String: TimeState] = [:]   // 只在今天页有意义

    let dir: URL
    weak var stats: StatsStore?
    private let fm = FileManager.default
    private var signature = ""
    private var timer: Timer?
    private var nowTimer: Timer?
    private var statsVisible = false
    private var undoBlocks: [[String: Any]]?
    private var undoSelection: String?
    private var undoDayKey: String?
    private var pendingNewID: String?
    private var outcomeDayKey: String?   // 记录区是在哪一天展开的
    private var outcomeDayURL: URL?

    init(dir: URL, stats: StatsStore?) {
        self.dir = dir
        self.stats = stats
        reload()
    }

    func startWatching() {
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.reloadIfChanged()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refreshNowClock()
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
        stopNowClock()
    }

    // MARK: 日期

    static func keyFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    static func lastNDays(_ n: Int, from now: Date = Date()) -> [String] {
        let cal = Calendar(identifier: .gregorian)
        let kf = keyFormatter()
        return (0..<n).compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: now).map { kf.string(from: $0) }
        }.reversed()
    }

    static func lastSevenDays(from now: Date = Date()) -> [(key: String, weekday: String)] {
        lastNDays(7, from: now).reversed().map { ($0, DateText.weekday($0)) }
    }

    static func stamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    static func newID() -> String {
        var s = ""
        let chars = Array("0123456789abcdef")
        for _ in 0..<8 { s.append(chars[Int.random(in: 0..<chars.count)]) }
        return s
    }

    static func validID(_ s: String) -> Bool {
        s.range(of: "^[0-9a-f]{8}$", options: .regularExpression) != nil
    }

    // MARK: 读取

    private func fileURL(_ key: String) -> URL {
        dir.appendingPathComponent("\(key).json")
    }

    private var latestURL: URL? {
        let u = dir.appendingPathComponent("latest.json").resolvingSymlinksInPath()
        return fm.fileExists(atPath: u.path) ? u : nil
    }

    private func mtime(_ url: URL) -> String {
        guard let d = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return "-" }
        return String(d.timeIntervalSince1970)
    }

    private func currentSignature() -> String {
        var parts = Store.lastSevenDays().map { "\($0.key)=\(mtime(fileURL($0.key)))" }
        if let l = latestURL { parts.append("latest=\(l.path)@\(mtime(l))") }
        return parts.joined(separator: "|")
    }

    private func loadDay(_ key: String, weekday fallback: String, isToday: Bool, migrate: Bool) -> DayDigest {
        let url = PlanIO.fileURL(key, in: dir).resolvingSymlinksInPath()
        guard fm.fileExists(atPath: url.path) else {
            return DayDigest(key: key, weekday: fallback, isToday: isToday, day: nil, broken: false)
        }
        guard let loaded = try? PlanIO.read(key, in: dir) else {
            return DayDigest(key: key, weekday: fallback, isToday: isToday, day: nil, broken: true)
        }
        // root 保留整份原始 JSON：reflection、title/subtitle 以及任何不认识的字段都不拆解，
        // 写回时直接基于它改 blocks，读者不认识的东西也会原样带回。
        var obj = loaded.root
        if loaded.changed, migrate {
            obj["updated_at"] = Store.stamp()
            try? PlanIO.write(obj, to: url, backup: false)
        }
        let blocks = (obj["blocks"] as? [[String: Any]]) ?? []
        let weekday = DateText.weekday(key)
        let day = DayData(key: key, url: url, raw: obj, weekday: weekday,
                          footer: Raw.string(obj, "footer"),
                          blocks: blocks.map { Raw.block($0) })
        return DayDigest(key: key, weekday: weekday, isToday: isToday, day: day, broken: false)
    }

    func reloadIfChanged() {
        guard editing == nil, expandedOutcome == nil else { return }   // 正在输入时不打断
        if currentSignature() != signature { reload() }
    }

    // 写之前先确认没有外部改动，有就重新读一遍再改。
    private func refreshIfChanged() {
        if currentSignature() != signature { reload() }
    }

    func reload() {
        let seven = Store.lastSevenDays()
        let k = seven.first?.key ?? ""
        todayKey = k

        var digests: [DayDigest] = []
        var today: DayData?
        for (i, d) in seven.enumerated() {
            let dig = loadDay(d.key, weekday: d.weekday, isToday: i == 0, migrate: i == 0)
            if i == 0 { today = dig.day }
            digests.append(dig)
        }
        days = digests
        todayDay = today
        weekDone = digests.compactMap { $0.day?.doneCount }.reduce(0, +)
        weekTotal = digests.compactMap { $0.day?.blocks.count }.reduce(0, +)

        // 空日子也在近七天里，照样能点进去；只有日期彻底不在窗口内才退回今天。
        if let v = viewingKey, !digests.contains(where: { $0.key == v }) {
            viewingKey = nil
        }
        if let s = selectedID, !(shownDay?.blocks.contains { $0.id == s } ?? false) {
            selectedID = nil
        }
        if let k = undoDayKey, k != shownKey {
            undoBlocks = nil
            undoSelection = nil
            undoDayKey = nil
        }
        if let e = editing, !(shownDay?.blocks.contains { $0.id == e.blockID } ?? false) {
            editing = nil
        }
        if let o = expandedOutcome, !(shownDay?.blocks.contains { $0.id == o } ?? false) {
            expandedOutcome = nil
        }
        if let d = todayDay {
            stats?.upsert(todayKey, total: d.blocks.count, done: d.doneCount)
        }
        if let shown = shownDigest, shown.broken {
            errorText = L.parseFailed("\(shown.key).json")
        } else {
            errorText = nil
        }
        signature = currentSignature()
        refreshNowClock()
    }

    // MARK: 当前时段

    // 统计窗口盖在前面时也算「不在今天页」，停表省电；关掉后立刻重算。
    func setStatsVisible(_ on: Bool) {
        guard statsVisible != on else { return }
        statsVisible = on
        refreshNowClock()
    }

    // 回到前台时调用：先确认该不该跑，再立刻算一遍，不等下一分钟。
    func refreshNow() {
        refreshNowClock()
        recalcNow()
    }

    private func refreshNowClock() {
        if nowActive {
            if nowTimer == nil { startNowClock() }
            recalcNow()
        } else {
            stopNowClock()
        }
    }

    private func startNowClock() {
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.recalcNow()
        }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        nowTimer = t
        nowLog("clock start")
    }

    private func stopNowClock() {
        let wasRunning = nowTimer != nil
        nowTimer?.invalidate()
        nowTimer = nil
        if !nowStates.isEmpty { nowStates = [:] }
        if wasRunning { nowLog("clock stop") }
    }

    // 每分钟、文件重载、回到前台都会走这里；状态没变就不发布，少刷界面。
    private func recalcNow() {
        guard nowActive, let day = todayDay else {
            if !nowStates.isEmpty { nowStates = [:] }
            return
        }
        let next = TimeStatus.states(day.blocks.map { (id: $0.id, time: $0.time) }, at: Date())
        nowLog("recalc \(day.blocks.count) entries, now=\(next.values.filter { $0 == .now }.count)")
        if next != nowStates { nowStates = next }
    }

    private func nowLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["DAYPLAN_NOW_DEBUG"] == "1" else { return }
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        FileHandle.standardError.write(Data("[now] \(stamp) \(message)\n".utf8))
    }

    // MARK: 展示状态

    // 当前显示的那一天：一周视图点进来的历史日期，否则是今天。
    var shownKey: String { viewingKey ?? todayKey }

    var shownDigest: DayDigest? { days.first(where: { $0.key == shownKey }) }

    // 还没建文件的日子给一份空白模型：可看、可点「添加」，第一次写入时才落盘。
    // 文件存在但解析失败时返回 nil，交给空状态显示错误，避免覆盖坏文件。
    var shownDay: DayData? {
        if let d = shownDigest?.day { return d }
        if shownDigest?.broken == true { return nil }
        return emptyDay(shownKey)
    }

    private func emptyDay(_ key: String) -> DayData {
        DayData(key: key,
                url: PlanIO.fileURL(key, in: dir),
                raw: PlanIO.newDayRoot(key),
                weekday: DateText.weekday(key),
                footer: "",
                blocks: [])
    }

    var shownIsToday: Bool { shownKey == todayKey }
    var isHistorical: Bool { shownKey != todayKey }

    // 显示中的那天只要文件能读就能改：今天和历史一视同仁；文件不存在则第一次操作时新建。
    var editable: Bool { shownDigest?.broken != true }

    // 当前时段只对今天算；看历史日期时停表，圆点保持常态。
    var nowActive: Bool { mode == .day && shownIsToday && editable && !statsVisible && todayDay != nil }

    // 文件还不存在时给一句提示；只读横幅已经取消。
    var banner: String? {
        guard shownDigest?.day == nil, shownDigest?.broken != true else { return nil }
        return L.noDayPlan
    }

    var canUndo: Bool { editable && undoBlocks != nil }

    func select(_ id: String?) { selectedID = id }

    func toggleMode() {
        finishEditing()
        selectedID = nil
        mode = (mode == .day) ? .week : .day
        refreshNowClock()
    }

    func show(_ m: Mode) {
        finishEditing()
        selectedID = nil
        if m == .day { viewingKey = nil }
        mode = m
        refreshNowClock()
    }

    func openDay(_ key: String) {
        guard days.contains(where: { $0.key == key }) else { return }
        finishEditing()
        selectedID = nil
        viewingKey = (key == todayKey) ? nil : key
        mode = .day
        refreshNowClock()
    }

    func backToToday() {
        finishEditing()
        selectedID = nil
        viewingKey = nil
        mode = .day
        refreshNowClock()
    }

    // MARK: 编辑

    func finishEditing() {
        ActiveEditor.commitNow()
        if editing != nil { editing = nil }
        ActiveOutcome.commitNow()
        if expandedOutcome != nil { expandedOutcome = nil }
    }

    func commitEdit(_ target: EditTarget, value: String) {
        editing = nil
        refreshIfChanged()
        guard editable, let day = shownDay,
              var blocks = day.raw["blocks"] as? [[String: Any]],
              let i = blocks.firstIndex(where: { Raw.string($0, "id") == target.blockID }) else { return }

        var changed = false
        switch target.field {
        case .text:
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if target.blockID == pendingNewID, v.isEmpty, Raw.string(blocks[i], "note").isEmpty {
                blocks.remove(at: i)
                pendingNewID = nil
                applyBlocks(blocks)
                return
            }
            if v != Raw.string(blocks[i], "text") { blocks[i]["text"] = v; changed = true }
        case .note:
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if v != Raw.string(blocks[i], "note") {
                if v.isEmpty { blocks[i].removeValue(forKey: "note") } else { blocks[i]["note"] = v }
                changed = true
            }
        case .time:
            let v = Fmt.normalizeTime(value)
            if v != Fmt.normalizeTime(Raw.string(blocks[i], "time")) { blocks[i]["time"] = v; changed = true }
        case .units:
            let v = value.trimmingCharacters(in: .whitespaces)
            let old = Raw.number(blocks[i], "units")
            if v.isEmpty {
                if old != nil { blocks[i].removeValue(forKey: "units"); changed = true }
            } else if let d = Double(v), d.isFinite, d >= 0, d <= 1000 {
                if old != d { blocks[i]["units"] = d; changed = true }
            } else {
                return   // 只接受 0…1000 的有限数字
            }
        }
        pendingNewID = nil
        if changed { applyBlocks(blocks) }
    }

    func cancelEdit() {
        let id = editing?.blockID
        editing = nil
        guard let target = id, target == pendingNewID else { return }
        pendingNewID = nil
        guard editable, let day = shownDay,
              var blocks = day.raw["blocks"] as? [[String: Any]],
              let i = blocks.firstIndex(where: { Raw.string($0, "id") == target }) else { return }
        blocks.remove(at: i)
        selectedID = nil
        applyBlocks(blocks)
    }

    func toggle(_ id: String) {
        finishEditing()
        refreshIfChanged()
        guard editable, let day = shownDay,
              var blocks = day.raw["blocks"] as? [[String: Any]],
              let i = blocks.firstIndex(where: { Raw.string($0, "id") == id }) else { return }
        blocks[i]["done"] = !Raw.bool(blocks[i], "done")
        applyBlocks(blocks)
    }

    func addBlock() {
        finishEditing()
        refreshIfChanged()
        guard editable, let day = shownDay,
              var blocks = day.raw["blocks"] as? [[String: Any]] else { return }
        let id = Store.newID()
        blocks.append(["id": id, "origin": "user", "time": "", "units": 1,
                       "text": "", "note": "", "done": false])
        applyBlocks(blocks)
        pendingNewID = id
        selectedID = id
        editing = EditTarget(blockID: id, field: .text)
        scrollTarget = id
    }

    func deleteSelected() {
        finishEditing()
        refreshIfChanged()
        guard editable, let id = selectedID, let day = shownDay,
              var blocks = day.raw["blocks"] as? [[String: Any]],
              let i = blocks.firstIndex(where: { Raw.string($0, "id") == id }) else { return }
        let snapshot = blocks
        blocks.remove(at: i)
        undoBlocks = snapshot
        undoSelection = id
        undoDayKey = shownKey
        selectedID = nil
        applyBlocks(blocks, keepUndo: true)
    }

    func undoDelete() {
        finishEditing()
        guard editable, let snap = undoBlocks, undoDayKey == shownKey else {
            undoBlocks = nil
            undoSelection = nil
            undoDayKey = nil
            return
        }
        undoBlocks = nil
        selectedID = undoSelection
        undoSelection = nil
        undoDayKey = nil
        applyBlocks(snap)
    }

    func move(_ id: String, by delta: Int) {
        finishEditing()
        refreshIfChanged()
        guard editable, let day = shownDay,
              var blocks = day.raw["blocks"] as? [[String: Any]],
              let i = blocks.firstIndex(where: { Raw.string($0, "id") == id }) else { return }
        let j = i + delta
        guard blocks.indices.contains(j) else { return }
        let b = blocks.remove(at: i)
        blocks.insert(b, at: j)
        applyBlocks(blocks)
        selectedID = id
    }

    func canMove(_ id: String, by delta: Int) -> Bool {
        guard editable, let day = shownDay,
              let i = day.blocks.firstIndex(where: { $0.id == id }) else { return false }
        return day.blocks.indices.contains(i + delta)
    }

    // MARK: 结果记录

    func setHover(_ id: String, _ on: Bool) {
        if on {
            if hoveredID != id { hoveredID = id }
        } else if hoveredID == id {
            hoveredID = nil
        }
    }

    func expandOutcome(_ id: String) {
        guard editable, expandedOutcome != id else { return }
        ActiveEditor.commitNow()
        if editing != nil { editing = nil }
        ActiveOutcome.commitNow()   // 上一条还开着：先存好、收起来
        // 提交行内编辑可能顺手删掉了刚建的空条目，这里要重新确认
        guard editable, let day = shownDay,
              day.blocks.contains(where: { $0.id == id }) else {
            if expandedOutcome != nil { expandedOutcome = nil }
            return
        }
        outcomeDayKey = shownKey
        outcomeDayURL = day.url
        outcomeEditorHeight = Layout.outcomeMinHeight
        expandedOutcome = id
    }

    // 收起（「收起」按钮与 Esc 都走这里）：存不进去就不收，别让字丢了。
    func collapseOutcome(_ id: String) {
        ActiveOutcome.commitNow()
        if expandedOutcome == id { expandedOutcome = nil }
    }

    func closeOutcome(_ id: String, _ text: String) {
        if saveOutcome(id, text), expandedOutcome == id {
            expandedOutcome = nil
            outcomeDayKey = nil
            outcomeDayURL = nil
        }
    }

    func clearOutcome(_ id: String) {
        ActiveOutcome.clearNow()
        _ = saveOutcome(id, "")
    }

    // 只有内容真的变了才写盘；写法和其它字段一样基于原始 JSON 字典改。
    // 记录区开着时轮询是停的，所以跨午夜 / 今天文件被换掉都可能发生：
    // 那时仍然写回展开时那一天的文件，不能让框里的字凭空消失。
    @discardableResult
    func saveOutcome(_ id: String, _ text: String) -> Bool {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        refreshIfChanged()
        if let day = shownDay, editable, outcomeDayKey == nil || outcomeDayKey == day.key {
            guard var blocks = day.raw["blocks"] as? [[String: Any]] else { return false }
            guard let i = blocks.firstIndex(where: { Raw.string($0, "id") == id }) else { return true }
            let cur = Raw.string(blocks[i], "outcome").trimmingCharacters(in: .whitespacesAndNewlines)
            if v == cur { return true }
            if v.isEmpty {
                blocks[i]["outcome"] = ""
                blocks[i].removeValue(forKey: "outcome_at")
            } else {
                blocks[i]["outcome"] = v
                blocks[i]["outcome_at"] = Store.stamp()
            }
            return writeBlocks(blocks)
        }
        if let url = outcomeDayURL { return writeOutcome(id, v, to: url) }
        return true
    }

    // 写回某一天的某个条目：整份读进来、只改这一条，未知字段照旧保留。
    @discardableResult
    private func writeOutcome(_ id: String, _ v: String, to url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var blocks = root["blocks"] as? [[String: Any]],
              let i = blocks.firstIndex(where: { Raw.string($0, "id") == id }) else { return true }
        let cur = Raw.string(blocks[i], "outcome").trimmingCharacters(in: .whitespacesAndNewlines)
        if v == cur { return true }
        if v.isEmpty {
            blocks[i]["outcome"] = ""
            blocks[i].removeValue(forKey: "outcome_at")
        } else {
            blocks[i]["outcome"] = v
            blocks[i]["outcome_at"] = Store.stamp()
        }
        root["blocks"] = blocks
        root["updated_at"] = Store.stamp()
        do {
            try write(root, to: url)
            writeError = nil
            reload()
            return true
        } catch {
            writeError = L.writeFailed(error.localizedDescription)
            return false
        }
    }

    // MARK: 写回

    // 每次都按原始字典改，再整份写回；未知字段不动。
    private func applyBlocks(_ blocks: [[String: Any]], keepUndo: Bool = false) {
        _ = writeBlocks(blocks, keepUndo: keepUndo)
    }

    @discardableResult
    private func writeBlocks(_ blocks: [[String: Any]], keepUndo: Bool = false) -> Bool {
        guard editable, let day = shownDay else { return false }
        var root = day.raw
        root["blocks"] = blocks
        root["updated_at"] = Store.stamp()
        let url = day.url
        let isNew = !fm.fileExists(atPath: url.path)
        do {
            if isNew { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
            // 新建的文件没有旧版，不留 prev；已有文件照旧备份。
            try write(root, to: url, backup: !isNew)
            // 今天的第一条落盘时，latest.json 跟着指向这份新文件。
            if isNew, day.key == todayKey { PlanIO.touchLatest(day.key, in: dir) }
            writeError = nil
            if !keepUndo { undoBlocks = nil; undoSelection = nil; undoDayKey = nil }
            reload()
            return true
        } catch {
            writeError = L.writeFailed(error.localizedDescription)
            return false
        }
    }

    // 写前留一份 <date>.prev.json，只保留最近一份；具体做法见 PlanIO.write。
    private func write(_ root: [String: Any], to url: URL, backup: Bool = true) throws {
        try PlanIO.write(root, to: url, backup: backup)
    }
}


// MARK: - 统计

struct StatDay: Equatable {
    var total: Int
    var done: Int
    var rate: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

struct DayStat: Identifiable, Equatable {
    let key: String      // yyyy-MM-dd
    let total: Int
    let done: Int
    let isToday: Bool
    var id: String { key }
    var rate: Double { total == 0 ? 0 : Double(done) / Double(total) }
    var hasData: Bool { total > 0 }
}

// stats.json 只记每天的总数/完成数，供柱状图与点评用；删日程文件不动这里。
final class StatsStore: ObservableObject {
    @Published private(set) var days: [String: StatDay] = [:]   // 全量历史
    @Published private(set) var series: [DayStat] = []         // 最近 30 天，含没有数据的日期
    @Published private(set) var comment: String?
    @Published private(set) var commentIsExternal = false
    @Published var selectedKey: String?                        // 点中的柱

    let dir: URL
    private var root: [String: Any] = ["schema": 1]
    private let fm = FileManager.default

    init(dir: URL) {
        self.dir = dir
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
        loadComment()
        refreshSeries()
    }

    private var fileURL: URL { dir.appendingPathComponent("stats.json") }
    private var commentURL: URL { dir.appendingPathComponent("comment.txt") }

    // MARK: 读写

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            root = ["schema": 1]
            days = [:]
            refreshSeries()
            return
        }
        root = obj
        var parsed: [String: StatDay] = [:]
        if let map = obj["days"] as? [String: Any] {
            for (k, v) in map {
                guard let d = v as? [String: Any] else { continue }
                parsed[k] = StatDay(total: Int(Raw.number(d, "total") ?? 0),
                                    done: Int(Raw.number(d, "done") ?? 0))
            }
        }
        days = parsed
        refreshSeries()
    }

    func reload() {
        load()
        loadComment()
        refreshSeries()
    }

    private func save() {
        let daysMap = days.mapValues { ["total": $0.total, "done": $0.done] }
        root["schema"] = 1
        root["days"] = daysMap
        let prev = dir.appendingPathComponent("stats.prev.json")
        if fm.fileExists(atPath: fileURL.path) {
            try? fm.removeItem(at: prev)
            try? fm.copyItem(at: fileURL, to: prev)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return }
        var out = data
        out.append(0x0A)
        try? out.write(to: fileURL, options: .atomic)
    }

    func upsert(_ key: String, total: Int, done: Int) {
        guard key.count == 10 else { return }
        if let cur = days[key], cur.total == total, cur.done == done { return }
        days[key] = StatDay(total: total, done: done)
        save()
        refreshSeries()
    }

    // 首次启动 / 缺某天时，从日程目录只读回填；文件删了也不从 stats 删。
    func backfill(from plansDir: URL) {
        let files = (try? fm.contentsOfDirectory(at: plansDir, includingPropertiesForKeys: nil)) ?? []
        var changed = false
        for f in files where f.pathExtension == "json" {
            let name = f.lastPathComponent
            if name == "latest.json" || name.contains(".prev.") { continue }
            guard let data = try? Data(contentsOf: f),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            var key = Raw.string(obj, "date")
            if key.count != 10 { key = f.deletingPathExtension().lastPathComponent }
            guard key.count == 10, days[key] == nil else { continue }
            let blocks = (obj["blocks"] as? [[String: Any]]) ?? []
            let done = blocks.filter { Raw.bool($0, "done") }.count
            days[key] = StatDay(total: blocks.count, done: done)
            changed = true
        }
        if changed { save(); refreshSeries() }
    }

    // MARK: 点评

    func loadComment() {
        guard fm.fileExists(atPath: commentURL.path),
              let attrs = try? fm.attributesOfItem(atPath: commentURL.path),
              let m = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(m) <= 48 * 3600,
              let text = try? String(contentsOf: commentURL, encoding: .utf8) else {
            comment = nil
            commentIsExternal = false
            return
        }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        comment = t.isEmpty ? nil : t
        commentIsExternal = !t.isEmpty
    }

    // MARK: 近 30 天

    // 固定 30 根柱：有数据的画柱，没有数据的日子留空但不跳过日期。
    private func refreshSeries() {
        let keys = Store.lastNDays(30)
        let today = keys.last
        series = keys.map { key in
            let d = days[key]
            return DayStat(key: key,
                           total: d?.total ?? 0,
                           done: d?.done ?? 0,
                           isToday: key == today)
        }
        if let s = selectedKey, series.first(where: { $0.key == s && $0.hasData }) == nil {
            selectedKey = nil
        }
    }

    var selectedDay: DayStat? {
        guard let k = selectedKey else { return nil }
        return series.first { $0.key == k && $0.hasData }
    }

    func selectDay(_ key: String) {
        selectedKey = (selectedKey == key) ? nil : key
    }

    var windowDone: Int { series.reduce(0) { $0 + $1.done } }
    var windowTotal: Int { series.reduce(0) { $0 + $1.total } }
    var windowRate: Double { windowTotal == 0 ? 0 : Double(windowDone) / Double(windowTotal) }
    var windowIsEmpty: Bool { !series.contains { $0.hasData } }

    func windowDays() -> [(key: String, day: DayStat)] {
        series.filter { $0.hasData }.map { (key: $0.key, day: $0) }
    }
}

// MARK: - 格式化

enum Fmt {
    static func dateLabel(_ raw: String) -> String {
        let p = raw.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return raw }
        return "\(m)月\(d)日"
    }

    static func shortDate(_ key: String) -> String {
        String(key.dropFirst(5))
    }

    static func time(_ raw: String) -> String {
        raw.replacingOccurrences(of: " – ", with: "–")
            .replacingOccurrences(of: " - ", with: "–")
    }

    static func units(_ v: Double) -> String {
        guard v.isFinite, abs(v) < 1_000_000 else { return "—" }
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    static func unitsInput(_ v: Double) -> String {
        guard v.isFinite, abs(v) < 1_000_000 else { return "" }
        return v == v.rounded() ? String(Int(v)) : String(v)
    }

    static func percent(_ done: Int, _ total: Int) -> String {
        total == 0 ? "—" : "\(Int((Double(done) / Double(total) * 100).rounded()))%"
    }

    // 输入允许 "14:30"、"14:30-15:30"、"9:00 ~ 10:30"，统一成排版用的写法。
    static func normalizeTime(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        let parts = s.split(whereSeparator: { "-–—~～".contains($0) })
        func tidy(_ t: Substring) -> String {
            let v = t.trimmingCharacters(in: .whitespaces)
            let p = v.split(separator: ":")
            if p.count == 2, let h = Int(p[0]), let m = Int(p[1]), m >= 0, m < 60 {
                return String(format: "%02d:%02d", h, m)
            }
            return v
        }
        if parts.count == 2 {
            return "\(tidy(parts[0])) – \(tidy(parts[1]))"
        }
        return tidy(s[s.startIndex...])
    }
}

// MARK: - 当前时段（v10）

// time 的解析与状态计算都在这里，纯函数，方便单独测。
// 支持 "14:30 – 17:30"、"09:00 - 10:30"、"14:30"、空串；解析失败一律 .none，不报错。
// 只有开始时间时，结束取「下一条有时间的开始」与 23:59 的较小值；跨午夜不支持。

enum TimeState: String, Equatable {
    case now
    case past
    case next
    case none
}

struct TimeSlot {
    let start: Int   // 当天 0 点起的秒数
    let end: Int

    func contains(_ seconds: Int) -> Bool { seconds >= start && seconds < end }
}

enum TimeStatus {
    private static let endOfDay = 23 * 3600 + 59 * 60
    private static let pattern = try! NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})"#)

    // 取前两个 HH:mm；格式与取值都要合法。
    private static func times(_ raw: String) -> [(hour: Int, minute: Int)]? {
        let ns = raw as NSString
        let found = pattern.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        guard !found.isEmpty else { return nil }
        var out: [(hour: Int, minute: Int)] = []
        for m in found.prefix(2) {
            guard m.numberOfRanges == 3,
                  let h = Int(ns.substring(with: m.range(at: 1))),
                  let mm = Int(ns.substring(with: m.range(at: 2))),
                  (0...23).contains(h), (0...59).contains(mm) else { return nil }
            out.append((h, mm))
        }
        return out
    }

    private static func seconds(_ t: (hour: Int, minute: Int)) -> Int {
        t.hour * 3600 + t.minute * 60
    }

    private static func clock(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
    }

    // 第一个时间是开始；第二个是结束。只有开始时用 nextStart 兜底。
    static func slot(_ raw: String, nextStart: String? = nil) -> TimeSlot? {
        guard let parsed = times(raw), let first = parsed.first else { return nil }
        let start = seconds(first)
        if parsed.count >= 2 {
            let end = seconds(parsed[1])
            guard end > start else { return nil }   // 结束早于/等于开始：无时间
            return TimeSlot(start: start, end: end)
        }
        var end = endOfDay
        if let nextStart, let next = times(nextStart)?.first {
            end = min(seconds(next), endOfDay)
        }
        guard end > start else { return nil }
        return TimeSlot(start: start, end: end)
    }

    static func state(_ raw: String, at now: Date, nextStart: String? = nil,
                      calendar: Calendar = .current) -> TimeState {
        guard let slot = slot(raw, nextStart: nextStart) else { return .none }
        let t = clock(now, calendar)
        if t < slot.start { return .next }
        if t >= slot.end { return .past }
        return .now
    }

    // 一次算一整天的条目。同一时刻最多一个 now：重叠时开始更早的赢，另一条按 next。
    static func states(_ entries: [(id: String, time: String)], at now: Date,
                       calendar: Calendar = .current) -> [String: TimeState] {
        var found: [(id: String, slot: TimeSlot, index: Int)] = []
        for (i, e) in entries.enumerated() {
            // 只有开始时间时，往后找最近一条能解析出开始的条目。
            var nextStart: String?
            if i + 1 < entries.count {
                nextStart = entries[(i + 1)...].lazy.compactMap { item -> String? in
                    guard let t = times(item.time)?.first else { return nil }
                    return String(format: "%02d:%02d", t.hour, t.minute)
                }.first
            }
            if let slot = slot(e.time, nextStart: nextStart) {
                found.append((e.id, slot, i))
            }
        }

        let t = clock(now, calendar)
        var out: [String: TimeState] = [:]
        for e in entries { out[e.id] = TimeState.none }
        for e in found {
            if t < e.slot.start { out[e.id] = .next }
            else if t >= e.slot.end { out[e.id] = .past }
            else { out[e.id] = .now }
        }

        let active = found.filter { $0.slot.contains(t) }
        if let winner = active.min(by: { a, b in
            a.slot.start == b.slot.start ? a.index < b.index : a.slot.start < b.slot.start
        }) {
            out[winner.id] = .now
            for e in active where e.id != winner.id { out[e.id] = .next }
        }
        return out
    }
}

// MARK: - 视图

struct CheckMark: View {
    let done: Bool
    let dim: Bool

    var body: some View {
        ZStack {
            if done {
                Circle().fill(Palette.done)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Circle().stroke(Palette.secondary.opacity(dim ? 0.25 : 0.45), lineWidth: 1.2)
            }
        }
        .frame(width: 18, height: 18)
    }
}

struct OriginDot: View {
    let user: Bool
    var state: TimeState = .none

    var body: some View {
        Circle()
            .fill(state == .now ? Palette.nowDot : (user ? Palette.time.opacity(0.85) : Palette.inkAlpha(0.13, 0.20)))
            .frame(width: state == .now ? 6 : 4, height: state == .now ? 6 : 4)

    }
}

// MARK: 行内编辑

// 全局只允许一个编辑框；点别处、切视图、写盘前都先 commit。
enum ActiveEditor {
    static weak var field: InlineField?

    static func commitNow() {
        guard let f = field else { return }
        field = nil
        f.forceCommit()
    }
}

final class InlineField: NSTextField, NSTextFieldDelegate {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private(set) var live = ""
    private(set) var closed = false

    static func make(text: String, font: NSFont, color: NSColor, placeholder: String) -> InlineField {
        let f = InlineField()
        f.live = text
        f.stringValue = text
        f.font = font
        f.textColor = color
        f.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: Palette.doneNS, .font: font])
        f.isBordered = false
        f.isBezeled = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.usesSingleLineMode = true
        f.lineBreakMode = .byTruncatingTail
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.cell?.usesSingleLineMode = true
        f.delegate = f
        f.isEditable = true
        f.isSelectable = true
        f.isContinuous = true
        f.isAutomaticTextCompletionEnabled = false
        return f
    }

    func controlTextDidChange(_ obj: Notification) {
        if let tv = obj.userInfo?["NSFieldEditor"] as? NSTextView {
            live = tv.string
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let movement = (obj.userInfo?["NSTextMovement"] as? Int).flatMap { NSTextMovement(rawValue: $0) }
        if movement == .cancel {
            cancel()
        } else {
            if let tv = obj.userInfo?["NSFieldEditor"] as? NSTextView { live = tv.string }
            commit(live)
        }
    }

    // 单行框默认不会因为回车结束编辑，这里显式处理回车与 Esc。
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
           commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            live = textView.string
            finish(committing: true)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finish(committing: false)
            return true
        }
        return false
    }

    private func finish(committing: Bool) {
        guard !closed else { return }
        closed = true
        if let w = window, let ed = currentEditor(), w.firstResponder === ed {
            w.makeFirstResponder(nil)
        }
        if committing { onCommit?(live) } else { onCancel?() }
    }

    func forceCommit() {
        guard !closed else { return }
        if let ed = currentEditor() as? NSTextView { live = ed.string }
        if window != nil { window?.makeFirstResponder(nil) }
        commit(live)
    }

    func commit(_ v: String) {
        guard !closed else { return }
        closed = true
        onCommit?(v)
    }

    func cancel() {
        guard !closed else { return }
        closed = true
        onCancel?()
    }
}

struct InlineTextField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let font: NSFont
    let color: NSColor
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> InlineField {
        let f = InlineField.make(text: text, font: font, color: color, placeholder: placeholder)
        f.onCommit = onCommit
        f.onCancel = onCancel
        ActiveEditor.field = f
        focus(f, tries: 0)
        return f
    }

    func updateNSView(_ nsView: InlineField, context: Context) {}

    static func dismantleNSView(_ nsView: InlineField, coordinator: Void) {
        if ActiveEditor.field === nsView { ActiveEditor.field = nil }
        if !nsView.closed, let cb = nsView.onCommit {
            let v = nsView.live
            DispatchQueue.main.async { cb(v) }   // 异常移除时也不丢字
        }
        nsView.onCommit = nil
        nsView.onCancel = nil
    }

    private func focus(_ f: InlineField, tries: Int) {
        DispatchQueue.main.async {
            if let w = f.window {
                w.makeFirstResponder(f)
                f.currentEditor()?.selectAll(nil)
            } else if tries < 4 {
                focus(f, tries: tries + 1)
            }
        }
    }
}

// MARK: 结果记录（多行）

// 同 ActiveEditor：全局只允许一个记录区展开，点别处 / Esc / 切视图都先落盘再收起。
enum ActiveOutcome {
    static weak var field: OutcomeField?

    static func commitNow() {
        guard let f = field else { return }
        field = nil
        if let w = f.window { w.makeFirstResponder(nil) }
        f.commit()
    }

    static func clearNow() {
        field?.clearText()
    }
}

final class OutcomeField: NSTextView, NSTextViewDelegate {
    var onCommit: ((String) -> Void)?   // 收起：保存 + 收起
    var onBlur: ((String) -> Void)?     // 失焦：只保存，不收起（否则下面的点击会被吞掉）
    var onHeight: ((CGFloat) -> Void)?
    var blockID = ""
    private(set) var closed = false
    private let ownUndo = UndoManager()

    static func make(text: String) -> OutcomeField {
        let f = OutcomeField(frame: NSRect(x: 0, y: 0, width: 200, height: Layout.outcomeMinHeight))
        f.isRichText = false
        f.importsGraphics = false
        f.drawsBackground = false
        f.isEditable = true
        f.isSelectable = true
        f.allowsUndo = true
        f.isHorizontallyResizable = false
        f.isVerticallyResizable = true
        f.autoresizingMask = [.width]
        f.minSize = NSSize(width: 0, height: Layout.outcomeMinHeight)
        f.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        f.textContainerInset = NSSize(width: 0, height: Layout.outcomeInset / 2)
        f.textContainer?.lineFragmentPadding = 0
        f.textContainer?.widthTracksTextView = true
        f.textContainer?.containerSize = NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        f.insertionPointColor = Palette.timeNS
        f.defaultParagraphStyle = OutcomeField.paragraph()
        f.delegate = f
        f.setContent(text)
        return f
    }

    // 每个记录框用自己的一份撤销栈，别和窗口共享（收起后不该留旧记录）。
    func undoManager(for view: NSTextView) -> UndoManager? { ownUndo }

    static func paragraph() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = Layout.outcomeLineHeight
        p.maximumLineHeight = Layout.outcomeLineHeight
        return p
    }

    private var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: EditFont.outcome,
         .foregroundColor: Palette.inkNS,
         .paragraphStyle: OutcomeField.paragraph()]
    }

    func setContent(_ text: String) {
        textStorage?.setAttributedString(NSAttributedString(string: text, attributes: bodyAttributes))
        typingAttributes = bodyAttributes
    }

    // 「清空」：走 NSTextView 的替换流程，Cmd+Z 还回得来；写盘由 Store 负责。
    func clearText() {
        let all = NSRange(location: 0, length: (string as NSString).length)
        if shouldChangeText(in: all, replacementString: "") {
            textStorage?.replaceCharacters(in: all, with: "")
            didChangeText()
        } else {
            setContent("")
            onHeight?(measuredHeight())
        }
    }

    func textDidChange(_ notification: Notification) {
        onHeight?(measuredHeight())
    }

    func textDidEndEditing(_ notification: Notification) {
        // 只落盘：点一下别处就立刻收起会让这一下点击落空（行会重排）。
        onBlur?(string)
    }

    // Esc 收起并保存。
    override func cancelOperation(_ sender: Any?) {
        commit()
    }

    // 没夹到 6 行的高度，用来撑开文档视图（否则超过 6 行滚不到）。
    func contentHeight() -> CGFloat {
        guard let lm = layoutManager, let tc = textContainer else { return Layout.outcomeMinHeight }
        lm.ensureLayout(for: tc)
        let h = lm.usedRect(for: tc).height + textContainerInset.height * 2
        guard h.isFinite else { return Layout.outcomeMinHeight }
        return max(Layout.outcomeMinHeight, ceil(h))
    }

    // 上报给 Store 的高度：2–6 行。
    func measuredHeight() -> CGFloat {
        min(Layout.outcomeMaxHeight, contentHeight())
    }

    func commit() {
        guard !closed else { return }
        closed = true
        onCommit?(string)
    }
}

// 文本比自己高时内部滚动；框的高度始终由 Store 给（随内容 2–6 行）。
final class OutcomeScroller: NSScrollView {
    var onHeight: ((CGFloat) -> Void)?
    private var reported: CGFloat = 0

    static func make(text: String) -> (OutcomeScroller, OutcomeField) {
        let sv = OutcomeScroller()
        sv.drawsBackground = false
        sv.borderType = .noBorder
        sv.hasVerticalScroller = false
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.verticalScrollElasticity = .none
        sv.horizontalScrollElasticity = .none
        let tv = OutcomeField.make(text: text)
        sv.documentView = tv
        return (sv, tv)
    }

    override func layout() {
        super.layout()
        guard let tv = documentView as? OutcomeField else { return }
        let w = max(40, contentSize.width)
        // 先同步宽度，再按宽度量高度
        if abs(tv.frame.width - w) > 0.5 {
            tv.setFrameSize(NSSize(width: w, height: max(tv.frame.height, contentSize.height)))
        }
        let need = tv.contentHeight()
        let h = max(need, contentSize.height)
        if abs(tv.frame.height - h) > 0.5 {
            tv.setFrameSize(NSSize(width: w, height: h))
        }
        let capped = tv.measuredHeight()
        if abs(capped - reported) > 0.5 {
            reported = capped
            DispatchQueue.main.async { [weak self] in self?.onHeight?(capped) }
        }
    }
}

struct OutcomeTextView: NSViewRepresentable {
    let blockID: String
    let text: String
    let onCommit: (String) -> Void
    let onBlur: (String) -> Void
    let onHeight: (CGFloat) -> Void

    func makeNSView(context: Context) -> OutcomeScroller {
        let (sv, tv) = OutcomeScroller.make(text: text)
        tv.blockID = blockID
        tv.onCommit = onCommit
        tv.onBlur = onBlur
        tv.onHeight = onHeight
        sv.onHeight = onHeight
        ActiveOutcome.field = tv
        focus(tv, tries: 0)
        return sv
    }

    func updateNSView(_ nsView: OutcomeScroller, context: Context) {
        guard let tv = nsView.documentView as? OutcomeField else { return }
        tv.blockID = blockID
        tv.onCommit = onCommit
        tv.onBlur = onBlur
        tv.onHeight = onHeight
        nsView.onHeight = onHeight
    }

    static func dismantleNSView(_ nsView: OutcomeScroller, coordinator: Void) {
        guard let tv = nsView.documentView as? OutcomeField else { return }
        if ActiveOutcome.field === tv { ActiveOutcome.field = nil }
        if !tv.closed, let cb = tv.onCommit {
            let v = tv.string
            DispatchQueue.main.async { cb(v) }   // 异常移除时也不丢字
        }
        tv.onCommit = nil
        tv.onBlur = nil
        tv.onHeight = nil
        nsView.onHeight = nil
    }

    // 视图刚挂上时 window 可能还没给，重试几次；光标放末尾并滚到可见。
    private func focus(_ tv: OutcomeField, tries: Int) {
        DispatchQueue.main.async {
            guard let w = tv.window else {
                if tries < 4 { focus(tv, tries: tries + 1) }
                return
            }
            w.makeFirstResponder(tv)
            let n = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: n, length: 0))
            tv.scrollRangeToVisible(NSRange(location: n, length: 0))
        }
    }
}

// MARK: 条目

struct BlockRow: View {
    @ObservedObject var store: Store
    @ObservedObject var settings = SettingsStore.shared
    private var L: L10n { settings.l10n }
    let block: Block
    let editable: Bool
    let nowState: TimeState

    private var field: Store.Field? {
        guard let e = store.editing, e.blockID == block.id else { return nil }
        return e.field
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Layout.timeGap) {
                timeColumn
                    .frame(width: Layout.timeColumn, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if store.editing == nil { store.select(block.id) } }
                textColumn
                    .layoutPriority(1)
                    .contentShape(Rectangle())
                    .onTapGesture { if store.editing == nil { store.select(block.id) } }
                check
                    .padding(.top, 2)
            }
            outcomeArea
        }
        .frame(minHeight: 96, alignment: .top)
        .overlay(alignment: .topTrailing) { pencilHint }
        .padding(.vertical, Layout.rowVPad)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(store.selectedID == block.id ? Palette.inkAlpha(0.045, 0.08) : Color.clear)
        )

        .onHover { store.setHover(block.id, $0) }
        .contextMenu { menu }
    }

    // MARK: 结果记录

    private var isExpanded: Bool { editable && store.expandedOutcome == block.id }

    @ViewBuilder
    private var outcomeArea: some View {
        Group {
            if isExpanded {
                outcomeEditor
            } else if block.hasOutcome {
                outcomeSummary
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.expandedOutcome)
    }

    // 没有记录时：平时什么都不显示，鼠标移进来才在右侧窄缝里浮一个小图标。
    @ViewBuilder
    private var pencilHint: some View {
        if editable, !isExpanded, !block.hasOutcome {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 11))
                .foregroundColor(Palette.secondary)
                .opacity(store.hoveredID == block.id ? 0.4 : 0)
                .frame(width: 14, height: 14)
                .allowsHitTesting(store.hoveredID == block.id)   // 透明时不吞掉勾选圈的点击
                .contentShape(Rectangle())
                .onTapGesture { store.expandOutcome(block.id) }
                .help(L.editOutcome)
                .padding(.top, 22)
                .padding(.trailing, 18)
        }
    }

    private var summaryText: String {
        block.outcome
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 有记录时：备注下方一行摘要（单行截断），点它展开。
    // 一行一条：换行即新条目，每条只显示一行，超出省略。
    private var outcomeLines: [String] {
        block.outcome
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var outcomeSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 任务与实况之间一条极淡分隔线（2026-11-24 15:14）
            Rectangle()
                .fill(Palette.inkAlpha(0.04, 0.06))
                .frame(height: 1)
                .padding(.leading, Layout.timeColumn + Layout.timeGap)
                .padding(.trailing, Layout.hPad)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(outcomeLines.prefix(2).enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .center, spacing: 5) {
                        Circle()
                            .fill(Palette.time.opacity(0.6))
                            .frame(width: 3, height: 3)
                        Text(line)
                            .font(Typo.summary)
                            .foregroundColor(block.done ? Palette.done : Palette.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                }
                if outcomeLines.count > 2 {
                    Text("…")
                        .font(Typo.summary)
                        .foregroundColor(Palette.secondary)
                        .padding(.leading, 8)
                }
            }
            .padding(.top, 6)
            .padding(.leading, Layout.timeColumn + Layout.timeGap)
        }
        .contentShape(Rectangle())
        .onTapGesture { if editable { store.expandOutcome(block.id) } }
    }

    private var outcomeEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Palette.time.opacity(0.7))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                OutcomeTextView(blockID: block.id, text: block.outcome,
                                onCommit: { v in store.closeOutcome(block.id, v) },
                                onBlur: { v in _ = store.saveOutcome(block.id, v) },
                                onHeight: { h in
                                    if store.expandedOutcome == block.id,
                                       store.outcomeEditorHeight != h {
                                        store.outcomeEditorHeight = h
                                    }
                                })
                    .frame(height: store.outcomeEditorHeight)
            }
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                Button(action: { store.collapseOutcome(block.id) }) {
                    Text(L.collapseOutcome)
                        .font(Typo.summary)
                        .foregroundColor(Palette.secondary)
                }
                .buttonStyle(.plain)
                Button(action: { store.clearOutcome(block.id) }) {
                    Text(L.clearOutcome)
                        .font(Typo.summary)
                        .foregroundColor(Palette.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 5)
        }
        .padding(.top, 4)
        .padding(.leading, Layout.timeColumn + Layout.timeGap)
        .padding(.trailing, 2)
        .transition(.opacity)
    }

    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                OriginDot(user: block.isUser, state: nowState)
                    .offset(y: -3)
                timeView
            }
            unitsView
                .padding(.leading, 9)
        }
    }

    @ViewBuilder
    private var timeView: some View {
        if field == .time {
            inlineEditor(field: .time, text: block.time, placeholder: L.phTime,
                         font: EditFont.time, color: Palette.timeNS, height: 16)
        } else {
            Text(block.time.isEmpty ? "—" : Fmt.time(block.time))
                .font(Typo.time)
                .foregroundColor(block.done ? Palette.done : Palette.time)

                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 16, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { begin(.time) }
        }
    }

    @ViewBuilder
    private var unitsView: some View {
        if field == .units {
            inlineEditor(field: .units, text: block.units.map { Fmt.unitsInput($0) } ?? "",
                         placeholder: L.phUnits, font: EditFont.units, color: Palette.doneNS, height: 14)
                .frame(width: 46)
        } else {
            Text(block.units.map { L.units($0) } ?? "")
                .font(Typo.units)
                .foregroundColor(Palette.done)
                .frame(height: 14, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { begin(.units) }
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            if field == .text {
                inlineEditor(field: .text, text: block.text, placeholder: L.phTask,
                             font: EditFont.item, color: Palette.inkNS, height: 21)
            } else {
                Text(block.text.isEmpty ? L.emptyBlock : block.text)
                    .font(Typo.item)
                    .foregroundColor(block.text.isEmpty ? Palette.done : Palette.ink)
                    .strikethrough(block.done, color: Palette.ink)
                    .opacity(block.done ? 0.55 : 1)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 21, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { begin(.text) }
            }
            if field == .note {
                inlineEditor(field: .note, text: block.note, placeholder: L.phNote,
                             font: EditFont.note, color: Palette.secondaryNS, height: 16)
            } else if !block.note.isEmpty {
                Text(block.note)
                    .font(Typo.note)
                    .foregroundColor(block.done ? Palette.done : Palette.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { begin(.note) }
            }
        }
    }

    private var check: some View {
        // 不给 Button 加 .disabled：禁用态在 SwiftUI 里会让整块区域不接收点击，
        // 而 editable 的判定曾经误伤过。改成 action 内守卫 + 放大命中区。
        Button(action: { if editable { store.toggle(block.id) } }) {
            CheckMark(done: block.done, dim: !editable)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .zIndex(2)
    }

    @ViewBuilder
    private var menu: some View {
        if editable {
            Button(L.editText) { begin(.text) }
            Button(L.editNote) { begin(.note) }
            Button(L.editTime) { begin(.time) }
            Button(L.editUnits) { begin(.units) }
            Button(L.editOutcome) { store.expandOutcome(block.id) }
            Divider()
            Button(L.moveUp) { store.move(block.id, by: -1) }
                .disabled(!store.canMove(block.id, by: -1))
            Button(L.moveDown) { store.move(block.id, by: 1) }
                .disabled(!store.canMove(block.id, by: 1))
            Divider()
            Button(L.delete) {
                store.select(block.id)
                store.deleteSelected()
            }
        } else {
            Text(L.readOnlyHistory)
        }
    }

    private func begin(_ f: Store.Field) {
        guard editable else { return }
        ActiveEditor.commitNow()
        store.select(block.id)
        store.editing = Store.EditTarget(blockID: block.id, field: f)
    }

    private func inlineEditor(field f: Store.Field, text: String, placeholder: String,
                              font: NSFont, color: NSColor, height: CGFloat) -> some View {
        InlineTextField(text: text, placeholder: placeholder, font: font, color: color,
                        onCommit: { v in
                            store.commitEdit(Store.EditTarget(blockID: block.id, field: f), value: v)
                        },
                        onCancel: { store.cancelEdit() })
            .frame(height: height)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.time.opacity(0.8)).frame(height: 1)
            }
            .padding(.bottom, 1)
    }
}

struct AddRow: View {
    @ObservedObject var store: Store
    @ObservedObject var settings = SettingsStore.shared
    private var L: L10n { settings.l10n }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .semibold))
            Text(L.add)
                .font(Typo.summary)
            Spacer(minLength: 0)
        }
        .foregroundColor(Palette.secondary.opacity(0.7))
        .padding(.vertical, 11)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { store.addBlock() }
    }
}

// MARK: 今天

struct DayView: View {
    @ObservedObject var store: Store
    @ObservedObject var settings = SettingsStore.shared
    private var L: L10n { settings.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let day = store.shownDay {
                header(day)
                list(day)
                    .padding(.bottom, 6)
                footer(day)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 背景交给 RootView 的玻璃与半透明纸色，这里不能再铺一层实心色
    }

    private func header(_ day: DayData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DateText.label(day.key))
                    .font(Typo.date)
                    .foregroundColor(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(day.weekday)
                    .font(Typo.weekday)
                    .foregroundColor(Palette.secondary)
                Spacer(minLength: 4)
                if store.isHistorical {
                    Button(action: { store.backToToday() }) {
                        Text(L.backToToday)
                            .font(Typo.summary)
                            .foregroundColor(Palette.time)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button(action: { store.toggleMode() }) {
                    Text(L.week)
                        .font(Typo.summary)
                        .foregroundColor(Palette.time)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L.switchToWeek)
            }
            if let e = store.writeError {
                Text(e)
                    .font(Typo.summary)
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .padding(.top, 3)
            }
            if let banner = store.banner {
                Text(banner)
                    .font(Typo.summary)
                    .foregroundColor(Palette.time)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, Layout.hPad)
        .padding(.top, Layout.topPad)
        .padding(.bottom, 8)
    }

    private func list(_ day: DayData) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(day.blocks) { b in
                        BlockRow(store: store, block: b, editable: store.editable,
                                 nowState: store.nowStates[b.id] ?? TimeState.none)
                            .id(b.id)
                    }
                    if store.editable {
                        AddRow(store: store)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollIndicators(.hidden)
            .onChange(of: store.scrollTarget) { _, target in
                guard let t = target else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(t, anchor: .bottom)
                    store.scrollTarget = nil
                }
            }
            // 展开记录区后滚一下，保证输入框和「收起/清空」在视野里。
            .onChange(of: store.expandedOutcome) { _, target in
                reveal(target, proxy)
            }
            .onChange(of: store.outcomeEditorHeight) { _, _ in
                reveal(store.expandedOutcome, proxy)
            }
        }
    }

    private func reveal(_ target: String?, _ proxy: ScrollViewProxy) {
        guard let t = target else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            proxy.scrollTo(t)   // 最小滚动：已经看得见就不动
        }
    }

    private func footer(_ day: DayData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Palette.rule).frame(height: 1)
                .padding(.horizontal, Layout.hPad)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L.footerDone(DateText.num(day.doneCount), DateText.num(day.blocks.count)))
                    .font(Typo.summary)
                    .foregroundColor(Palette.secondary)
                if day.unitsTotal > 0 {
                    Text(L.unitsPair(Fmt.units(day.unitsDone), Fmt.units(day.unitsTotal)))
                        .font(Typo.summary)
                        .foregroundColor(Palette.done)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Layout.hPad)
            .padding(.top, 8)
            if !day.footer.isEmpty {
                Text(day.footer)
                    .font(Typo.footer)
                    .foregroundColor(Palette.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Layout.hPad)
                    .padding(.top, 3)
            }
            Color.clear.frame(height: Layout.bottomPad)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DateText.label(store.shownKey))
                    .font(Typo.date)
                    .foregroundColor(Palette.ink)
                Text(DateText.weekday(store.shownKey))
                    .font(Typo.weekday)
                    .foregroundColor(Palette.secondary)
                Spacer(minLength: 4)
                Button(action: { store.show(.week) }) {
                    Text(L.week)
                        .font(Typo.summary)
                        .foregroundColor(Palette.time)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L.switchToWeek)
            }
            Text(store.errorText ?? L.noPlan)
                .font(Typo.note)
                .foregroundColor(Palette.secondary)
            Button(action: { store.reload() }) {
                Text(L.reload)
                    .font(Typo.summary)
                    .foregroundColor(Palette.time)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Layout.hPad)
        .padding(.top, Layout.topPad)
    }
}

// MARK: 本周

struct ProgressLine: View {
    let rate: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.inkAlpha(0.06, 0.10))
                Capsule().fill(Palette.time.opacity(0.7))
                    .frame(width: max(0, min(1, rate)) * g.size.width)
            }
        }
        .frame(height: 4)
    }
}

struct WeekRow: View {
    @ObservedObject var store: Store
    @ObservedObject var settings = SettingsStore.shared
    private var L: L10n { settings.l10n }
    let day: DayDigest
    let height: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Text(DateText.short(day.key))
                .font(Typo.weekDate)
                .foregroundColor(day.day == nil ? Palette.done : Palette.ink)
                .frame(width: 44, alignment: .leading)
            Text(day.weekday)
                .font(Typo.summary)
                .foregroundColor(day.day == nil ? Palette.done : Palette.secondary)
                .frame(width: 30, alignment: .leading)
            Text(day.isToday ? L.todayMarker : "")
                .font(Typo.summary)
                .foregroundColor(Palette.time)
                .frame(width: L.isZH ? 28 : 44, alignment: .leading)
            Text(day.day.map { "\($0.doneCount) / \($0.blocks.count)" } ?? "—")
                .font(Typo.weekCount)
                .foregroundColor(day.day == nil ? Palette.done : Palette.ink)
                .frame(width: 48, alignment: .trailing)
            if let d = day.day {
                ProgressLine(rate: d.rate)
            } else {
                Color.clear.frame(height: 4)
            }
        }
        .frame(height: height)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(highlight ? Palette.inkAlpha(0.045, 0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { store.openDay(day.key) }
    }

    private var highlight: Bool {
        guard store.mode == .week else { return false }
        return store.viewingKey == day.key || (store.viewingKey == nil && day.isToday)
    }
}

struct WeekView: View {
    @ObservedObject var store: Store
    @ObservedObject var settings = SettingsStore.shared
    private var L: L10n { settings.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L.week)
                    .font(Typo.date)
                    .foregroundColor(Palette.ink)
                Text(L.lastSeven)
                    .font(Typo.weekday)
                    .foregroundColor(Palette.secondary)
                Spacer(minLength: 4)
                Button(action: { store.show(.day) }) {
                    Text(L.today)
                        .font(Typo.summary)
                        .foregroundColor(Palette.time)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L.switchToToday)
            }
            .padding(.horizontal, Layout.hPad)
            .padding(.top, Layout.topPad)

            Text(L.weekSummary(DateText.num(store.weekDone), DateText.num(store.weekTotal),
                               DateText.pct(store.weekTotal == 0 ? 0 : Double(store.weekDone) / Double(store.weekTotal))))
                .font(Typo.summary)
                .foregroundColor(Palette.secondary)
                .padding(.horizontal, Layout.hPad)
                .padding(.top, 10)

            // 七行按可用高度均分，最小 56；行间靠留白分组，不画分割线。
            GeometryReader { g in
                let rowH = max(56, g.size.height / 7)
                VStack(spacing: 0) {
                    ForEach(store.days) { d in
                        WeekRow(store: store, day: d, height: rowH)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, Layout.hPad)
            .padding(.top, 12)

            Text(L.weekHint)
                .font(Typo.summary)
                .foregroundColor(Palette.done)
                .lineLimit(2)
                .padding(.horizontal, Layout.hPad)
                .padding(.top, 10)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper)
    }
}

// MARK: 根视图

/// 桌面透出来的毛玻璃底。放在纸色下面，纸色半透明，于是卡片像一片浮在桌面上的玻璃。
struct BlurBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = false
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// v11：外观由设置决定。system 时不写 colorScheme，跟随系统与窗口 appearance；
// light / dark 强制整棵视图树的 SwiftUI 色彩环境与动态色解析。
struct ThemedScheme: ViewModifier {
    @ObservedObject var settings = SettingsStore.shared

    func body(content: Content) -> some View {
        Group {
            if let scheme = settings.theme.colorScheme {
                content.environment(\.colorScheme, scheme)
            } else {
                content
            }
        }
    }
}

extension View {
    func themedScheme() -> some View { modifier(ThemedScheme()) }
}

struct RootView: View {
    @ObservedObject var store: Store
    @ObservedObject var settings = SettingsStore.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            Palette.paperVeil
            if store.mode == .week {
                WeekView(store: store)
            } else {
                DayView(store: store)
            }
        }
        .frame(width: Layout.width, height: Layout.height)
        .clipShape(RoundedRectangle(cornerRadius: Layout.corner, style: .continuous))
        // 顶部一道极细的高光，底部略暗，做出玻璃的厚度感
        // 边缘完全交给系统的玻璃与窗口阴影，这里不再画任何描边或内发光
        .themedScheme()
    }
}

// MARK: - 统计视图

struct StatsRootView: View {
    @ObservedObject var stats: StatsStore
    @ObservedObject var settings = SettingsStore.shared
    let onClose: () -> Void

    var body: some View {
        StatsView(stats: stats, onClose: onClose)
            .frame(width: Layout.statsWidth, height: Layout.statsHeight)
            .background(Palette.paper)
            .clipShape(RoundedRectangle(cornerRadius: Layout.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.corner, style: .continuous)
                    .stroke(Palette.inkAlpha(0.06, 0.10), lineWidth: 1)
            )
            .themedScheme()
    }
}

struct StatsView: View {
    @ObservedObject var stats: StatsStore
    @ObservedObject var settings = SettingsStore.shared
    private var L: L10n { settings.l10n }
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L.statsTitle)
                    .font(Typo.statsTitle)
                    .foregroundColor(Palette.ink)
                Text(L.statsRange)
                    .font(Typo.summary)
                    .kerning(0.4)
                    .foregroundColor(Palette.secondary)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Palette.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L.close)
            }
            .padding(.bottom, 14)

            if stats.windowIsEmpty {
                VStack {
                    Spacer()
                    Text(L.statsEmpty)
                        .font(Typo.statsBody)
                        .foregroundColor(Palette.done)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: Layout.statsGap) {
                    chartPane
                        .frame(width: Layout.statsChartWidth, alignment: .topLeading)
                    notePane
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(Layout.statsPad)
    }

    // MARK: 柱状图

    private var chartPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { g in
                chart(size: g.size)
            }
            .frame(maxHeight: .infinity)

            Text(L.statsSummary(DateText.num(stats.windowDone),
                                DateText.num(stats.windowTotal),
                                stats.windowTotal == 0 ? "—" : DateText.pct(stats.windowRate)))
                .font(Typo.summary)
                .foregroundColor(Palette.secondary)
        }
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    private func chart(size: CGSize) -> some View {
        let barW: CGFloat = 7
        let gap: CGFloat = 3
        let axisH: CGFloat = 18
        let plotH = max(40, size.height - axisH)
        let barsW = 30 * barW + 29 * gap
        let startX = max(0, (size.width - barsW) / 2)
        let series = stats.series

        return ZStack(alignment: .topLeading) {
            // 100% 极淡实线，50% 虚线；不标数字。
            Rectangle()
                .fill(Palette.inkAlpha(0.045, 0.10))
                .frame(width: barsW, height: 1)
                .offset(x: startX, y: 0)
            Path { p in
                p.move(to: CGPoint(x: 0, y: plotH * 0.5))
                p.addLine(to: CGPoint(x: barsW, y: plotH * 0.5))
            }
            .stroke(Palette.inkAlpha(0.10, 0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .offset(x: startX)

            ForEach(Array(series.enumerated()), id: \.element.id) { i, d in
                let x = startX + CGFloat(i) * (barW + gap)

                if d.hasData {
                    let h = max(2, CGFloat(d.rate) * plotH)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(d.isToday ? Palette.timeDeep : Palette.bar)
                        .frame(width: barW, height: h)
                        .offset(x: x, y: plotH - h)
                }

                // 每 5 天一个标签，格式 11-04。
                if i % 5 == 0 {
                    Text(DateText.short(d.key))
                        .font(Typo.statsAxis)
                        .foregroundColor(Palette.secondary.opacity(0.75))
                        .frame(width: 44, alignment: .center)
                        .offset(x: x - (44 - barW) / 2, y: plotH + 5)
                }

                // 点击热区比柱子宽一点，方便点中。
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: barW + gap, height: plotH)
                    .contentShape(Rectangle())
                    .offset(x: x - gap / 2, y: 0)
                    .onTapGesture { stats.selectDay(d.key) }
            }
        }
    }

    // MARK: 点评

    private var notePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isExternal ? L.badgeAssistant : L.badgeLocal)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Palette.time)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Palette.time.opacity(0.08)))

            if let d = stats.selectedDay {
                Text(L.pickedDay(DateText.short(d.key), "\(d.done)", "\(d.total)"))
                    .font(Typo.summary)
                    .foregroundColor(Palette.ink)
            }

            Text(noteText)
                .font(Typo.statsBody)
                .foregroundColor(Palette.ink)
                .lineSpacing(15 * 0.55)
                .lineLimit(9)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var isExternal: Bool {
        stats.commentIsExternal && !(stats.comment ?? "").isEmpty
    }

    private var noteText: String {
        if let c = stats.comment, !c.isEmpty { return clipped(c) }
        if stats.windowIsEmpty { return L.statsEmpty }

        var parts: [String] = []
        let rate = stats.windowRate
        if rate >= 0.8 { parts.append(L.localLoosen) }
        else if rate <= 0.5 { parts.append(L.localTight) }
        else { parts.append(L.localSteady) }

        let days = stats.windowDays()
        if days.count >= 2,
           let low = days.min(by: { $0.day.rate < $1.day.rate }),
           let high = days.max(by: { $0.day.rate < $1.day.rate }),
           low.key != high.key {
            parts.append(L.localBestWorst(DateText.monthDay(high.key), DateText.pct(high.day.rate),
                                          DateText.monthDay(low.key), DateText.pct(low.day.rate)))
        }
        return parts.joined(separator: L.isZH ? "" : " ")
    }

    // comment.txt 由外部脚本写入，正常不超过 120 字；超了也不让它撑出右列。
    private func clipped(_ s: String, limit: Int = 120) -> String {
        if s.count <= limit { return s }
        return String(s.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

// MARK: - 设置面板

// 460 × 300 的普通窗口，纸底、自定义标题（不用系统设置窗口的样式）。
// 语言即时生效：settings 是 @ObservedObject，改 language 会推动所有视图重算 body。
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let onLanguageChange: () -> Void
    let onDataDirChange: (URL) -> Void
    @ObservedObject var updates = UpdateStore.shared

    private let repoURL = URL(string: "https://github.com/PeberWang/dayplan")!

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }

    var body: some View {
        let L = settings.l10n
        VStack(alignment: .leading, spacing: 0) {
            Text(L.settingsTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Palette.ink)
                .padding(.bottom, 18)

            Text(L.languageLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.ink)
                .padding(.bottom, 7)
            Picker("", selection: Binding(get: { settings.language },
                                          set: { s in
                                              settings.setLanguage(s)
                                              onLanguageChange()
                                          })) {
                ForEach(LangSource.allCases) { s in
                    Text(L.langName(s)).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300, alignment: .leading)

            // v11：外观三态，切换立即生效
            Text(L.themeLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.ink)
                .padding(.top, 20)
                .padding(.bottom, 7)
            Picker("", selection: Binding(get: { settings.theme },
                                          set: { settings.setTheme($0) })) {
                ForEach(ThemeSource.allCases) { t in
                    Text(L.themeName(t)).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300, alignment: .leading)

            // v13：登录时自动启动，默认开
            Text(L.startupLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.ink)
                .padding(.top, 20)
                .padding(.bottom, 7)
            Toggle(isOn: Binding(get: { settings.launchAtLogin },
                                 set: { settings.setLaunchAtLogin($0) })) {
                Text(L.launchAtLoginLabel)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.ink)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            Text(L.launchAtLoginHint)
                .font(.system(size: 11))
                .foregroundColor(Palette.secondary)
                .padding(.top, 4)

            Text(L.dataDirLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.ink)
                .padding(.top, 20)
                .padding(.bottom, 7)
            HStack(spacing: 8) {
                Text(settings.dataDirText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(settings.dataDirText)
                Spacer(minLength: 4)
                Button(L.openFolder) { openDataDir() }
                    .controlSize(.small)
                Button(L.changeFolder) { chooseDataDir(L) }
                    .controlSize(.small)
            }
            Text(L.envHint)
                .font(.system(size: 11))
                .foregroundColor(Palette.done)
                .padding(.top, 5)

            // 更新（v9）
            Text(L.updateLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.ink)
                .padding(.top, 20)
                .padding(.bottom, 7)

            Toggle(isOn: Binding(get: { settings.autoUpdate },
                                 set: { settings.setAutoUpdate($0) })) {
                Text(L.autoUpdateLabel)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.ink)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            HStack(spacing: 8) {
                Text(L.versionLine(AppVersion.current, updates.lastUpdatedText ?? L.neverUpdated))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Button(L.checkNow) { updates.checkNow() }
                    .controlSize(.small)
                    .disabled(updates.phase == .checking)
            }
            .padding(.top, 6)

            Text(updateStatusText(L))
                .font(.system(size: 11))
                .foregroundColor(updates.pendingRestart ? Palette.time : Palette.done)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L.aboutLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.ink)
                Text("DayPlan \(version)")
                    .font(.system(size: 13))
                    .foregroundColor(Palette.secondary)
                Button("GitHub") { NSWorkspace.shared.open(repoURL) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Palette.time)
                Spacer(minLength: 0)
            }
            .padding(.top, 20)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: 460, height: 560, alignment: .topLeading)
        .background(Palette.paper)
        .themedScheme()
    }

    // 更新状态一行：检查中 > 已更新待重启 > 最近一次手动检查结果 > 说明
    private func updateStatusText(_ L: L10n) -> String {
        if updates.phase == .checking { return L.checking }
        if updates.pendingRestart { return L.restartToApply }
        if let o = updates.lastOutcome { return L.updateOutcome(o) }
        return L.updateHint
    }

    // 在 Finder 里定位到当前目录；目录被删了就打开它的上一层。
    private func openDataDir() {
        let path = settings.dataDirText
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func chooseDataDir(_ L: L10n) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L.chooseFolder
        panel.directoryURL = URL(fileURLWithPath: settings.dataDirText)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onDataDirChange(url)
    }
}

// MARK: - AppKit 窗口

final class CardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class FirstMouseHostingView: NSHostingView<RootView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let settings = SettingsStore.shared
    private var store: Store!
    private var stats: StatsStore!
    private var window: CardWindow!
    private var host: FirstMouseHostingView!
    private var glassView: NSGlassEffectView?
    private var statsWindow: CardWindow?
    private var statsHost: NSHostingView<StatsRootView>?
    private var settingsWindow: NSWindow?
    private var themeCancellable: AnyCancellable?
    private var statusItem: NSStatusItem?
    private var statusToggleItem: NSMenuItem?
    private var statusStatsItem: NSMenuItem?
    private var statusSettingsItem: NSMenuItem?
    private var statusQuitItem: NSMenuItem?
    private var statusRestartItem: NSMenuItem?
    private var statusRestartSeparator: NSMenuItem?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var outcomeDownOutside: String?   // 记录区开着时，这次点击落在框外的那一条

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "io.github.peberwang.dayplan"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        // v13：默认随登录启动；用户关过就不再装，plist 被删掉会自动补回。
        settings.syncLaunchAtLogin()

        buildMenu()

        // v11：设置里切外观时，AppKit 的窗口 / 玻璃容器要同步改 appearance。
        themeCancellable = settings.$theme.sink { [weak self] theme in self?.applyTheme(theme) }

        let env = ProcessInfo.processInfo.environment
        let plansDir = PlanIO.resolveDir()
        let statsDir = env["DAYPLAN_STATS_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DayPlan")

        stats = StatsStore(dir: statsDir)
        store = Store(dir: plansDir, stats: stats)
        stats.backfill(from: plansDir)

        buildWindow()
        applyTheme(settings.theme)
        buildStatusItem()
        store.startWatching()

        // 应用在后台照样每分钟算；回到前台立刻补算一次。
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.store.refreshNow()
        }

        NotificationCenter.default.addObserver(forName: .dayplanUpdateStateChanged,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.refreshUpdateIndicators()
        }
        UpdateStore.shared.startScheduling()

        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                               object: window, queue: .main) { _ in
            ActiveEditor.commitNow()
            ActiveOutcome.commitNow()
        }

        installKeyMonitor()
        installMouseMonitor()
        placeWindow()

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        tuneScrollers()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ActiveEditor.commitNow()   // 退出前把没回车的输入落盘
        ActiveOutcome.commitNow()
        return .terminateNow
    }

    // MARK: 主窗口

    private func buildWindow() {
        // 便签：无边框、不可拖动、固定 360×620，圆角与阴影由内容卡片给。
        let w = CardWindow(contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
                           styleMask: [.borderless],
                           backing: .buffered, defer: false)
        w.level = .normal
        w.collectionBehavior = []
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovable = false
        w.isMovableByWindowBackground = false
        w.isReleasedWhenClosed = false
        w.appearance = settings.theme.nsAppearance
        w.delegate = self

        host = FirstMouseHostingView(rootView: RootView(store: store))
        // 原生 Liquid Glass：玻璃作为容器，内容放进它的 contentView，折射与高光由系统给。
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = Layout.corner
        glass.appearance = settings.theme.nsAppearance
        glass.contentView = host
        w.contentView = glass
        glassView = glass
        window = w
    }

    // 外观切换后：窗口与玻璃的 appearance 跟着走；system 传 nil，交还系统。
    // SwiftUI 那层由各根视图的 themedScheme() 观察 SettingsStore 自己刷新。
    // @Published 在属性真正赋值之前就发出新值，所以这里用回调参数而不是 settings.theme，
    // 否则切主题时 AppKit 那层永远慢一拍（玻璃停在旧外观，界面只换了文字色）。
    private func applyTheme(_ theme: ThemeSource) {
        let appearance = theme.nsAppearance
        window?.appearance = appearance
        glassView?.appearance = appearance
        statsWindow?.appearance = appearance
        settingsWindow?.appearance = appearance
        settingsWindow?.backgroundColor = Palette.paperNS
    }

    private func placeWindow() {
        let vf = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: Layout.width, height: Layout.height)
        let origin = NSPoint(x: vf.maxX - Layout.margin - size.width,
                             y: vf.maxY - Layout.margin - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // 滚动条完全隐藏（2026-11-24 14:28 定）。SwiftUI 会晚于启动才建 NSScrollView，
    // 所以不能只调一次，要在前几秒反复扫，并且明确用 overlay 样式，避免回落到 legacy。
    private func tuneScrollers() {
        func sweep() {
            func walk(_ v: NSView) {
                if let s = v as? NSScrollView {
                    s.scrollerStyle = .overlay
                    s.autohidesScrollers = true
                    s.hasVerticalScroller = false
                    s.hasHorizontalScroller = false
                    s.verticalScroller?.alphaValue = 0
                }
                for sub in v.subviews { walk(sub) }
            }
            for w in NSApp.windows {
                if let cv = w.contentView { walk(cv) }
            }
        }
        for delay in [0.1, 0.3, 0.7, 1.2, 2.0, 3.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { sweep() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                               object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { sweep() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification,
                                               object: nil, queue: .main) { _ in sweep() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        ActiveEditor.commitNow()
        ActiveOutcome.commitNow()
        if sender === statsWindow { store.setStatsVisible(false) }
        sender.orderOut(nil)
        return false
    }

    private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideWindow() {
        ActiveEditor.commitNow()
        ActiveOutcome.commitNow()
        window.orderOut(nil)
    }

    @objc private func toggleWindow() {
        if window.isVisible { hideWindow() } else { showWindow() }
    }

    // MARK: 统计窗口

    private func showStats() {
        stats.reload()
        if statsWindow == nil { buildStatsWindow() }
        guard let w = statsWindow else { return }
        store.setStatsVisible(true)
        if !w.isVisible { w.center() }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildStatsWindow() {
        let w = CardWindow(contentRect: NSRect(x: 0, y: 0, width: Layout.statsWidth, height: Layout.statsHeight),
                           styleMask: [.borderless],
                           backing: .buffered, defer: false)
        w.level = .normal
        w.collectionBehavior = []
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.appearance = settings.theme.nsAppearance
        w.delegate = self

        let root = StatsRootView(stats: stats, onClose: { [weak self] in
            self?.closeStats()
        })
        let h = NSHostingView(rootView: root)
        w.contentView = h
        statsHost = h
        statsWindow = w
    }

    private func closeStats() {
        statsWindow?.orderOut(nil)
        store.setStatsVisible(false)
    }

    // MARK: 设置窗口

    private func showSettings() {
        if settingsWindow == nil { buildSettingsWindow() }
        guard let w = settingsWindow else { return }
        w.title = L.settingsTitle
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildSettingsWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = L.settingsTitle
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.backgroundColor = Palette.paperNS
        w.isMovableByWindowBackground = true
        w.appearance = settings.theme.nsAppearance
        w.contentMinSize = NSSize(width: 460, height: 560)
        w.contentMaxSize = NSSize(width: 460, height: 560)

        let root = SettingsView(settings: settings,
                                onLanguageChange: { [weak self] in self?.refreshLocalizedTitles() },
                                onDataDirChange: { [weak self] url in self?.applyDataDir(url) })
        w.contentView = NSHostingView(rootView: root)
        w.center()
        settingsWindow = w
    }

    // 语言切换后：菜单项、窗口标题是 AppKit 的，得手动改；界面文案由 SwiftUI 自己刷。
    private func refreshLocalizedTitles() {
        buildMenu()
        statusToggleItem?.title = window.isVisible ? L.hideWindow : L.showWindow
        statusStatsItem?.title = L.statsMenu
        statusSettingsItem?.title = L.settingsMenu
        statusQuitItem?.title = L.quit
        statusRestartItem?.title = L.restartNow
        settingsWindow?.title = L.settingsTitle
        // errorText 是写入时定下的字符串，重读一遍让它跟着语言走。
        ActiveEditor.commitNow()
        ActiveOutcome.commitNow()
        store?.reload()
        refreshUpdateIndicators()
    }

    // 数据目录换了：Store 的 dir 是 let，所以换一个 Store，再把宿主视图的 rootView 换掉。
    private func applyDataDir(_ url: URL) {
        ActiveEditor.commitNow()
        ActiveOutcome.commitNow()
        settings.setDataDir(url)
        guard !settings.envDirActive else { return }   // 环境变量优先，实际目录没变
        let plansDir = PlanIO.resolveDir()
        store.stopWatching()
        store = Store(dir: plansDir, stats: stats)
        stats.backfill(from: plansDir)
        stats.reload()
        host.rootView = RootView(store: store)
        store.startWatching()
    }

    // MARK: 键盘

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let ch = (event.charactersIgnoringModifiers ?? "").lowercased()

            if mods == .command {
                if ch == "3" { self.showStats(); return nil }
                if ch == "," { self.showSettings(); return nil }
                if ch == "q" { NSApp.terminate(nil); return nil }
                if ch == "w" { self.closeKeyWindow(); return nil }
            }

            guard let key = NSApp.keyWindow else { return event }

            if key === self.window {
                if self.store.editing != nil || self.store.expandedOutcome != nil {
                    // 编辑框里保留系统编辑快捷键（无菜单栏时也能用）
                    if mods == .command {
                        let action: String?
                        switch ch {
                        case "c": action = "copy:"
                        case "v": action = "paste:"
                        case "x": action = "cut:"
                        case "a": action = "selectAll:"
                        default: action = nil
                        }
                        if let a = action {
                            NSApp.sendAction(NSSelectorFromString(a), to: nil, from: nil)
                            return nil
                        }
                    }
                    return event
                }
                if mods.isEmpty, !event.isARepeat, event.keyCode == 51 || event.keyCode == 117 {
                    if self.store.selectedID != nil {
                        self.store.deleteSelected()
                        return nil
                    }
                }
                if mods.isEmpty, !event.isARepeat, ch == "o", let id = self.store.selectedID {
                    self.store.expandOutcome(id)
                    return nil
                }
                if mods == .command, ch == "z" {
                    if self.store.canUndo {
                        self.store.undoDelete()
                        return nil
                    }
                }
                if mods.isEmpty, event.keyCode == 53 {
                    self.store.select(nil)
                    return nil
                }
            } else if key === self.statsWindow, mods.isEmpty, event.keyCode == 53 {
                self.closeStats()
                return nil
            }
            return event
        }
    }

    private func closeKeyWindow() {
        if let s = statsWindow, s.isKeyWindow {
            closeStats()
        } else if window.isKeyWindow {
            hideWindow()
        }
    }

    // MARK: 鼠标

    // 点在编辑框之外时先落盘，再让这次点击照常生效（失焦保存）。
    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handleMouse(event)
            return event
        }
    }

    // 点在编辑框之外时先落盘，再让这次点击照常生效（失焦保存）。
    private func handleMouse(_ event: NSEvent) {
        if let f = ActiveEditor.field, let w = f.window, event.window === w {
            let p = f.convert(event.locationInWindow, from: nil)
            if !f.bounds.contains(p) {
                ActiveEditor.commitNow()
            }
        }

        guard let f = ActiveOutcome.field, let w = f.window, event.window === w else {
            outcomeDownOutside = nil
            return
        }
        let inside = outcomeHitRect(f).contains(event.locationInWindow)
        switch event.type {
        case .leftMouseDown:
            // 按下时先别收：这一下可能点在下面某条的勾或摘要上，立刻收起会重排、把这次点击吞掉。
            outcomeDownOutside = inside ? nil : f.blockID
        case .leftMouseUp:
            guard let id = outcomeDownOutside else { return }
            outcomeDownOutside = nil
            // 多等一点点：SwiftUI 的手势/按钮动作也在主队列里排队，太早收起会把这一下点击吞掉。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                if let cur = ActiveOutcome.field, cur.blockID == id { ActiveOutcome.commitNow() }
            }
        case .rightMouseDown:
            if !inside { ActiveOutcome.commitNow() }   // 右键菜单：直接收起
        default:
            break
        }
    }

    // 输入框可见区域 + 正下方「收起 / 清空」那一条，别让点击先被当成「点别处」。
    private func outcomeHitRect(_ f: OutcomeField) -> NSRect {
        var r = f.convert(f.visibleRect, to: nil)
        r.origin.x -= 14
        r.origin.y -= 30
        r.size.width += 28
        r.size.height += 30
        return r
    }

    // MARK: 菜单

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L.about,
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L.statsMenu, action: #selector(menuStats), keyEquivalent: "3").target = self
        appMenu.addItem(withTitle: L.settingsMenu, action: #selector(menuSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L.hideApp, action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: L.editMenu)
        editMenu.addItem(withTitle: L.undo, action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: L.redo, action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L.cut, action: NSSelectorFromString("cut:"), keyEquivalent: "x")
        editMenu.addItem(withTitle: L.copy, action: NSSelectorFromString("copy:"), keyEquivalent: "c")
        editMenu.addItem(withTitle: L.paste, action: NSSelectorFromString("paste:"), keyEquivalent: "v")
        editMenu.addItem(withTitle: L.selectAll, action: NSSelectorFromString("selectAll:"), keyEquivalent: "a")
        editItem.submenu = editMenu

        let winItem = NSMenuItem()
        main.addItem(winItem)
        let winMenu = NSMenu(title: L.windowMenu)
        winMenu.addItem(withTitle: L.close, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = winMenu

        NSApp.mainMenu = main
    }

    // MARK: 菜单栏图标

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: "DayPlan")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.toolTip = "DayPlan"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        // 更新装好后出现，平时隐藏：不强制重启，用户自己点。
        let restart = NSMenuItem(title: L.restartNow, action: #selector(restartToApply), keyEquivalent: "")
        restart.target = self
        restart.isHidden = true
        menu.addItem(restart)
        let restartSep = NSMenuItem.separator()
        restartSep.isHidden = true
        menu.addItem(restartSep)

        let toggle = NSMenuItem(title: L.showWindow, action: #selector(toggleWindow), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let statsItem = NSMenuItem(title: L.statsMenu, action: #selector(menuStats), keyEquivalent: "")
        statsItem.target = self
        menu.addItem(statsItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L.settingsMenu, action: #selector(menuSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L.quit, action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        statusToggleItem = toggle
        statusStatsItem = statsItem
        statusSettingsItem = settingsItem
        statusQuitItem = quitItem
        statusRestartItem = restart
        statusRestartSeparator = restartSep
        refreshUpdateIndicators()
    }

    // 已更新待重启：菜单栏图标文字与菜单项都提示一句，不弹窗、不强退。
    private func refreshUpdateIndicators() {
        let pending = UpdateStore.shared.pendingRestart
        statusItem?.button?.toolTip = pending ? "DayPlan · \(L.restartToApply)" : "DayPlan"
        statusRestartItem?.title = L.restartNow
        statusRestartItem?.isHidden = !pending
        statusRestartSeparator?.isHidden = !pending
    }

    @objc private func restartToApply() {
        // 先起一个 1 秒后打开新实例的 shell，再退出自己：新进程的「只允许一份」检查才不会被自己挡住。
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$1\"", "sh", path]
        try? p.run()
        NSApp.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusToggleItem?.title = window.isVisible ? L.hideWindow : L.showWindow
    }

    @objc private func menuStats() {
        showStats()
    }

    @objc private func menuSettings() {
        showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - 命令行

// 参数里出现下列任意一个开关就走 CLI 分支：不建窗口、不读统计，执行完直接退出。
// 读写全部走 PlanIO，和窗口共用同一套规则与同一批文件。

struct CLIFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum CLI {
    private enum Action {
        case add(text: String, time: String, units: Double?, note: String)
        case setDone(Int, Bool)
        case setOutcome(Int, String)
    }

    static let usage = """
    DayPlan —— 今天的计划，窗口与命令行共用同一份数据

      DayPlan --today                      打印今天的计划
      DayPlan --json                       同上，输出 JSON
      DayPlan --date 2026-11-24 --today    指定日期
      DayPlan --add "读两篇审稿意见" [--time "14:00 – 15:00"] [--units 2] [--note "只看方法部分"]
      DayPlan --done 3                     第 3 条标记完成（序号从 1 开始）
      DayPlan --undone 3
      DayPlan --outcome 3 "卡在识别策略，换了个 IV"

    动作可以连写，按先后执行，最后打印当天的状态。
    """

    static func wantsCLI(_ argv: [String]) -> Bool {
        let known: Set<String> = ["--today", "--json", "--add", "--done", "--undone",
                                  "--outcome", "--date", "--time", "--units", "--note",
                                  "--help", "-h"]
        return argv.dropFirst().contains { known.contains($0) }
    }

    static func run(_ argv: [String]) -> Int32 {
        let dir = PlanIO.resolveDir()
        let args = Array(argv.dropFirst())
        var dateKey: String?
        var json = false
        var actions: [Action] = []
        var i = 0

        while i < args.count {
            switch args[i] {
            case "--help", "-h":
                print(usage)
                return 0
            case "--json":
                json = true
                i += 1
            case "--today":
                i += 1
            case "--date":
                guard i + 1 < args.count else { return fail("--date 后面要跟 yyyy-MM-dd") }
                guard validKey(args[i + 1]) else { return fail("日期格式应为 yyyy-MM-dd：\(args[i + 1])") }
                dateKey = args[i + 1]
                i += 2
            case "--add":
                i += 1
                var words: [String] = []
                while i < args.count, !isFlag(args[i]) { words.append(args[i]); i += 1 }
                let text = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return fail("--add 后面要跟任务正文") }
                var time = "", note = ""
                var units: Double?
                var bad: String?
                modifiers: while i < args.count {
                    switch args[i] {
                    case "--time":
                        guard i + 1 < args.count else { bad = "--time 后面要跟时间段"; break modifiers }
                        time = args[i + 1]
                        i += 2
                    case "--units":
                        guard i + 1 < args.count else { bad = "--units 后面要跟数字"; break modifiers }
                        guard let d = Double(args[i + 1]), d.isFinite, d >= 0, d <= 1000 else {
                            bad = "--units 只接受 0…1000 的数字"
                            break modifiers
                        }
                        units = d
                        i += 2
                    case "--note":
                        guard i + 1 < args.count else { bad = "--note 后面要跟备注"; break modifiers }
                        note = args[i + 1]
                        i += 2
                    default:
                        break modifiers
                    }
                }
                if let bad { return fail(bad) }
                actions.append(.add(text: text, time: time, units: units, note: note))
            case "--done", "--undone":
                guard i + 1 < args.count, let n = Int(args[i + 1]) else {
                    return fail("\(args[i]) 后面要跟条目序号（从 1 开始）")
                }
                actions.append(.setDone(n, args[i] == "--done"))
                i += 2
            case "--outcome":
                guard i + 1 < args.count, let n = Int(args[i + 1]) else {
                    return fail("--outcome 后面要跟条目序号（从 1 开始）")
                }
                i += 2
                var words: [String] = []
                while i < args.count, !isFlag(args[i]) { words.append(args[i]); i += 1 }
                actions.append(.setOutcome(n, words.joined(separator: " ")))
            default:
                return fail("看不懂的参数：\(args[i])\n\n\(usage)")
            }
        }

        let key = dateKey ?? Store.keyFormatter().string(from: Date())
        do {
            for action in actions {
                try apply(action, key: key, dir: dir)
            }
        } catch {
            return fail(error.localizedDescription)
        }
        report(key: key, dir: dir, json: json)
        return 0
    }

    // MARK: 写

    private static func apply(_ action: Action, key: String, dir: URL) throws {
        var root: [String: Any]
        var url: URL
        var created = false
        if let loaded = try? PlanIO.read(key, in: dir) {
            root = loaded.root
            url = loaded.url
        } else if case .add = action {
            // 当天还没有文件：按窗口里新建那天的形状建一份空的。
            root = PlanIO.newDayRoot(key)
            url = PlanIO.fileURL(key, in: dir)
            try PlanIO.fm.createDirectory(at: dir, withIntermediateDirectories: true)
            created = true
        } else {
            throw PlanError.missing(key)
        }

        var blocks = (root["blocks"] as? [[String: Any]]) ?? []

        switch action {
        case .add(let text, let time, let units, let note):
            blocks.append(["id": Store.newID(),
                           "origin": "user",
                           "time": Fmt.normalizeTime(time),
                           "units": units ?? 1,
                           "text": text,
                           "note": note,
                           "done": false])
        case .setDone(let n, let done):
            let i = try index(n, in: blocks, key: key)
            blocks[i]["done"] = done
        case .setOutcome(let n, let text):
            let i = try index(n, in: blocks, key: key)
            let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty {
                blocks[i]["outcome"] = ""
                blocks[i].removeValue(forKey: "outcome_at")
            } else {
                blocks[i]["outcome"] = v
                blocks[i]["outcome_at"] = Store.stamp()
            }
        }

        root["blocks"] = blocks
        root["updated_at"] = Store.stamp()
        try PlanIO.write(root, to: url)
        if created, key == Store.keyFormatter().string(from: Date()) {
            PlanIO.touchLatest(key, in: dir)
        }
    }

    private static func index(_ n: Int, in blocks: [[String: Any]], key: String) throws -> Int {
        guard !blocks.isEmpty else { throw CLIFailure("\(key) 还没有任何条目") }
        guard n >= 1, n <= blocks.count else {
            throw CLIFailure("序号 \(n) 越界，有效范围 1–\(blocks.count)")
        }
        return n - 1
    }

    // MARK: 输出

    private static func report(key: String, dir: URL, json: Bool) {
        let weekday = DateText.weekday(key)
        let loaded = try? PlanIO.read(key, in: dir)
        let blocks = (loaded?.root["blocks"] as? [[String: Any]]) ?? []
        let doneCount = blocks.filter { Raw.bool($0, "done") }.count
        let unitsTotal = blocks.reduce(0.0) { $0 + (Raw.number($1, "units") ?? 0) }
        let unitsDone = blocks.filter { Raw.bool($0, "done") }
            .reduce(0.0) { $0 + (Raw.number($1, "units") ?? 0) }

        if json {
            var items: [[String: Any]] = []
            for (i, b) in blocks.enumerated() {
                var o: [String: Any] = ["index": i + 1,
                                        "id": Raw.string(b, "id"),
                                        "origin": Raw.string(b, "origin"),
                                        "time": Raw.string(b, "time"),
                                        "text": Raw.string(b, "text"),
                                        "note": Raw.string(b, "note"),
                                        "done": Raw.bool(b, "done"),
                                        "outcome": Raw.string(b, "outcome")]
                if let u = Raw.number(b, "units") { o["units"] = u }
                if !Raw.string(b, "outcome_at").isEmpty { o["outcome_at"] = Raw.string(b, "outcome_at") }
                items.append(o)
            }
            let payload: [String: Any] = ["date": key,
                                          "weekday": weekday,
                                          "file": PlanIO.fileURL(key, in: dir).path,
                                          "exists": loaded != nil,
                                          "done": doneCount,
                                          "total": blocks.count,
                                          "units_done": unitsDone,
                                          "units_total": unitsTotal,
                                          "blocks": items]
            let data = (try? JSONSerialization.data(withJSONObject: payload,
                                                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
                ?? Data("{}".utf8)
            print(String(data: data, encoding: .utf8) ?? "{}")
            return
        }

        guard loaded != nil else {
            print("\(key) \(weekday) 还没有计划文件")
            return
        }
        var head = "\(key) \(weekday)  \(doneCount)/\(blocks.count) 完成"
        if unitsTotal > 0 { head += " · \(Fmt.units(unitsDone))/\(Fmt.units(unitsTotal))u" }
        print(head)
        if blocks.isEmpty { print("（没有条目）") }
        for b in blocks {
            let mark = Raw.bool(b, "done") ? "[x]" : "[ ]"
            let t = Raw.string(b, "time")
            var line = "\(mark) \(t.isEmpty ? "—" : t)  \(Raw.string(b, "text"))"
            if let u = Raw.number(b, "units"), u != 1 { line += "  · \(Fmt.units(u))u" }
            line += "  #\(Raw.string(b, "id"))"
            print(line)
            let note = oneLine(Raw.string(b, "note"))
            if !note.isEmpty { print("    note: \(note)") }
            let outcome = oneLine(Raw.string(b, "outcome"))
            if !outcome.isEmpty { print("    outcome: \(outcome)") }
        }
    }

    // MARK: 小工具

    private static func oneLine(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " / ")
    }

    private static func isFlag(_ s: String) -> Bool { s.hasPrefix("-") }

    private static func validKey(_ s: String) -> Bool {
        s.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil
            && DateText.date(from: s) != nil
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("DayPlan: \(message)\n".utf8))
        return 1
    }
}

// MARK: - 入口

#if !DAYPLAN_TEST
@main
enum DayPlanMain {
    @MainActor
    static func main() {
        let argv = CommandLine.arguments
        if CLI.wantsCLI(argv) {
            exit(CLI.run(argv))
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif
