import Foundation

struct EnergyDetector: Sendable {
    private var backgroundRMS: Float = 0.004
    private var consecutiveHits = 0

    mutating func isCandidate(_ samples: [Int16]) -> Bool {
        guard !samples.isEmpty else { return false }

        let meanSquare = samples.reduce(0.0) { partial, sample in
            let normalized = Double(sample) / 32_768.0
            return partial + normalized * normalized
        } / Double(samples.count)
        let rms = Float(meanSquare.squareRoot())
        let hit = rms > max(0.012, backgroundRMS * 2.5)
        consecutiveHits = hit ? consecutiveHits + 1 : 0
        let adaptation: Float = consecutiveHits > 160 ? 0.05 : (hit ? 0.001 : 0.02)
        backgroundRMS += (rms - backgroundRMS) * adaptation
        return hit && consecutiveHits <= 160
    }
}
