import SwiftUI

struct AheadBehindView: View {
    let behind: Int
    let ahead: Int

    var body: some View {
        HStack(spacing: 3) {
            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                Text("\(ahead)")
            }
            HStack(spacing: 2) {
                Image(systemName: "arrow.down")
                Text("\(behind)")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}
