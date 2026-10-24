import Foundation
import Testing
@testable import TypingCore

@Test func fingerCountsRoundTripThroughData() {
    let counts: [Finger: Int] = [.leftPinky: 12, .thumb: 30, .rightIndex: 0]
    let data = FingerCounts.data(counts)
    #expect(FingerCounts.counts(data) == counts)
    #expect(FingerCounts.raw(data) == ["leftPinky": 12, "thumb": 30, "rightIndex": 0])
    #expect(FingerCounts.counts(FingerCounts.data([:])) == [:])
}

@Test func unknownFingerKeysAreSkipped() {
    let data = FingerCounts.data(raw: ["leftPinky": 3, "sixthFinger": 7])
    #expect(FingerCounts.counts(data) == [.leftPinky: 3])
    // Сырые значения (для архива) сохраняются как есть.
    #expect(FingerCounts.raw(data) == ["leftPinky": 3, "sixthFinger": 7])
}

@Test func garbageAndNilAreNil() {
    #expect(FingerCounts.counts(nil) == nil)
    #expect(FingerCounts.raw(nil) == nil)
    #expect(FingerCounts.counts(Data("мусор".utf8)) == nil)
    #expect(FingerCounts.raw(Data("[1, 2]".utf8)) == nil)
}

@Test func rawDataIsDeterministicWithSortedKeys() {
    let raw = ["rightPinky": 1, "leftPinky": 2, "thumb": 3, "leftIndex": 4]
    let first = FingerCounts.data(raw: raw)
    for _ in 0..<20 { #expect(FingerCounts.data(raw: raw) == first) }
    #expect(String(decoding: first, as: UTF8.self) == #"{"leftIndex":4,"leftPinky":2,"rightPinky":1,"thumb":3}"#)
    #expect(FingerCounts.data([.thumb: 3, .leftPinky: 2]) == FingerCounts.data(raw: ["leftPinky": 2, "thumb": 3]))
}
