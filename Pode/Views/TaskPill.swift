import SwiftUI

/// Compact, persistent indicator for the most relevant background task.
/// Lives in the sidebar footer; hides itself when there's nothing to show.
struct TaskPill: View {
    @State private var center = TaskCenter.shared

    var body: some View {
        if let item = center.current {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    statusIcon(for: item)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.sans(11.5, weight: .semibold))
                            .foregroundColor(Ink.primary)
                            .lineLimit(1)
                        Text(item.subtitle)
                            .font(.mono(10))
                            .foregroundColor(Ink.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !item.status.isTerminal {
                        Button {
                            center.cancel(item.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Ink.secondary)
                                .frame(width: 18, height: 18)
                                .background(
                                    Circle().fill(Color.black.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Cancel")
                    }
                }

                if !item.status.isTerminal {
                    progressBar(progress: item.progress)
                }
            }
            .padding(10)
            .background(GlassBackground(variant: .deep))
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeOut(duration: 0.18), value: center.current?.id)
        }
    }

    @ViewBuilder
    private func statusIcon(for item: TaskItem) -> some View {
        let (name, color): (String, Color) = {
            switch item.status {
            case .succeeded: return ("checkmark.circle.fill", Success.primary)
            case .failed:    return ("exclamationmark.triangle.fill", Danger.primary)
            case .cancelled: return ("xmark.circle.fill", Ink.tertiary)
            default:
                switch item.kind {
                case .transcribeLocal, .transcribeCloud:
                    return ("waveform", Brand.orange)
                case .analysis: return ("sparkles", Brand.orange)
                case .download: return ("arrow.down.circle", Brand.orange)
                }
            }
        }()
        Image(systemName: name)
            .font(.system(size: 12))
            .foregroundColor(color)
            .frame(width: 18)
    }

    @ViewBuilder
    private func progressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.06))
                    .frame(height: 3)
                Capsule().fill(Brand.orange)
                    .frame(width: max(0, geo.size.width * progress), height: 3)
                    .animation(.easeOut(duration: 0.2), value: progress)
            }
        }
        .frame(height: 3)
    }
}
