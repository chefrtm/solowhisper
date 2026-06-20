import SwiftUI

enum RecordingPillState {
    case recording
    case transcribing
}

struct RecordingPillView: View {
    let state: RecordingPillState
    let audioLevel: Float

    var body: some View {
        HStack(spacing: 0) {
            switch state {
            case .recording:
                SoundBarsView(level: audioLevel)
                    .frame(width: 40, height: 16)
            case .transcribing:
                SpinnerView()
                    .frame(width: 16, height: 16)
            }
        }
        .frame(width: 64, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.7))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
    }
}

// MARK: - Sound Bars

struct SoundBarsView: View {
    let level: Float

    private let barCount = 5
    private let barMultipliers: [Float] = [0.4, 0.8, 1.0, 0.7, 0.35]
    private let phaseOffsets: [Double] = [0, 0.12, 0.06, 0.18, 0.09]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                BarView(
                    level: level,
                    multiplier: barMultipliers[index],
                    phaseOffset: phaseOffsets[index]
                )
            }
        }
    }
}

private struct BarView: View {
    let level: Float
    let multiplier: Float
    let phaseOffset: Double

    @State private var animatedHeight: CGFloat = 3
    @State private var idlePulse: Bool = false

    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(.white.opacity(0.85))
            .frame(width: 3, height: animatedHeight)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.6 + phaseOffset * 2)
                    .repeatForever(autoreverses: true)
                ) {
                    idlePulse = true
                }
            }
            .onChange(of: level) { _, newLevel in
                let amplified = min(newLevel * 40, 1.0)
                let normalized = CGFloat(amplified)

                let target: CGFloat
                if normalized > 0.05 {
                    target = minHeight + (maxHeight - minHeight) * normalized * CGFloat(multiplier)
                } else {
                    let idleRange: CGFloat = 2
                    let idleBase = minHeight + idleRange * CGFloat(multiplier)
                    target = idlePulse ? idleBase : minHeight
                }

                let jitter = CGFloat.random(in: -0.5...0.5)
                let finalHeight = max(minHeight, min(maxHeight, target + jitter))

                withAnimation(.easeInOut(duration: 0.08 + phaseOffset)) {
                    animatedHeight = finalHeight
                }
            }
    }
}

// MARK: - Spinner

private struct SpinnerView: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(
                AngularGradient(
                    colors: [.white.opacity(0), .white.opacity(0.7)],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
