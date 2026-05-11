/* =============================================================
   Pode website — language switching.

   Strategy:
     - Source language is English (lives directly in index.html).
     - Chinese strings live in this file, keyed by `data-i18n="…"`
       on the corresponding element. Toggling the language swaps
       textContent in-place; no page reload, no flicker.
     - User preference persists in localStorage under "pode.lang".
       Default falls back to `navigator.language` — Chinese
       browsers see 中文 on first visit.
     - The toggle's two halves get a `data-lang-active` attribute
       on the currently-selected option so CSS can style them.
   ============================================================= */

const STORAGE_KEY = "pode.lang";

// Chinese translations keyed by the same i18n string the HTML uses.
// Keep this map in sync with `data-i18n="…"` attributes in index.html.
const ZH = {
    // Nav
    "nav.download":           "下载",

    // Hero
    "hero.eyebrow":           "PODCASTS · 全文转录",
    "hero.title.before":      "专注地",
    "hero.title.em":          "听",
    "hero.title.after":       "。",
    "hero.sub":               "原生 macOS 播客客户端。智能队列、全文字幕、AI 摘要 —— 包裹在安静的、纸张般温暖的界面里，尊重你的注意力。",
    "hero.cta.primary":       "下载 Mac 版",
    "hero.req":               "需要 macOS 14 (Sonoma) 或更高 · Apple Silicon",

    // Mockup
    "mockup.tagline":         "podcasts, transcribed",
    "mockup.nav.listen":      "立即收听",
    "mockup.nav.browse":      "浏览",
    "mockup.nav.library":     "资料库",
    "mockup.nav.knowledge":   "知识库",
    "mockup.today":           "星期二 · 5 月 11 日",
    "mockup.greeting.before": "早上好，",
    "mockup.greeting.em":     "朋友",
    "mockup.featured":        "精选 · 科技",
    "mockup.epTitle":         "聊聊 Agent、边界、与注意力的形状",
    "mockup.resume":          "继续 · 1:42:18",

    // Philosophy
    "philosophy.eyebrow":     "为什么是 PODE",
    "philosophy.title.before":"为",
    "philosophy.title.em":    "听",
    "philosophy.title.after": "而设计，不是为算法。",

    "phil.1.title":           "彻底原生",
    "phil.1.body":             "SwiftUI、SwiftData、AVFoundation。没有 Electron、没有网页套壳、没有遥测。安装包约 13 MB，运行起来也像。",
    "phil.2.title":           "你的字幕，在你的机器上",
    "phil.2.body":             "WhisperKit 本地转录完全在你 Mac 的神经引擎上跑，或者用 OpenAI Whisper API。不管哪种，字幕都保存在你自己的磁盘里。",
    "phil.3.title":           "值得存在的 AI",
    "phil.3.body":             "自带 API key —— Claude、GPT、Gemini，或任何兼容 OpenAI 的服务。摘要、要点、向字幕提问 —— 统一在一个供应商切换后面。",
    "phil.4.title":           "安静的界面",
    "phil.4.body":             "纸张般温暖的画布。意大利斜体的标题。液态玻璃的层级。界面让路，让声音说话。",

    // Features
    "features.eyebrow":       "里面装着什么",
    "features.title.before":  "一个认真的工具，外面是一层",
    "features.title.em":      "柔软",
    "features.title.after":   "的壳。",

    "feat.scrubber.title":    "章节时间线",
    "feat.scrubber.body":     "Pode 从节目简介里解析章节时间戳 —— bullet 列表、括号、全角冒号都吃 —— 把它们排成进度条上的小点。鼠标悬停看章节标题，点击跳转。",

    "feat.queue.title":       "会听你的队列",
    "feat.queue.body":        "真正的播放队列，持久化到 SwiftData。订阅节目的新单集刷新时自动升到「插队」位置。点播任意 episode 它就升到队首，之前那个不会丢，排在后面。",
    "feat.queue.now":         "正在播放",
    "feat.queue.up1":         "库克的道德锚点",
    "feat.queue.up2":         "十字路口：蔡康永",

    "feat.transcribe.title":  "本地或云端转录",
    "feat.transcribe.body":   "WhisperKit 在设备上跑 Small / Medium / Large-v3-Turbo 模型。或用 OpenAI Whisper API。Pode 负责模型下载、缓存，以及下载中断时的自动修复。",
    "feat.transcribe.stage":  "转录中 · 47%",

    "feat.ai.title":          "按你的方式做 AI 摘要",
    "feat.ai.body":           "自带 API key —— Anthropic Claude、OpenAI、Google Gemini，或任何 OpenAI 兼容服务。摘要、要点、概念提取、向字幕提问，统一在一个供应商切换之下。Key 不会离开你的 Mac。",
    "feat.ai.summary":        "摘要",
    "feat.ai.takeaways":      "要点",
    "feat.ai.ask":            "提问",
    "feat.ai.text":           "本期对谈中，苏煜梳理了 Agent 的技术脉络 —— 从 1960 年代的逻辑代理，到神经代理，再到今天的语言代理 —— 并提出最有意思的…",
    "feat.ai.chip1":          "Language Agent",
    "feat.ai.chip2":          "语义解析",
    "feat.ai.chip3":          "工具使用",

    // Also
    "also.eyebrow":           "盒子里还有",
    "also.1.title":           "从 Apple Podcasts 订阅",
    "also.1.body":            "按地区 + 分类浏览 iTunes 目录，或直接粘 RSS URL。内置人工精选的 AI 编辑推荐。",
    "also.2.title":           "属于你的高亮",
    "also.2.body":            "右键任意字幕行保存为高亮。在进度条上以书签出现，episode 页有专门的高亮 tab。",
    "also.3.title":           "中英双语界面",
    "also.3.body":            "界面完整支持英文和简体中文。AI 摘要也跟随你设定的语言。",
    "also.4.title":           "自动刷新",
    "also.4.body":            "后台每 30 分钟轮询一次。订阅节目的新单集会安静地出现在你的队列里。",
    "also.5.title":           "概念图谱",
    "also.5.body":            "AI 从所有转录过的 episode 中提取的概念汇总成一张个人知识地图。",
    "also.6.title":           "沙盒 + 公证",
    "also.6.body":            "开启 App Sandbox、Hardened Runtime，已通过 Apple 公证。双击即开 —— 没有 Gatekeeper 警告。",

    // CTA
    "cta.eyebrow":            "准备好了？",
    "cta.title.em":           "免费",
    "cta.title.after":        "。本地。属于你。",
    "cta.sub":                "无需账号。不追踪。不订阅。需要 AI 功能时自带 API key —— 或者不带。",
    "cta.btn":                "下载 Pode 0.2.0",
    "cta.req":                "macOS 14 (Sonoma) 或更高 · Apple Silicon · 已通过 Apple 公证",

    // Footer
    "footer.tagline":         "podcasts, transcribed",
    "footer.copy":            "© steve studio · 在 Mac 上做的。",
};

/** Original English strings, captured from the DOM on first apply.
 *  We snapshot once so flipping back to EN doesn't need to be hard-coded. */
let EN = null;

/** Apply translations to all `data-i18n` elements based on current lang.
 *  EN path uses the snapshot of original HTML; ZH uses the map above. */
function applyLang(lang) {
    document.documentElement.lang = lang === "zh" ? "zh-Hans" : "en";
    document.documentElement.setAttribute("data-lang", lang);

    if (EN === null) {
        // First call — snapshot every node's English text in document order.
        EN = {};
        for (const el of document.querySelectorAll("[data-i18n]")) {
            EN[el.getAttribute("data-i18n")] = el.textContent;
        }
    }

    const table = lang === "zh" ? ZH : EN;
    for (const el of document.querySelectorAll("[data-i18n]")) {
        const key = el.getAttribute("data-i18n");
        const txt = table[key];
        if (txt !== undefined) {
            el.textContent = txt;
        }
    }

    // Toggle visual state on the two-half pill.
    for (const opt of document.querySelectorAll("[data-lang-opt]")) {
        if (opt.getAttribute("data-lang-opt") === lang) {
            opt.setAttribute("data-lang-active", "");
        } else {
            opt.removeAttribute("data-lang-active");
        }
    }
}

/** Initial lang resolution: explicit user choice > browser locale. */
function initialLang() {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved === "zh" || saved === "en") return saved;
    const nav = (navigator.language || navigator.userLanguage || "en").toLowerCase();
    return nav.startsWith("zh") ? "zh" : "en";
}

document.addEventListener("DOMContentLoaded", () => {
    let current = initialLang();
    applyLang(current);

    document.getElementById("lang-toggle").addEventListener("click", () => {
        current = current === "zh" ? "en" : "zh";
        localStorage.setItem(STORAGE_KEY, current);
        applyLang(current);
    });
});
