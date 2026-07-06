import Foundation

struct Project: Identifiable, Equatable {
    let id: UUID
    let url: URL

    var name: String { url.lastPathComponent }

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }
}
