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
    "hero.sub":               "为你不想速通的播客做的 Mac 应用。每一集都有完整字幕，每一行都可搜索，你保存的每一句都触手可及。",
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
    "manifesto.eyebrow":      "概览",
    "manifesto.body":         "Pode 围绕长内容播客的真实收听方式而设计：可搜索的字幕、时间轴上的书签、由你掌控的队列。界面让出位置，让对话本身不必与之争夺注意力。",

    // Story 1 — transcription
    "story.t.eyebrow":        "字幕",
    "story.t.title.em":       "每一句话",
    "story.t.title.after":    "，落成文字。",
    "story.t.body":           "每一集都完整转录 —— 本地在 Mac 上跑，或者使用你自己的 OpenAI key。在整个资料库中搜索、跳转到任意一行、或将某段内容复制分享 —— 都在同一个视图内完成。",
    "feat.transcribe.stage":  "转录中 · 47%",

    // Story 2 — highlights
    "story.h.eyebrow":        "高亮",
    "story.h.title.before":   "留得下来的",
    "story.h.title.em":       "句子",
    "story.h.title.after":    "。",
    "story.h.body":           "右键字幕中任意一行即可保存为高亮。高亮以书签的形式出现在播放时间轴上，并集中在专门的「高亮」标签页中 —— 由你在意的那些瞬间，积累而成的参考资料库。",
    "story.h.quote":          "做出第一版的那一刻，对问题的理解就完全变了。在那之前你以为知道的一切，其实都只是猜测。",
    "story.h.quote.attr":     "— 聊聊 Agent、边界、与注意力 · 00:42:18",
    "story.h.chip1":          "Language Agent",
    "story.h.chip2":          "第一性原理",
    "story.h.chip3":          "注意力",
    "story.h.chip4":          "工具，不是机器人",

    // Story 3 — queue
    "story.q.eyebrow":        "队列",
    "story.q.title.before":   "一个真正",
    "story.q.title.em":       "听你的",
    "story.q.title.after":    "队列。",
    "story.q.body":           "点击任意单集播放，它会移到队列最前。拖拽换序。订阅节目的新单集自动加入队列 —— 你和你选择收听的内容之间，没有算法 feed 介入。",
    "feat.queue.now":         "正在播放",
    "feat.queue.up1":         "库克的道德锚点",
    "feat.queue.up2":         "十字路口：蔡康永",

    // Story 4 — interface
    "story.i.eyebrow":        "开放，且私密",
    "story.i.title.before":   "免费，",
    "story.i.title.em":       "没有附加条件",
    "story.i.title.after":    "。",
    "story.i.body":           "无需账号。不追踪。无内购。你和节目之间没有推荐 feed。",
    "story.i.tail":           "AI 摘要可选。接入你自己的 API key —— Anthropic Claude、OpenAI、Google Gemini，或任何 OpenAI 兼容服务 —— Key 不会离开你的 Mac。",
    "story.i.pillTitle":      "聊聊 Agent、边界、与注意力",

    // CTA
    "cta.eyebrow":            "准备好了？",
    "cta.title.em":           "免费",
    "cta.title.after":        "。本地。属于你。",
    "cta.sub":                "为 macOS 14 及以上而生。免费，无需注册。",
    "cta.btn":                "下载 Pode 0.5.3",
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
