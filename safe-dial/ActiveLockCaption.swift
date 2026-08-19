//
//  ActiveLockCaption.swift
//  safe-dial (006e)
//

import SwiftUI

/// 자물쇠 정보창 **하나**. 지금 거리에 해당하는 자물쇠만 말한다.
///
/// 006d는 자물쇠 세 개의 정보를 카드 세 장으로 겹쳐 쌓아서, 뒤 카드의 글자가 앞 카드에
/// 잘렸다. 여기서는 겹쳐 쌓지 않는다 — 화면에 자물쇠 글자는 언제나 한 벌만 존재하고,
/// 어느 자물쇠를 보여줄지는 **거리가 정한다.**
///
/// 앞뒤 위치는 위쪽 `DepthDialStack`이 그림으로 말하므로 여기서는 숫자만 덧붙인다.
struct ActiveLockCaption: View {
    let model: SpatialSafeDialModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.2), value: title)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 내용

    private var title: String {
        guard let index = model.expectedZone?.rawValue else { return allLocksTitle }
        return "\(index + 1)번째 자물쇠 · \(positionLabel(index))"
    }

    private var detail: String {
        guard let index = model.expectedZone?.rawValue else {
            return model.game.phase == .cleared
                ? "오디오와 햅틱만으로 다시 완주해 보세요."
                : "시작하면 현재 위치가 첫 번째 자물쇠가 됩니다."
        }
        if model.isAligned {
            return model.game.isTracking ? model.game.directionHint : "다이얼 링을 터치해 돌리세요."
        }
        return remainingLabel(index)
    }

    private var symbol: String {
        guard let index = model.expectedZone?.rawValue else {
            return model.game.phase == .cleared ? "lock.open.fill" : "lock.fill"
        }
        return index < model.game.solvedCount ? "lock.open.fill" : "lock.fill"
    }

    private var tint: Color {
        guard model.expectedZone != nil else {
            return model.game.phase == .cleared ? .green : .secondary
        }
        return model.isAligned ? .cyan : .accentColor
    }

    // MARK: - 거리 문구

    private var allLocksTitle: String {
        let positions = model.depthConfiguration.centers
            .map { String(Int(($0 * 100).rounded())) }
            .joined(separator: " / ")
        return "세 자물쇠 · \(positions)cm"
    }

    /// 시작 위치를 기준으로 한 자물쇠의 절대 위치.
    private func positionLabel(_ index: Int) -> String {
        let centimeters = Int((model.depthConfiguration.centers[index] * 100).rounded())
        return centimeters == 0 ? "시작 위치" : "시작에서 +\(centimeters)cm"
    }

    /// 목표까지 남은 거리. **0.5cm 단위로 끊는다** — ARKit 잡음이 0.1cm 자리를
    /// 60Hz로 흔들면 읽을 수 없는 숫자가 된다. 진입 반경이 ±3cm라 이 해상도면 충분하다.
    private func remainingLabel(_ index: Int) -> String {
        let remaining = model.depthConfiguration.centers[index] - model.visualDepth
        let centimeters = (abs(remaining) * 100 * 2).rounded() / 2
        let amount = String(format: "%.1f", centimeters)
        return remaining > 0 ? "앞으로 \(amount)cm 더" : "뒤로 \(amount)cm 되돌아오기"
    }
}
