// Deterministic replacement for the old fixed-string-per-category MESSAGES
// map (Phase 2: see docs/coaching-personalization-plan.md) -- a short,
// plain-language sentence citing the ACTUAL numbers that drove today's
// category, generalized off whichever wearable fields are actually
// populated rather than assuming any one of them exists.
//
// Deliberately NOT an LLM call: generate-recommendation has zero AI calls
// today, and every number this needs is already sitting in local variables
// right where the old MESSAGES[category] lookup lived. A deterministic
// builder keeps BOTH the category decision and its explanation fully
// deterministic and unit-testable -- same "split into a pure module" shape
// as healthkitBand.ts/independentCaps.ts, this function's own siblings.
//
// The precedence used below to pick WHICH driver to cite mirrors index.ts's
// own computedCategory conditional exactly (same booleans, same left-to-
// right order) so this message can never contradict the category it's
// explaining -- it is purely a "why", never a second vote on "what".
//
// Item 4 fix: returns { summary, detail } instead of one string. `summary`
// is hard-capped to ~90 chars so it always fits the card's 2-3 line limit
// without truncating mid-word (the original bug); `detail` is the fuller
// sentence (same content the old single-string version returned) shown in
// the "Why this?" disclosure instead.
//
// Item 7 fix: every phrase fragment is looked up by `language` (one of the
// 9 codes _shared/language.ts already normalizes to) instead of being a
// hardcoded English literal -- this is what was making "Moderate"/"You're
// in decent shape today..." always render in English regardless of the
// client's selected locale.

import type { Band, DataConfidence } from "./healthkitBand.ts";
import type { Category } from "../_shared/independentCaps.ts";

export type Source = "whoop" | "oura" | "healthkit";

export interface ReasoningMessageCaps {
  sleep: boolean;
  hrv: boolean;
  stress: boolean;
  mood: boolean;
  consecutiveDays: boolean;
  consecutiveDaysRestEscalated: boolean;
  volume: boolean;
  injury: boolean;
  injuryModerate: boolean;
  injuryRest: boolean;
}

export interface ReasoningMessageInput {
  category: Category;
  /// The user's own explicit rest/active-recovery request for today, if
  /// any -- wins outright over every computed signal below, same
  /// precedence `category` itself already gives it (set-recommendation-
  /// override).
  userRequestedCategory: Category | null;
  source: Source;
  band: Band;
  /// True only for a HealthKit read with literally zero usable signals
  /// today (index.ts's own insufficientData) -- every number below is
  /// meaningless in that case, so the message must not cite any of them.
  insufficientData: boolean;
  dataConfidence: DataConfidence;
  recoveryScore: number | null;
  readinessScore: number | null;
  hrvMs: number | null;
  sleepHours: number | null;
  restingHr: number | null;
  strainScore: number | null;
  stressMinutes: number | null;
  caps: ReasoningMessageCaps;
  /// One of _shared/language.ts's 9 normalized codes -- already validated
  /// by the caller (normalizeLanguageCode), so an unrecognized/missing
  /// value never reaches here.
  language: string;
}

export interface ReasoningMessage {
  summary: string;
  detail: string;
}

interface Phrases {
  categoryOpening: Record<Category, string>;
  categoryLabel: Record<Category, string>;
  bandPhrase: Record<Band, string>;
  whoopRecovery: (percent: string) => string;
  ouraReadiness: (score: string) => string;
  healthkitSignals: (bandPhrase: string) => string;
  sleepHoursBit: (h: number) => string;
  hrvBit: (ms: number) => string;
  restingHrBit: (bpm: number) => string;
  strainWhoopBit: (score: number) => string;
  strainOtherBit: (n: number) => string;
  stressBit: (min: number) => string;
  userRequested: (label: string) => string;
  userRequestedWithNumbers: (label: string, numbers: string) => string;
  insufficientData: (label: string) => string;
  lowConfidenceTrailer: string;
  lightCap: {
    consecutiveDays: string;
    injury: string;
    volume: string;
    sleep: (sleepBit: string) => string;
    hrv: string;
    stress: string;
    mood: string;
  };
  consecutiveDaysRestEscalated: string;
  injuryRest: string;
  injuryModerate: string;
}

const EN: Phrases = {
  categoryOpening: {
    push_hard: "Today's a good day to push",
    moderate: "Today calls for a moderate session",
    light: "Today's a lighter day",
    rest: "Today's a full recovery day",
  },
  categoryLabel: { push_hard: "high-intensity", moderate: "moderate", light: "light", rest: "rest" },
  bandPhrase: {
    high: "well recovered",
    medium_high: "solidly recovered",
    medium: "recovering about average",
    low: "showing signs of poor recovery",
  },
  whoopRecovery: (p) => `Whoop recovery is ${p}%`,
  ouraReadiness: (s) => `Oura readiness is ${s}`,
  healthkitSignals: (b) => `Apple Health signals point to ${b}`,
  sleepHoursBit: (h) => `${h}h sleep`,
  hrvBit: (ms) => `HRV ${ms}ms`,
  restingHrBit: (bpm) => `resting HR ${bpm}bpm`,
  strainWhoopBit: (s) => `day strain ${s}/21`,
  strainOtherBit: (n) => `${n} recent hard session(s)`,
  stressBit: (min) => `${min}min high stress`,
  userRequested: (label) => `You asked for a ${label} day today, so that's what's planned.`,
  userRequestedWithNumbers: (label, numbers) => `You asked for a ${label} day today, so that's what's planned (today's data for reference: ${numbers}).`,
  insufficientData: (label) => `No wearable or HealthKit signals yet today, so we're starting you at a safe ${label} baseline until there's enough history to read your recovery accurately.`,
  lowConfidenceTrailer: "Your recovery baseline is still building, so treat this as a rough read for now.",
  lightCap: {
    consecutiveDays: "you've trained hard enough days in a row that it's time to back off",
    injury: "your active injury protocol is capping today's intensity",
    volume: "your recent training volume is already high for this stretch",
    sleep: (sleepBit) => `last night's ${sleepBit} is capping today's intensity`,
    hrv: "today's HRV is down from your usual baseline",
    stress: "today's stress load is elevated",
    mood: "you checked in feeling rough today",
  },
  consecutiveDaysRestEscalated: "you've pushed hard enough days in a row that your body needs a real reset, not just a lighter session",
  injuryRest: "your active injury protocol calls for full rest today, regardless of how your recovery data looks",
  injuryModerate: "a moderate injury protocol is keeping today capped below your usual push-hard days",
};

const RU: Phrases = {
  categoryOpening: {
    push_hard: "Сегодня хороший день, чтобы выложиться",
    moderate: "Сегодня подходит умеренная тренировка",
    light: "Сегодня день полегче",
    rest: "Сегодня день полного восстановления",
  },
  categoryLabel: { push_hard: "интенсивный", moderate: "умеренный", light: "лёгкий", rest: "день отдыха" },
  bandPhrase: {
    high: "хорошо восстановился",
    medium_high: "неплохо восстановился",
    medium: "восстановление в среднем диапазоне",
    low: "признаки слабого восстановления",
  },
  whoopRecovery: (p) => `Восстановление по Whoop ${p}%`,
  ouraReadiness: (s) => `Готовность по Oura ${s}`,
  healthkitSignals: (b) => `Данные Apple Health указывают: ${b}`,
  sleepHoursBit: (h) => `сон ${h} ч`,
  hrvBit: (ms) => `ВСР ${ms} мс`,
  restingHrBit: (bpm) => `пульс покоя ${bpm} уд/мин`,
  strainWhoopBit: (s) => `нагрузка дня ${s}/21`,
  strainOtherBit: (n) => `тяжёлых тренировок недавно: ${n}`,
  stressBit: (min) => `${min} мин высокого стресса`,
  userRequested: (label) => `Ты попросил(а) ${label} день сегодня — так и запланировано.`,
  userRequestedWithNumbers: (label, numbers) => `Ты попросил(а) ${label} день сегодня — так и запланировано (данные дня для справки: ${numbers}).`,
  insufficientData: (label) => `Пока нет данных с носимых устройств или Apple Health, поэтому Soma начинает с безопасного уровня «${label}», пока не накопится история для точного анализа восстановления.`,
  lowConfidenceTrailer: "Твой базовый уровень восстановления ещё формируется, так что пока считай это приблизительной оценкой.",
  lightCap: {
    consecutiveDays: "ты тренировался(ась) интенсивно уже несколько дней подряд, пора немного снизить темп",
    injury: "активный протокол травмы ограничивает интенсивность сегодня",
    volume: "недавний объём тренировок уже высокий для этого периода",
    sleep: (sleepBit) => `вчерашний ${sleepBit} ограничивает интенсивность сегодня`,
    hrv: "сегодняшняя ВСР ниже твоего обычного уровня",
    stress: "сегодня повышенный уровень стресса",
    mood: "ты отметил(а) плохое самочувствие сегодня",
  },
  consecutiveDaysRestEscalated: "ты тренировался(ась) интенсивно достаточно дней подряд, телу нужен настоящий отдых, а не просто облегчённая тренировка",
  injuryRest: "активный протокол травмы требует полного отдыха сегодня, независимо от показателей восстановления",
  injuryModerate: "умеренный протокол травмы ограничивает сегодня интенсивность ниже твоих обычных тяжёлых дней",
};

const ES: Phrases = {
  categoryOpening: {
    push_hard: "Hoy es un buen día para esforzarte",
    moderate: "Hoy toca una sesión moderada",
    light: "Hoy es un día más ligero",
    rest: "Hoy es un día de recuperación completa",
  },
  categoryLabel: { push_hard: "de alta intensidad", moderate: "moderado", light: "ligero", rest: "de descanso" },
  bandPhrase: {
    high: "bien recuperado",
    medium_high: "razonablemente recuperado",
    medium: "recuperación media",
    low: "señales de recuperación baja",
  },
  whoopRecovery: (p) => `La recuperación de Whoop es ${p}%`,
  ouraReadiness: (s) => `La preparación de Oura es ${s}`,
  healthkitSignals: (b) => `Las señales de Apple Health indican: ${b}`,
  sleepHoursBit: (h) => `${h}h de sueño`,
  hrvBit: (ms) => `VFC ${ms}ms`,
  restingHrBit: (bpm) => `FC en reposo ${bpm}lpm`,
  strainWhoopBit: (s) => `esfuerzo del día ${s}/21`,
  strainOtherBit: (n) => `${n} sesión(es) intensa(s) reciente(s)`,
  stressBit: (min) => `${min}min de estrés alto`,
  userRequested: (label) => `Pediste un día ${label} hoy, así que eso es lo planeado.`,
  userRequestedWithNumbers: (label, numbers) => `Pediste un día ${label} hoy, así que eso es lo planeado (datos de hoy como referencia: ${numbers}).`,
  insufficientData: (label) => `Todavía no hay señales de tu dispositivo o de Apple Health hoy, así que Soma empieza con un nivel seguro de "${label}" hasta tener suficiente historial para leer tu recuperación con precisión.`,
  lowConfidenceTrailer: "Tu línea base de recuperación todavía se está formando, así que considera esto una lectura aproximada por ahora.",
  lightCap: {
    consecutiveDays: "has entrenado fuerte suficientes días seguidos como para bajar el ritmo",
    injury: "tu protocolo de lesión activo está limitando la intensidad de hoy",
    volume: "tu volumen de entrenamiento reciente ya es alto para este período",
    sleep: (sleepBit) => `el ${sleepBit} de anoche está limitando la intensidad de hoy`,
    hrv: "tu VFC de hoy está por debajo de tu línea base habitual",
    stress: "tu nivel de estrés de hoy está elevado",
    mood: "hoy registraste que te sentías mal",
  },
  consecutiveDaysRestEscalated: "has entrenado fuerte suficientes días seguidos como para que tu cuerpo necesite un descanso real, no solo una sesión más ligera",
  injuryRest: "tu protocolo de lesión activo requiere descanso total hoy, sin importar cómo se vean tus datos de recuperación",
  injuryModerate: "un protocolo de lesión moderado mantiene la intensidad de hoy por debajo de tus días de esfuerzo alto habituales",
};

const FR: Phrases = {
  categoryOpening: {
    push_hard: "Aujourd'hui est un bon jour pour se dépasser",
    moderate: "Aujourd'hui appelle une séance modérée",
    light: "Aujourd'hui est une journée plus légère",
    rest: "Aujourd'hui est une journée de récupération complète",
  },
  categoryLabel: { push_hard: "de haute intensité", moderate: "modéré", light: "léger", rest: "de repos" },
  bandPhrase: {
    high: "bien récupéré",
    medium_high: "plutôt bien récupéré",
    medium: "récupération moyenne",
    low: "signes de faible récupération",
  },
  whoopRecovery: (p) => `La récupération Whoop est de ${p}%`,
  ouraReadiness: (s) => `La préparation Oura est de ${s}`,
  healthkitSignals: (b) => `Les signaux Apple Health indiquent : ${b}`,
  sleepHoursBit: (h) => `${h}h de sommeil`,
  hrvBit: (ms) => `VFC ${ms}ms`,
  restingHrBit: (bpm) => `FC au repos ${bpm}bpm`,
  strainWhoopBit: (s) => `effort du jour ${s}/21`,
  strainOtherBit: (n) => `${n} séance(s) intense(s) récente(s)`,
  stressBit: (min) => `${min}min de stress élevé`,
  userRequested: (label) => `Tu as demandé une journée ${label} aujourd'hui, c'est donc ce qui est prévu.`,
  userRequestedWithNumbers: (label, numbers) => `Tu as demandé une journée ${label} aujourd'hui, c'est donc ce qui est prévu (données du jour pour référence : ${numbers}).`,
  insufficientData: (label) => `Pas encore de signaux de ta montre ou d'Apple Health aujourd'hui, donc Soma démarre avec une base "${label}" prudente en attendant assez d'historique pour lire précisément ta récupération.`,
  lowConfidenceTrailer: "Ta base de récupération est encore en construction, considère donc ceci comme une estimation approximative pour l'instant.",
  lightCap: {
    consecutiveDays: "tu t'es entraîné(e) intensément assez de jours d'affilée pour lever le pied",
    injury: "ton protocole de blessure actif limite l'intensité d'aujourd'hui",
    volume: "ton volume d'entraînement récent est déjà élevé pour cette période",
    sleep: (sleepBit) => `le ${sleepBit} de la nuit dernière limite l'intensité d'aujourd'hui`,
    hrv: "ta VFC d'aujourd'hui est en dessous de ta base habituelle",
    stress: "ton niveau de stress est élevé aujourd'hui",
    mood: "tu as signalé te sentir mal aujourd'hui",
  },
  consecutiveDaysRestEscalated: "tu t'es entraîné(e) intensément assez de jours d'affilée pour que ton corps ait besoin d'une vraie coupure, pas juste d'une séance plus légère",
  injuryRest: "ton protocole de blessure actif exige un repos complet aujourd'hui, quelles que soient tes données de récupération",
  injuryModerate: "un protocole de blessure modéré maintient l'intensité d'aujourd'hui en dessous de tes journées intenses habituelles",
};

const IT: Phrases = {
  categoryOpening: {
    push_hard: "Oggi è una buona giornata per spingere",
    moderate: "Oggi è indicata una sessione moderata",
    light: "Oggi è una giornata più leggera",
    rest: "Oggi è una giornata di recupero completo",
  },
  categoryLabel: { push_hard: "ad alta intensità", moderate: "moderato", light: "leggero", rest: "di riposo" },
  bandPhrase: {
    high: "ben recuperato",
    medium_high: "abbastanza recuperato",
    medium: "recupero nella media",
    low: "segnali di scarso recupero",
  },
  whoopRecovery: (p) => `Il recupero Whoop è ${p}%`,
  ouraReadiness: (s) => `La prontezza Oura è ${s}`,
  healthkitSignals: (b) => `I segnali di Apple Health indicano: ${b}`,
  sleepHoursBit: (h) => `${h}h di sonno`,
  hrvBit: (ms) => `HRV ${ms}ms`,
  restingHrBit: (bpm) => `FC a riposo ${bpm}bpm`,
  strainWhoopBit: (s) => `sforzo del giorno ${s}/21`,
  strainOtherBit: (n) => `${n} sessione/i intensa/e recente/i`,
  stressBit: (min) => `${min}min di stress alto`,
  userRequested: (label) => `Hai chiesto una giornata ${label} oggi, quindi è quello che è previsto.`,
  userRequestedWithNumbers: (label, numbers) => `Hai chiesto una giornata ${label} oggi, quindi è quello che è previsto (dati di oggi per riferimento: ${numbers}).`,
  insufficientData: (label) => `Ancora nessun segnale dal tuo dispositivo o da Apple Health oggi, quindi Soma parte da una base prudente "${label}" finché non c'è abbastanza storico per leggere il tuo recupero con precisione.`,
  lowConfidenceTrailer: "La tua base di recupero è ancora in costruzione, quindi considera questa una stima approssimativa per ora.",
  lightCap: {
    consecutiveDays: "ti sei allenato/a intensamente per abbastanza giorni di fila da dover rallentare",
    injury: "il tuo protocollo infortunio attivo sta limitando l'intensità di oggi",
    volume: "il tuo volume di allenamento recente è già alto per questo periodo",
    sleep: (sleepBit) => `il ${sleepBit} di ieri notte sta limitando l'intensità di oggi`,
    hrv: "la tua HRV di oggi è sotto la tua base abituale",
    stress: "il tuo livello di stress oggi è elevato",
    mood: "hai segnalato di sentirti giù oggi",
  },
  consecutiveDaysRestEscalated: "ti sei allenato/a intensamente per abbastanza giorni di fila da aver bisogno di un vero reset, non solo di una sessione più leggera",
  injuryRest: "il tuo protocollo infortunio attivo richiede riposo completo oggi, indipendentemente da come appaiono i tuoi dati di recupero",
  injuryModerate: "un protocollo infortunio moderato mantiene l'intensità di oggi sotto le tue solite giornate intense",
};

const DE: Phrases = {
  categoryOpening: {
    push_hard: "Heute ist ein guter Tag, um an deine Grenzen zu gehen",
    moderate: "Heute passt eine moderate Einheit",
    light: "Heute ist ein leichterer Tag",
    rest: "Heute ist ein voller Erholungstag",
  },
  categoryLabel: { push_hard: "intensiv", moderate: "moderat", light: "leicht", rest: "Ruhetag" },
  bandPhrase: {
    high: "gut erholt",
    medium_high: "solide erholt",
    medium: "durchschnittlich erholt",
    low: "Anzeichen schlechter Erholung",
  },
  whoopRecovery: (p) => `Die Whoop-Erholung liegt bei ${p}%`,
  ouraReadiness: (s) => `Die Oura-Readiness liegt bei ${s}`,
  healthkitSignals: (b) => `Apple-Health-Daten deuten auf: ${b}`,
  sleepHoursBit: (h) => `${h}Std Schlaf`,
  hrvBit: (ms) => `HRV ${ms}ms`,
  restingHrBit: (bpm) => `Ruhepuls ${bpm}bpm`,
  strainWhoopBit: (s) => `Tagesbelastung ${s}/21`,
  strainOtherBit: (n) => `${n} intensive Einheit(en) kürzlich`,
  stressBit: (min) => `${min}min hoher Stress`,
  userRequested: (label) => `Du hast heute einen ${label} Tag angefragt, genau das ist geplant.`,
  userRequestedWithNumbers: (label, numbers) => `Du hast heute einen ${label} Tag angefragt, genau das ist geplant (heutige Daten zur Referenz: ${numbers}).`,
  insufficientData: (label) => `Noch keine Wearable- oder HealthKit-Signale heute, daher startet Soma vorsichtshalber mit "${label}", bis genug Verlauf für eine genaue Erholungsanalyse vorliegt.`,
  lowConfidenceTrailer: "Deine Erholungs-Baseline wird noch aufgebaut, betrachte das also vorerst als groben Richtwert.",
  lightCap: {
    consecutiveDays: "du hast an genug Tagen in Folge hart trainiert, es ist Zeit, kürzerzutreten",
    injury: "dein aktives Verletzungsprotokoll begrenzt die heutige Intensität",
    volume: "dein jüngstes Trainingsvolumen ist für diesen Zeitraum bereits hoch",
    sleep: (sleepBit) => `der gestrige Schlaf (${sleepBit}) begrenzt die heutige Intensität`,
    hrv: "deine heutige HRV liegt unter deiner üblichen Baseline",
    stress: "deine heutige Stressbelastung ist erhöht",
    mood: "du hast dich heute schlecht gefühlt",
  },
  consecutiveDaysRestEscalated: "du hast an genug Tagen in Folge hart trainiert, dass dein Körper einen echten Reset braucht, nicht nur eine leichtere Einheit",
  injuryRest: "dein aktives Verletzungsprotokoll erfordert heute vollständige Ruhe, unabhängig von deinen Erholungsdaten",
  injuryModerate: "ein moderates Verletzungsprotokoll hält die heutige Intensität unter deinen üblichen intensiven Tagen",
};

const KA: Phrases = {
  categoryOpening: {
    push_hard: "დღეს კარგი დღეა ინტენსიური ვარჯიშისთვის",
    moderate: "დღეს ზომიერი ვარჯიშია საჭირო",
    light: "დღეს მსუბუქი დღეა",
    rest: "დღეს სრული აღდგენის დღეა",
  },
  categoryLabel: { push_hard: "ინტენსიური", moderate: "ზომიერი", light: "მსუბუქი", rest: "დასვენების" },
  bandPhrase: {
    high: "კარგად აღდგენილი",
    medium_high: "საკმაოდ აღდგენილი",
    medium: "საშუალო აღდგენა",
    low: "სუსტი აღდგენის ნიშნები",
  },
  whoopRecovery: (p) => `Whoop-ის აღდგენა არის ${p}%`,
  ouraReadiness: (s) => `Oura-ს მზადყოფნა არის ${s}`,
  healthkitSignals: (b) => `Apple Health-ის მონაცემები აჩვენებს: ${b}`,
  sleepHoursBit: (h) => `${h}სთ ძილი`,
  hrvBit: (ms) => `HRV ${ms}მწმ`,
  restingHrBit: (bpm) => `მოსვენების პულსი ${bpm}დარტ/წთ`,
  strainWhoopBit: (s) => `დღის დატვირთვა ${s}/21`,
  strainOtherBit: (n) => `${n} ბოლოდროინდელი ინტენსიური ვარჯიში`,
  stressBit: (min) => `${min}წთ მაღალი სტრესი`,
  userRequested: (label) => `დღეს მოითხოვე ${label} დღე, ასეც არის დაგეგმილი.`,
  userRequestedWithNumbers: (label, numbers) => `დღეს მოითხოვე ${label} დღე, ასეც არის დაგეგმილი (დღევანდელი მონაცემები საცნობარისთვის: ${numbers}).`,
  insufficientData: (label) => `დღეს ჯერ არ არის მოწყობილობის ან Apple Health-ის სიგნალები, ამიტომ Soma იწყებს უსაფრთხო "${label}" დონით, სანამ საკმარისი ისტორია არ დაგროვდება ზუსტი აღდგენის შესაფასებლად.`,
  lowConfidenceTrailer: "შენი აღდგენის საბაზისო მაჩვენებელი ჯერ კიდევ ყალიბდება, ამიტომ ეს განიხილე როგორც მიახლოებითი შეფასება.",
  lightCap: {
    consecutiveDays: "საკმარისი დღეების განმავლობაში ინტენსიურად ვარჯიშობდი, დროა შემცირდეს ტემპი",
    injury: "აქტიური დაზიანების პროტოკოლი ზღუდავს დღევანდელ ინტენსივობას",
    volume: "ბოლოდროინდელი ვარჯიშის მოცულობა უკვე მაღალია ამ პერიოდისთვის",
    sleep: (sleepBit) => `წუხელინდელი ${sleepBit} ზღუდავს დღევანდელ ინტენსივობას`,
    hrv: "დღევანდელი HRV შენს ჩვეულ დონეზე დაბალია",
    stress: "დღეს სტრესის დონე მომატებულია",
    mood: "დღეს ცუდად გრძნობდი თავს",
  },
  consecutiveDaysRestEscalated: "საკმარისი დღეების განმავლობაში ინტენსიურად ვარჯიშობდი და სხეულს ნამდვილი დასვენება სჭირდება, არა უბრალოდ მსუბუქი ვარჯიში",
  injuryRest: "აქტიური დაზიანების პროტოკოლი დღეს სრულ დასვენებას მოითხოვს, აღდგენის მონაცემების მიუხედავად",
  injuryModerate: "ზომიერი დაზიანების პროტოკოლი დღევანდელ ინტენსივობას შენს ჩვეულ ინტენსიურ დღეებზე დაბლა ინახავს",
};

const HY: Phrases = {
  categoryOpening: {
    push_hard: "Այսօր լավ օր է ինտենսիվ մարզվելու համար",
    moderate: "Այսօր պահանջվում է չափավոր մարզում",
    light: "Այսօր ավելի թեթև օր է",
    rest: "Այսօր լրիվ վերականգնման օր է",
  },
  categoryLabel: { push_hard: "ինտենսիվ", moderate: "չափավոր", light: "թեթև", rest: "հանգստի" },
  bandPhrase: {
    high: "լավ վերականգնված",
    medium_high: "բավականին վերականգնված",
    medium: "միջին վերականգնում",
    low: "թույլ վերականգնման նշաններ",
  },
  whoopRecovery: (p) => `Whoop-ի վերականգնումը ${p}% է`,
  ouraReadiness: (s) => `Oura-ի պատրաստվածությունը ${s} է`,
  healthkitSignals: (b) => `Apple Health-ի տվյալները ցույց են տալիս՝ ${b}`,
  sleepHoursBit: (h) => `${h}ժ քուն`,
  hrvBit: (ms) => `HRV ${ms}մվ`,
  restingHrBit: (bpm) => `հանգստի զարկերակ ${bpm}զ/ր`,
  strainWhoopBit: (s) => `օրվա ծանրաբեռնվածություն ${s}/21`,
  strainOtherBit: (n) => `${n} վերջին ինտենսիվ մարզում(ներ)`,
  stressBit: (min) => `${min}րոպե բարձր սթրես`,
  userRequested: (label) => `Այսօր դու խնդրել ես ${label} օր, ուստի հենց դա է պլանավորված։`,
  userRequestedWithNumbers: (label, numbers) => `Այսօր դու խնդրել ես ${label} օր, ուստի հենց դա է պլանավորված (այսօրվա տվյալները տեղեկատվության համար՝ ${numbers})։`,
  insufficientData: (label) => `Այսօր դեռ սարքից կամ Apple Health-ից տվյալներ չկան, ուստի Soma-ն սկսում է անվտանգ "${label}" մակարդակից, մինչև բավարար պատմություն կուտակվի ճշգրիտ վերականգնում գնահատելու համար։`,
  lowConfidenceTrailer: "Քո վերականգնման բազային մակարդակը դեռ ձևավորվում է, ուստի սա առայժմ համարիր մոտավոր գնահատական։",
  lightCap: {
    consecutiveDays: "դու բավականաչափ օրեր անընդմեջ ինտենսիվ ես մարզվել, ժամանակն է դանդաղեցնել",
    injury: "ակտիվ վնասվածքի արձանագրությունը սահմանափակում է այսօրվա ինտենսիվությունը",
    volume: "քո վերջին մարզումների ծավալն արդեն բարձր է այս ժամանակահատվածի համար",
    sleep: (sleepBit) => `երեկվա ${sleepBit}-ը սահմանափակում է այսօրվա ինտենսիվությունը`,
    hrv: "այսօրվա HRV-ն ցածր է քո սովորական մակարդակից",
    stress: "այսօր սթրեսի մակարդակը բարձրացված է",
    mood: "դու նշել ես, որ այսօր վատ ես զգում",
  },
  consecutiveDaysRestEscalated: "դու բավականաչափ օրեր անընդմեջ ինտենսիվ ես մարզվել, և մարմինդ իսկական հանգիստ է պահանջում, ոչ թե պարզապես ավելի թեթև մարզում",
  injuryRest: "ակտիվ վնասվածքի արձանագրությունը այսօր լրիվ հանգիստ է պահանջում՝ անկախ վերականգնման տվյալներից",
  injuryModerate: "չափավոր վնասվածքի արձանագրությունը այսօրվա ինտենսիվությունը պահում է քո սովորական ինտենսիվ օրերից ցածր",
};

const SR: Phrases = {
  categoryOpening: {
    push_hard: "Danas je dobar dan da se maksimalno potrudiš",
    moderate: "Danas je vreme za umeren trening",
    light: "Danas je lakši dan",
    rest: "Danas je dan potpunog oporavka",
  },
  categoryLabel: { push_hard: "intenzivan", moderate: "umeren", light: "lak", rest: "dan odmora" },
  bandPhrase: {
    high: "dobro oporavljen",
    medium_high: "solidno oporavljen",
    medium: "prosečan oporavak",
    low: "znaci slabog oporavka",
  },
  whoopRecovery: (p) => `Whoop oporavak je ${p}%`,
  ouraReadiness: (s) => `Oura spremnost je ${s}`,
  healthkitSignals: (b) => `Apple Health podaci ukazuju na: ${b}`,
  sleepHoursBit: (h) => `${h}h sna`,
  hrvBit: (ms) => `HRV ${ms}ms`,
  restingHrBit: (bpm) => `puls u mirovanju ${bpm}bpm`,
  strainWhoopBit: (s) => `dnevno opterećenje ${s}/21`,
  strainOtherBit: (n) => `${n} nedavni intenzivni trening(zi)`,
  stressBit: (min) => `${min}min visokog stresa`,
  userRequested: (label) => `Tražio/la si ${label} dan danas, tako da je to isplanirano.`,
  userRequestedWithNumbers: (label, numbers) => `Tražio/la si ${label} dan danas, tako da je to isplanirano (današnji podaci za referencu: ${numbers}).`,
  insufficientData: (label) => `Još nema signala sa uređaja ili Apple Health-a danas, pa Soma kreće od bezbednog "${label}" nivoa dok se ne prikupi dovoljno istorije za precizno očitavanje oporavka.`,
  lowConfidenceTrailer: "Tvoja osnovna linija oporavka se još uvek gradi, pa ovo za sada smatraj grubom procenom.",
  lightCap: {
    consecutiveDays: "treniraš intenzivno dovoljno dana zaredom da je vreme da usporiš",
    injury: "tvoj aktivni protokol povrede ograničava današnji intenzitet",
    volume: "tvoj nedavni obim treninga je već visok za ovaj period",
    sleep: (sleepBit) => `sinoćni san (${sleepBit}) ograničava današnji intenzitet`,
    hrv: "tvoj današnji HRV je ispod tvoje uobičajene osnovne linije",
    stress: "tvoj nivo stresa danas je povišen",
    mood: "prijavio/la si da se danas loše osećaš",
  },
  consecutiveDaysRestEscalated: "treniraš intenzivno dovoljno dana zaredom da je tvom telu potreban pravi reset, ne samo lakši trening",
  injuryRest: "tvoj aktivni protokol povrede zahteva potpuni odmor danas, bez obzira na tvoje podatke o oporavku",
  injuryModerate: "umeren protokol povrede drži današnji intenzitet ispod tvojih uobičajenih intenzivnih dana",
};

const PHRASES: Record<string, Phrases> = { en: EN, ru: RU, es: ES, fr: FR, it: IT, de: DE, ka: KA, hy: HY, sr: SR };

function scoreClause(t: Phrases, input: ReasoningMessageInput): string {
  if (input.source === "whoop" && input.recoveryScore !== null) return t.whoopRecovery(String(input.recoveryScore));
  if (input.source === "oura" && input.readinessScore !== null) return t.ouraReadiness(String(input.readinessScore));
  return t.healthkitSignals(t.bandPhrase[input.band]);
}

/// Trailing list of whichever secondary numbers are actually populated --
/// generalizes across sources rather than assuming any one field exists
/// (degrade gracefully with no wearable connected / a partial read).
function supportingNumbers(t: Phrases, input: ReasoningMessageInput): string | null {
  const bits: string[] = [];
  if (input.sleepHours !== null) bits.push(t.sleepHoursBit(input.sleepHours));
  if (input.hrvMs !== null) bits.push(t.hrvBit(Math.round(input.hrvMs)));
  if (input.restingHr !== null) bits.push(t.restingHrBit(Math.round(input.restingHr)));
  if (input.strainScore !== null) {
    bits.push(input.source === "whoop" ? t.strainWhoopBit(input.strainScore) : t.strainOtherBit(input.strainScore));
  }
  if (input.stressMinutes !== null) bits.push(t.stressBit(Math.round(input.stressMinutes)));
  return bits.length > 0 ? bits.join(", ") : null;
}

/// Every populated number worth citing "for reference" -- the primary
/// recovery/readiness score (when the source actually reports one; skipped
/// for HealthKit, which has no single number, only a derived band) plus
/// whichever supportingNumbers exist. Used only by the user-requested-
/// override path, which isn't explaining a data-driven decision but still
/// wants to show the user their numbers alongside their own choice.
function referenceNumbers(t: Phrases, input: ReasoningMessageInput): string | null {
  const bits: string[] = [];
  if (input.source === "whoop" && input.recoveryScore !== null) bits.push(t.whoopRecovery(String(input.recoveryScore)));
  if (input.source === "oura" && input.readinessScore !== null) bits.push(t.ouraReadiness(String(input.readinessScore)));
  const supporting = supportingNumbers(t, input);
  if (supporting) bits.push(supporting);
  return bits.length > 0 ? bits.join(", ") : null;
}

/// Same left-to-right order as index.ts's light-tier OR-chain
/// (consecutiveDaysCapApplied || injuryProtocolCapApplied ||
/// volumeCapApplied || sleepCapApplied || hrvCapApplied || stressCapApplied
/// || moodCapApplied) -- picks ONE explanation to name even when several
/// caps are simultaneously true, for a readable sentence rather than a
/// laundry list.
function lightCapExplanation(t: Phrases, input: ReasoningMessageInput): string | null {
  if (input.caps.consecutiveDays) return t.lightCap.consecutiveDays;
  if (input.caps.injury) return t.lightCap.injury;
  if (input.caps.volume) return t.lightCap.volume;
  if (input.caps.sleep) return t.lightCap.sleep(input.sleepHours !== null ? t.sleepHoursBit(input.sleepHours) : "short sleep");
  if (input.caps.hrv) return t.lightCap.hrv;
  if (input.caps.stress) return t.lightCap.stress;
  if (input.caps.mood) return t.lightCap.mood;
  return null;
}

/// Word-boundary truncation to `max` chars -- never cuts mid-word (the
/// original bug). Logs (console.warn, this function's equivalent of an
/// analytics event -- there's no analytics pipeline reachable from this
/// Deno function) whenever it actually has to cut something.
function capSummary(text: string, max: number): string {
  if (text.length <= max) return text;
  const truncated = text.slice(0, max);
  const lastSpace = truncated.lastIndexOf(" ");
  const cut = lastSpace > max * 0.5 ? truncated.slice(0, lastSpace) : truncated;
  console.warn(`[copy_overflow] reasoningMessage summary truncated from ${text.length} to ${cut.length + 1} chars`);
  return `${cut}…`;
}

/// The full reasoning sentence(s) for daily_recommendation -- `summary`
/// (capped, always fits the card) and `detail` (fuller, shown in the "Why
/// this?" disclosure). The CATEGORY decision itself is never recomputed
/// here; `input.category` is trusted as-is and this function only ever
/// explains it.
export function buildReasoningMessage(input: ReasoningMessageInput): ReasoningMessage {
  const t = PHRASES[input.language] ?? EN;

  // The user's own request wins outright, same as it does for `category`
  // itself -- still splices in today's data as context, never as the
  // reason (that would misattribute the user's own choice to the wearable).
  if (input.userRequestedCategory !== null) {
    const numbers = referenceNumbers(t, input);
    const full = numbers ? t.userRequestedWithNumbers(t.categoryLabel[input.category], numbers) : t.userRequested(t.categoryLabel[input.category]);
    return { summary: capSummary(full, 90), detail: full };
  }

  if (input.insufficientData) {
    const full = t.insufficientData(t.categoryLabel[input.category]);
    return { summary: capSummary(full, 90), detail: full };
  }

  const opening = t.categoryOpening[input.category];
  const score = scoreClause(t, input);
  const numbers = supportingNumbers(t, input);
  const dataClause = numbers ? `${score}, ${numbers}` : score;

  let whyClause: string | null = null;
  if (input.caps.consecutiveDaysRestEscalated) {
    whyClause = t.consecutiveDaysRestEscalated;
  } else if (input.caps.injuryRest) {
    whyClause = t.injuryRest;
  } else {
    const firedLightCap = lightCapExplanation(t, input);
    if (firedLightCap) {
      whyClause = firedLightCap;
    } else if (input.caps.injuryModerate) {
      whyClause = t.injuryModerate;
    }
  }

  const base = whyClause ? `${opening} -- ${whyClause} (${dataClause}).` : `${opening} -- ${dataClause}.`;

  // Only the HealthKit path can ever be low-confidence (a provisional
  // baseline built from as little as 2 days of history) -- flagged so the
  // user knows to treat today's read as a rough one, not silently trusted
  // the same as a firm baseline. Summary is capped from `opening --
  // dataClause` alone (no whyClause, no confidence trailer) -- both still
  // live in `detail`, surfaced via the "Why this?" disclosure instead of
  // fighting the card's line limit.
  const shortBase = `${opening} -- ${dataClause}.`;
  const detail = input.dataConfidence === "low" ? `${base} ${t.lowConfidenceTrailer}` : base;
  return { summary: capSummary(shortBase, 90), detail };
}
