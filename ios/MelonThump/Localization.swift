import Foundation

/// In-app UI language (design doc 1.2.0 §2): Simplified Chinese /
/// English / Español. The default follows the system; an explicit
/// choice under Settings › Language persists and applies immediately,
/// no restart. Scope is UI strings only — text baked into Stephanie's
/// artwork is out of scope (art freeze). Modeled on Retax's L10n.
enum AppLanguage: String, CaseIterable, Identifiable {
    case zh = "zh-Hans"
    case en
    case es

    var id: String { rawValue }

    /// Each language names itself, as in Retax.
    var displayName: String {
        switch self {
        case .zh: return "简体中文"
        case .en: return "English"
        case .es: return "Español"
        }
    }

    /// The system's preferred language mapped onto the three supported
    /// ones (any Chinese → Simplified Chinese; unsupported → English).
    static var system: AppLanguage {
        for id in Locale.preferredLanguages {
            let code = id.lowercased()
            if code.hasPrefix("zh") { return .zh }
            if code.hasPrefix("es") { return .es }
            if code.hasPrefix("en") { return .en }
        }
        return .en
    }
}

/// Minimal string table: every UI string of the app in all three
/// languages. Views hold `@AppStorage(L10n.storageKey)` so that a
/// language switch re-renders them on the spot.
struct L10n {
    /// "system" or an AppLanguage raw value.
    static let storageKey = "app.language"
    static let followSystem = "system"

    let language: AppLanguage

    init(preference: String) {
        language = AppLanguage(rawValue: preference) ?? .system
    }

    /// For non-view code (error descriptions, share text).
    static var current: L10n {
        L10n(preference: UserDefaults.standard.string(forKey: storageKey) ?? followSystem)
    }

    func t(_ key: String) -> String {
        Self.strings[key]?[language] ?? Self.strings[key]?[.en] ?? key
    }

    func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale(identifier: language.rawValue), arguments: args)
    }

    #if DEBUG
    /// Launch self-check: the table is complete for all three languages.
    static func assertComplete() {
        for (key, row) in strings {
            assert(AppLanguage.allCases.allSatisfy { row[$0]?.isEmpty == false }, "L10n key \(key) incomplete")
        }
    }
    #endif

    static let strings: [String: [AppLanguage: String]] = [
        // MARK: Home
        "home.tagline": [.zh: "拍一拍，就知道！", .en: "thump it & know it!", .es: "¡dale un golpe y sabrás!"],
        "home.howTitle": [.zh: "使用方法", .en: "How it works", .es: "Cómo funciona"],
        "home.howBody": [
            .zh: "把手机靠近西瓜，拍一下，我们来听听它熟没熟。",
            .en: "Hold your phone near a watermelon, thump it once, and we'll listen to how ripe it is.",
            .es: "Acerca el teléfono a una sandía, dale un golpe y escucharemos qué tan madura está.",
        ],
        "home.start": [.zh: "开始录音", .en: "Start Recording", .es: "Empezar a grabar"],
        "home.hint": [
            .zh: "拍一下就好——%d 秒后自动停止",
            .en: "One good thump — it stops itself at %d seconds",
            .es: "Un buen golpe: se detiene solo a los %d segundos",
        ],
        "home.menu": [.zh: "菜单", .en: "Menu", .es: "Menú"],
        "home.invite": [.zh: "邀请", .en: "Invite", .es: "Invitar"],

        // MARK: Allowance row & gates
        "credits.promoGate": [
            .zh: "上线推广——看一支广告，本次打开内随便拍",
            .en: "Launch promo — one ad unlocks thumping until you leave",
            .es: "Promo de lanzamiento: un anuncio desbloquea los golpes hasta que salgas",
        ],
        "credits.promoUnlocked": [
            .zh: "推广已解锁——本次打开无限次拍瓜",
            .en: "Promo unlocked — unlimited thumps this visit",
            .es: "Promo desbloqueada: golpes ilimitados en esta visita",
        ],
        "credits.freeDay": [
            .zh: "免费日——今天无限次拍瓜，不看广告",
            .en: "Free day — unlimited thumps, no ads today",
            .es: "Día gratis: golpes ilimitados y sin anuncios hoy",
        ],
        "credits.firstFree": [
            .zh: "首次拍瓜免费，无需看广告",
            .en: "Your first thump is free — no ad",
            .es: "Tu primer golpe es gratis, sin anuncios",
        ],
        "credits.promoFreeMany": [
            .zh: "还有 %d 次免费拍瓜，无需看广告",
            .en: "%d free thumps left — no ad",
            .es: "Te quedan %d golpes gratis, sin anuncios",
        ],
        "credits.promoFreeOne": [
            .zh: "还有 1 次免费拍瓜，无需看广告",
            .en: "1 free thump left — no ad",
            .es: "Te queda 1 golpe gratis, sin anuncios",
        ],
        "credits.sessionUnlocked": [
            .zh: "已解锁——退出 App 前无限次拍瓜",
            .en: "Unlocked — unlimited thumps until you leave the app",
            .es: "Desbloqueado: golpes ilimitados hasta que salgas de la app",
        ],
        "credits.unlimited": [.zh: "无限次拍瓜", .en: "Unlimited thumps", .es: "Golpes ilimitados"],
        "credits.gate": [
            .zh: "看一支短广告，退出 App 前无限次拍瓜",
            .en: "One short ad unlocks unlimited thumps until you leave",
            .es: "Un anuncio corto desbloquea golpes ilimitados hasta que salgas",
        ],
        "credits.gateWithBalance": [
            .zh: "Credit：%d · 可免广告解锁本次使用",
            .en: "Credits: %d · unlock this visit ad-free",
            .es: "Créditos: %d · desbloquea esta visita sin anuncios",
        ],
        "credits.balance": [.zh: "Credit：%d", .en: "Credits: %d", .es: "Créditos: %d"],
        "promo.title": [.zh: "上线推广", .en: "Launch promo", .es: "Promo de lanzamiento"],
        "promo.message": [
            .zh: "看一支短广告，即可在退出 App 前无限次拍瓜。",
            .en: "Watch one short ad to unlock unlimited thumps until you leave the app.",
            .es: "Mira un anuncio corto para desbloquear golpes ilimitados hasta que salgas de la app.",
        ],
        "gate.title": [.zh: "解锁本次使用", .en: "Unlock this visit", .es: "Desbloquea esta visita"],
        "gate.messageAd": [
            .zh: "看一支短广告，即可在退出 App 前无限次拍瓜。",
            .en: "Watch one short ad to unlock unlimited thumps until you leave the app.",
            .es: "Mira un anuncio corto para desbloquear golpes ilimitados hasta que salgas de la app.",
        ],
        "gate.messageCredits": [
            .zh: "看一支短广告，或用 credit 免广告解锁（你有 %d 个）。解锁后退出 App 前无限次拍瓜。",
            .en: "Watch one short ad, or use credits to unlock without an ad (you have %d). Either way, thumping is unlimited until you leave the app.",
            .es: "Mira un anuncio corto o usa créditos para desbloquear sin anuncios (tienes %d). En ambos casos, los golpes son ilimitados hasta que salgas de la app.",
        ],
        "gate.watchAd": [.zh: "看广告", .en: "Watch an ad", .es: "Ver un anuncio"],
        "gate.useCredit": [.zh: "用 1 个 credit（免广告）", .en: "Use 1 credit — no ad", .es: "Usar 1 crédito, sin anuncio"],
        "gate.useCredits": [.zh: "用 %d 个 credit（免广告）", .en: "Use %d credits — no ad", .es: "Usar %d créditos, sin anuncio"],
        "ad.loading": [
            .zh: "广告还在加载——稍等几秒再试。",
            .en: "The ad is still loading — give it a few seconds and try again.",
            .es: "El anuncio aún se está cargando; espera unos segundos e inténtalo de nuevo.",
        ],

        // MARK: Common
        "common.ok": [.zh: "好", .en: "OK", .es: "Aceptar"],
        "common.notNow": [.zh: "以后再说", .en: "Not now", .es: "Ahora no"],
        "common.done": [.zh: "完成", .en: "Done", .es: "Listo"],
        "common.cancel": [.zh: "取消", .en: "Cancel", .es: "Cancelar"],
        "error.title": [.zh: "出了点问题", .en: "Something went wrong", .es: "Algo salió mal"],
        "error.mic": [.zh: "麦克风权限被拒绝。", .en: "Microphone permission denied.", .es: "Permiso de micrófono denegado."],
        "error.startRecording": [.zh: "无法开始录音：%@", .en: "Failed to start recording: %@", .es: "No se pudo empezar a grabar: %@"],
        "error.noRecording": [.zh: "找不到录音。", .en: "No recording found.", .es: "No se encontró la grabación."],
        "error.unreadable": [.zh: "无法读取录音。", .en: "Could not read the recording.", .es: "No se pudo leer la grabación."],
        "error.tooShort": [
            .zh: "录音太短——再拍一次。",
            .en: "Recording is too short — thump once more.",
            .es: "La grabación es demasiado corta; golpea otra vez.",
        ],

        // MARK: Recording
        "rec.listening": [.zh: "正在听…", .en: "listening…", .es: "escuchando…"],
        "rec.secondLeft": [.zh: "秒后结束", .en: "second left", .es: "segundo restante"],
        "rec.secondsLeft": [.zh: "秒后结束", .en: "seconds left", .es: "segundos restantes"],
        "rec.prompt": [
            .zh: "现在拍西瓜——\n拍一下就够了",
            .en: "Thump the melon now —\none good knock is enough",
            .es: "Golpea la sandía ahora:\ncon un buen golpe basta",
        ],
        "rec.stop": [.zh: "■  停止并分析", .en: "■  Stop & Analyze", .es: "■  Detener y analizar"],
        "rec.autoStops": [
            .zh: "倒计时结束自动停止",
            .en: "Auto-stops when the countdown ends",
            .es: "Se detiene solo al terminar la cuenta atrás",
        ],
        "rec.canStopAfter": [
            .zh: "%d 秒后可以手动停止",
            .en: "You can stop after %d seconds",
            .es: "Puedes detener después de %d segundos",
        ],

        // MARK: Analyzing
        "an.caption": [
            .zh: "她的原稿页面，原样保留——\n猫咪们正在听你的拍瓜声…",
            .en: "Her original page, kept as-is —\nthe cats are listening to your thump…",
            .es: "Su página original, tal cual:\nlos gatos están escuchando tu golpe…",
        ],
        "an.analyzing": [.zh: "分析中…", .en: "Analyzing…", .es: "Analizando…"],

        // MARK: Result
        "res.badge": [.zh: "结果", .en: "RESULT", .es: "RESULTADO"],
        "verdict.unripe": [.zh: "还没熟", .en: "Not ripe yet", .es: "Aún no está madura"],
        "verdict.ripe": [.zh: "熟了——开吃吧！", .en: "Ripe — enjoy!", .es: "¡Madura, a disfrutar!"],
        "verdict.overripe": [.zh: "熟过头了", .en: "Overripe", .es: "Demasiado madura"],
        "verdict.unknown": [.zh: "听不出来", .en: "Unknown", .es: "Desconocido"],
        "tagline.unripe": [
            .zh: "这一声又高又空。\n再放几天吧。",
            .en: "That thump sounds too high and hollow.\nGive this melon a few more days.",
            .es: "Ese golpe suena demasiado agudo y hueco.\nDale unos días más a esta sandía.",
        ],
        "tagline.ripe": [
            .zh: "又甜又多汁，可以切了。\n猫咪们都点头了。",
            .en: "Sweet, juicy and ready to cut.\nThe cats approve.",
            .es: "Dulce, jugosa y lista para cortar.\nLos gatos lo aprueban.",
        ],
        "tagline.overripe": [
            .zh: "这一声又沉又闷。\n今天就吃——或者榨成汁！",
            .en: "That thump sounds deep and dull.\nEat it today — or blend it into juice!",
            .es: "Ese golpe suena grave y apagado.\n¡Cómela hoy o hazla jugo!",
        ],
        "tagline.unknown": [
            .zh: "这一下没听清。\n再靠近一点拍一次试试。",
            .en: "That thump was hard to read.\nTry thumping again, a little closer.",
            .es: "Ese golpe fue difícil de leer.\nIntenta golpear otra vez, un poco más cerca.",
        ],
        "res.dominant": [.zh: "主频", .en: "DOMINANT", .es: "DOMINANTE"],
        "res.confidence": [.zh: "置信度", .en: "CONFIDENCE", .es: "CONFIANZA"],
        "res.decay": [.zh: "衰减", .en: "DECAY", .es: "DECAIMIENTO"],
        "res.ripeRange": [.zh: "熟区间：%@–%@ Hz", .en: "Ripe range: %@–%@ Hz", .es: "Rango maduro: %@–%@ Hz"],
        "res.above": [.zh: "高于 %@ Hz——还没熟", .en: "Above %@ Hz — not ripe yet", .es: "Por encima de %@ Hz: aún no está madura"],
        "res.below": [.zh: "低于 %@ Hz——过了最佳期", .en: "Below %@ Hz — past its prime", .es: "Por debajo de %@ Hz: ya pasó su mejor momento"],
        "res.unknownNote": [
            .zh: "熟瓜的拍击声落在绿色区间",
            .en: "A ripe thump lands in the green zone",
            .es: "Un golpe maduro cae en la zona verde",
        ],
        "zone.unripe": [.zh: "生", .en: "unripe", .es: "verde"],
        "zone.ripe": [.zh: "熟", .en: "ripe", .es: "madura"],
        "zone.overripe": [.zh: "过熟", .en: "overripe", .es: "pasada"],
        "res.again": [.zh: "再拍一个瓜", .en: "Thump Another Melon", .es: "Golpear otra sandía"],

        // MARK: Version gate / splash
        "upd.softTitle": [.zh: "有新版本可用", .en: "A new version is available", .es: "Hay una nueva versión disponible"],
        "upd.notNow": [.zh: "以后再说", .en: "Not Now", .es: "Ahora no"],
        "upd.update": [.zh: "更新", .en: "Update", .es: "Actualizar"],
        "upd.softMessage": [
            .zh: "MelonThump %@ 已就绪。可以现在更新，也可以继续拍瓜。",
            .en: "MelonThump %@ is ready. You can update now or keep thumping.",
            .es: "MelonThump %@ está lista. Puedes actualizar ahora o seguir golpeando.",
        ],
        "upd.title": [.zh: "该更新啦！", .en: "Time to update!", .es: "¡Hora de actualizar!"],
        "upd.body": [
            .zh: "MelonThump 有新版本了。\n请更新后继续拍瓜。",
            .en: "A newer version of MelonThump is ready.\nPlease update to keep thumping.",
            .es: "Hay una versión más nueva de MelonThump.\nActualiza para seguir golpeando.",
        ],
        "upd.latest": [.zh: "最新版本：%@", .en: "Latest version: %@", .es: "Última versión: %@"],
        "upd.get": [.zh: "获取最新版本", .en: "Get the Latest Version", .es: "Obtener la última versión"],
        "upd.noLink": [
            .zh: "更新链接尚未配置。",
            .en: "The update link is not configured yet.",
            .es: "El enlace de actualización aún no está configurado.",
        ],
        "splash.version": [.zh: "版本 %@", .en: "Version %@", .es: "Versión %@"],
        // Launch-screen role credits: roles localize, names never do.
        "credit.uiDesigner": [.zh: "UI 设计", .en: "UI Designer", .es: "Diseño de UI"],
        "credit.projectOwner": [.zh: "项目负责人", .en: "Project Owner", .es: "Responsable del proyecto"],
        "credit.architecture": [.zh: "架构", .en: "Architecture", .es: "Arquitectura"],
        "credit.developer": [.zh: "开发", .en: "Developer", .es: "Desarrollo"],
        "credit.baqa": [.zh: "BA/QA", .en: "BA/QA", .es: "BA/QA"],
        "credit.separator": [.zh: "：", .en: ": ", .es: ": "],

        // MARK: Menu
        "menu.models": [.zh: "模型选择", .en: "Model", .es: "Modelo"],
        "menu.settings": [.zh: "设置", .en: "Settings", .es: "Ajustes"],
        "menu.about": [.zh: "关于", .en: "About", .es: "Acerca de"],

        // MARK: Model picker
        "models.title": [.zh: "模型选择", .en: "Models", .es: "Modelos"],
        "models.default": [.zh: "默认", .en: "Default", .es: "Predeterminado"],
        "models.free": [.zh: "免费", .en: "Free", .es: "Gratis"],
        "models.paid": [.zh: "付费", .en: "Paid", .es: "De pago"],
        "models.purchased": [.zh: "已购买", .en: "Purchased", .es: "Comprado"],
        "models.version": [.zh: "版本 %@", .en: "Version %@", .es: "Versión %@"],
        "models.footer": [
            .zh: "所选模型从下一次拍瓜起生效。",
            .en: "Your choice applies from the next thump.",
            .es: "Tu elección se aplica desde el próximo golpe.",
        ],

        // MARK: Settings
        "set.title": [.zh: "设置", .en: "Settings", .es: "Ajustes"],
        "set.language": [.zh: "语言", .en: "Language", .es: "Idioma"],
        "set.followSystem": [.zh: "跟随系统", .en: "Follow System", .es: "Según el sistema"],
        "set.duration": [.zh: "聆听时长", .en: "Listening Duration", .es: "Duración de escucha"],
        "set.seconds": [.zh: "%d 秒", .en: "%d s", .es: "%d s"],
        "set.secondsDefault": [.zh: "%d 秒（默认）", .en: "%d s (default)", .es: "%d s (predeterminado)"],
        "set.durationFooter": [
            .zh: "每次录音聆听多久，下一次录音起生效。",
            .en: "How long each recording listens. Applies from the next recording.",
            .es: "Cuánto escucha cada grabación. Se aplica desde la próxima grabación.",
        ],
        "set.server": [.zh: "服务器", .en: "Server", .es: "Servidor"],
        "set.serverFooter": [
            .zh: "仅测试版本可见。",
            .en: "Shown on test builds only.",
            .es: "Solo visible en versiones de prueba.",
        ],
        "server.prod": [.zh: "生产服务器", .en: "Prod Server", .es: "Servidor de producción"],
        "server.dev": [.zh: "开发服务器", .en: "Dev Server", .es: "Servidor de desarrollo"],
        "set.feedback": [.zh: "意见与建议", .en: "Feedback & Suggestions", .es: "Comentarios y sugerencias"],
        "set.feedbackSubject": [.zh: "MelonThump 意见反馈", .en: "MelonThump Feedback", .es: "Comentarios sobre MelonThump"],
        "set.team": [.zh: "开发团队", .en: "Development Team", .es: "Equipo de desarrollo"],
        "set.about": [.zh: "关于", .en: "About", .es: "Acerca de"],
        "set.version": [.zh: "版本", .en: "Version", .es: "Versión"],

        // MARK: Development Team
        "team.title": [.zh: "开发团队", .en: "Development Team", .es: "Equipo de desarrollo"],

        // MARK: About
        "about.title": [.zh: "关于", .en: "About", .es: "Acerca de"],
        "about.blurb": [
            .zh: "拍一拍西瓜，就知道熟没熟。分析完全在你的 iPhone 上完成——录音从不离开手机。",
            .en: "Thump a watermelon, know if it's ripe. Analysis runs entirely on your iPhone — recordings never leave it.",
            .es: "Golpea una sandía y sabrás si está madura. El análisis se hace por completo en tu iPhone: las grabaciones nunca salen de él.",
        ],
        "about.version": [.zh: "版本", .en: "Version", .es: "Versión"],
        "about.privacy": [.zh: "隐私政策", .en: "Privacy Policy", .es: "Política de privacidad"],
        "about.terms": [.zh: "使用条款", .en: "Terms of Use", .es: "Términos de uso"],
        "about.contact": [.zh: "联系我们", .en: "Contact", .es: "Contacto"],
        "about.github": [.zh: "GitHub 项目说明（README）", .en: "Project README on GitHub", .es: "README del proyecto en GitHub"],

        // MARK: Invite
        "invite.title": [.zh: "邀请好友", .en: "Invite friends", .es: "Invita a tus amigos"],
        "invite.blurb": [
            .zh: "你邀请的好友完成第一次拍瓜后，你们各得 %d 个 credit（最多 %d 位好友）。1 个 credit 可免广告解锁一次使用。",
            .en: "When a friend you invite finishes their first thump, you each get %d credits (up to %d friends). A credit unlocks a visit without ads.",
            .es: "Cuando un amigo invitado complete su primer golpe, cada uno recibe %d créditos (hasta %d amigos). Un crédito desbloquea una visita sin anuncios.",
        ],
        "invite.share": [.zh: "分享我的邀请", .en: "Share my invite", .es: "Compartir mi invitación"],
        "invite.haveCode": [.zh: "我有邀请码", .en: "I have a code", .es: "Tengo un código"],
        "invite.codePlaceholder": [.zh: "邀请码", .en: "Invite code", .es: "Código de invitación"],
        "invite.apply": [.zh: "使用邀请码", .en: "Apply code", .es: "Aplicar código"],
        "invite.codeHint": [
            .zh: "邀请码需在第一次拍瓜前填写。",
            .en: "Enter a code before your first thump.",
            .es: "Introduce el código antes de tu primer golpe.",
        ],
        "invite.shareText": [
            .zh: "拍一拍西瓜就知道熟没熟！用我的邀请码 %@ 加入 MelonThump：%@",
            .en: "Thump a watermelon, know if it's ripe! Join me on MelonThump with my invite code %@: %@",
            .es: "¡Golpea una sandía y sabrás si está madura! Únete a MelonThump con mi código %@: %@",
        ],
        "invite.applied": [
            .zh: "邀请码已生效！完成第一次拍瓜后，你们各得 %d 个 credit。",
            .en: "Code applied! Finish your first thump and you'll each get %d credits.",
            .es: "¡Código aplicado! Completa tu primer golpe y cada uno recibirá %d créditos.",
        ],
        "invite.linkReceived": [
            .zh: "已收到邀请——完成第一次拍瓜后生效。",
            .en: "Invite received — it counts once you finish your first thump.",
            .es: "Invitación recibida: cuenta cuando completes tu primer golpe.",
        ],
        "invite.err.unknown": [.zh: "邀请码不存在。", .en: "That invite code doesn't exist.", .es: "Ese código de invitación no existe."],
        "invite.err.malformed": [
            .zh: "邀请码由 8 位字母和数字组成。",
            .en: "Invite codes have 8 letters and digits.",
            .es: "Los códigos tienen 8 letras y números.",
        ],
        "invite.err.self": [.zh: "这是你自己的邀请码。", .en: "That's your own code.", .es: "Ese es tu propio código."],
        "invite.err.taken": [
            .zh: "这台设备已经用过邀请了。",
            .en: "This device has already used an invite.",
            .es: "Este dispositivo ya usó una invitación.",
        ],
        "invite.err.active": [
            .zh: "邀请码只能在第一次拍瓜前填写。",
            .en: "Invite codes can only be entered before your first thump.",
            .es: "Los códigos solo se pueden introducir antes de tu primer golpe.",
        ],
        "invite.err.network": [
            .zh: "连不上服务器，请稍后再试。",
            .en: "Couldn't reach the server. Try again in a moment.",
            .es: "No se pudo conectar con el servidor. Inténtalo de nuevo en un momento.",
        ],
        "invite.reward": [
            .zh: "邀请奖励：+%d 个 credit",
            .en: "Invite reward: +%d credits",
            .es: "Recompensa por invitación: +%d créditos",
        ],
        "invite.progress": [
            .zh: "已有 %d/%d 位好友完成首次拍瓜",
            .en: "%d of %d friends have thumped",
            .es: "%d de %d amigos ya golpearon",
        ],
    ]
}
