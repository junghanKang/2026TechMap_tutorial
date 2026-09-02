import Foundation

/// 금고 다이얼 한 바퀴의 숫자와 눈금 체계.
///
/// 게임 판정, 화면 눈금, 접근성 입력이 모두 이 값을 기준으로 각도를 계산한다.
enum DialScale {
    static let numberCount = 100
    static let majorNumberInterval = 10

    static let radiansPerNumber = 2 * Double.pi / Double(numberCount)
    static let degreesPerNumber = 360.0 / Double(numberCount)

    static func reading(at position: Double) -> Int {
        let rounded = Int(position.rounded())
        return ((rounded % numberCount) + numberCount) % numberCount
    }
}
