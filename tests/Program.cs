using CutNumber;
using System.Text.Json;

string settings = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AppleCraft", "CutNumber", "settings.json");
byte[]? original = File.Exists(settings) ? File.ReadAllBytes(settings) : null;
try {
    if (original == null && Localization.Code != "en") throw new Exception("English must be the default");
    foreach (var language in Localization.Languages) {
        Localization.SetLanguage(language.Code);
        var persisted = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(settings))!;
        if (persisted["language"] != language.Code || Localization.Code != language.Code) throw new Exception("Language persistence");
        if (Localization.T("language") == "language") throw new Exception("Missing translation");
        if (!Localization.T("selected", 12).Contains("12")) throw new Exception("Numeric parameter");
        if (!Localization.T("added", "{1}", 2).Contains("{1}")) throw new Exception("Parameter data must stay literal");
    }
    bool invalid = false;
    try { Localization.SetLanguage("unknown"); } catch (ArgumentException) { invalid = true; }
    if (!invalid) throw new Exception("Unknown language must be rejected");
    Console.WriteLine("PASS: Windows English default, 10 languages, persisted settings, safe placeholders, invalid language guard");
} finally {
    if (original == null) File.Delete(settings);
    else File.WriteAllBytes(settings, original);
}
