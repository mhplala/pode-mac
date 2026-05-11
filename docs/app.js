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
    "hero.sub":               "有些对话不该 1.5 倍速速通。Pode 是为那些你真心想记住的单集做的 —— 完整字幕、安静整理、围绕你的注意力。",
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
    "manifesto.body":         "大部分播客应用想留住你 —— 推你可能会播的内容，统计你的分钟数，弄丢你真正听过的那条线。Pode 走反方向。它把字幕交还给你，让你标记下打动你的部分，剩下的时候安静地让出位置。界面像纸一样温暖、克制，就是为了让声音本身能传过来。",

    // Story 1 — transcription
    "story.t.eyebrow":        "每一句，都留下",
    "story.t.title.em":       "每一句话",
    "story.t.title.after":    "，落成文字。",
    "story.t.body":           "三小时的对话里，最打动你的那句往往不在你以为的时间点。Pode 给每一集生成完整字幕 —— 在你的 Mac 本地跑，或者通过你自己的 AI 服务 —— 让那些你想回去找的瞬间，可搜索、可引用、属于你。",
    "feat.transcribe.stage":  "转录中 · 47%",

    // Story 2 — highlights
    "story.h.eyebrow":        "更安静的资料库",
    "story.h.title.before":   "留得下来的",
    "story.h.title.em":       "句子",
    "story.h.title.after":    "。",
    "story.h.body":           "右键任意字幕行就能保存。高亮以书签的形式出现在时间轴上，汇成你的私人 canon，慢慢织出一张你反复回到的想法地图 —— 来自你的收听，不是别人的算法。",
    "story.h.quote":          "改变你的不是答案 —— 是你意识到问题本身错了的那个瞬间。",
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
    "story.q.body":           "点播任意一集，它就是下一首 —— 今晚剩下的时间排在它后面。拖拽换序。给一档节目加星，新一集出来就安静地排进队列。顺序属于你，不属于推荐引擎。",
    "feat.queue.now":         "正在播放",
    "feat.queue.up1":         "库克的道德锚点",
    "feat.queue.up2":         "十字路口：蔡康永",

    // Story 4 — interface
    "story.i.eyebrow":        "为听设计",
    "story.i.title.before":   "让路的",
    "story.i.title.em":       "界面",
    "story.i.title.after":    "。",
    "story.i.body":           "纸张般温暖的画布。意大利斜体的标题。液态玻璃表面，透出底下一丝暖光。每一屏的设计都贴着真实使用场景 —— 听一段，找一句，做点笔记，往下走。",
    "story.i.tail":           "没有广告。不追踪。不订阅。AI 摘要按需开启，用你自己的 API key —— 想用再用。",
    "story.i.pillTitle":      "聊聊 Agent、边界、与注意力",

    // CTA
    "cta.eyebrow":            "准备好了？",
    "cta.title.em":           "免费",
    "cta.title.after":        "。本地。属于你。",
    "cta.sub":                "一个长成了样子的周末项目。一个人做的，在 Mac 上，给那些还相信长内容音频的人。",
    "cta.btn":                "下载 Pode 0.2.0",
    "cta.req":                "macOS 14 及以上 · Apple Silicon",

    // Footer
    "footer.tagline":         "podcasts, with presence",
    "footer.copy":            "© steve studio · 在 Mac 上做的。",
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
