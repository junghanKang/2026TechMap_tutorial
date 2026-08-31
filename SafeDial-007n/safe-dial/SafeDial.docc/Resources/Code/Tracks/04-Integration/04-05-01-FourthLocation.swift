struct FourthLockExercise {
    enum Zone: Int, CaseIterable {
        case near = 0
        case middle, far, distant
    }
    static let centersMeters = [0.0, 0.10, 0.20, 0.30]
}
