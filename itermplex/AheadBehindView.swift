import SwiftUI

struct AheadBehindView: View {
    let behind: Int
    let ahead: Int

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                Text("\(behind)")
                Image(systemName: "chevron.down")
            }
            HStack(spacing: 2) {
                Text("\(ahead)")
                Image(systemName: "chevron.up")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}
