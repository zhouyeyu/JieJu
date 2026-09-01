import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("JieJu")
                .font(.largeTitle.weight(.semibold))

            Text("从真实阅读中学习语言")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("PDF 阅读与划线解句功能即将从这里开始。")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .accessibilityIdentifier("welcome.screen")
    }
}

#Preview {
    WelcomeView()
        .frame(width: 800, height: 520)
}

