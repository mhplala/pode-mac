/* =============================================================
   Pode website — language switching.

   Source language is English (lives directly in index.html).
   Chinese strings keyed by `data-i18n="…"` on each translatable
   element. Toggling swaps textContent in place; no reload.
   Preference persists in localStorage under "pode.lang".
   Default falls back to navigator.language.
   ============================================================= */

const STORAGE_KEY = "pode.lang";

const ZH = {
    // Nav
    "nav.download":           "下载",

    // Hero
    "hero.eyebrow":           "原生 MAC 播客客户端",
    "hero.title.before":      "听播客，",
    "hero.title.em":          "在场",
    "hero.title.after":       "。",
    "hero.sub":               "给那些你想真的记住的播客单集做的 Mac 应用。每一集都完整转录。你保存过的每一行，时间轴上都有书签。没有别的东西在抢你的注意力。",
    "hero.cta.primary":       "下载 Mac 版",
    "hero.req":               "macOS 14 及以上 · Apple Silicon · 免费",

    // Mockup (kept simple — mirrors the in-app strings)
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

    // Manifesto
    "manifesto.eyebrow":      "我们为什么做这个",
    "manifesto.body":         "做 Pode 是因为，我用过的播客应用都没办法让我「重读」什么。这里每一集都有字幕，每一行都能搜，你保存的句子会作为书签落在时间轴上。大概就这样。",

    // Story 1 — transcription
    "story.t.eyebrow":        "每一句，都留下",
    "story.t.title.em":       "每一句话",
    "story.t.title.after":    "，落成文字。",
    "story.t.body":           "Pode 给每一集都做完整字幕 —— 在你 Mac 上本地跑（WhisperKit），或者用你自己的 OpenAI key。然后你可以全局搜索、跳到某一行，或者把想发给朋友的那一段直接复制走。",
    "feat.transcribe.stage":  "转录中 · 47%",

    // Story 2 — highlights
    "story.h.eyebrow":        "更安静的资料库",
    "story.h.title.before":   "留得下来的",
    "story.h.title.em":       "句子",
    "story.h.title.after":    "。",
    "story.h.body":           "右键字幕里任意一行就能保存。你的高亮在时间轴上以书签出现，也整理在专门的「高亮」tab 里 —— 你听到的句子，你自己的合集。",
    "story.h.quote":          "做出第一版的那一刻，对问题的理解就完全变了。在那之前你以为知道的一切，其实都只是猜测。",
    "story.h.quote.attr":     "— 聊聊 Agent、边界、与注意力 · 00:42:18",
    "story.h.chip1":          "Language Agent",
    "story.h.chip2":          "第一性原理",
    "story.h.chip3":          "注意力",
    "story.h.chip4":          "工具，不是机器人",

    // Story 3 — queue
    "story.q.eyebrow":        "下一首已经在路上",
    "story.q.title.before":   "一个真正",
    "story.q.title.em":       "听你的",
    "story.q.title.after":    "队列。",
    "story.q.body":           "点播任意一集，它就插到队列最前。拖拽换序。订阅的节目出新一集会自动落进队列 —— 中间没有推荐 feed 挡着。",
    "feat.queue.now":         "正在播放",
    "feat.queue.up1":         "库克的道德锚点",
    "feat.queue.up2":         "十字路口：蔡康永",

    // Story 4 — interface
    "story.i.eyebrow":        "为听设计",
    "story.i.title.before":   "让路的",
    "story.i.title.em":       "界面",
    "story.i.title.after":    "。",
    "story.i.body":           "没有广告。不追踪。不订阅。你和节目之间没有推荐 feed。",
    "story.i.tail":           "想用 AI 摘要的时候随时开。粘上你自己的 API key —— Claude、GPT、Gemini，或者任何 OpenAI 兼容服务都行。Key 留在你的 Mac 上。",
    "story.i.pillTitle":      "聊聊 Agent、边界、与注意力",

    // CTA
    "cta.eyebrow":            "准备好了？",
    "cta.title.em":           "免费",
    "cta.title.after":        "。本地。属于你。",
    "cta.sub":                "独立 Mac 应用。无需账号，不订阅，没有套路。",
    "cta.btn":                "下载 Pode 0.3.0",
    "cta.req":                "macOS 14 及以上 · Apple Silicon",

    // Footer
    "footer.tagline":         "podcasts, with presence",
    "footer.copy":            "© steve studio",
};

/** Original English strings, captured from the DOM on first apply. */
let EN = null;

function applyLang(lang) {
    document.documentElement.lang = lang === "zh" ? "zh-Hans" : "en";
    document.documentElement.setAttribute("data-lang", lang);

    if (EN === null) {
        EN = {};
        for (const el of document.querySelectorAll("[data-i18n]")) {
            EN[el.getAttribute("data-i18n")] = el.textContent;
        }
    }

    const table = lang === "zh" ? ZH : EN;
    for (const el of document.querySelectorAll("[data-i18n]")) {
        const key = el.getAttribute("data-i18n");
        const txt = table[key];
        if (txt !== undefined) el.textContent = txt;
    }

    for (const opt of document.querySelectorAll("[data-lang-opt]")) {
        if (opt.getAttribute("data-lang-opt") === lang) {
            opt.setAttribute("data-lang-active", "");
        } else {
            opt.removeAttribute("data-lang-active");
        }
    }
}

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
