import Foundation
import SwiftUI

// MARK: - Language

/// Supported display + AI-output languages. `auto` follows the system locale.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case auto
    case en
    case zh_Hans = "zh-Hans"
    case ja
    case es
    case fr
    case de

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:    return "Automatic"
        case .en:      return "English"
        case .zh_Hans: return "中文（简体）"
        case .ja:      return "日本語"
        case .es:      return "Español"
        case .fr:      return "Français"
        case .de:      return "Deutsch"
        }
    }

    /// What to tell the LLM to write in. Empty for `.auto` (let it pick from
    /// the input transcript's language). Specific languages get an English
    /// directive plus the native-name tag in parentheses for clarity.
    var aiDirective: String {
        switch self {
        case .auto:    return ""
        case .en:      return "English"
        case .zh_Hans: return "Simplified Chinese (中文/简体)"
        case .ja:      return "Japanese (日本語)"
        case .es:      return "Spanish (Español)"
        case .fr:      return "French (Français)"
        case .de:      return "German (Deutsch)"
        }
    }

    /// Resolve `.auto` against the live system locale; otherwise return the
    /// explicit Locale.
    var resolvedLocale: Locale {
        switch self {
        case .auto: return .current
        default:    return Locale(identifier: rawValue)
        }
    }

    /// Two-letter language code for L10n table lookups (`en`, `zh`, `ja`…).
    /// Resolves `auto` against the system locale.
    var lookupCode: String {
        switch self {
        case .auto:
            return Locale.current.language.languageCode?.identifier ?? "en"
        case .zh_Hans:
            return "zh"
        default:
            return rawValue
        }
    }
}

// MARK: - L10n Environment

/// Active app language pushed through SwiftUI environment so leaf views can
/// translate without threading a binding through every parent.
private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .auto
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

// MARK: - Translation table

/// Minimal hand-rolled string catalog. Add entries as new translatable UI
/// surfaces are touched. Keys are the English source string verbatim — that
/// way a missing entry just falls through to the original English without
/// breaking the UI.
enum L10n {
    /// Translate `english` to the active app language. Pass the language
    /// through SwiftUI environment via `@Environment(\.appLanguage)`.
    static func t(_ english: String, language: AppLanguage) -> String {
        let code = language.lookupCode
        guard let table = tables[code] else { return english }
        return table[english] ?? english
    }

    /// SwiftUI sugar — `Text.localized("Listen Now", language)`.
    static func text(_ english: String, language: AppLanguage) -> Text {
        Text(t(english, language: language))
    }

    private static let tables: [String: [String: String]] = [
        "zh": zh_Hans
    ]

    /// Simplified Chinese strings. Add entries here as you touch UI files.
    private static let zh_Hans: [String: String] = [
        // App chrome
        "Settings": "设置",
        "Save settings": "保存设置",
        "Saving…": "保存中…",
        "Saved": "已保存",
        "Editing…": "编辑中…",
        "Changes save automatically": "更改会自动保存",
        "Configuration": "偏好设置",

        // Sidebar
        "Listen Now":     "立即收听",
        "Browse":         "浏览",
        "Library":        "资料库",
        "Knowledge":      "知识库",
        "Filter your shows…": "筛选订阅…",
        "Shows":          "节目",
        "No subscriptions yet.": "还没有订阅。",
        "No matches.":    "没有匹配项。",
        "Set your name":  "设置你的名字",

        // Listen Now
        "In progress":         "继续收听",
        "Continue Listening":  "继续收听",
        "Up next":             "接下来",
        "Queue":               "队列",
        "Clear queue":         "清空队列",
        "Queue is empty.":     "队列为空。",
        "Add to queue":        "添加到队列",

        // Download / Transcribe pipeline stage labels (the rest are
        // defined alongside their existing siblings further down).
        "Downloading model…":  "下载模型中…",
        "Finalizing…":         "整理中…",
        "Downloading":         "下载中",
        "Now":                 "正在播放",
        "Remove from queue":   "从队列中移除",
        "Auto-queue":          "自动入队",
        "When new episodes arrive…": "新单集发布时…",
        "Off":                 "关",
        "Play next":           "插队",
        "Add to end":          "排到末尾",
        "Recently updated":    "最近更新",
        "Your Shows":          "你的节目",
        "Featured":            "精选",
        "Open episode":        "打开单集",
        "Play":                "播放",
        "Pause":               "暂停",
        "Resume":              "继续",
        "Play latest":         "播放最新一期",
        "Replay":              "重新播放",
        "Good morning":        "早上好",
        "Good afternoon":      "下午好",
        "Good evening":        "晚上好",
        "Good night":          "晚安",
        "friend":              "朋友",

        // Episode actions
        "Download":            "下载",
        "Downloaded":          "已下载",
        "Downloading…":        "下载中…",
        "Cancel":              "取消",
        "Retry":               "重试",
        "Transcribe":          "转录",
        "Transcribed":         "已转录",
        "Transcribing…":       "转录中…",
        "Fetching audio…":     "获取音频中…",
        "Back":                "返回",
        "Open full →":         "打开完整 →",
        "Live transcript":     "实时字幕",

        // Tabs
        "Transcript":          "字幕",
        "Description":         "简介",
        "Highlights":          "高亮",

        // AI inspector
        "Summary":             "摘要",
        "Takeaways":           "要点",
        "Ask":                 "提问",
        "Concepts surfaced":   "提取的概念",
        "Re-analyze":          "重新分析",
        "Re-analyzing…":       "重新分析中…",
        "Transcribe first to enable AI.": "请先转录，AI 才能工作。",
        "Run analysis to extract a summary, takeaways, and concepts.":
            "运行分析以生成摘要、要点和概念。",
        "Run analysis to surface key takeaways.": "运行分析以提炼关键要点。",
        "Thinking":            "思考中",
        "Analyzing":           "分析中",
        "Answer":              "回答",
        "What's the main argument?":     "主要论点是什么？",
        "Summarize in one paragraph":    "用一段话总结",
        "What are the surprising claims?": "有哪些令人意外的观点？",
        "Save highlight at current position": "保存当前位置的高亮",

        // Browse
        "Discover":      "发现",
        "Pick a room":   "选个分类",
        "Categories":    "分类",
        "Top podcasts":  "热门播客",
        "Editor's chart":"编辑推荐",
        "Subscribe":     "订阅",
        "Subscribed":    "已订阅",
        "Subscribing…":  "订阅中…",
        "Search Apple's podcast directory…": "搜索 Apple 播客目录…",
        "Or paste an RSS feed URL":          "或粘贴 RSS feed URL",
        "Add feed":      "添加",
        "Search":        "搜索",
        "Searching…":    "搜索中…",
        "All":           "全部",
        "Loading…":      "加载中…",
        "Loading episodes…":      "加载单集中…",
        "No episodes in this feed yet.": "这个 RSS 还没有单集。",
        "Clear":         "清除",

        // Library
        "Your collection":    "你的收藏",
        "Episodes":           "单集",
        "Downloads":          "下载",
        "Transcripts":        "转录",
        "Refresh feeds":      "刷新订阅",
        "Refreshing…":        "刷新中…",
        "Nothing here yet. Browse the directory, paste a feed URL, or search for a show.":
            "还什么都没有。从目录浏览、粘贴 RSS 链接、或搜索一个节目开始。",
        "Browse podcasts":    "浏览播客",
        "Search…":            "搜索…",
        "local results":      "条本地结果",
        "shows":              "个节目",
        "episodes":           "个单集",
        "matches":            "条匹配",
        "Nothing in your library matches.": "你的资料库里没有匹配项。",
        "Try Apple Podcasts to find new shows.": "去 Apple 播客找找新节目。",
        "Search Apple Podcasts for": "在 Apple 播客中搜索",
        "Find new podcasts to subscribe to.": "找到新播客来订阅。",
        "Download & Go":      "下载并启动",
        "Recommended":        "推荐",
        "Cached":             "已缓存",
        "Presets":            "预设",
        "fast, cheap":        "快、便宜",
        "better":             "更好",
        "best":               "最佳",

        // Knowledge
        "Your":               "你的",
        "canon":              "canon",   // intentionally English (brand moment)
        "What you've learned":"你学到的",
        "Concept galaxy":     "概念星图",
        "Concept timeline":   "概念时间线",
        "How ideas cluster across your listening": "想法在你的收听里如何聚拢",
        "When ideas appeared":"想法何时出现",
        "Galaxy":             "星图",
        "Timeline":           "时间线",
        "Saved highlights":   "保存的高亮",
        "Steve noticed":      "Steve 注意到",
        "Editorial":          "编辑",
        "Mind":               "心智",
        "Body":               "身体",
        "Craft":              "技艺",

        // Settings cards
        "You":                "你",
        "Display name":       "显示名字",
        "Your name":          "你的名字",
        "Used for the greeting on Listen Now.": "用于「立即收听」页的问候语。",

        "Transcription":      "转录",
        "Engine":              "引擎",
        "Local model":        "本地模型",
        "Language":           "语言",
        "Auto-detect":        "自动检测",

        "Summary & analysis": "摘要与分析",
        "Provider":           "供应商",
        "Model":              "模型",
        "Test connection":    "测试连接",
        "Testing…":           "测试中…",

        "AI keys":            "AI 密钥",
        "Liquid glass":       "液态玻璃",
        "Accent color":       "强调色",
        "Bloom strength":     "光晕强度",
        "Secondary bloom":    "次级光晕",
        "Maintenance":        "维护",
        "Rebuild concept index": "重建概念索引",

        "App language":       "应用语言",
        "Used for UI labels and as the language Claude/GPT/Gemini reply in.":
            "用于界面文案，也作为 AI 回复的语言。",

        // Toasts / status
        "Settings saved":     "设置已保存",
        "Concepts rebuilt":   "概念已重建",
        "Highlight saved":    "高亮已保存",
        "Download cancelled": "下载已取消",
        "Transcription cancelled": "转录已取消",
        "AI analysis ready":  "AI 分析就绪",
        "Already subscribed": "已订阅",
        "Unsubscribed":       "已退订",
        "Refresh failed":     "刷新失败",
        "Couldn't fetch feed": "获取订阅源失败",
        "Search failed":      "搜索失败",
        "Couldn't load top":  "加载榜单失败",
        "Highlight removed":  "高亮已移除",
        "Download removed":   "下载已移除",
        "Transcribed · ":     "已转录 · ",
        "AI failed":          "AI 失败",
        "Add your name":      "添加你的名字",
        "Bad audio URL":      "音频 URL 无效",

        // EpisodeView extras
        "No transcript yet. Generate one to enable AI summaries, search, and concept extraction.":
            "还没有字幕。生成一份以启用 AI 摘要、搜索和概念提取。",
        "Transcribe this episode": "为这集生成字幕",
        "FETCHING AUDIO":     "获取音频中",
        "STREAMING ·":        "流式生成 ·",
        "auto · 99.4% confidence": "自动 · 99.4% 置信度",
        "lines":              "条",
        "Delete transcript?": "删除字幕？",
        "AI summaries will be cleared too.": "AI 摘要也会被清除。",
        "Delete":             "删除",
        "Remove downloaded audio?": "移除已下载的音频？",
        "Remove":             "移除",
        "downloading…":       "下载中…",
        "downloaded ·":       "已下载 ·",
        "starting…":          "准备中…",
        "left":               "剩余",
        "Steve · listening":  "Steve · 收听中",
        "Network timed out. Try again.": "网络超时，请重试。",
        "No internet connection.": "网络未连接。",
        "Connection lost mid-download. Tap retry.": "下载中途断网，点击重试。",
        "Couldn't reach the host. The feed may be down.": "无法连接到服务器，订阅源可能下线。",
        "The server returned a bad response.": "服务器返回了无效响应。",
        "Downloads are blocked on this network.": "当前网络禁止下载。",
        "Save all to canon": "全部保存到 canon",
        "Filed to knowledge": "已归入知识库",
        "Linked to":         "已关联到",
        "cluster":           "簇",
        "nearby episodes":   "相邻单集",
        "No description in the feed.": "订阅源没有描述信息。",
        "No highlights yet. Right-click any transcript line to save it as a highlight.":
            "还没有高亮。右键点击任意字幕行即可保存为高亮。",
        "Save highlight":    "保存高亮",
        "Add note":          "添加笔记",
        "File to canon":     "归入 canon",
        "No transcript line at this position": "当前位置没有字幕行",
        "haiku-4.5":         "haiku-4.5",
        "Analyze with":      "用 AI 分析:",
        "Ask anything about this episode…": "随便问关于这集的问题…",
        "transcript ·":      "字幕 ·",
        "audio · 192 kbps":  "音频 · 192 kbps",
        "words":             "字",

        // Library
        "downloaded":        "已下载",
        "transcripts":       "字幕",
        "Sort":              "排序",
        "recent":            "最近",
        "No episodes loaded yet — try refreshing.": "还没有加载到单集 — 试试刷新。",
        "Show not found.":   "节目不存在。",
        "Episode not found.": "单集不存在。",
        "No downloads yet.": "还没有下载。",
        "No transcripts yet.": "还没有字幕。",
        "Back to Library":   "返回资料库",
        "Unsubscribe":       "退订",
        "Unsubscribe?":      "退订？",
        "Episodes, transcripts and highlights for this show will be removed.":
            "该节目的所有单集、字幕和高亮都会被移除。",

        // Browse
        "中国":                "中国",
        "results":             "条结果",
        "No results — try a different region or genre.": "暂无结果 — 试试其他地区或分类。",
        "Editor's pick":      "编辑推荐",
        "The shows that respect your reading time.": "尊重你阅读时间的节目。",

        // Knowledge (extras)
        "When ideas appeared in your week":      "本周想法出现的时间线",
        "Each dot is one episode mention.":      "每个点是单集中的一次提及。",
        "Find a path":         "寻找思路",
        "Path mode":           "路径模式",
        "Reset":               "重置",
        "Pick another concept…": "选择另一个概念…",
        "Suggested endings":   "建议的目标",
        "The thread ·":        "思路 ·",
        "stops":               "站",
        "Open full canon →":   "打开完整 canon →",
        "transcripts ·":       "份字幕",
        "ep":                  "集",
        "Save this thread to canon": "把这条思路存到 canon",
        "Open":                "打开",
        "Saved highlights · ": "已保存高亮 · ",
        "Infer speakers (AI)": "推断说话人 (AI)",
        "After transcription, the AI assigns each line to a speaker using context.":
            "转录后,AI 会根据上下文为每句话标注说话人。",
        "Whisper outputs Traditional by default; we convert to Simplified post-transcription. Turn off to keep Traditional.":
            "Whisper 默认输出繁体;转录后我们会转成简体。关闭则保留繁体。",
        "Listen to and analyze a few more episodes — patterns will start showing up here.":
            "再听几集并分析 — 模式会开始显现。",
        "No concepts yet. Transcribe an episode and run AI analysis — Claude will pull out concepts, and they'll cluster here as a galaxy of what you've heard.":
            "还没有概念。转录一集并运行 AI 分析 — AI 会提取概念，在这里聚成一张你听过的星图。",
        "Open Library":        "打开资料库",

        // SettingsView extras
        "Reads transcripts and writes summaries, takeaways, concepts, and answers. Pick any provider — keys live on this device.":
            "读取字幕并生成摘要、要点、概念和问答。任选供应商 — 密钥仅保存在本机。",
        "Local runs on this Mac (free, offline). Cloud uses your OpenAI key.":
            "本地在此 Mac 运行(免费、离线);云端使用你的 OpenAI 密钥。",
        "Tune the look and feel of the canvas.": "调节画布的视觉风格。",
        "Recompute the concept galaxy from current AI analysis.":
            "依据当前 AI 分析重建概念星图。",
        "Local · WhisperKit": "本地 · WhisperKit",
        "Cloud · OpenAI Whisper": "云端 · OpenAI Whisper",
        "Get one at platform.openai.com → API keys.":
            "在 platform.openai.com → API keys 获取。",
        "Get one at console.anthropic.com → API keys.":
            "在 console.anthropic.com → API keys 获取。",
        "Get one at aistudio.google.com → Get API key.":
            "在 aistudio.google.com → Get API key 获取。",
        "Same OpenAI key — also drives Whisper if the cloud engine is selected.":
            "与上面同一个 OpenAI 密钥 — 选择云端引擎时也用于 Whisper。",
        "Any OpenAI-compatible endpoint: DeepSeek, OpenRouter, Together, Groq, local Ollama, etc.":
            "任意 OpenAI 兼容的端点:DeepSeek、OpenRouter、Together、Groq、本地 Ollama 等。",
        "Type any model id Google supports. Presets fill the field; the API itself accepts new ids the moment Google ships them.":
            "可以输入 Google 支持的任何 model id。下拉只是预设;Google 发布新模型时无需更新 app 即可使用。",
        "Used by the OpenAI Whisper engine selected above.":
            "上面选择的 OpenAI Whisper 引擎使用。",
        "Hide":                "隐藏",
        "Show":                "显示",
        "OpenAI key (cloud transcription)": "OpenAI 密钥(云端转录)",
        "Whisper model":       "Whisper 模型",
        "OpenAI API key":      "OpenAI API 密钥",
        "Anthropic API key":   "Anthropic API 密钥",
        "Gemini API key":      "Gemini API 密钥",
        "API key":             "API 密钥",
        "Base URL":            "Base URL",
        "Model name":          "模型名",
        "Custom (OpenAI-compatible)": "自定义(OpenAI 兼容)",
        "Anthropic Claude":    "Anthropic Claude",
        "OpenAI":              "OpenAI",
        "Google Gemini":       "Google Gemini",
        "Glass blur":          "玻璃模糊",
        "Simplified Chinese output": "繁体转简体",

        // TaskPill / Sidebar
        "Background tasks":    "后台任务",
        "Tagging speakers…":   "标注说话人…",
        "Loading model…":      "加载模型中…",
        "Downloading model":   "下载模型",
        "Checking model…":     "检查模型…",
        "Done":                "完成",
        "Speakers":            "说话人",
        "speakers":            "位说话人",

        // PlayerDock
        "speaker":             "说话人",
        "live":                "实时",

    ]
}

/// Terse global so call sites can write `Text(t("Settings", lang))` instead
/// of `Text(L10n.t("Settings", language: lang))`. Use only in view files
/// that have `@Environment(\.appLanguage) private var lang`.
@inline(__always)
func t(_ english: String, _ lang: AppLanguage) -> String {
    L10n.t(english, language: lang)
}
