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
    "cta.btn":                "下载 Pode 0.5.27",
    "cta.req":                "macOS 14 及以上 · Apple Silicon",

    // Footer
    "footer.tagline":         "podcasts, with presence",
    "footer.copy":            "© steve studio",
    "footer.privacy":         "隐私",
    "footer.terms":           "条款",

    // Privacy page
    "privacy.eyebrow":        "Pode · 隐私",
    "privacy.title":          "隐私",
    "privacy.updated":        "最近更新 · 2026 年 5 月",
    "privacy.lead":           "Pode 是一款本地优先的 app —— 运行在你的 Mac，所有数据存在你的 Mac，不与任何 Pode 服务器通讯，因为 Pode 没有服务器。",
    "privacy.h.collect":      "Pode 收集的数据",
    "privacy.collect.body":   "没有。Pode 不内置任何数据分析、崩溃上报、或其他遥测。启动时不上报、崩溃时不上报、任何时候都不上报。没有账户、没有任何与你绑定的标识符。",
    "privacy.h.stores":       "Pode 在你 Mac 上保存的数据",
    "privacy.stores.subs":    "<strong>订阅、单集、播放进度</strong> —— 写入 app 沙盒里的本地 SwiftData 数据库。",
    "privacy.stores.transcripts": "<strong>转录、AI 摘要、要点、概念释义</strong> —— 存在同一个本地数据库里。除非你主动复制出去，否则永远不会离开你的 Mac。",
    "privacy.stores.audio":   "<strong>下载的音频</strong> —— 保存在 app 缓存目录，用于离线播放。",
    "privacy.stores.keys":    "<strong>AI 供应商的 API 密钥</strong> —— 保存在 macOS 钥匙串中，只在你触发 AI 操作时读取。",
    "privacy.h.third":        "Pode 通过网络访问的服务",
    "privacy.third.lead":     "Pode 仅在你主动使用相应功能时才请求外部服务：",
    "privacy.third.itunes":   "<strong>iTunes Search API</strong> —— 公开的播客目录接口，你搜索节目或浏览榜单时使用。不发送任何身份信息。",
    "privacy.third.rss":      "<strong>播客 RSS feed 与音频文件</strong> —— 直接从播客发布方的服务器拉取，和所有播客 app 一样。",
    "privacy.third.ai":       "<strong>你选择的 AI 供应商</strong>（Anthropic、OpenAI、Google 或自定义 OpenAI 兼容端点）—— 仅在你触发摘要、提问或概念释义时调用。请求从你的 Mac 直接发到供应商，使用你自己的密钥。这些请求受供应商自身的隐私政策约束。",
    "privacy.third.hf":       "<strong>Hugging Face</strong> —— 仅首次下载本地 Whisper 模型时调用。之后转录完全离线、在 Apple Silicon 上本地完成。",
    "privacy.h.share":        "Pode 分享的数据",
    "privacy.share.body":     "不对任何人分享任何数据。没有「分享」按钮上传你的资料库，没有排行榜，没有社区动态。你的收听是你自己的事。",
    "privacy.h.children":     "儿童",
    "privacy.children.body":  "Pode 是一款通用的播客 app，没有定向广告也没有数据收集。本 app 并非面向 13 岁以下儿童，亦无任何机制会收集来自他们的数据。",
    "privacy.h.rights":       "你的权利",
    "privacy.rights.body":    "因为 Pode 没有你的数据，所以没有任何「查询、导出、删除」的服务器侧操作。要彻底清除一切，把 app 拖进废纸篓即可 —— macOS 会一并清掉 app 沙盒。",
    "privacy.h.changes":      "变更",
    "privacy.changes.body":   "如果本政策有影响到用户的变更，更新版本会发布在这里并标注新的「最近更新」日期。",
    "privacy.h.contact":      "联系",
    "privacy.contact.body":   "隐私相关问题请发邮件至 <a href='mailto:hi@podecast.cc'>hi@podecast.cc</a>。",

    // Terms page
    "terms.eyebrow":          "Pode · 条款",
    "terms.title":            "使用条款",
    "terms.updated":          "最近更新 · 2026 年 5 月",
    "terms.lead":             "Pode 是一款播客客户端。一句话版本：按现状提供，你对自己用它做的事负责，AI 功能通过你自己配置的供应商完成。",
    "terms.h.license":        "使用许可",
    "terms.license.body":     "你可以在你拥有或被授权使用的 Mac 上下载、安装和运行 Pode。app 本身免费提供，遵循本条款；它依赖的开源库列在 设置 → 关于 中，各自遵循其自身的开源协议。",
    "terms.h.content":        "播客内容",
    "terms.content.body":     "Pode 订阅公开的播客 RSS feed，直接从 feed 中给出的 URL 播放音频。播客的版权属于其创作者。Pode 不托管、不重新分发、不镜像任何播客音频，也不剥离广告。请以尊重播客创作者的方式使用 Pode。",
    "terms.h.transcripts":    "转录与 AI 输出",
    "terms.transcripts.body": "你本地转录一集播客，或生成 AI 摘要、要点、释义、问答时，输出属于原播客内容的衍生作品。Pode 把这些数据留在你的设备上，供你个人收听、研究或记录使用 —— 在多数司法管辖区这属于个人合理使用范畴。如果你打算公开发布或商业分发由他人播客衍生的转录或 AI 输出，请自行获取所需授权。Pode 不对你如何分享衍生内容表态、也不承担相应责任。",
    "terms.h.ai":             "AI 供应商",
    "terms.ai.body":          "AI 功能（摘要、要点、概念释义、问答）需要你为第三方供应商（Anthropic、OpenAI、Google 或 OpenAI 兼容端点）配置 API 密钥。Pode 从你的 Mac 直接调用这些供应商。你需要为：通过密钥产生的任何费用、遵守该供应商的服务条款、以及模型返回内容的准确性，自行负责。Pode 除了解析以供显示外，不验证、不编辑、不过滤输出。",
    "terms.h.warranty":       "免责声明",
    "terms.warranty.body":    "Pode 按「现状」提供，不提供任何形式的明示或暗示担保，包括但不限于适销性、特定用途适用性或不侵权的担保。转录与 AI 生成的内容可能包含错误、遗漏或幻觉 —— 在涉及安全、法律、医疗、金融决策时请勿无核实使用。",
    "terms.h.liability":      "责任限制",
    "terms.liability.body":   "在适用法律允许的最大范围内，Pode 作者不对因你使用或无法使用本 app 而产生的任何直接、间接、偶然、特殊、衍生或惩戒性损害承担责任 —— 包括但不限于通过你配置的密钥产生的 API 费用、设备上的数据丢失、以及因依赖 AI 生成内容而产生的损害。",
    "terms.h.feedback":       "反馈",
    "terms.feedback.body":    "如果你提交了 bug 报告或功能建议，作者可以用它们改进 Pode，对此不欠你任何回报。",
    "terms.h.changes":        "变更",
    "terms.changes.body":     "本条款会随着 Pode 的演进而更新。实质性更新后继续使用 app 视为接受更新后的条款。",
    "terms.h.contact":        "联系",
    "terms.contact.body":     "问题请联系：<a href='mailto:hi@podecast.cc'>hi@podecast.cc</a>。",
};

/** Original English strings, captured from the DOM on first apply. */
let EN = null;

function applyLang(lang) {
    document.documentElement.lang = lang === "zh" ? "zh-Hans" : "en";
    document.documentElement.setAttribute("data-lang", lang);

    // Capture innerHTML (not textContent) so inline emphasis like
    // <strong>, <em>, and inline links survive the EN-side capture and
    // the ZH-side swap. Strings are author-controlled, so injecting
    // innerHTML here is safe.
    if (EN === null) {
        EN = {};
        for (const el of document.querySelectorAll("[data-i18n]")) {
            EN[el.getAttribute("data-i18n")] = el.innerHTML;
        }
    }

    const table = lang === "zh" ? ZH : EN;
    for (const el of document.querySelectorAll("[data-i18n]")) {
        const key = el.getAttribute("data-i18n");
        const txt = table[key];
        if (txt !== undefined) el.innerHTML = txt;
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
