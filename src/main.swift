import Foundation

let user = NSUserName()
let host = ProcessInfo.processInfo.hostName
    .components(separatedBy: ".").first ?? "localhost"

struct LaunchOptions {
    var vfsPath: String?
    var scriptPath: String?
    var configPath: String?
}

func parseLaunchOptions(_ arguments: [String]) -> LaunchOptions? {
    var options = LaunchOptions()
    var index = 0

    while index < arguments.count {
        let key = arguments[index]

        guard ["--vfs", "--script", "--config"].contains(key) else {
            print("Ошибка: неизвестный параметр \(key)")
            return nil
        }

        guard index + 1 < arguments.count else {
            print("Ошибка: для параметра \(key) не указан путь")
            return nil
        }

        let value = arguments[index + 1]

        guard !value.isEmpty && !value.hasPrefix("--") else {
            print("Ошибка: для параметра \(key) не указан путь")
            return nil
        }

        switch key {
        case "--vfs":
            options.vfsPath = value
        case "--script":
            options.scriptPath = value
        case "--config":
            options.configPath = value
        default:
            print("Ошибка: неизвестный параметр \(key)")
            return nil
        }

        index += 2
    }

    return options
}

func loadINI(at path: String) -> LaunchOptions? {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("Ошибка: не удалось прочитать конфигурационный файл \(path)")
        return nil
    }

    var options = LaunchOptions()
    var inEmulatorSection = false

    for (index, rawLine) in content.components(separatedBy: .newlines).enumerated() {
        let line = rawLine.trimmingCharacters(in: .whitespaces)

        if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
            continue
        }

        if line.hasPrefix("[") {
            guard line == "[emulator]" else {
                print("Ошибка: неизвестный раздел INI в строке \(index + 1)")
                return nil
            }
            inEmulatorSection = true
            continue
        }

        let parts = line.split(
            separator: "=",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )

        guard inEmulatorSection, parts.count == 2 else {
            print("Ошибка: неверная строка INI \(index + 1)")
            return nil
        }

        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let value = parts[1].trimmingCharacters(in: .whitespaces)

        guard !value.isEmpty else {
            print("Ошибка: пустое значение \(key) в строке \(index + 1)")
            return nil
        }

        switch key {
        case "vfs_path":
            options.vfsPath = value
        case "script_path":
            options.scriptPath = value
        default:
            print("Ошибка: неизвестный параметр INI \(key)")
            return nil
        }
    }

    return options
}

func parseCommand(_ line: String) -> [String]? {
    var words: [String] = []
    var current = ""
    var quote: Character?
    var escaped = false
    var started = false

    for character in line {
        if escaped {
            current.append(character)
            escaped = false
            started = true
        } else if character == "\\" && quote != "'" {
            escaped = true
            started = true
        } else if let closingQuote = quote {
            if character == closingQuote {
                quote = nil
            } else {
                current.append(character)
            }
        } else if character == "\"" || character == "'" {
            quote = character
            started = true
        } else if character.isWhitespace {
            if started {
                words.append(current)
                current = ""
                started = false
            }
        } else {
            current.append(character)
            started = true
        }
    }

    guard quote == nil && !escaped else {
        return nil
    }

    if started {
        words.append(current)
    }
    return words
}

indirect enum VFSNode {
    case directory(name: String, children: [VFSNode])
    case file(name: String, data: Data)

    var name: String {
        switch self {
        case let .directory(name, _), let .file(name, _):
            return name
        }
    }
}

struct VFSLoadError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

func readVFSNode(_ element: XMLElement) throws -> VFSNode {
    guard let name = element.attribute(forName: "name")?.stringValue,
          !name.isEmpty,
          name != ".",
          name != "..",
          !name.contains("/") else {
        throw VFSLoadError(message: "неверное имя файла или папки")
    }

    switch element.name {
    case "directory":
        guard (element.attributes ?? []).count == 1 else {
            throw VFSLoadError(message: "лишние атрибуты папки \(name)")
        }
        return .directory(name: name, children: try readVFSEntries(element))

    case "file":
        guard element.attribute(forName: "encoding")?.stringValue == "base64",
              (element.attributes ?? []).count == 2,
              !(element.children ?? []).contains(where: { $0 is XMLElement }) else {
            throw VFSLoadError(message: "неверный формат файла \(name)")
        }

        let encoded = (element.stringValue ?? "").filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: encoded) else {
            throw VFSLoadError(message: "неверный Base64 в файле \(name)")
        }
        return .file(name: name, data: data)

    default:
        throw VFSLoadError(message: "неизвестный элемент XML")
    }
}

func readVFSEntries(_ parent: XMLElement) throws -> [VFSNode] {
    var entries: [VFSNode] = []
    var names: Set<String> = []

    for child in parent.children ?? [] {
        guard let element = child as? XMLElement else {
            let value = child.stringValue ?? ""
            if child.kind == .comment ||
                value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            throw VFSLoadError(message: "текст вне файла в XML")
        }

        let node = try readVFSNode(element)
        guard names.insert(node.name).inserted else {
            throw VFSLoadError(message: "повтор имени \(node.name)")
        }
        entries.append(node)
    }

    return entries
}

func loadVFS(at path: String) throws -> VFSNode {
    let url = URL(fileURLWithPath: path)
    let document = try XMLDocument(contentsOf: url, options: [])

    guard let root = document.rootElement(),
          root.name == "vfs",
          (root.attributes ?? []).isEmpty,
          document.dtd == nil else {
        throw VFSLoadError(message: "корневой элемент должен быть <vfs>")
    }

    return .directory(name: "/", children: try readVFSEntries(root))
}

func vfsLines(_ node: VFSNode, path: String = "/") -> [String] {
    switch node {
    case let .directory(_, children):
        return children.flatMap { child -> [String] in
            let fullPath = path == "/"
                ? "/\(child.name)"
                : "\(path)/\(child.name)"

            switch child {
            case .directory:
                return ["\(fullPath)/"] + vfsLines(child, path: fullPath)
            case let .file(_, data):
                return ["\(fullPath) (\(data.count) байт)"]
            }
        }

    case .file:
        return []
    }
}

var loadedVFS: VFSNode?

enum CommandResult {
    case success
    case failure
    case exit
}

func executeCommand(_ line: String) -> CommandResult {
    guard let words = parseCommand(line) else {
        print("Ошибка: незакрытая кавычка или незавершённое экранирование")
        return .failure
    }

    guard let command = words.first else {
        return .success
    }

    let arguments = Array(words.dropFirst())

    switch command {
    case "ls", "cd":
        if arguments.count > 1 {
            print("Ошибка: неверные аргументы команды \(command)")
            return .failure
        }
        print("\(command): \(arguments)")
        return .success

    case "vfs-info":
        guard arguments.isEmpty else {
            print("Ошибка: команда vfs-info не принимает аргументы")
            return .failure
        }
        guard let root = loadedVFS else {
            print("Ошибка: VFS не загружена")
            return .failure
        }
        print("/")
        vfsLines(root).forEach { print($0) }
        return .success

    case "exit":
        if arguments.isEmpty {
            return .exit
        }
        print("Ошибка: команда exit не принимает аргументы")
        return .failure

    default:
        print("Ошибка: неизвестная команда \(command)")
        return .failure
    }
}

guard let cliOptions = parseLaunchOptions(
    Array(CommandLine.arguments.dropFirst())
) else {
    exit(1)
}

var options = LaunchOptions()

if let configPath = cliOptions.configPath {
    guard let fileOptions = loadINI(at: configPath) else {
        exit(1)
    }
    options = fileOptions
}

options.vfsPath = cliOptions.vfsPath ?? options.vfsPath
options.scriptPath = cliOptions.scriptPath ?? options.scriptPath
options.configPath = cliOptions.configPath

print("Параметры запуска:")
print("VFS: \(options.vfsPath ?? "не задан")")
print("Стартовый скрипт: \(options.scriptPath ?? "не задан")")
print("Конфигурационный файл: \(options.configPath ?? "не задан")")

if let vfsPath = options.vfsPath {
    do {
        loadedVFS = try loadVFS(at: vfsPath)
        print("VFS загружена: \(vfsPath)")
    } catch {
        print("Ошибка загрузки VFS: \(error.localizedDescription)")
        exit(1)
    }
}

if let scriptPath = options.scriptPath {
    guard let content = try? String(
        contentsOfFile: scriptPath,
        encoding: .utf8
    ) else {
        print("Ошибка: не удалось прочитать стартовый скрипт \(scriptPath)")
        exit(1)
    }

    for (index, line) in content.components(separatedBy: .newlines).enumerated() {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            continue
        }

        print("\(user)@\(host):~$ \(line)")

        switch executeCommand(line) {
        case .success:
            break
        case .failure:
            print("Ошибка исполнения стартового скрипта: строка \(index + 1)")
            exit(1)
        case .exit:
            exit(0)
        }
    }
}

while true {
    print("\(user)@\(host):~$ ", terminator: "")
    fflush(stdout)

    guard let line = readLine() else {
        break
    }

    if case .exit = executeCommand(line) {
        break
    }
}