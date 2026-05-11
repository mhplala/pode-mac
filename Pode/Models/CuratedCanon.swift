import Foundation

// MARK: - Curated canon types
//
// A small editorial layer on top of iTunes search/charts. We hand-pick a
// roster of shows around a theme (e.g. AI), group them into sub-clusters,
// and ship a one-line "why" per show. Artwork + feedUrl get hydrated from
// iTunes lookup at runtime so this static data only carries identifiers
// and the editorial copy.

struct CuratedShow: Identifiable, Hashable {
    let itunesId: Int
    let title: String
    let host: String
    /// Fallback feed URL — used if the iTunes lookup fails or hasn't
    /// returned yet. iTunes still owns the canonical source.
    let feedUrl: String
    /// Editorial one-liner. Why this show specifically, in this cluster.
    let why: String

    var id: Int { itunesId }
}

struct CuratedCluster: Identifiable, Hashable {
    let id: String
    let title: String
    let blurb: String
    let shows: [CuratedShow]
}

struct CuratedCanon: Hashable {
    let id: String
    let title: String
    let description: String
    let updatedAt: String
    let clusters: [CuratedCluster]

    /// Flat list of every show across every cluster — for the one-shot
    /// `ITunesService.lookup` call that hydrates the whole canon at once.
    var allItunesIds: [Int] {
        clusters.flatMap { $0.shows.map(\.itunesId) }
    }
}

// MARK: - AI canon (v1, May 2026)
//
// Hand-curated editorial roster. To extend: add a CuratedShow to the right
// cluster (or define a new cluster). Verify the iTunes ID resolves with
// `curl 'https://itunes.apple.com/lookup?id=<ID>&entity=podcast'` first.

extension CuratedCanon {
    static let ai = CuratedCanon(
        id: "ai",
        title: "AI: an editor's listening canon",
        description: "一份手选的 AI 播客地图——前沿模型缔造者、工程师、投资人、以及担心方向的人。中英文双语,Curated v1, May 2026.",
        updatedAt: "2026-05-09",
        clusters: [
            CuratedCluster(
                id: "zh-depth",
                title: "华语 · 深度访谈",
                blurb: "中文世界里少数能把 AI 故事讲到几小时长度还撑得住信息密度的几档节目。",
                shows: [
                    CuratedShow(
                        itunesId: 1634356920,
                        title: "张小珺Jùn｜商业访谈录",
                        host: "张小珺",
                        feedUrl: "https://feed.xyzfm.space/dk4yh3pkpjp3",
                        why: "中文 AI 访谈的天花板。两到七小时的长对话,前沿模型公司、芯片、AGI 一线人物几乎都坐过这把椅子。可以理解为中文版 Dwarkesh。"
                    ),
                    CuratedShow(
                        itunesId: 1613083252,
                        title: "OnBoard!",
                        host: "Monica & 高宁",
                        feedUrl: "https://feed.xyzfm.space/xxg7ryklkkft",
                        why: "Monica 在硅谷,高宁在国内,聊海外 AI 创业、模型公司、Infra,经常请到一手当事人。中英混杂,信号极高。"
                    ),
                    CuratedShow(
                        itunesId: 1498541229,
                        title: "硅谷101",
                        host: "泓君",
                        feedUrl: "https://feeds.fireside.fm/sv101/rss",
                        why: "泓君以财经记者的功底拆解硅谷,DeepSeek、芯片战、模型经济这种题做得最扎实的中文节目之一。"
                    ),
                    CuratedShow(
                        itunesId: 1564877433,
                        title: "晚点聊 LateTalk",
                        host: "晚点 LatePost",
                        feedUrl: "https://feeds.fireside.fm/latetalk/rss",
                        why: "中国最严肃的科技商业媒体的口播版。AI 大模型、自动驾驶、机器人专题选题精准,记者亲自下场。"
                    ),
                    CuratedShow(
                        itunesId: 1671502201,
                        title: "AI炼金术",
                        host: "徐文浩、任鑫",
                        feedUrl: "https://www.ximalaya.com/album/74194808.xml",
                        why: "两位资深 AI 产品人聊技术、产品、应用。比偏访谈类的节目更靠近「我们到底怎么用起来」。"
                    )
                ]
            ),
            CuratedCluster(
                id: "zh-strategy",
                title: "华语 · 战略与评论",
                blurb: "中文 AI 圈的「圆桌时间」—— 投资人、研究员、产品人凑一块复盘行情、争论赛道、解构事件。",
                shows: [
                    CuratedShow(
                        itunesId: 1729552193,
                        title: "十字路口 Crossing",
                        host: "Koji",
                        feedUrl: "https://feed.xyzfm.space/68fyjknth9hj",
                        why: "AI 含量极高,几乎每集都在讨论模型、产品、Agent。节奏轻、密度大,很适合通勤听。"
                    ),
                    CuratedShow(
                        itunesId: 1591595410,
                        title: "乱翻书",
                        host: "潘乱",
                        feedUrl: "https://feed.xyzfm.space/yxuruh3f9mc4",
                        why: "国内最敏锐的科技战略评论之一。AI 时代的字节、阿里、腾讯、新势力——他往往比一般报道早半个身位。"
                    ),
                    CuratedShow(
                        itunesId: 1709213889,
                        title: "屠龙之术",
                        host: "庄明浩",
                        feedUrl: "https://feed.xyzfm.space/834hyx3v9k74",
                        why: "前 VC 视角的犀利复盘。AI 创业公司估值、商业模式、生态位,讲得不留情面。"
                    ),
                    CuratedShow(
                        itunesId: 1689996400,
                        title: "此话当真",
                        host: "真格基金",
                        feedUrl: "https://www.ximalaya.com/album/76257752.xml",
                        why: "真格内部 + 被投创业者的对谈。投资视角下中国 AI 创业的现场感很强,信息保鲜度高。"
                    ),
                    CuratedShow(
                        itunesId: 1615939013,
                        title: "半拿铁 | 商业沉浮录",
                        host: "潇磊 & 刘飞",
                        feedUrl: "https://proxy.wavpub.com/caffebreve.xml",
                        why: "不是纯 AI,但 AI 浪潮下的公司、人物、商业故事讲得极有节奏。刘飞是少有产品 sense 在线的主持人。"
                    )
                ]
            ),
            CuratedCluster(
                id: "frontier",
                title: "Frontier research",
                blurb: "Where the people doing the work talk about the work. Long-form, high-context, low patience for hype.",
                shows: [
                    CuratedShow(
                        itunesId: 1516093381,
                        title: "Dwarkesh Podcast",
                        host: "Dwarkesh Patel",
                        feedUrl: "https://apple.dwarkesh-podcast.workers.dev/feed.rss",
                        why: "The current gold standard for frontier-lab interviews — researched to a level that gets researchers to actually answer the question."
                    ),
                    CuratedShow(
                        itunesId: 1510472996,
                        title: "Machine Learning Street Talk",
                        host: "Tim Scarfe",
                        feedUrl: "https://anchor.fm/s/1e4a0eac/podcast/rss",
                        why: "The most technically rigorous AI show in English. Multi-hour deep dives that won't soften the math for you."
                    ),
                    CuratedShow(
                        itunesId: 1719552353,
                        title: "Interconnects",
                        host: "Nathan Lambert",
                        feedUrl: "https://api.substack.com/feed/podcast/48206.rss",
                        why: "Post-training, RLHF, open models. Lambert reads what's happening as a working researcher, not a commentator."
                    ),
                    CuratedShow(
                        itunesId: 1116303051,
                        title: "The TWIML AI Podcast",
                        host: "Sam Charrington",
                        feedUrl: "https://feeds.megaphone.fm/MLN2155636147",
                        why: "Running since 2016, 700+ episodes. The institutional memory of the field."
                    ),
                    CuratedShow(
                        itunesId: 1569777340,
                        title: "The Gradient",
                        host: "Daniel Bashir",
                        feedUrl: "https://api.substack.com/feed/podcast/265424/s/1354.rss",
                        why: "Researcher conversations with academic depth — papers, not press releases."
                    )
                ]
            ),
            CuratedCluster(
                id: "applied",
                title: "For builders",
                blurb: "If you ship LLM features for a living, this is your row.",
                shows: [
                    CuratedShow(
                        itunesId: 1674008350,
                        title: "Latent Space",
                        host: "swyx & Alessio",
                        feedUrl: "https://api.substack.com/feed/podcast/1084089.rss",
                        why: "The AI engineer's home base. RAG, agents, eval, infra — practitioners talking to practitioners."
                    ),
                    CuratedShow(
                        itunesId: 1406537385,
                        title: "Practical AI",
                        host: "Daniel Whitenack & Chris Benson",
                        feedUrl: "https://feeds.transistor.fm/practical-ai-machine-learning-data-science-llm",
                        why: "Custom LLMs, edge deployment, real production stories. Less hype, more 'here's what broke'."
                    ),
                    CuratedShow(
                        itunesId: 1505372978,
                        title: "MLOps Community",
                        host: "Demetrios Brinkmann",
                        feedUrl: "https://anchor.fm/s/174cb1b8/podcast/rss",
                        why: "Getting models into production — pipelines, evals, infra, the unglamorous middle of the stack."
                    )
                ]
            ),
            CuratedCluster(
                id: "business",
                title: "Builders & money",
                blurb: "The investor and operator view: who's winning, who's bluffing, what gets funded next.",
                shows: [
                    CuratedShow(
                        itunesId: 1668002688,
                        title: "No Priors",
                        host: "Sarah Guo & Elad Gil",
                        feedUrl: "https://feeds.megaphone.fm/nopriors",
                        why: "Two top-tier AI investors interviewing the founders they back. High signal on what's working at scale."
                    ),
                    CuratedShow(
                        itunesId: 1669813431,
                        title: "The Cognitive Revolution",
                        host: "Nathan Labenz",
                        feedUrl: "https://feeds.megaphone.fm/RINTP3108857801",
                        why: "Labenz is one of the few people who can actually evaluate model capabilities live. Heavy episodes, weekly cadence."
                    ),
                    CuratedShow(
                        itunesId: 1750736528,
                        title: "Training Data",
                        host: "Sequoia Capital",
                        feedUrl: "https://feeds.megaphone.fm/trainingdata",
                        why: "Sequoia partners interviewing AI founders. Shorter and more polished than No Priors — same caliber of guest."
                    ),
                    CuratedShow(
                        itunesId: 1740178076,
                        title: "AI + a16z",
                        host: "a16z",
                        feedUrl: "https://feeds.simplecast.com/Hb_IuXOo",
                        why: "Andreessen Horowitz's AI line. Worth listening even if you ignore everything else they put out."
                    ),
                    CuratedShow(
                        itunesId: 1677184070,
                        title: "Possible",
                        host: "Reid Hoffman & Aria Finger",
                        feedUrl: "https://feeds.megaphone.fm/possible",
                        why: "Hoffman thinks in scenarios. Less news, more 'what does the next decade look like if this works'."
                    )
                ]
            ),
            CuratedCluster(
                id: "safety",
                title: "Safety, alignment & what could go wrong",
                blurb: "The technical and philosophical seriousness about where this is all headed.",
                shows: [
                    CuratedShow(
                        itunesId: 1544393261,
                        title: "AXRP — AI X-risk Research Podcast",
                        host: "Daniel Filan",
                        feedUrl: "https://rss.libsyn.com/shows/312947/destinations/2517215.xml",
                        why: "Conversations with actual alignment researchers about actual papers. The technical end of the safety stack."
                    ),
                    CuratedShow(
                        itunesId: 1245002988,
                        title: "80,000 Hours Podcast",
                        host: "Rob Wiblin & Luisa Rodriguez",
                        feedUrl: "https://feeds.transistor.fm/80000-hours-podcast",
                        why: "Long-form interviews with AI safety researchers and policymakers. The flagship pod for this worldview."
                    ),
                    CuratedShow(
                        itunesId: 1170991978,
                        title: "Future of Life Institute Podcast",
                        host: "Future of Life Institute",
                        feedUrl: "https://feeds.transistor.fm/future-of-life-institute-podcast-4e4d1fa5-a878-4cb2-91be-91c3ce266dfd",
                        why: "Researchers, policy wonks, philosophers on existential risk and governance. Drier than 80K, more focused."
                    ),
                    CuratedShow(
                        itunesId: 1565088425,
                        title: "The Inside View",
                        host: "Michaël Trazzi",
                        feedUrl: "https://anchor.fm/s/56df2194/podcast/rss",
                        why: "Independent interviews from inside the alignment community. Lower production, higher candor."
                    )
                ]
            ),
            CuratedCluster(
                id: "news",
                title: "Daily & weekly news",
                blurb: "If you only have 20 minutes a day, pick one of these.",
                shows: [
                    CuratedShow(
                        itunesId: 1680633614,
                        title: "The AI Daily Brief",
                        host: "Nathaniel Whittemore",
                        feedUrl: "https://anchor.fm/s/f7cac464/podcast/rss",
                        why: "Daily 15-min digest. The fastest way to stay roughly current."
                    ),
                    CuratedShow(
                        itunesId: 1502782720,
                        title: "Last Week in AI",
                        host: "Andrey Kurenkov & Jeremie Harris",
                        feedUrl: "https://rss.art19.com/last-week-in-ai",
                        why: "Two researchers actually reading the papers, then summarizing the week. Comprehensive."
                    ),
                    CuratedShow(
                        itunesId: 1528594034,
                        title: "Hard Fork",
                        host: "Kevin Roose & Casey Newton",
                        feedUrl: "https://feeds.simplecast.com/6HKOhNgS",
                        why: "The NYT/Platformer take. Broadest audience, sharpest journalism, weekly."
                    )
                ]
            ),
            CuratedCluster(
                id: "horizon",
                title: "The wide angle",
                blurb: "Long conversations that step back from the news cycle.",
                shows: [
                    CuratedShow(
                        itunesId: 1434243584,
                        title: "Lex Fridman Podcast",
                        host: "Lex Fridman",
                        feedUrl: "https://lexfridman.com/feed/podcast/",
                        why: "Not strictly AI, but the AI episodes are essential. Where most lab CEOs end up sooner or later."
                    ),
                    CuratedShow(
                        itunesId: 1476316441,
                        title: "Google DeepMind: The Podcast",
                        host: "Hannah Fry",
                        feedUrl: "https://feeds.simplecast.com/JT6pbPkg",
                        why: "First-party from DeepMind, but Hannah Fry hosts — meaning it's actually good, not a press release."
                    ),
                    CuratedShow(
                        itunesId: 1820330260,
                        title: "OpenAI Podcast",
                        host: "OpenAI",
                        feedUrl: "https://feeds.acast.com/public/shows/68470ba8d911dedd6501609c",
                        why: "First-party, treat accordingly — useful as primary source, not as analysis."
                    ),
                    CuratedShow(
                        itunesId: 1438378439,
                        title: "Eye on AI",
                        host: "Craig S. Smith",
                        feedUrl: "https://rss.libsyn.com/shows/123267/destinations/727317.xml",
                        why: "Veteran NYT correspondent interviewing researchers, regulators, and builders. Underrated."
                    ),
                    CuratedShow(
                        itunesId: 1289062927,
                        title: "ChinaTalk",
                        host: "Jordan Schneider",
                        feedUrl: "https://feeds.megaphone.fm/CHTAL4990341033",
                        why: "Geopolitics and chips. If you only listen to US-perspective AI shows, you're missing half the picture."
                    )
                ]
            )
        ]
    )
}
