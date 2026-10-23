public enum LessonScoring {
    public static let passAccuracy = 0.96
    public static let threeStarFactor = 1.3

    /// 0 — урок не засчитан; 1–3 — звёзды по скорости относительно цели.
    public static func stars(cpm: Double, accuracy: Double, targetCpm: Int) -> Int {
        guard accuracy >= passAccuracy else { return 0 }
        let target = Double(targetCpm)
        if cpm < target { return 1 }
        if cpm < target * threeStarFactor { return 2 }
        return 3
    }
}
