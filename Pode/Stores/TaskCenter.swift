import Foundation
import SwiftUI

/// Long-running background work that's worth a persistent indicator —
/// transcription, model download, batch operations, AI analysis.
///
/// The pill in the sidebar reads the current item; the full panel (later)
/// reads the whole list.
@MainActor
@Observable
final class TaskCenter {
    static let shared = TaskCenter()

    private(set) var items: [TaskItem] = []

    /// The most relevant item to surface in a single-line pill — first running
    /// item, or the most recent terminal one.
    var current: TaskItem? {
        items.first(where: { $0.status == .running })
            ?? items.first(where: { $0.status == .pending })
            ?? items.last
    }

    @discardableResult
    func add(_ item: TaskItem) -> UUID {
        items.insert(item, at: 0)
        return item.id
    }

    func update(_ id: UUID, mutate: (inout TaskItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
    }

    func setProgress(_ id: UUID, _ p: Double, subtitle: String? = nil) {
        update(id) {
            $0.progress = p
            if let s = subtitle { $0.subtitle = s }
            $0.status = .running
        }
    }

    func setSubtitle(_ id: UUID, _ s: String) {
        update(id) { $0.subtitle = s }
    }

    func succeed(_ id: UUID, subtitle: String? = nil) {
        update(id) {
            $0.status = .succeeded
            $0.progress = 1
            if let s = subtitle { $0.subtitle = s }
        }
        // Auto-clear successful items after 4s.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            remove(id)
        }
    }

    func fail(_ id: UUID, _ message: String) {
        update(id) {
            $0.status = .failed(message)
            // Surface the failure reason in the pill subtitle. Without
            // this, the pill keeps the last stage label ("Loading model…")
            // even after the work blew up, and users can't tell what went
            // wrong without opening the episode.
            $0.subtitle = message
        }
    }

    func cancel(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].status = .cancelled
        items[idx].onCancel?()
        // Drop cancelled items immediately.
        items.remove(at: idx)
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }
}

/// One unit of work shown in the task center.
struct TaskItem: Identifiable {
    let id = UUID()
    let kind: Kind
    var title: String          // e.g. "Episode 138"
    var subtitle: String       // e.g. "Downloading model · 23%"
    var progress: Double       // 0..1, or 0 for indeterminate at start
    var status: Status
    /// Invoked when the user hits cancel on the pill. Owners attach their
    /// `Task` cancellation closure here.
    var onCancel: (@Sendable () -> Void)?
    /// If this task is associated with a specific episode, store the ID so
    /// the pill can deep-link back to it on click.
    var episodeID: String? = nil

    enum Kind: Equatable {
        case transcribeLocal
        case transcribeCloud
        case analysis
        case download
    }

    enum Status: Equatable {
        case pending
        case running
        case succeeded
        case failed(String)
        case cancelled

        static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.pending, .pending), (.running, .running),
                 (.succeeded, .succeeded), (.cancelled, .cancelled): return true
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }

        var isTerminal: Bool {
            switch self {
            case .succeeded, .failed, .cancelled: return true
            case .pending, .running: return false
            }
        }
    }
}
