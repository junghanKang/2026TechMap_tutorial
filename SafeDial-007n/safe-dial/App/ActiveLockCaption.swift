import SwiftUI

/// 지금 다루는 자물쇠의 학습자용 설명 한 벌만 보여준다.
struct ActiveLockCaption: View {
    let content: SafeDialModel.LockCaption

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: content.symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.headline)
                Text(content.detail)
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
        .animation(.easeInOut(duration: 0.2), value: content.tone)
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch content.tone {
        case .neutral: return .secondary
        case .searching: return .accentColor
        case .aligned: return .cyan
        case .cleared: return .green
        }
    }
}
