import Foundation

struct ToolCall {
    let name: String
    let arguments: [String: Any]
    let raw: [String: Any]
}
struct BrainReply {
    let text: String
    let calls: [ToolCall]
    let message: [String: Any]
}
enum NovaError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let s): return s } }
}
struct Brain {
    static let endpoint = URL(string: "http://127.0.0.1:11435")!
    static let toolDefinitions: [[String: Any]] = [
        tool("open_app", "Open an installed Mac app by name. Supported: Safari, Chrome, Finder, Notes, Calendar, Calculator, Music, Terminal, Visual Studio Code, Mail, System Settings.", ["name":"string"]),
        tool("open_website", "Open an HTTPS website in the browser. Does not read page contents.", ["url":"string"]),
        tool("web_search", "Open a browser search for the query. Does not return search results or read websites.", ["query":"string"]),
        tool("get_status", "Read current local date, time, basic Mac information and active timers.", [:]),
        tool("remember", "Save a short personal fact ONLY when the user explicitly asks you to remember it.", ["fact":"string"]),
        tool("create_note", "Save a text note in Nova's own notes folder.", ["title":"string", "content":"string"]),
        tool("list_notes", "List Nova notes available to read.", [:]),
        tool("read_note", "Read a Nova note by the exact filename returned by list_notes.", ["filename":"string"]),
        tool("set_timer", "Set a timer in seconds, from 1 to 86400. Notify while Nova is open.", ["seconds":"number", "label":"string"])
    ]
    static func tool(_ name: String, _ description: String, _ fields: [String:String]) -> [String:Any] {
        ["type":"function", "function":["name":name, "description":description, "parameters":["type":"object", "properties":fields.mapValues { ["type":$0] }, "required":fields.keys.sorted(), "additionalProperties":false]]]
    }
    static func parse(_ data: Data) throws -> BrainReply {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw NovaError.message("Invalid response from the local AI.") }
        if let error = object["error"] as? String { throw NovaError.message(error) }
        guard var message = object["message"] as? [String:Any] else { throw NovaError.message("The local AI returned no message.") }
        var calls: [ToolCall] = []
        for raw in message["tool_calls"] as? [[String:Any]] ?? [] {
            guard let function = raw["function"] as? [String:Any], let name = function["name"] as? String else { throw NovaError.message("Malformed tool request.") }
            let args: [String:Any]
            if let object = function["arguments"] as? [String:Any] { args = object }
            else if let text = function["arguments"] as? String, let data = text.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String:Any] { args = object }
            else { throw NovaError.message("Malformed tool arguments.") }
            calls.append(ToolCall(name: name, arguments: args, raw: raw))
        }
        let visible = visibleText(message["content"] as? String ?? "")
        message["content"] = visible
        message.removeValue(forKey: "thinking")
        return BrainReply(text: visible, calls: calls, message: message)
    }
    static func visibleText(_ raw: String) -> String {
        // Some Qwen templates include a closing think tag even when the opening
        // tag is supplied by the template, so retain only the final answer.
        if let end = raw.range(of: "</think>", options: .backwards) {
            return String(raw[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if raw.contains("<think>") { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func wakeCommand(_ transcript: String) -> String? {
        let pattern = #"\bhey[\s,]+nova\b"#
        guard let range = transcript.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var command = String(transcript[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if let wake = command.range(of: #"^wake[\s,]+up\b"#, options: [.regularExpression, .caseInsensitive]) { command = String(command[wake.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
        return command
    }
    static func validatedURL(_ text: String) throws -> URL {
        guard let parts = URLComponents(string: text), parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, let url = parts.url else { throw NovaError.message("Only valid HTTPS websites are supported.") }
        return url
    }
    static func safeTitle(_ text: String) -> String {
        let clean = String(text.unicodeScalars.filter { CharacterSet.alphanumerics.union(.init(charactersIn: " -_")).contains($0) }.prefix(70))
        return clean.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : clean
    }
    static func validNoteName(_ name: String) -> Bool { !name.isEmpty && !name.contains("/") && !name.contains("\\") && !name.contains("..") && name.hasSuffix(".txt") }
    static func timerSeconds(_ value: Any?) throws -> Double {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite, number.doubleValue >= 1, number.doubleValue <= 86400 else { throw NovaError.message("Timer must be between 1 second and 24 hours.") }
        return number.doubleValue
    }
    func chat(model: String, messages: [[String:Any]], session: URLSession = .shared, onText: (@MainActor (String) -> Void)? = nil) async throws -> BrainReply {
        var request = URLRequest(url: Self.endpoint.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"; request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model":model, "messages":messages, "tools":Self.toolDefinitions, "stream":onText != nil, "think":false, "keep_alive":"30m", "options":["num_ctx":4096, "num_predict":512, "temperature":0.5]])
        if let onText {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw NovaError.message("Local AI connection failed.") }
            var content = ""
            var calls: [[String:Any]] = []
            var finished = false
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard !line.isEmpty, let data = line.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { continue }
                if let error = object["error"] as? String { throw NovaError.message(error) }
                if let message = object["message"] as? [String:Any] {
                    content += message["content"] as? String ?? ""
                    calls += message["tool_calls"] as? [[String:Any]] ?? []
                    if calls.isEmpty { await onText(Self.visibleText(content)) }
                }
                if object["done"] as? Bool == true { finished = true; break }
            }
            guard finished else { throw NovaError.message("The AI response was interrupted.") }
            return try Self.parse(JSONSerialization.data(withJSONObject: ["message":["role":"assistant", "content":content, "tool_calls":calls]]))
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NovaError.message("No response from Ollama.") }
        guard (200..<300).contains(http.statusCode) else {
            let reason = (try? JSONSerialization.jsonObject(with: data) as? [String:Any])?["error"] as? String
            throw NovaError.message(reason ?? "Local AI returned HTTP \(http.statusCode).")
        }
        return try Self.parse(data)
    }
}
import CoreFoundation
