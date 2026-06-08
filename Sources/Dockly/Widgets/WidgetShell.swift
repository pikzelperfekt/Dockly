import SwiftUI

struct WidgetShell<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
