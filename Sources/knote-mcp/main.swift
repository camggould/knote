import Foundation
import KnoteCore
import KnoteEmbeddings
import KnoteVector

// MARK: - No-op encoder (lexical-only, no ML model needed)

private final class NoEncoder: Encoder, @unchecked Sendable {
    let id = "none"
    let dimension = 0
    func embed(_ text: String, kind: EmbedKind) -> [Float]? { nil }
}

// MARK: - Tool definitions

private func toolDefinitions() -> [[String: Any]] {
    [
        [
            "name": "search_notes",
            "description": "Search knote notes by keyword or #tag. Returns matching notes with id, title, snippet, tags, and link count.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Search query (may include #tag filters)"
                    ],
                    "space": [
                        "type": "string",
                        "description": "Restrict results to this space name (optional)"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum number of results to return (default 8)"
                    ]
                ],
                "required": ["query"]
            ]
        ],
        [
            "name": "get_note",
            "description": "Retrieve the full body of a single note by its ID.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": [
                        "type": "string",
                        "description": "The note ID"
                    ]
                ],
                "required": ["id"]
            ]
        ],
        [
            "name": "list_spaces",
            "description": "List all spaces (workspaces) in the knote database.",
            "inputSchema": [
                "type": "object",
                "properties": [String: Any]()
            ]
        ],
        [
            "name": "list_tags",
            "description": "List all tags used across notes in the knote database.",
            "inputSchema": [
                "type": "object",
                "properties": [String: Any]()
            ]
        ]
    ]
}

// MARK: - Tool dispatch

private func callTool(name: String, arguments: [String: Any],
                      store: NoteStore, search: SearchService) -> [String: Any] {
    do {
        let text: String
        switch name {
        case "search_notes":
            let query = arguments["query"] as? String ?? ""
            let spaceNameArg = arguments["space"] as? String
            let limit = arguments["limit"] as? Int ?? 8

            var spaceID: String?
            if let spaceName = spaceNameArg {
                spaceID = try store.space(named: spaceName)?.id
            }

            let results = search.search(query, spaceID: spaceID)
            let capped = Array(results.prefix(limit))

            let items: [[String: Any]] = capped.map { r in
                let snippet = String(
                    r.note.body
                        .replacingOccurrences(of: "\n", with: " ")
                        .prefix(160)
                )
                return [
                    "id": r.note.id,
                    "title": r.note.title,
                    "snippet": snippet,
                    "tags": r.tags,
                    "linkCount": r.linkCount
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: items)
            text = String(data: data, encoding: .utf8) ?? "[]"

        case "get_note":
            let noteID = arguments["id"] as? String ?? ""
            guard let note = try store.fetch(id: noteID) else {
                return toolError("Note not found: \(noteID)")
            }
            text = note.body

        case "list_spaces":
            let spaces = try store.spaces()
            let names = spaces.map { $0.name }
            let data = try JSONSerialization.data(withJSONObject: names)
            text = String(data: data, encoding: .utf8) ?? "[]"

        case "list_tags":
            let tags = try store.allTags()
            let names = tags.map { $0.name }
            let data = try JSONSerialization.data(withJSONObject: names)
            text = String(data: data, encoding: .utf8) ?? "[]"

        default:
            return toolError("Unknown tool: \(name)")
        }

        return [
            "content": [["type": "text", "text": text]],
            "isError": false
        ]
    } catch {
        return toolError(error.localizedDescription)
    }
}

private func toolError(_ message: String) -> [String: Any] {
    [
        "content": [["type": "text", "text": message]],
        "isError": true
    ]
}

// MARK: - JSON-RPC helpers

private func successResponse(id: Any, result: Any) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "result": result]
}

private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message] as [String: Any]]
}

private func writeResponse(_ dict: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: dict),
          let line = String(data: data, encoding: .utf8) else { return }
    print(line)
    fflush(stdout)
}

// MARK: - Request handler (shared by stdio loop and selftest)

func handleRequest(_ request: [String: Any], store: NoteStore, search: SearchService) -> [String: Any]? {
    // Notifications have no "id" field — do not respond
    guard let id = request["id"] else { return nil }

    guard let method = request["method"] as? String else {
        return errorResponse(id: id, code: -32600, message: "Invalid request")
    }
    let params = request["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        return successResponse(id: id, result: [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:] as [String: Any]],
            "serverInfo": ["name": "knote", "version": "0.2.0"] as [String: Any]
        ] as [String: Any])

    case "tools/list":
        return successResponse(id: id, result: ["tools": toolDefinitions()] as [String: Any])

    case "tools/call":
        let toolName = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let result = callTool(name: toolName, arguments: arguments, store: store, search: search)
        return successResponse(id: id, result: result)

    default:
        return errorResponse(id: id, code: -32601, message: "Method not found")
    }
}

// MARK: - Self-test

func runSelftest() {
    do {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("knote-mcp-selftest-\(Int.random(in: 0..<1_000_000))")
        let dbPath = tmpDir.appendingPathComponent("test.sqlite")
        let store = try NoteStore(path: dbPath)
        let search = SearchService(store: store, encoder: NoEncoder(), index: InMemoryVectorIndex())

        // Populate with 2 sample notes
        _ = try store.create(body: "Meeting notes for the team #work")
        _ = try store.create(body: "Personal tasks to complete")

        // 1. initialize
        let initReq: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:] as [String: Any]]
        guard let initResp = handleRequest(initReq, store: store, search: search),
              let initResult = initResp["result"] as? [String: Any],
              (initResult["protocolVersion"] as? String) == "2024-11-05" else {
            fputs("FAIL: initialize response malformed\n", stderr)
            exit(1)
        }

        // 2. tools/list — assert 4 tools
        let listReq: [String: Any] = ["jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": [:] as [String: Any]]
        guard let listResp = handleRequest(listReq, store: store, search: search),
              let listResult = listResp["result"] as? [String: Any],
              let tools = listResult["tools"] as? [[String: Any]],
              tools.count == 4 else {
            fputs("FAIL: tools/list should return 4 tools\n", stderr)
            exit(1)
        }
        let toolNames = Set(tools.compactMap { $0["name"] as? String })
        for expected in ["search_notes", "get_note", "list_spaces", "list_tags"] {
            guard toolNames.contains(expected) else {
                fputs("FAIL: missing tool \(expected)\n", stderr)
                exit(1)
            }
        }

        // 3. search_notes — expect at least 1 result for "meeting"
        let searchReq: [String: Any] = [
            "jsonrpc": "2.0", "id": 3,
            "method": "tools/call",
            "params": ["name": "search_notes", "arguments": ["query": "meeting"] as [String: Any]] as [String: Any]
        ]
        guard let searchResp = handleRequest(searchReq, store: store, search: search),
              let searchResult = searchResp["result"] as? [String: Any],
              let content = searchResult["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String,
              let jsonData = text.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]],
              !items.isEmpty else {
            fputs("FAIL: search_notes returned no results for 'meeting'\n", stderr)
            exit(1)
        }

        // 4. list_tags — assert "work" is present
        let tagsReq: [String: Any] = [
            "jsonrpc": "2.0", "id": 4,
            "method": "tools/call",
            "params": ["name": "list_tags", "arguments": [:] as [String: Any]] as [String: Any]
        ]
        guard let tagsResp = handleRequest(tagsReq, store: store, search: search),
              let tagsResult = tagsResp["result"] as? [String: Any],
              let tagsContent = tagsResult["content"] as? [[String: Any]],
              let tagsText = tagsContent.first?["text"] as? String,
              let tagsData = tagsText.data(using: .utf8),
              let tagNames = try? JSONSerialization.jsonObject(with: tagsData) as? [String],
              tagNames.contains("work") else {
            fputs("FAIL: list_tags should contain 'work'\n", stderr)
            exit(1)
        }

        // 5. Notifications (no id) get no response
        let notification: [String: Any] = ["jsonrpc": "2.0", "method": "notifications/initialized"]
        guard handleRequest(notification, store: store, search: search) == nil else {
            fputs("FAIL: notification should produce no response\n", stderr)
            exit(1)
        }

        try? FileManager.default.removeItem(at: tmpDir)
        print("MCP selftest OK")
        exit(0)
    } catch {
        fputs("FAIL: \(error)\n", stderr)
        exit(1)
    }
}

// MARK: - Entry point

if CommandLine.arguments.contains("--selftest") {
    runSelftest()
}

// Determine DB path from env or default
let dbPath: URL
if let envPath = ProcessInfo.processInfo.environment["KNOTE_DB"] {
    dbPath = URL(fileURLWithPath: envPath)
} else {
    let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask).first!
    dbPath = appSupport.appendingPathComponent("knote/knote.sqlite")
}

fputs("[knote-mcp] opening db at \(dbPath.path)\n", stderr)

let store: NoteStore
do {
    store = try NoteStore(path: dbPath)
} catch {
    fputs("[knote-mcp] failed to open store: \(error)\n", stderr)
    exit(1)
}

let search = SearchService(store: store, encoder: NoEncoder(), index: InMemoryVectorIndex())

fputs("[knote-mcp] ready\n", stderr)

// Protocol loop: read one JSON-RPC message per line from stdin
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty else { continue }
    guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        fputs("[knote-mcp] parse error for line: \(line)\n", stderr)
        continue
    }
    if let response = handleRequest(obj, store: store, search: search) {
        writeResponse(response)
    }
}
