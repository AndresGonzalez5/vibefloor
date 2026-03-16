// ABOUTME: Loads setup/run/teardown script configuration from project config files.
// ABOUTME: Resolves from .ff2.json, falling back to emdash, conductor, and superset formats.

import Foundation

struct ScriptConfig {
    let setup: String?
    let run: String?
    let teardown: String?
    let source: String?

    static let empty = ScriptConfig(setup: nil, run: nil, teardown: nil, source: nil)

    /// Load script config for a project directory, checking multiple config file formats.
    static func load(from directory: String) -> ScriptConfig {
        let resolvers: [(String, (String) -> ScriptConfig?)] = [
            (".ff2.json", loadFF2),
            (".ff2/config.json", loadFF2),
            (".emdash.json", loadEmdash),
            ("conductor.json", loadConductor),
            (".superset/config.json", loadSuperset),
        ]

        for (filename, loader) in resolvers {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(filename).path
            guard FileManager.default.fileExists(atPath: path) else { continue }
            if let config = loader(path) {
                return config
            }
        }

        return .empty
    }

    var hasAnyScript: Bool {
        setup != nil || run != nil || teardown != nil
    }

    // MARK: - Loaders

    /// .ff2.json / .ff2/config.json format:
    /// { "setup": "cmd", "run": "cmd", "teardown": "cmd" }
    private static func loadFF2(_ path: String) -> ScriptConfig? {
        guard let dict = loadJSON(path) else { return nil }
        let setup = dict["setup"] as? String
        let run = dict["run"] as? String
        let teardown = dict["teardown"] as? String
        guard setup != nil || run != nil || teardown != nil else { return nil }
        return ScriptConfig(setup: nonEmpty(setup), run: nonEmpty(run), teardown: nonEmpty(teardown), source: URL(fileURLWithPath: path).lastPathComponent)
    }

    /// .emdash.json format:
    /// { "scripts": { "setup": "cmd", "run": "cmd", "teardown": "cmd" } }
    private static func loadEmdash(_ path: String) -> ScriptConfig? {
        guard let dict = loadJSON(path),
              let scripts = dict["scripts"] as? [String: Any] else { return nil }
        let setup = scripts["setup"] as? String
        let run = scripts["run"] as? String
        let teardown = scripts["teardown"] as? String
        guard setup != nil || run != nil || teardown != nil else { return nil }
        return ScriptConfig(setup: nonEmpty(setup), run: nonEmpty(run), teardown: nonEmpty(teardown), source: ".emdash.json")
    }

    /// conductor.json format:
    /// { "scripts": { "setup": "cmd", "run": "cmd", "archive": "cmd" } }
    private static func loadConductor(_ path: String) -> ScriptConfig? {
        guard let dict = loadJSON(path),
              let scripts = dict["scripts"] as? [String: Any] else { return nil }
        let setup = scripts["setup"] as? String
        let run = scripts["run"] as? String
        let teardown = scripts["archive"] as? String
        guard setup != nil || run != nil || teardown != nil else { return nil }
        return ScriptConfig(setup: nonEmpty(setup), run: nonEmpty(run), teardown: nonEmpty(teardown), source: "conductor.json")
    }

    /// .superset/config.json format:
    /// { "setup": ["cmd1", "cmd2"], "teardown": ["cmd1"] }
    private static func loadSuperset(_ path: String) -> ScriptConfig? {
        guard let dict = loadJSON(path) else { return nil }
        let setupArr = dict["setup"] as? [String]
        let teardownArr = dict["teardown"] as? [String]
        let setup = setupArr?.joined(separator: " && ")
        let teardown = teardownArr?.joined(separator: " && ")
        guard setup != nil || teardown != nil else { return nil }
        return ScriptConfig(setup: nonEmpty(setup), run: nil, teardown: nonEmpty(teardown), source: ".superset/config.json")
    }

    // MARK: - Helpers

    private static func loadJSON(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }
}
