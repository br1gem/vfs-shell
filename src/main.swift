import Foundation

let user = NSUserName()
let host = ProcessInfo.processInfo.hostName
    .components(separatedBy: ".").first ?? "localhost"

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

repl: while true {
    print("\(user)@\(host):~$ ", terminator: "")
    fflush(stdout)

    guard let line = readLine() else {
        break
    }

    guard let words = parseCommand(line) else {
        print("Ошибка: незакрытая кавычка или незавершённое экранирование")
        continue
    }

    guard let command = words.first else {
        continue
    }

    let arguments = Array(words.dropFirst())

    switch command {
    case "ls", "cd":
        if arguments.count > 1 {
            print("Ошибка: неверные аргументы команды \(command)")
        } else {
            print("\(command): \(arguments)")
        }

    case "exit":
        if arguments.isEmpty {
            break repl
        }
        print("Ошибка: команда exit не принимает аргументы")

    default:
        print("Ошибка: неизвестная команда \(command)")
    }
}