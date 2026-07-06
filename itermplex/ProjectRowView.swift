import SwiftUI

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: project.isGitRepository ? "arrow.triangle.branch" : "folder")
                .foregroundStyle(.secondary)
            Text(project.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }
}
