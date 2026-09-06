import SwiftUI

struct WaveSoundBar: View {
    var level: Float
    var color: Color = Color.primary.opacity(0.8)

    private let barCount = 7
    @State private var barParams: [(speed: Double, offset: Double)] = []
    @State private var displayLevel: Double = 0.0

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(spacing: 1.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.0, height: barHeight(for: index, time: time))
                }
            }
            .frame(height: 16, alignment: .center)
        }
        .onAppear {
            setupParams()
        }
        .onChange(of: level) { _, newLevel in
            withAnimation(.interpolatingSpring(stiffness: 180, damping: 18)) {
                displayLevel = Double(max(0, newLevel))
            }
        }
    }

    private func setupParams() {
        var params: [(Double, Double)] = []
        for i in 0..<barCount {
            let normalized = Double(i) / Double(max(1, barCount - 1))
            // Harmonious speeds for adjacent bars so motion flows smoothly like a wave
            let speed = 2.4 + 0.8 * sin(normalized * .pi)
            let offset = normalized * .pi * 1.2
            params.append((speed: speed, offset: offset))
        }
        barParams = params
    }

    private func barHeight(for index: Int, time: Double) -> CGFloat {
        let baseHeight: CGFloat = 2.5
        let maxExtra: CGFloat = 11.0

        guard index < barParams.count else { return baseHeight }
        let param = barParams[index]

        // Smooth wave oscillation between 0 and 1
        let wave = (sin(time * param.speed + param.offset) + 1.0) / 2.0

        // Center envelope: center bars are naturally taller and more reactive
        let normalizedIndex = Double(index) / Double(max(1, barCount - 1))
        let envelope = 0.35 + 0.65 * sin(normalizedIndex * .pi)

        let isListening = displayLevel > 0.015

        if isListening {
            // Smooth combination of audio level and harmonic wave
            let dynamicAmp = min(1.0, (displayLevel * 2.2) + (wave * 0.2))
            return baseHeight + CGFloat(dynamicAmp * envelope) * maxExtra
        } else {
            // Calm, fluid resting breathe when sound is silent
            let idleWave = (sin(time * 2.2 + param.offset) + 1.0) / 2.0
            return baseHeight + CGFloat(idleWave * 0.12) * maxExtra
        }
    }
}
