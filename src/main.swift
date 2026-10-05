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