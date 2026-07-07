import SwiftUI
import AppKit

struct IssuePRLineView: View {
    let issueNumber: Int?
    let issueURL: URL?
    let prNumber: Int?
    let prURL: URL?

    var body: some View {
        HStack(spacing: 10) {
            if let issueNumber {
                linkButton(text: "ISSUE #\(issueNumber)", url: issueURL)
            }
            if let prNumber {
                linkButton(text: "PR #\(prNumber)", url: prURL)
            }
        }
        .font(.caption2.weight(.semibold))
        .padding(.leading, 22)
    }

    @ViewBuilder
    private func linkButton(text: String, url: URL?) -> some View {
        Button(text) {
            if let url { NSWorkspace.shared.open(url) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .disabled(url == nil)
    }
}
