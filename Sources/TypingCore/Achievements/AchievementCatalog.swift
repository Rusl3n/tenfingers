/// Все ачивки приложения (§12, §21; фаза 5 — §7.4 спецификации фазы 5, новые в конце своей категории).
/// Порядок — порядок показа на экране.
/// Id стабильны: по ним хранятся полученные ачивки, переименовывать нельзя.
public enum AchievementCatalog {
    public static let all: [Achievement] =
        streak + speed + accuracy + course + milestone + volume + special + letters + fun + rhythm

    private static let streak: [Achievement] = [
        Achievement(id: "streak.3", category: .streak, icon: "flame", condition: .streak(days: 3)),
        Achievement(id: "streak.7", category: .streak, icon: "flame.fill", condition: .streak(days: 7)),
        Achievement(id: "streak.14", category: .streak, icon: "calendar", condition: .streak(days: 14)),
        Achievement(id: "streak.30", category: .streak, icon: "calendar.badge.checkmark", condition: .streak(days: 30)),
        Achievement(id: "streak.50", category: .streak, icon: "star.circle.fill", condition: .streak(days: 50)),
        Achievement(id: "streak.100", category: .streak, icon: "medal.fill", condition: .streak(days: 100)),
        Achievement(id: "streak.200", category: .streak, icon: "rosette", condition: .streak(days: 200)),
        Achievement(id: "streak.365", category: .streak, icon: "crown.fill", condition: .streak(days: 365)),
        Achievement(id: "spark.7", category: .streak, icon: "sparkle", condition: .sparkStreak(days: 7)),
        Achievement(id: "spark.30", category: .streak, icon: "sparkles", condition: .sparkStreak(days: 30)),
        Achievement(id: "spark.100", category: .streak, icon: "wand.and.stars", condition: .sparkStreak(days: 100)),
        Achievement(id: "spark.365", category: .streak, icon: "sparkles.rectangle.stack",
                    condition: .sparkStreak(days: 365)),
        Achievement(id: "streak.iron_will", category: .streak, icon: "shield.lefthalf.filled",
                    condition: .fullStreakNoFreeze(days: 30)),
        Achievement(id: "streak.fire_month", category: .streak, icon: "flame.circle.fill", condition: .fullFireMonth),
        Achievement(id: "streak.insurance", category: .streak, icon: "umbrella.fill", condition: .freezeSavedStreak),
        Achievement(id: "streak.repair", category: .streak, icon: "bandage.fill", repeatable: true,
                    condition: .streakRepair),
    ]

    private static let speedSteps: [(cpm: Int, icon: String)] = [
        (100, "hare"),
        (150, "gauge.with.dots.needle.33percent"),
        (200, "gauge.with.dots.needle.67percent"),
        (250, "wifi"),
        (300, "pianokeys"),
    ]

    private static let speed: [Achievement] = Language.allCases.flatMap { language in
        speedSteps.map { step in
            Achievement(id: "speed.\(language.rawValue).\(step.cpm)", category: .speed, icon: step.icon,
                        condition: .speed(language, cpm: step.cpm))
        }
    } + [
        Achievement(id: "speed.growth.150", category: .speed, icon: "chart.line.uptrend.xyaxis",
                    condition: .speedGrowth(factor: 1.5, minExercises: 5)),
        Achievement(id: "speed.growth.200", category: .speed, icon: "arrow.up.right.circle.fill",
                    condition: .speedGrowth(factor: 2, minExercises: 5)),
        // 6d: повторяемая, получение — каждое обновление рекорда языка (в `AchievementOccurrences.swift`).
        Achievement(id: "speed.record", category: .speed, icon: "gauge.with.dots.needle.100percent",
                    repeatable: true, condition: .speedRecord),
    ]

    private static let accuracy: [Achievement] = [
        Achievement(id: "accuracy.sniper", category: .accuracy, icon: "scope", condition: .perfectAccuracy),
        Achievement(id: "accuracy.sniper.100", category: .accuracy, icon: "target", condition: .perfectCount(100)),
        Achievement(id: "accuracy.surgeon", category: .accuracy, icon: "stethoscope",
                    condition: .accuracyRun(count: 10, minimum: 0.98)),
        Achievement(id: "accuracy.surgeon.50", category: .accuracy, icon: "cross.circle.fill",
                    condition: .accuracyRun(count: 50, minimum: 0.98)),
        Achievement(id: "accuracy.clean_day", category: .accuracy, icon: "sparkles",
                    condition: .cleanDay(exercises: 5, minimum: 0.97)),
        Achievement(id: "accuracy.clean_day.100", category: .accuracy, icon: "sparkle.magnifyingglass",
                    condition: .cleanDays(count: 100, exercises: 5, minimum: 0.97)),
        Achievement(id: "accuracy.all_fingers", category: .accuracy, icon: "hand.raised.fill",
                    condition: .allFingersAccuracy(minimum: 0.97, presses: 30, days: 7)),
        // 6d: занятие «Точность пальца» по каждому из восьми пальцев (разовая).
        Achievement(id: "fingers.all_eight", category: .accuracy, icon: "hands.clap.fill",
                    condition: .allFingersDrilled),
    ]

    private static let course: [Achievement] = [
        Achievement(id: "course.first_lesson", category: .course, icon: "graduationcap", condition: .firstLesson),
        Achievement(id: "course.first_stage", category: .course, icon: "flag.checkered", condition: .firstStage),
        Achievement(id: "course.ru", category: .course, icon: "checkmark.seal.fill", condition: .courseCompleted(.ru)),
        Achievement(id: "course.en", category: .course, icon: "checkmark.seal", condition: .courseCompleted(.en)),
        Achievement(id: "course.polyglot", category: .course, icon: "globe", condition: .polyglot),
        Achievement(id: "course.stars.ru", category: .course, icon: "star.fill", condition: .allLessonsExcellent(.ru)),
        Achievement(id: "course.stars.en", category: .course, icon: "star.square.fill", condition: .allLessonsExcellent(.en)),
        // 6d: повторяемые, ключ получения — id этапа или урока.
        Achievement(id: "course.stage", category: .course, icon: "flag.2.crossed.fill", repeatable: true,
                    condition: .stagePassed),
        Achievement(id: "course.five_stars", category: .course, icon: "trophy.fill", repeatable: true,
                    condition: .lessonStars(5)),
        Achievement(id: "course.speed_tier", category: .course, icon: "stairs", repeatable: true,
                    condition: .tierPassed),
        // 6d, идея пользователя (решение 18): ключ получения — `<lessonId>#<stepIndex>`.
        Achievement(id: "course.first_try", category: .course, icon: "hand.thumbsup.fill", repeatable: true,
                    condition: .firstTry),
    ]

    /// Вехи курса (6d, §8.2): разовые.
    private static let milestone: [Achievement] = [
        Achievement(id: "milestone.ru.digits", category: .milestone, icon: "textformat.123",
                    condition: .keysUnlocked(.ru, .digits)),
        Achievement(id: "milestone.en.digits", category: .milestone, icon: "123.rectangle",
                    condition: .keysUnlocked(.en, .digits)),
        Achievement(id: "milestone.ru.symbols", category: .milestone, icon: "at",
                    condition: .keysUnlocked(.ru, .symbols)),
        Achievement(id: "milestone.en.symbols", category: .milestone, icon: "number.square",
                    condition: .keysUnlocked(.en, .symbols)),
        Achievement(id: "milestone.first_clean_text", category: .milestone, icon: "text.badge.checkmark",
                    condition: .cleanText(minChars: 200, hard: false)),
        Achievement(id: "milestone.first_hard_text", category: .milestone, icon: "text.badge.star",
                    condition: .cleanText(minChars: 200, hard: true)),
        Achievement(id: "milestone.first_long_text", category: .milestone, icon: "doc.plaintext",
                    condition: .cleanText(minChars: 600, hard: false)),
        Achievement(id: "milestone.first_blind_check", category: .milestone, icon: "eye.slash.circle",
                    condition: .blindStageCheck),
        Achievement(id: "milestone.first_plan", category: .milestone, icon: "checklist.checked",
                    condition: .firstPlanDay),
        Achievement(id: "milestone.first_tier", category: .milestone, icon: "arrow.up.forward.circle",
                    condition: .firstTier),
        // 6e, уровни опыта (§10.3): разовые; уровень 50 остаётся званием без ачивки.
        Achievement(id: "level.10", category: .milestone, icon: "star.circle", condition: .level(10)),
        Achievement(id: "level.30", category: .milestone, icon: "star.square", condition: .level(30)),
        Achievement(id: "level.45", category: .milestone, icon: "crown", condition: .level(45)),
    ]

    private static let volume: [Achievement] = [
        Achievement(id: "volume.chars.10k", category: .volume, icon: "keyboard", condition: .volumeChars(10_000)),
        Achievement(id: "volume.chars.100k", category: .volume, icon: "doc.text", condition: .volumeChars(100_000)),
        Achievement(id: "volume.chars.500k", category: .volume, icon: "doc.on.doc", condition: .volumeChars(500_000)),
        Achievement(id: "volume.chars.1m", category: .volume, icon: "books.vertical.fill",
                    condition: .volumeChars(1_000_000)),
        Achievement(id: "volume.hours.1", category: .volume, icon: "clock", condition: .volumeHours(1)),
        Achievement(id: "volume.hours.10", category: .volume, icon: "clock.fill", condition: .volumeHours(10)),
        Achievement(id: "volume.hours.50", category: .volume, icon: "hourglass", condition: .volumeHours(50)),
        Achievement(id: "volume.hours.100", category: .volume, icon: "hourglass.bottomhalf.filled",
                    condition: .volumeHours(100)),
        Achievement(id: "volume.exercises.100", category: .volume, icon: "checklist",
                    condition: .exercisesCompleted(100)),
        Achievement(id: "volume.exercises.500", category: .volume, icon: "list.bullet.clipboard",
                    condition: .exercisesCompleted(500)),
        Achievement(id: "volume.exercises.1000", category: .volume, icon: "list.star",
                    condition: .exercisesCompleted(1000)),
        Achievement(id: "volume.exercises.2500", category: .volume, icon: "gearshape.2",
                    condition: .exercisesCompleted(2500)),
        Achievement(id: "volume.exercises.4000", category: .volume, icon: "building.2",
                    condition: .exercisesCompleted(4000)),
        Achievement(id: "volume.books.5", category: .volume, icon: "book", condition: .booksFinished(5)),
        Achievement(id: "volume.books.25", category: .volume, icon: "books.vertical", condition: .booksFinished(25)),
    ] + distance

    /// Дистанция (6d, §8.5): разовые лестницы после прежних ачивок объёма; первая ступень — на середину обучения.
    private static let distanceSteps: [(id: String, icon: String, kind: DistanceKind, count: Int)] = [
        ("space.75k", "space", .spaces, 75_000),
        ("space.100k", "arrow.left.and.right.square", .spaces, 100_000),
        ("space.150k", "moon.stars", .spaces, 150_000),
        ("pinky.45k", "hand.point.up.fill", .pinkies, 45_000),
        ("pinky.60k", "dumbbell.fill", .pinkies, 60_000),
        ("pinky.85k", "medal", .pinkies, 85_000),
        ("training.100", "figure.walk", .trainings, 100),
        ("training.300", "figure.strengthtraining.functional", .trainings, 300),
        ("training.500", "figure.highintensity.intervaltraining", .trainings, 500),
        ("lessons.100", "graduationcap.fill", .lessons, 100),
        ("lessons.200", "studentdesk", .lessons, 200),
        ("lessons.300", "building.columns", .lessons, 300),
        ("texts.100", "book.closed", .texts, 100),
        ("texts.200", "newspaper.fill", .texts, 200),
        ("texts.300", "text.book.closed.fill", .texts, 300),
        ("plans.100", "list.clipboard", .plans, 100),
        ("plans.300", "calendar.day.timeline.left", .plans, 300),
    ]

    private static let distance: [Achievement] = distanceSteps.map { step in
        Achievement(id: "distance." + step.id, category: .volume, icon: step.icon,
                    condition: .distance(step.kind, step.count))
    }

    private static let special: [Achievement] = [
        Achievement(id: "special.night_owl", category: .special, icon: "moon.stars.fill", secret: true, repeatable: true,
                    condition: .finishedBetween(startHour: 0, endHour: 4)),
        Achievement(id: "special.early_bird", category: .special, icon: "sunrise.fill", secret: true, repeatable: true,
                    condition: .finishedBetween(startHour: 6, endHour: 8)),
        Achievement(id: "special.no_peeking", category: .special, icon: "eye.slash", condition: .noKeyboard),
        Achievement(id: "special.steel_pinkies", category: .special, icon: "hand.raised.fingers.spread.fill",
                    condition: .steelPinkies(presses: 30)),
        Achievement(id: "special.weak_spot", category: .special, icon: "bandage",
                    condition: .weakSpotsClean(count: 1, minimum: 0.98)),
        Achievement(id: "special.weak_spot.10", category: .special, icon: "cross.case.fill",
                    condition: .weakSpotsClean(count: 10, minimum: 0.98)),
        Achievement(id: "special.own_words", category: .special, icon: "text.quote", condition: .ownText),
        // 6d: время суток и заходы (повторяемые; `habit.visits.5` — разовая секретная).
        Achievement(id: "time.morning", category: .special, icon: "sunrise", repeatable: true,
                    condition: .dayPart(startHour: 5, endHour: 12)),
        Achievement(id: "time.afternoon", category: .special, icon: "sun.max", repeatable: true,
                    condition: .dayPart(startHour: 12, endHour: 18)),
        Achievement(id: "time.evening", category: .special, icon: "sunset", repeatable: true,
                    condition: .dayPart(startHour: 18, endHour: 24)),
        Achievement(id: "habit.visits.2", category: .special, icon: "2.circle.fill", repeatable: true,
                    condition: .visits(2)),
        Achievement(id: "habit.visits.3", category: .special, icon: "3.circle.fill", repeatable: true,
                    condition: .visits(3)),
        Achievement(id: "habit.visits.5", category: .special, icon: "5.circle.fill", secret: true,
                    condition: .visits(5)),
        Achievement(id: "plan.week", category: .special, icon: "calendar.badge.clock", repeatable: true,
                    condition: .planWeek(days: 7)),
        // 6d, идеи пользователя (решение 18): ключ получения — день, значение — минуты за день.
        Achievement(id: "habit.goal.x2", category: .special, icon: "2.square.fill", repeatable: true,
                    condition: .goalMultiple(2)),
        Achievement(id: "habit.goal.x3", category: .special, icon: "3.square.fill", repeatable: true,
                    condition: .goalMultiple(3)),
        // 6e, испытания (§10.2): ключ получения — неделя или месяц. Значки плана (`flag.checkered`,
        // `calendar.badge.checkmark`) заняты ачивками «Первый этап» и «30 дней».
        Achievement(id: "challenge.week", category: .special, icon: "checkmark.circle.fill", repeatable: true,
                    condition: .challengeWeek),
        Achievement(id: "challenge.month", category: .special, icon: "calendar.circle.fill", repeatable: true,
                    condition: .challengeMonth),
    ]

    /// `letters` — слово или команда, из которых набрано условие; `display` — как показывать буквы на экране, если
    /// не в порядке слова (у ругательств — по алфавиту, чтобы условие не выдавало слово). Все «взрослые» секретные.
    private static func unlock(_ id: String, _ language: Language, _ letters: String, display: String? = nil,
                                icon: String, adult: Bool = false) -> Achievement {
        Achievement(id: "letters.\(language.rawValue).\(id)", category: .letters, icon: icon, adult: adult,
                    secret: adult, condition: .lettersUnlocked(language, Set(letters)),
                    lettersDisplay: display ?? letters)
    }

    private static let letters: [Achievement] = [
        unlock("hello", .ru, "привет", icon: "hand.wave"),
        unlock("pizza", .ru, "пицца", icon: "fork.knife"),
        unlock("borscht", .ru, "борщ", icon: "carrot.fill"),
        unlock("b_word", .ru, "бля", display: "бля", icon: "exclamationmark.bubble", adult: true),
        unlock("three_letters", .ru, "хуй", display: "йух", icon: "pencil.and.scribble", adult: true),
        unlock("deadline", .ru, "жопа", icon: "clock.badge.exclamationmark", adult: true),
        unlock("yo", .ru, "ё", icon: "character.textbox"),
        unlock("hard_sign", .ru, "ъ", icon: "scroll"),
        Achievement(id: "letters.ru.alphabet", category: .letters, icon: "character.book.closed",
                    condition: .wholeAlphabet(.ru)),
        Achievement(id: "letters.en.alphabet", category: .letters, icon: "textformat.abc",
                    condition: .wholeAlphabet(.en)),
        unlock("fluent_f", .en, "fuck", display: "cfku", icon: "f.cursive", adult: true),
        unlock("shit_happens", .en, "shit", display: "hist", icon: "tornado", adult: true),
        unlock("wtf", .en, "wtf", icon: "exclamationmark.questionmark", adult: true),
        unlock("pizza", .en, "pizza", icon: "takeoutbag.and.cup.and.straw"),
        unlock("hello_world", .en, "helloworld", icon: "chevron.left.forwardslash.chevron.right"),
        unlock("sudo", .en, "sudo", icon: "terminal"),
        unlock("vim", .en, ":q!", icon: "door.left.hand.open"),
    ]

    private static let fun: [Achievement] = [
        Achievement(id: "fun.ghbdtn", category: .fun, icon: "arrow.left.arrow.right", secret: true,
                    condition: .counter(name: "wrongLayoutStarts", threshold: 10)),
        Achievement(id: "fun.sausage_fingers", category: .fun, icon: "hand.thumbsdown", secret: true,
                    condition: .errorStreak(10)),
        Achievement(id: "fun.ctrl_z", category: .fun, icon: "arrow.uturn.backward", secret: true,
                    condition: .errorsInExercise(50)),
        Achievement(id: "fun.oy_vsyo", category: .fun, icon: "capslock.fill", secret: true,
                    condition: .counter(name: "capsLockPresses", threshold: 1)),
        Achievement(id: "fun.perfectionist", category: .fun, icon: "arrow.counterclockwise", secret: true,
                    condition: .lessonReplays(10)),
        Achievement(id: "fun.not_today", category: .fun, icon: "bed.double.fill", secret: true,
                    condition: .abandonsInDay(3)),
        Achievement(id: "fun.no_coffee", category: .fun, icon: "cup.and.saucer", secret: true, repeatable: true,
                    condition: .finishedBetween(startHour: 5, endHour: 6)),
        Achievement(id: "fun.new_year", category: .fun, icon: "party.popper", secret: true,
                    condition: .dayOfYear(month: 1, day: 1)),
        Achievement(id: "fun.friday13", category: .fun, icon: "calendar.badge.exclamationmark", secret: true,
                    condition: .fridayThe13th),
        Achievement(id: "fun.bilingual", category: .fun, icon: "character.bubble", secret: true,
                    condition: .bilingualDay),
        Achievement(id: "fun.marathon", category: .fun, icon: "figure.run", secret: true,
                    condition: .marathonDay(minutes: 60)),
        Achievement(id: "fun.comeback", category: .fun, icon: "figure.wave", secret: true,
                    condition: .comeback(gapDays: 7)),
        Achievement(id: "fun.pi", category: .fun, icon: "function", secret: true, condition: .exactSpeed(cpm: 314)),
        Achievement(id: "fun.answer42", category: .fun, icon: "number.circle", secret: true,
                    condition: .exactSeconds(42)),
        Achievement(id: "fun.yo_master", category: .fun, icon: "textformat", secret: true, condition: .yoPresses(100)),
        Achievement(id: "fun.learning_from_mistakes", category: .fun, icon: "xmark.circle", secret: true,
                    condition: .totalErrors(1000)),
        Achievement(id: "fun.cinderella", category: .fun, icon: "wand.and.stars", secret: true,
                    condition: .finishedAtMinute(hour: 0, minute: 0)),
        Achievement(id: "fun.friday_night", category: .fun, icon: "music.note", secret: true, repeatable: true,
                    condition: .fridayEvening(fromHour: 21)),
        Achievement(id: "fun.weekend_warrior", category: .fun, icon: "figure.strengthtraining.traditional",
                    secret: true, condition: .weekendStreak(4)),
        Achievement(id: "fun.almost", category: .fun, icon: "smallcircle.filled.circle", secret: true,
                    condition: .almostPerfect(minChars: 300, minimum: 0.999)),
        // 6d: «Вайбкодер» — шуточные разовые по буквам слов; слова условие не раскрывает (секретные).
        Achievement(id: "fun.vibe_coder.ru", category: .fun, icon: "moon.zzz", secret: true,
                    condition: .lettersUnlocked(.ru, Set("сделайисправьпродолжайдавай")),
                    lettersDisplay: "сделай исправь продолжай давай"),
        Achievement(id: "fun.vibe_coder.en", category: .fun, icon: "cpu", secret: true,
                    condition: .lettersUnlocked(.en, Set("fixcheckmakerefactor")),
                    lettersDisplay: "fix check make refactor"),
        // 6d, идея пользователя (решение 18): ключ получения — день.
        Achievement(id: "fun.slow_steady", category: .fun, icon: "tortoise.fill", secret: true, repeatable: true,
                    condition: .slowAndSteady),
    ]

    /// Игра «Ритм» (решение 12): разовые, не секретные; дата — результат, на котором условие выполнилось.
    private static let rhythm: [Achievement] = [
        Achievement(id: "rhythm.first", category: .rhythm, icon: "music.note", condition: .rhythmCleared),
        Achievement(id: "rhythm.fullcombo", category: .rhythm, icon: "flame.fill", condition: .rhythmFullCombo),
        Achievement(id: "rhythm.perfect", category: .rhythm, icon: "star.circle.fill", condition: .rhythmAllPerfect),
        Achievement(id: "rhythm.combo100", category: .rhythm, icon: "bolt.fill", condition: .rhythmCombo(100)),
        Achievement(id: "rhythm.s.expert", category: .rhythm, icon: "crown.fill",
                    condition: .rhythmGrade(.s, level: .expert)),
        Achievement(id: "rhythm.allmodes", category: .rhythm, icon: "square.grid.2x2.fill",
                    condition: .rhythmAllModes),
        Achievement(id: "rhythm.hour", category: .rhythm, icon: "clock.fill", condition: .rhythmSeconds(3600)),
    ]
}
