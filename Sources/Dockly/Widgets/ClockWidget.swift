import SwiftUI

struct ClockWidget: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        WidgetShell(title: "clock") {
            VStack(alignment: .leading, spacing: 2) {
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Text(now, format: .dateTime.weekday(.wide).month().day())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 120)
        .onReceive(timer) { now = $0 }
    }
}
