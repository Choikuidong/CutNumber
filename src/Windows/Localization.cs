using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CutNumber;

public sealed record AppLanguage(string Code, string Name);

public static class Localization {
    public static readonly AppLanguage[] Languages = [
        new("en", "English"), new("ko", "한국어"), new("ja", "日本語"), new("zh-Hans", "简体中文"),
        new("es", "Español"), new("fr", "Français"), new("de", "Deutsch"), new("pt", "Português"),
        new("ru", "Русский"), new("ar", "العربية")
    ];
    private static readonly string SettingsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AppleCraft", "CutNumber", "settings.json");
    private static readonly Dictionary<string, Dictionary<string, string>> Messages = LoadMessages();
    public static string Code { get; private set; } = LoadLanguage();

    private static Dictionary<string, Dictionary<string, string>> LoadMessages() {
        using var resource = typeof(Localization).Assembly.GetManifestResourceStream("CutNumber.translations.json")
            ?? throw new InvalidOperationException("Missing translation catalog");
        return JsonSerializer.Deserialize<Dictionary<string, Dictionary<string, string>>>(resource)!;
    }
    private static string LoadLanguage() {
        try {
            var settings = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(SettingsPath));
            if (settings != null && settings.TryGetValue("language", out string? code) && Languages.Any(l => l.Code == code)) return code;
        } catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException) { }
        return "en";
    }
    public static void SetLanguage(string code) {
        if (!Languages.Any(l => l.Code == code)) throw new ArgumentException("Unknown language", nameof(code));
        Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
        string temporary = SettingsPath + "." + Guid.NewGuid() + ".tmp";
        try {
            File.WriteAllText(temporary, JsonSerializer.Serialize(new { language = code }));
            File.Move(temporary, SettingsPath, true);
        } finally { if (File.Exists(temporary)) File.Delete(temporary); }
        Code = code;
    }
    public static string T(string key, params object[] arguments) {
        if (!Messages.TryGetValue(key, out var translations)) return key;
        string text = translations.GetValueOrDefault(Code) ?? translations["en"];
        return Regex.Replace(text, @"\{(\d+)\}", match => {
            int index = int.Parse(match.Groups[1].Value);
            return index < arguments.Length ? Convert.ToString(arguments[index], System.Globalization.CultureInfo.CurrentCulture) ?? "" : match.Value;
        });
    }
}
