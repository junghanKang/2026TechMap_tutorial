struct FourthLockExercise {
    enum Zone: Int, CaseIterable {
        case near = 0
        case middle, far, distant
    }
    static let centersMeters = [0.0, 0.10, 0.20, 0.30]
    static var lockCount: Int { centersMeters.count }
    static var completionTitle: String {
        "\(lockCount)개의 자물쇠를 모두 열었습니다"
    }
}
