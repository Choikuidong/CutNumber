import Foundation
import Combine

struct AppLanguage: Identifiable {
    let id: String
    let name: String
    static let all = [
        AppLanguage(id: "en", name: "English"), AppLanguage(id: "ko", name: "한국어"),
        AppLanguage(id: "ja", name: "日本語"), AppLanguage(id: "zh-Hans", name: "简体中文"),
        AppLanguage(id: "es", name: "Español"), AppLanguage(id: "fr", name: "Français"),
        AppLanguage(id: "de", name: "Deutsch"), AppLanguage(id: "pt", name: "Português"),
        AppLanguage(id: "ru", name: "Русский"), AppLanguage(id: "ar", name: "العربية")
    ]
}

enum Translations {
    static let messages: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "translations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let messages = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            preconditionFailure("Missing translation catalog")
        }
        return messages
    }()
    static var language: String {
        let saved = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "en"
        return AppLanguage.all.contains(where: { $0.id == saved }) ? saved : "en"
    }
}

func T(_ key: String, _ arguments: Any...) -> String {
    let message = Translations.messages[key]?[Translations.language] ?? Translations.messages[key]?["en"] ?? key
    let pattern = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
    let matches = pattern.matches(in: message, range: NSRange(message.startIndex..., in: message))
    var result = message
    for match in matches.reversed() {
        guard let indexRange = Range(match.range(at: 1), in: message),
              let index = Int(message[indexRange]), arguments.indices.contains(index),
              let range = Range(match.range, in: result) else { continue }
        result.replaceSubrange(range, with: String(describing: arguments[index]))
    }
    return result
}

@MainActor final class InterfaceLanguage: ObservableObject {
    static let shared = InterfaceLanguage()
    @Published var code: String = Translations.language {
        didSet {
            UserDefaults.standard.set(code, forKey: "interfaceLanguage")
            NotificationCenter.default.post(name: .interfaceLanguageChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let interfaceLanguageChanged = Notification.Name("CutNumber.interfaceLanguageChanged")
}
