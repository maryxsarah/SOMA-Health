// Deterministic rationale text for a MealScore (scoreMeal.ts) -- built
// FROM the same modifier keys the score itself is derived from, so the
// sentence can never contradict the number it's explaining (the old
// version generated score and rationale via two independent paths inside
// one LLM call, with nothing tying them together). Same 9-language
// coverage as reasoningMessage.ts, just a much smaller phrase surface.

import type { MealScore, ModifierKey } from "./scoreMeal.ts";

interface Phrases {
  reason: Record<ModifierKey, string>;
  balanced: string;
  /// Used in place of a real label when the meal was logged with only
  /// numbers, no description.
  genericMeal: string;
  /// Joins the meal description with the leading positive/negative clause,
  /// e.g. "%@ -- %@." (description, clause).
  join: (mealDescription: string, clause: string) => string;
}

const EN: Phrases = {
  reason: {
    highProteinDensity: "high protein for its calories",
    solidProteinDensity: "solid protein for its calories",
    lowProteinDensity: "low protein for its calories",
    largeCutShare: "a large share of a day's calorie budget for a cut",
    strongProteinShare: "covers a large share of today's protein target",
    veryHighFatShare: "over half its calories are from fat",
    highFatShare: "a high share of its calories are from fat",
    ultraProcessed: "ultra-processed",
    alcohol: "contains alcohol, which works against training goals",
  },
  balanced: "A reasonably balanced meal for your goal.",
  genericMeal: "this meal",
  join: (desc, clause) => `${desc} -- ${clause}.`,
};

const RU: Phrases = {
  reason: {
    highProteinDensity: "много белка на калорию",
    solidProteinDensity: "неплохо по белку на калорию",
    lowProteinDensity: "мало белка на калорию",
    largeCutShare: "большая доля дневного лимита калорий для сушки",
    strongProteinShare: "покрывает значительную долю дневной нормы белка",
    veryHighFatShare: "больше половины калорий из жира",
    highFatShare: "высокая доля калорий из жира",
    ultraProcessed: "сильно переработанный продукт",
    alcohol: "содержит алкоголь, что мешает тренировочным целям",
  },
  balanced: "В целом сбалансированный приём пищи для твоей цели.",
  genericMeal: "этот приём пищи",
  join: (desc, clause) => `${desc} — ${clause}.`,
};

const ES: Phrases = {
  reason: {
    highProteinDensity: "mucha proteína por caloría",
    solidProteinDensity: "buena proteína por caloría",
    lowProteinDensity: "poca proteína por caloría",
    largeCutShare: "una gran parte del presupuesto calórico diario para un déficit",
    strongProteinShare: "cubre una gran parte de tu objetivo de proteína de hoy",
    veryHighFatShare: "más de la mitad de sus calorías vienen de grasa",
    highFatShare: "una alta proporción de sus calorías viene de grasa",
    ultraProcessed: "ultraprocesado",
    alcohol: "contiene alcohol, lo que va en contra de tus objetivos de entrenamiento",
  },
  balanced: "Una comida razonablemente equilibrada para tu objetivo.",
  genericMeal: "esta comida",
  join: (desc, clause) => `${desc} -- ${clause}.`,
};

const FR: Phrases = {
  reason: {
    highProteinDensity: "riche en protéines pour ses calories",
    solidProteinDensity: "bonne quantité de protéines pour ses calories",
    lowProteinDensity: "faible en protéines pour ses calories",
    largeCutShare: "une grande part du budget calorique du jour pour une sèche",
    strongProteinShare: "couvre une grande part de ton objectif de protéines du jour",
    veryHighFatShare: "plus de la moitié de ses calories viennent des graisses",
    highFatShare: "une forte part de ses calories vient des graisses",
    ultraProcessed: "ultra-transformé",
    alcohol: "contient de l'alcool, ce qui joue contre tes objectifs d'entraînement",
  },
  balanced: "Un repas raisonnablement équilibré pour ton objectif.",
  genericMeal: "ce repas",
  join: (desc, clause) => `${desc} -- ${clause}.`,
};

const IT: Phrases = {
  reason: {
    highProteinDensity: "molte proteine per le sue calorie",
    solidProteinDensity: "buone proteine per le sue calorie",
    lowProteinDensity: "poche proteine per le sue calorie",
    largeCutShare: "una grande parte del budget calorico giornaliero per un deficit",
    strongProteinShare: "copre una grande parte del tuo obiettivo proteico di oggi",
    veryHighFatShare: "oltre metà delle calorie provengono dai grassi",
    highFatShare: "un'alta quota di calorie proviene dai grassi",
    ultraProcessed: "ultra-processato",
    alcohol: "contiene alcol, che va contro i tuoi obiettivi di allenamento",
  },
  balanced: "Un pasto ragionevolmente equilibrato per il tuo obiettivo.",
  genericMeal: "questo pasto",
  join: (desc, clause) => `${desc} -- ${clause}.`,
};

const DE: Phrases = {
  reason: {
    highProteinDensity: "viel Eiweiß pro Kalorie",
    solidProteinDensity: "solides Eiweiß pro Kalorie",
    lowProteinDensity: "wenig Eiweiß pro Kalorie",
    largeCutShare: "ein großer Teil des Tageskalorienbudgets für eine Diätphase",
    strongProteinShare: "deckt einen großen Teil deines heutigen Eiweißziels ab",
    veryHighFatShare: "über die Hälfte der Kalorien stammt aus Fett",
    highFatShare: "ein hoher Kalorienanteil stammt aus Fett",
    ultraProcessed: "stark verarbeitet",
    alcohol: "enthält Alkohol, was deinen Trainingszielen entgegenwirkt",
  },
  balanced: "Eine für dein Ziel einigermaßen ausgewogene Mahlzeit.",
  genericMeal: "diese Mahlzeit",
  join: (desc, clause) => `${desc} -- ${clause}.`,
};

const KA: Phrases = {
  reason: {
    highProteinDensity: "მაღალი ცილის შემცველობა კალორიებთან შედარებით",
    solidProteinDensity: "საკმაოდ კარგი ცილა კალორიებთან შედარებით",
    lowProteinDensity: "დაბალი ცილა კალორიებთან შედარებით",
    largeCutShare: "დღიური კალორიების დიდი წილი შემცირების რეჟიმისთვის",
    strongProteinShare: "ფარავს დღევანდელი ცილის მიზნის დიდ ნაწილს",
    veryHighFatShare: "კალორიების ნახევარზე მეტი ცხიმისგანაა",
    highFatShare: "კალორიების დიდი წილი ცხიმისგანაა",
    ultraProcessed: "მაღალი დამუშავების ხარისხის პროდუქტი",
    alcohol: "შეიცავს ალკოჰოლს, რაც ვარჯიშის მიზნებს ეწინააღმდეგება",
  },
  balanced: "საკმაოდ დაბალანსებული კვება შენი მიზნისთვის.",
  genericMeal: "ეს კვება",
  join: (desc, clause) => `${desc} — ${clause}.`,
};

const HY: Phrases = {
  reason: {
    highProteinDensity: "բարձր սպիտակուց՝ կալորիաներին համեմատած",
    solidProteinDensity: "լավ սպիտակուց՝ կալորիաներին համեմատած",
    lowProteinDensity: "ցածր սպիտակուց՝ կալորիաներին համեմատած",
    largeCutShare: "օրական կալորիաների մեծ մասը՝ քաշի նվազեցման համար",
    strongProteinShare: "ծածկում է օրվա սպիտակուցի նպատակի մեծ մասը",
    veryHighFatShare: "կալորիաների կեսից ավելին ճարպից է",
    highFatShare: "կալորիաների մեծ մասը ճարպից է",
    ultraProcessed: "խիստ վերամշակված",
    alcohol: "պարունակում է ալկոհոլ, ինչը հակասում է մարզման նպատակներին",
  },
  balanced: "Քո նպատակի համար բավականին հավասարակշռված սնունդ։",
  genericMeal: "այս սնունդը",
  join: (desc, clause) => `${desc} — ${clause}։`,
};

const SR: Phrases = {
  reason: {
    highProteinDensity: "puno proteina za svoje kalorije",
    solidProteinDensity: "solidno proteina za svoje kalorije",
    lowProteinDensity: "malo proteina za svoje kalorije",
    largeCutShare: "veliki deo dnevnog budžeta kalorija za mršavljenje",
    strongProteinShare: "pokriva veliki deo dnevnog cilja za proteine",
    veryHighFatShare: "preko polovine kalorija je iz masti",
    highFatShare: "visok udeo kalorija je iz masti",
    ultraProcessed: "ultra-prerađeno",
    alcohol: "sadrži alkohol, što ide protiv tvojih ciljeva treninga",
  },
  balanced: "Razumno uravnotežen obrok za tvoj cilj.",
  genericMeal: "ovaj obrok",
  join: (desc, clause) => `${desc} -- ${clause}.`,
};

const PHRASES: Record<string, Phrases> = { en: EN, ru: RU, es: ES, fr: FR, it: IT, de: DE, ka: KA, hy: HY, sr: SR };

/// One short sentence, built directly from the fired modifiers -- never a
/// second, independently-generated judgment. `mealDescription` is the
/// user's own label, used verbatim (never re-translated) -- null/empty
/// falls back to a localized "this meal".
export function buildRationale(mealScore: MealScore, mealDescription: string | null, language: string): string {
  const t = PHRASES[language] ?? EN;
  if (mealScore.breakdown.length === 0) return t.balanced;

  // Comma-joined rather than "X and Y" -- avoids hand-translating a
  // connector word per language for what's already a readable list.
  const clause = mealScore.breakdown.map((m) => t.reason[m.key]).join(", ");
  const description = mealDescription && mealDescription.trim().length > 0 ? mealDescription : t.genericMeal;
  return t.join(description, clause);
}
