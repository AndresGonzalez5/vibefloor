// ABOUTME: Data models for projects and workstreams.
// ABOUTME: Each project has a directory and multiple workstreams, each with its own terminal.

import Foundation

struct Workstream: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String

    init(name: String, id: UUID = UUID()) {
        self.id = id
        self.name = name
    }
}

struct Project: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var directory: String
    var workstreams: [Workstream]

    init(name: String, directory: String, id: UUID = UUID(), workstreams: [Workstream] = []) {
        self.id = id
        self.name = name
        self.directory = directory
        self.workstreams = workstreams
    }
}
