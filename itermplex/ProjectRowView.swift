import SwiftUI

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        Text(project.name)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.vertical, 2)
    }
}
