import SwiftUI

/// Where playback is between the page's reports, which come every 5 s and on
/// every change. A report a little off from where the clock has got to (the
/// page's own timer, the message's way here) is eased in over a few seconds
/// instead of taken at once, so the seconds count on evenly and never go
/// back; a larger one, a seek or a stall, is taken at once.
struct PlaybackClock: Equatable, Sendable {
    var position: Double = 0
    var date = Date()
    var isPlaying = false
    var duration: Double = 0
    /// Added little by little over Tuning.clockEase.
    var correction: Double = 0

    init() {}

    init(_ state: PlayerState, at date: Date) {
        position = state.position
        self.date = date
        isPlaying = state.isPlaying
        duration = state.duration
    }

    func position(at now: Date) -> Double {
        guard isPlaying else { return position }
        let elapsed = max(0, now.timeIntervalSince(date))
        let eased = correction * min(1, elapsed / Tuning.clockEase)
        let running = max(0, position + elapsed + eased)
        return duration > 0 ? min(running, duration) : running
    }

    /// The clock after a report.
    func following(_ state: PlayerState, at now: Date, sameTrack: Bool) -> PlaybackClock {
        var next = PlaybackClock(state, at: now)
        guard sameTrack, isPlaying, state.isPlaying else { return next }
        let predicted = position(at: now)
        let error = state.position - predicted
        guard abs(error) < Tuning.clockTolerance else { return next }
        next.position = predicted
        next.correction = error
        return next
    }

    /// When the shown second changes next, at the clock's pace.
    func nextSecond(after now: Date) -> Date {
        let current = position(at: now)
        let wait = floor(current) + 1 - current
        return now.addingTimeInterval(max(wait, Tuning.clockMinimumTick) + Tuning.clockMargin)
    }
}

/// TimelineView ticks on each new second of playback, not on the wall
/// clock's, so 0:21 follows 0:20 a second later every time.
struct PlaybackSeconds: TimelineSchedule {
    let clock: PlaybackClock

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        // Paused, the time stands: one entry, and the next report redraws.
        var next: Date? = start
        return AnyIterator {
            guard let current = next else { return nil }
            next = clock.isPlaying ? clock.nextSecond(after: current) : nil
            return current
        }
    }
}
