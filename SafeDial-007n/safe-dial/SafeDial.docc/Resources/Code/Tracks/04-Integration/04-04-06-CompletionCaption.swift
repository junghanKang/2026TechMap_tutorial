extension SafeDialModel {
    var completionCaption: LockCaption? {
        guard phase == .cleared else { return nil }
        return LockCaption(
            title: "세 개의 자물쇠를 모두 열었습니다",
            detail: "소리와 햅틱에 집중해 다시 도전해 보세요.",
            symbol: "lock.open.fill",
            tone: .cleared
        )
    }
}
