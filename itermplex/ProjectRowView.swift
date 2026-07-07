import SwiftUI

struct ProjectRowView: View {
    let project: Project
    let gitInfo: GitInfo?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: project.isGitRepository ? "arrow.triangle.branch" : "folder")
                .foregroundStyle(.secondary)
            Text(project.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let gitInfo, gitInfo.hasUpstream {
                AheadBehindView(behind: gitInfo.behind, ahead: gitInfo.ahead)
            }
        }
        .padding(.vertical, 2)
    }
}
