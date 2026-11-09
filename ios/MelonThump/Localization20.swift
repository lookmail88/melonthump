import Foundation

/// 2.0 strings: melon records, unified capture, the Model Improvement
/// Program. Merged into L10n.strings (same completeness self-check).
/// The program's privacy lines follow design doc 2.0 §7 item 8 — the
/// same wording as the App Store privacy label.
extension L10n {
    static let strings20: [String: [AppLanguage: String]] = [
        // MARK: Menu / Settings
        "menu.records": [.zh: "我的瓜", .en: "My Melons", .es: "Mis sandías"],
        "set.joinProgram": [
            .zh: "参与模型提升计划",
            .en: "Join the Model Improvement Program",
            .es: "Unirse al Programa de Mejora del Modelo",
        ],

        // MARK: Records list
        "records.title": [.zh: "我的瓜", .en: "My Melons", .es: "Mis sandías"],
        "records.new": [.zh: "新的瓜", .en: "New melon", .es: "Nueva sandía"],
        "records.empty": [
            .zh: "还没有记录。每次拍瓜都会自动记在这里，也可以点右上角「＋」新建一只瓜。",
            .en: "No melons yet. Every thump is saved here automatically — or tap + to start a new melon.",
            .es: "Aún no hay sandías. Cada golpe se guarda aquí automáticamente, o toca + para empezar una nueva.",
        ],
        "records.noVariety": [.zh: "未选品种", .en: "Variety not set", .es: "Variedad sin elegir"],
        "records.noThump": [.zh: "还没拍", .en: "Not thumped yet", .es: "Aún sin golpear"],
        "records.contributed": [.zh: "已贡献", .en: "Contributed", .es: "Aportada"],
        "records.delete": [.zh: "删除记录", .en: "Delete record", .es: "Eliminar registro"],
        "records.deleteTitle": [.zh: "删除这条瓜记录？", .en: "Delete this melon record?", .es: "¿Eliminar este registro?"],
        "records.deleteMessage": [
            .zh: "照片和记录会从本机删除。录音文件按原有的保留规则处理。",
            .en: "Its photos and details are removed from this phone. Recordings follow the usual retention rule.",
            .es: "Sus fotos y datos se borran de este teléfono. Las grabaciones siguen la regla de conservación habitual.",
        ],
        "records.deleteSubmitted": [
            .zh: "只删除本机记录。服务器上的样本不受影响——要删除它，请在「我的贡献」里撤回。",
            .en: "This removes the record from this phone only. The sample on the server stays — withdraw it in My contributions to delete it there.",
            .es: "Solo se borra de este teléfono. La muestra del servidor se mantiene; retírala en Mis aportaciones para borrarla allí.",
        ],
        "records.gone": [.zh: "这条记录已删除。", .en: "This record was deleted.", .es: "Este registro se eliminó."],
        "records.thumpingFor": [
            .zh: "下一拍记入：%@ 的瓜",
            .en: "Next thump goes to the melon from %@",
            .es: "El próximo golpe va a la sandía del %@",
        ],

        // MARK: Result (verdict) → this thump's record
        "res.photograph": [.zh: "给这只瓜拍照", .en: "Photograph this melon", .es: "Fotografiar esta sandía"],

        // MARK: Capture steps
        "capture.step1": [.zh: "① 外观照片", .en: "1 · Appearance photos", .es: "1 · Fotos del exterior"],
        "capture.step2": [.zh: "② 拍瓜", .en: "2 · Thump", .es: "2 · Golpe"],
        "capture.step3": [.zh: "③ 重量（可不填）", .en: "3 · Weight (optional)", .es: "3 · Peso (opcional)"],
        "capture.step4": [.zh: "④ 品种", .en: "4 · Variety", .es: "4 · Variedad"],
        "capture.afterEating": [.zh: "切开以后", .en: "After cutting it open", .es: "Después de abrirla"],
        "capture.addRind": [.zh: "拍瓜皮纹理近照（主要）", .en: "Rind texture close-up (main)", .es: "Primer plano de la cáscara (principal)"],
        "capture.addWhole": [.zh: "拍整瓜照片", .en: "Whole melon photo", .es: "Foto de la sandía entera"],
        "capture.cardGuide": [
            .zh: "可选：在瓜旁放一张银行卡作尺寸参照。",
            .en: "Optional: place a bank card beside the melon as a size reference.",
            .es: "Opcional: pon una tarjeta bancaria junto a la sandía como referencia de tamaño.",
        ],
        "capture.photosFooter": [
            .zh: "照片以原画质保存在本机。长按照片可删除。",
            .en: "Photos are kept at full quality on this phone. Long-press a photo to remove it.",
            .es: "Las fotos se guardan con calidad completa en este teléfono. Mantén pulsada una foto para quitarla.",
        ],
        "capture.camera": [.zh: "拍照", .en: "Take photo", .es: "Hacer foto"],
        "capture.library": [.zh: "从相册选择", .en: "Choose from library", .es: "Elegir de la fototeca"],
        "capture.removePhoto": [.zh: "删除照片", .en: "Remove photo", .es: "Quitar foto"],
        "capture.rind": [.zh: "纹理", .en: "Rind", .es: "Cáscara"],
        "capture.whole": [.zh: "整瓜", .en: "Whole", .es: "Entera"],
        "capture.cut": [.zh: "切开", .en: "Cut open", .es: "Abierta"],
        "capture.addCut": [.zh: "拍切开图", .en: "Cut-open photo", .es: "Foto de la sandía abierta"],
        "capture.replaceCut": [.zh: "重拍切开图", .en: "Replace cut-open photo", .es: "Cambiar foto de la sandía abierta"],
        "capture.saveFailed": [.zh: "照片没能保存。", .en: "The photo could not be saved.", .es: "No se pudo guardar la foto."],
        "capture.thump": [.zh: "拍这只瓜", .en: "Thump this melon", .es: "Golpear esta sandía"],
        "capture.thumpMore": [.zh: "再拍一次这只瓜", .en: "Thump this melon again", .es: "Golpear esta sandía otra vez"],
        "capture.thumpFooter": [
            .zh: "回到首页录音并分析，结果记入这只瓜。敲赤道部效果最好。",
            .en: "Records and analyzes on the home screen; the result is saved to this melon. Knocking at the equator works best.",
            .es: "Graba y analiza en la pantalla principal; el resultado se guarda en esta sandía. Golpear en el ecuador funciona mejor.",
        ],
        "capture.recordingGone": [.zh: "录音已清理", .en: "Recording removed", .es: "Grabación borrada"],

        // MARK: Weight
        "weight.placeholder": [.zh: "重量（克）", .en: "Weight in grams", .es: "Peso en gramos"],
        "weight.how": [.zh: "重量来源", .en: "Weight source", .es: "Origen del peso"],
        "weight.scale": [.zh: "秤上称的", .en: "Weighed on a scale", .es: "Pesada en báscula"],
        "weight.estimate": [.zh: "我估的", .en: "My estimate", .es: "Mi estimación"],
        "weight.photo": [.zh: "照片估算", .en: "Estimated from photo", .es: "Estimado por foto"],
        "weight.footer": [
            .zh: "可不填，不影响后续步骤。",
            .en: "Optional — you can always skip it.",
            .es: "Opcional: siempre puedes omitirlo.",
        ],

        // MARK: Variety (selection only)
        "variety.title": [.zh: "品种", .en: "Variety", .es: "Variedad"],
        "variety.unset": [.zh: "未选择", .en: "Not chosen", .es: "Sin elegir"],
        "variety.seedless": [.zh: "无籽瓜", .en: "Seedless", .es: "Sin semillas"],
        "variety.seeded": [.zh: "有籽瓜", .en: "Seeded", .es: "Con semillas"],
        "variety.mini": [.zh: "迷你瓜", .en: "Mini", .es: "Mini"],
        "variety.yellowFlesh": [.zh: "黄瓤", .en: "Yellow-flesh", .es: "Pulpa amarilla"],
        "variety.kirin": [.zh: "麒麟瓜", .en: "Kirin", .es: "Kirin"],
        "variety.blackBeauty": [.zh: "黑美人", .en: "Black Beauty", .es: "Black Beauty"],
        "variety.other": [.zh: "其他 / 不清楚", .en: "Other / not sure", .es: "Otra / no sé"],

        // MARK: Feedback (the user's own score)
        "feedback.title": [.zh: "我的评价", .en: "My rating", .es: "Mi valoración"],
        "feedback.add": [.zh: "吃过了，给它打分", .en: "Tasted it — rate it", .es: "Ya la probé: valorarla"],
        "feedback.edit": [.zh: "修改我的评价", .en: "Edit my rating", .es: "Editar mi valoración"],
        "feedback.footer": [
            .zh: "切开吃过后补上切开图和你自己的评价，任何时候都可以回来补。",
            .en: "Once you've eaten it, add the cut-open photo and your own rating — come back any time.",
            .es: "Cuando la hayas comido, añade la foto abierta y tu valoración; puedes volver cuando quieras.",
        ],
        "feedback.score": [.zh: "我的评分", .en: "My score", .es: "Mi puntuación"],
        "feedback.scoreLine": [.zh: "我的评分：%d / 100", .en: "My score: %d / 100", .es: "Mi puntuación: %d / 100"],
        "feedback.scoreFooter": [
            .zh: "0–100，100 是理想中最好的瓜。",
            .en: "0–100, where 100 is the best melon you can imagine.",
            .es: "De 0 a 100; 100 es la mejor sandía imaginable.",
        ],
        "feedback.taste": [.zh: "口感（可多选）", .en: "Taste (pick any)", .es: "Sabor (elige varios)"],
        "feedback.band": [.zh: "实际熟度", .en: "How ripe it really was", .es: "Madurez real"],
        "feedback.bandFooter": [
            .zh: "按你吃到的真实情况选。",
            .en: "Pick what you actually found when you ate it.",
            .es: "Elige lo que encontraste al comerla.",
        ],
        "feedback.save": [.zh: "保存", .en: "Save", .es: "Guardar"],
        "taste.crisp": [.zh: "脆", .en: "Crisp", .es: "Crujiente"],
        "taste.mealy": [.zh: "面", .en: "Mealy", .es: "Harinosa"],
        "taste.sandy": [.zh: "沙", .en: "Sandy", .es: "Arenosa"],
        "taste.juicy": [.zh: "多汁", .en: "Juicy", .es: "Jugosa"],
        "taste.sweet": [.zh: "甜", .en: "Sweet", .es: "Dulce"],
        "taste.bland": [.zh: "淡", .en: "Bland", .es: "Sosa"],
        "band.unripe": [.zh: "生", .en: "Unripe", .es: "Verde"],
        "band.ripe": [.zh: "熟", .en: "Ripe", .es: "Madura"],
        "band.overripe": [.zh: "过熟", .en: "Overripe", .es: "Pasada"],

        // MARK: Sample parts
        "part.appearance": [.zh: "外观", .en: "Photos", .es: "Fotos"],
        "part.recording": [.zh: "录音", .en: "Sound", .es: "Sonido"],
        "part.cutOpen": [.zh: "切开图", .en: "Cut open", .es: "Abierta"],
        "part.feedback": [.zh: "评价", .en: "Rating", .es: "Valoración"],

        // MARK: Contribute
        "contrib.section": [.zh: "模型提升计划", .en: "Model Improvement Program", .es: "Programa de Mejora del Modelo"],
        "contrib.contribute": [.zh: "贡献这只瓜", .en: "Contribute this melon", .es: "Aportar esta sandía"],
        "contrib.upload": [.zh: "上传样本", .en: "Upload sample", .es: "Subir muestra"],
        "contrib.confirm": [
            .zh: "将上传这只瓜的样本包：外观照片、录音、切开图、你的评价和簿记信息（品种、重量、日期），只关联你的匿名贡献者 ID。缺的部分以后可以补。",
            .en: "This uploads the melon's sample package — appearance photos, recording, cut-open photo, your rating and bookkeeping (variety, weight, date) — linked only to your anonymous contributor ID. Missing parts can be added later.",
            .es: "Se sube el paquete de esta sandía —fotos, grabación, foto abierta, tu valoración y datos (variedad, peso, fecha)— vinculado solo a tu ID anónimo de colaborador. Lo que falte se puede añadir después.",
        ],
        "contrib.footer": [
            .zh: "不完整的样本也可以先提交，之后补齐四部分。只有通过审核的完整样本才计入奖励。",
            .en: "Incomplete samples can be submitted now and completed later. Only approved complete samples earn ad-free units.",
            .es: "Puedes enviar muestras incompletas y completarlas después. Solo las muestras completas aprobadas dan unidades sin anuncios.",
        ],
        "contrib.needVariety": [
            .zh: "先在上面选一个品种（「其他 / 不清楚」也可以）。",
            .en: "Choose a variety above first (\"Other / not sure\" is fine).",
            .es: "Elige antes una variedad arriba (\"Otra / no sé\" vale).",
        ],
        "contrib.appendFooter": [
            .zh: "吃完后补的切开图、评价和新照片，用「发送补充」上传到同一个样本。",
            .en: "The cut-open photo, rating and new photos you add later go to the same sample with Send updates.",
            .es: "La foto abierta, la valoración y las fotos nuevas se envían a la misma muestra con Enviar novedades.",
        ],
        "contrib.sendUpdates": [.zh: "发送补充", .en: "Send updates", .es: "Enviar novedades"],
        "contrib.sent": [.zh: "已发送。谢谢你！", .en: "Sent — thank you!", .es: "Enviado. ¡Gracias!"],
        "contrib.sampleNumber": [.zh: "样本 #%@", .en: "Sample #%@", .es: "Muestra n.º %@"],
        "contrib.returnReason": [.zh: "退回原因：%@", .en: "Returned: %@", .es: "Devuelta: %@"],
        "contrib.none": [.zh: "还没有提交过样本。", .en: "No samples submitted yet.", .es: "Aún no has enviado muestras."],
        "contrib.complete": [.zh: "四部分齐全", .en: "Complete — all four parts", .es: "Completa: las cuatro partes"],
        "contrib.incomplete": [.zh: "不完整", .en: "Incomplete", .es: "Incompleta"],
        "contrib.withdraw": [.zh: "撤回并删除", .en: "Withdraw & delete", .es: "Retirar y borrar"],
        "contrib.withdrawTitle": [.zh: "撤回这个样本？", .en: "Withdraw this sample?", .es: "¿Retirar esta muestra?"],
        "contrib.withdrawMessage": [
            .zh: "服务器上的照片、录音和评价会被真正删除（备份在 30 天内过期）。本机的瓜记录保留。",
            .en: "The server copies of its photos, recording and rating are truly deleted (backups age out within 30 days). Your melon record on this phone stays.",
            .es: "Las copias del servidor (fotos, grabación y valoración) se borran de verdad; las copias de seguridad caducan en 30 días. Tu registro en este teléfono se queda.",
        ],
        "sample.submitted": [.zh: "待审核", .en: "In review", .es: "En revisión"],
        "sample.approved": [.zh: "已通过", .en: "Approved", .es: "Aprobada"],
        "sample.returned": [.zh: "已退回", .en: "Returned", .es: "Devuelta"],
        "sample.voided": [.zh: "已作废", .en: "Voided", .es: "Anulada"],
        "sample.withdrawn": [.zh: "已撤回", .en: "Withdrawn", .es: "Retirada"],

        // MARK: Program
        "program.title": [.zh: "模型提升计划", .en: "Model Improvement Program", .es: "Programa de Mejora del Modelo"],
        "program.intro": [
            .zh: "自愿参与：把你吃过的瓜作为样本分享给我们，帮助训练更准的判瓜模型。默认关闭，提交申请并经审核通过后才能上传。",
            .en: "Voluntary: share melons you have eaten as samples to help train a more accurate model. Off by default — you apply, and uploading opens only once your application is approved.",
            .es: "Voluntario: comparte como muestras las sandías que hayas comido para entrenar un modelo más preciso. Desactivado por defecto: solicitas y solo podrás subir cuando se apruebe.",
        ],
        "program.partsHeader": [.zh: "一份完整样本的四部分", .en: "The four parts of a complete sample", .es: "Las cuatro partes de una muestra completa"],
        "program.part.appearance": [
            .zh: "外观照片：瓜皮纹理近照为主，整瓜照为辅（可在旁边放银行卡作尺寸参照）",
            .en: "Appearance photos: rind close-ups first, plus a whole-melon shot (a bank card beside it as a size reference is welcome)",
            .es: "Fotos del exterior: primeros planos de la cáscara y una foto entera (con una tarjeta bancaria al lado como referencia, si quieres)",
        ],
        "program.part.recording": [.zh: "拍瓜录音", .en: "The thump recording", .es: "La grabación del golpe"],
        "program.part.cutOpen": [.zh: "切开后的果肉照片", .en: "A photo of the cut flesh", .es: "Una foto de la pulpa abierta"],
        "program.part.feedback": [
            .zh: "你的评价：0–100 评分、口感标签、实际熟度",
            .en: "Your feedback: a 0–100 score, taste tags, and how ripe it really was",
            .es: "Tu valoración: puntuación 0–100, etiquetas de sabor y madurez real",
        ],
        "program.earnHeader": [.zh: "奖励", .en: "What you earn", .es: "Qué ganas"],
        "program.earn": [
            .zh: "每份审核通过的完整样本获得免广告次数（目前 5 次）；1 次可免看一支激励广告来解锁本次使用。不完整的样本不计奖励。免广告次数是唯一的奖励，与邀请 credit 分开记账。",
            .en: "Each approved complete sample earns ad-free units (currently 5); one unit skips one rewarded ad to unlock a session. Incomplete samples earn nothing. Ad-free units are the only reward and are kept separate from invite credits.",
            .es: "Cada muestra completa aprobada da unidades sin anuncios (ahora 5); una unidad evita un anuncio con recompensa para desbloquear la sesión. Las incompletas no dan nada. Es la única recompensa y va aparte de los créditos de invitación.",
        ],
        "program.privacyHeader": [.zh: "隐私", .en: "Privacy", .es: "Privacidad"],
        "program.privacy.uploaded": [
            .zh: "只上传样本包本身：外观照片、录音、切开图、你的评分 / 口感 / 熟度反馈，以及簿记信息（品种、重量、来源、日期）。不含姓名、联系方式或设备标识。开通留言只给项目负责人看，不属于样本数据。",
            .en: "Only the sample package itself is uploaded: appearance photos, recordings, the cut-open photo, your score / taste / ripeness feedback, and bookkeeping metadata (variety, weight, source, date). No names, contacts or device identifiers. Your enrollment note is seen by the project owner only and is never part of sample data.",
            .es: "Solo se sube el paquete de la muestra: fotos del exterior, grabaciones, la foto abierta, tu puntuación / sabor / madurez y los datos de registro (variedad, peso, origen, fecha). Sin nombres, contactos ni identificadores del dispositivo. Tu nota de inscripción solo la ve el responsable del proyecto y nunca forma parte de las muestras.",
        ],
        "program.privacy.anonymous": [
            .zh: "所有内容只关联一个在本机生成的匿名贡献者 ID——不关联 Apple ID，也不关联真实身份。",
            .en: "Everything is linked only to an anonymous contributor ID created on this phone — no Apple ID, no real-world identity.",
            .es: "Todo se vincula solo a un ID anónimo de colaborador creado en este teléfono: sin Apple ID ni identidad real.",
        ],
        "program.privacy.storage": [
            .zh: "素材存放在项目自己的服务器上，不使用第三方云。",
            .en: "Materials are stored on the project's own server — no third-party cloud.",
            .es: "Los materiales se guardan en el servidor propio del proyecto, sin nubes de terceros.",
        ],
        "program.privacy.label": [
            .zh: "收集照片和音频，只关联匿名贡献者 ID，用于模型改进；绝不用于追踪，绝不与第三方共享。",
            .en: "Photos and audio are collected, linked only to your anonymous contributor ID, used for model improvement — never used for tracking and never shared with third parties.",
            .es: "Se recogen fotos y audio, vinculados solo a tu ID anónimo de colaborador, para mejorar el modelo; nunca para rastrearte y nunca se comparten con terceros.",
        ],
        "program.privacy.delete": [
            .zh: "在「我的贡献」里撤回或删除提交，服务器上的副本会被真正删除，备份在 30 天内过期。",
            .en: "Withdrawing or deleting a submission in My contributions truly deletes the server copies; backups age out within 30 days.",
            .es: "Al retirar o borrar un envío en Mis aportaciones se borran de verdad las copias del servidor; las copias de seguridad caducan en 30 días.",
        ],
        "program.privacy.ordinary": [
            .zh: "只有你亲自点「贡献这只瓜」的记录才会上传；其他瓜记录永远不离开这部手机。",
            .en: "Only a melon you choose to contribute is uploaded; all your other melon records never leave this phone.",
            .es: "Solo se sube la sandía que decidas aportar; tus demás registros nunca salen de este teléfono.",
        ],
        "program.approval": [
            .zh: "提交的是申请：项目负责人审核通过后才能上传样本，资格之后也可能被收回。",
            .en: "This is an application: the project owner reviews it, and sample uploads open only once it is approved. Approval can later be revoked.",
            .es: "Es una solicitud: el responsable del proyecto la revisa y solo podrás subir muestras cuando se apruebe. La aprobación puede revocarse.",
        ],
        "program.continue": [.zh: "继续申请", .en: "Continue to apply", .es: "Continuar con la solicitud"],
        "program.applyTitle": [.zh: "申请加入", .en: "Apply", .es: "Solicitar"],
        "program.noteHeader": [.zh: "开通留言（必填）", .en: "Enrollment note (required)", .es: "Nota de inscripción (obligatoria)"],
        "program.noteFooter": [
            .zh: "简单说说你是谁，方便项目负责人认出你。只给负责人看，不属于样本数据。",
            .en: "Say briefly who you are so the project owner can tell. Seen by the owner only; never part of sample data.",
            .es: "Di brevemente quién eres para que el responsable te reconozca. Solo lo ve él; nunca forma parte de las muestras.",
        ],
        "program.submit": [.zh: "提交申请", .en: "Submit application", .es: "Enviar solicitud"],
        "program.status": [.zh: "申请状态", .en: "Application status", .es: "Estado de la solicitud"],
        "program.pending": [.zh: "审核中", .en: "Pending", .es: "Pendiente"],
        "program.approved": [.zh: "已通过", .en: "Approved", .es: "Aprobada"],
        "program.declined": [.zh: "未通过", .en: "Declined", .es: "Rechazada"],
        "program.revoked": [.zh: "已收回", .en: "Revoked", .es: "Revocada"],
        "program.pendingDetail": [
            .zh: "申请已收到，等待项目负责人审核。",
            .en: "Your application is in; the project owner will review it.",
            .es: "Hemos recibido tu solicitud; el responsable la revisará.",
        ],
        "program.approvedDetail": [
            .zh: "你可以从瓜记录里贡献样本了。",
            .en: "You can now contribute melons from your melon records.",
            .es: "Ya puedes aportar sandías desde tus registros.",
        ],
        "program.declinedDetail": [
            .zh: "这次申请没有通过。谢谢你的关注。",
            .en: "This application was not approved. Thank you for your interest.",
            .es: "Esta solicitud no se aprobó. Gracias por tu interés.",
        ],
        "program.revokedDetail": [
            .zh: "贡献资格已收回。你仍然可以查看和撤回自己的提交。",
            .en: "Contributor status was revoked. You can still view and withdraw your own submissions.",
            .es: "Se revocó tu condición de colaborador. Aún puedes ver y retirar tus envíos.",
        ],
        "program.adFreeHeader": [.zh: "免广告", .en: "Ad-free", .es: "Sin anuncios"],
        "program.balance": [.zh: "免广告次数", .en: "Ad-free units", .es: "Unidades sin anuncios"],
        "program.balanceFooter": [
            .zh: "需要看广告解锁时，可以改用 1 次免广告。",
            .en: "When an ad would unlock a session, you can use 1 ad-free unit instead.",
            .es: "Cuando haría falta un anuncio para desbloquear, puedes usar 1 unidad sin anuncios.",
        ],
        "program.exempt": [.zh: "永久免广告", .en: "Permanently ad-free", .es: "Sin anuncios para siempre"],
        "program.exemptFooter": [
            .zh: "感谢贡献！你不会再看到广告。",
            .en: "Thank you for contributing — you won't see ads.",
            .es: "¡Gracias por colaborar! No verás anuncios.",
        ],
        "program.myContributions": [.zh: "我的贡献", .en: "My contributions", .es: "Mis aportaciones"],
        "program.howToContribute": [
            .zh: "贡献方法：菜单 →「我的瓜」→ 打开一只瓜 →「贡献这只瓜」。",
            .en: "To contribute: menu → My Melons → open a melon → Contribute this melon.",
            .es: "Para aportar: menú → Mis sandías → abre una sandía → Aportar esta sandía.",
        ],
        "program.about": [.zh: "计划说明与隐私", .en: "About the program & privacy", .es: "Sobre el programa y la privacidad"],
        "program.idFooter": [
            .zh: "匿名贡献者 ID：%@…（保存在本机钥匙串）",
            .en: "Anonymous contributor ID: %@… (kept in this phone's Keychain)",
            .es: "ID anónimo de colaborador: %@… (guardado en el llavero de este teléfono)",
        ],
        "program.unavailableTitle": [.zh: "暂未开放", .en: "Not available yet", .es: "Aún no disponible"],
        "program.unavailable": [
            .zh: "这项功能暂时还用不了，请稍后再试。拍瓜和瓜记录不受影响。",
            .en: "This isn't available yet — please try again later. Thumping and your melon records work as usual.",
            .es: "Esto aún no está disponible; inténtalo más tarde. Golpear y tus registros funcionan con normalidad.",
        ],
        "program.retry": [.zh: "重试", .en: "Try again", .es: "Reintentar"],
        "program.notApproved": [
            .zh: "你的贡献者资格目前不能上传样本。",
            .en: "Your contributor status doesn't allow uploads right now.",
            .es: "Tu condición de colaborador no permite subir muestras ahora.",
        ],
        "program.unknown": [
            .zh: "服务器上找不到你的申请，请重新申请。",
            .en: "The server has no application for you — please apply again.",
            .es: "El servidor no tiene tu solicitud; vuelve a solicitarlo.",
        ],
        "program.tooLarge": [
            .zh: "文件太大，无法上传。",
            .en: "A file is too large to upload.",
            .es: "Un archivo es demasiado grande para subirlo.",
        ],
        "program.illegalState": [
            .zh: "这个样本已审核完成，不能再修改或撤回。",
            .en: "This sample has been finalized and can't be changed or withdrawn.",
            .es: "Esta muestra ya está cerrada y no se puede cambiar ni retirar.",
        ],
        "program.rejected": [
            .zh: "服务器没有接受这次提交。",
            .en: "The server did not accept this submission.",
            .es: "El servidor no aceptó este envío.",
        ],

        // MARK: Gates / credits
        "gate.useAdFree": [
            .zh: "用 1 次免广告（剩 %d 次）",
            .en: "Use 1 ad-free unit (%d left)",
            .es: "Usar 1 unidad sin anuncios (quedan %d)",
        ],
        "gate.adFreeFailed": [
            .zh: "免广告次数暂时用不了——可以先看广告解锁。",
            .en: "Couldn't use an ad-free unit right now — you can watch the ad instead.",
            .es: "No se pudo usar una unidad sin anuncios; puedes ver el anuncio.",
        ],
        "credits.adFree": [.zh: "免广告：随便拍", .en: "Ad-free: thump away", .es: "Sin anuncios: golpea cuanto quieras"],
    ]
}
