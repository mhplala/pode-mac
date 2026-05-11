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
    "hero.sub":               "有些单集只是背景噪音，有些会真的改变你怎么想问题。Pode 是为后一种做的 —— 听过的每一句都有字幕，在意的每一行都能找回来。",
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
    "manifesto.body":         "大部分播客应用把单集当内容 —— 可以消费、可以统计分钟数、可以划过去。Pode 把它当阅读看待。完整字幕给你，触动你的句子可以标，过几天可以回来再看。界面剩下的部分，安静地让位。",

    // Story 1 — transcription
    "story.t.eyebrow":        "每一句，都留下",
    "story.t.title.em":       "每一句话",
    "story.t.title.after":    "，落成文字。",
    "story.t.body":           "三个小时的对话里，最打动你的那句很少在你以为的时间点。Pode 给每一集生成完整字幕 —— 本地在你的 Mac 上跑，或者用你自己的 AI key —— 让你想回去找的那一刻，可搜索、可引用、就在你离开的地方等着。",
    "feat.transcribe.stage":  "转录中 · 47%",

    // Story 2 — highlights
    "story.h.eyebrow":        "更安静的资料库",
    "story.h.title.before":   "留得下来的",
    "story.h.title.em":       "句子",
    "story.h.title.after":    "。",
    "story.h.body":           "右键任意字幕行就能保存。高亮以书签的形式落在时间轴上，慢慢汇成你的私人 canon —— 一张安静的想法地图，画的是你自己听到的东西，不是别人的算法。",
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
    "story.q.body":           "点播任意一集，它就插到最前 —— 今晚剩下的时间排在后面。拖拽换序。订阅一档节目，它的新单集会自动落进队列。顺序由你定。",
    "feat.queue.now":         "正在播放",
    "feat.queue.up1":         "库克的道德锚点",
    "feat.queue.up2":         "十字路口：蔡康永",

    // Story 4 — interface
    "story.i.eyebrow":        "为听设计",
    "story.i.title.before":   "让路的",
    "story.i.title.em":       "界面",
    "story.i.title.after":    "。",
    "story.i.body":           "界面是故意安静的。没有广告。不追踪。没有滚动 feed 把你拽到下一首。你耳朵里的声音，不用跟屏幕上的东西争抢。",
    "story.i.tail":           "想用 AI 摘要的时候随时开 —— 用你自己的 key（Claude、GPT、Gemini，或任何 OpenAI 兼容服务）。Key 不会离开你的 Mac。",
    "story.i.pillTitle":      "聊聊 Agent、边界、与注意力",

    // CTA
    "cta.eyebrow":            "准备好了？",
    "cta.title.em":           "免费",
    "cta.title.after":        "。本地。属于你。",
    "cta.sub":                "一个失控了的周末项目。一个人做的，给那些还会把长对话从头听到尾的人。",
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
