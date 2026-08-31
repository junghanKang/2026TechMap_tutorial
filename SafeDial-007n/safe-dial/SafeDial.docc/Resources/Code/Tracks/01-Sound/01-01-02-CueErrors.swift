import Foundation

enum FeedbackCue: String, CaseIterable {
    case dialDetent01 = "dial-detent-01"
    case dialDetent02 = "dial-detent-02"
    case lockReleaseSequence = "lock-release-sequence"
    case depthArrivalClick = "depth-arrival-click"
}

enum CueInventoryError: Error {
    case missing(FeedbackCue)
    case invalid(FeedbackCue, Error)
    case incomplete(FeedbackCue)
}

struct DetentCueRotation {
    private var usesSecondCue = false
}
