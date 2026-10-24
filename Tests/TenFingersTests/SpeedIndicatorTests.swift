import Testing
@testable import TenFingers

@Test func speedIsNeutralWithoutTarget() {
    #expect(SpeedIndicator.state(cpm: 200, target: nil, typedChars: 50, activeSeconds: 20) == .neutral)
}

@Test func speedIsNeutralWhileTooLittleData() {
    #expect(SpeedIndicator.state(cpm: 30, target: 90, typedChars: 9, activeSeconds: 20) == .neutral)
    #expect(SpeedIndicator.state(cpm: 30, target: 90, typedChars: 50, activeSeconds: 2.9) == .neutral)
}

@Test func speedAheadAndBehindTarget() {
    #expect(SpeedIndicator.state(cpm: 120, target: 90, typedChars: 20, activeSeconds: 10) == .ahead)
    #expect(SpeedIndicator.state(cpm: 60, target: 90, typedChars: 20, activeSeconds: 10) == .behind)
}

@Test func speedExactlyOnTargetIsAhead() {
    #expect(SpeedIndicator.state(cpm: 90, target: 90, typedChars: 10, activeSeconds: 3) == .ahead)
}

@Test func speedStateHasNonColourCue() {
    #expect(SpeedIndicator.symbolName(for: .ahead) == "arrow.up")
    #expect(SpeedIndicator.symbolName(for: .behind) == "arrow.down")
    #expect(SpeedIndicator.symbolName(for: .neutral) == nil)
}

@Test func speedAccessibilityLabelMentionsTarget() {
    let unit = SpeedUnit.cpm
    let neutral = SpeedIndicator.accessibilityLabel(cpm: 100, target: 90, state: .neutral, unit: unit)
    let ahead = SpeedIndicator.accessibilityLabel(cpm: 100, target: 90, state: .ahead, unit: unit)
    let behind = SpeedIndicator.accessibilityLabel(cpm: 60, target: 90, state: .behind, unit: unit)
    #expect(ahead.hasPrefix(neutral) && ahead != neutral)
    #expect(behind.hasPrefix(SpeedIndicator.accessibilityLabel(cpm: 60, target: 90, state: .neutral, unit: unit)))
    #expect(ahead != behind)
    #expect(SpeedIndicator.accessibilityLabel(cpm: 60, target: nil, state: .neutral, unit: unit)
            == SpeedIndicator.accessibilityLabel(cpm: 60, target: nil, state: .behind, unit: unit))
}

@Test func speedTextIsDashWhileMeasuring() {
    let dash = SpeedIndicator.speedText(cpm: 200, typedChars: 9, activeSeconds: 20, unit: .cpm)
    #expect(dash.hasPrefix("—"))
    #expect(!dash.contains("200"))
    #expect(SpeedIndicator.speedText(cpm: 200, typedChars: 50, activeSeconds: 2.9, unit: .cpm) == dash)
    #expect(SpeedIndicator.speedText(cpm: 200, typedChars: 0, activeSeconds: 0, unit: .cpm) == dash)
    #expect(SpeedIndicator.speedText(cpm: 200, typedChars: 9, activeSeconds: 20, unit: .wpm) == "— WPM")
}

@Test func speedTextShowsNumberOnceEnoughData() {
    #expect(SpeedIndicator.speedText(cpm: 200, typedChars: 10, activeSeconds: 3, unit: .cpm) == SpeedUnit.cpm.format(200))
    #expect(SpeedIndicator.speedText(cpm: 200, typedChars: 10, activeSeconds: 3, unit: .wpm) == "40 WPM")
    #expect(SpeedIndicator.isMeasuring(typedChars: 9, activeSeconds: 3))
    #expect(!SpeedIndicator.isMeasuring(typedChars: 10, activeSeconds: 3))
}

@Test func accessibilityLabelWhileMeasuringHidesNumber() {
    let label = SpeedIndicator.accessibilityLabel(cpm: 200, target: 90, state: .neutral, unit: .cpm, measuring: true)
    #expect(!label.contains("200"))
    #expect(label != SpeedIndicator.accessibilityLabel(cpm: 200, target: 90, state: .neutral, unit: .cpm))
}
