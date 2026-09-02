extension SafeDialModel {
    var completionCaption: LockCaption? {
        guard phase == .cleared else { return nil }
    }
}
