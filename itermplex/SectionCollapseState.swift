import Foundation

struct SectionCollapseState {
    private let defaults: UserDefaults
    private let key = "itermplex.sidebar.collapsed"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var map: [String: Bool] { defaults.dictionary(forKey: key) as? [String: Bool] ?? [:] }
    func isCollapsed(_ k: String) -> Bool { map[k] ?? false }
    func setCollapsed(_ k: String, _ value: Bool) {
        var m = map; m[k] = value; defaults.set(m, forKey: key)
    }
}
