import SwiftUI

struct ChecksLineView: View {
    let summary: ChecksSummary

    var body: some View {
        Text(summary.summaryText)
            .font(.caption)
            .foregroundStyle(summary.hasFailures ? Color.red : Color.green)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
