using System.Text.RegularExpressions;

namespace CaspianMessenger.Server.Services;

/// <summary>
/// Серверный фильтр нецензурной лексики.
/// Заменяет найденные слова на звёздочки той же длины.
/// Список слов задаётся через конфигурацию (ProfanityFilter:Words) —
/// если не задан, используется встроенный список.
/// </summary>
public sealed class ProfanityFilter
{
    private readonly Regex? _regex;

    public ProfanityFilter(IConfiguration config)
    {
        var configured = config.GetSection("ProfanityFilter:Words").Get<string[]>();
        var words = configured is { Length: > 0 } ? configured : BuiltinWords;

        if (words.Length == 0)
        {
            _regex = null;
            return;
        }

        // Паттерн: слово на границе (не-буква или начало/конец строки).
        // Поддерживает русский и латинский алфавит.
        var boundary = @"(?<![а-яёА-ЯЁa-zA-Z0-9])";
        var boundaryEnd = @"(?![а-яёА-ЯЁa-zA-Z0-9])";
        var pattern = boundary
            + "(?:" + string.Join("|", words.Select(Regex.Escape)) + ")"
            + boundaryEnd;

        _regex = new Regex(pattern,
            RegexOptions.IgnoreCase | RegexOptions.Compiled | RegexOptions.CultureInvariant);
    }

    /// <summary>Возвращает текст с цензурой (нецензурные слова заменены на ****).</summary>
    public string Filter(string? text)
    {
        if (string.IsNullOrEmpty(text) || _regex == null)
            return text ?? string.Empty;

        return _regex.Replace(text, m => new string('*', m.Length));
    }

    /// <summary>true если текст содержит нецензурную лексику.</summary>
    public bool HasProfanity(string? text)
        => !string.IsNullOrEmpty(text) && _regex != null && _regex.IsMatch(text);

    // ── Встроенный список ─────────────────────────────────────────────────────
    // Добавьте или уберите слова по необходимости.
    // Для расширения без пересборки используйте ProfanityFilter:Words в appsettings.json.
    private static readonly string[] BuiltinWords =
    [
        "блять", "блядь", "блядство",
        "ебать", "ебёт", "ебут", "ебал", "ебала", "ёб", "еби",
        "хуй", "хуя", "хуе", "хую", "хуём", "хуйня",
        "пизда", "пизды", "пизде", "пиздой", "пиздец", "пиздить",
        "мудак", "мудила", "мудло",
        "сука", "суки", "суке", "сукой",
        "ёбаный", "ёбаная", "ёбан",
        "залупа", "залупу", "залупой",
        "пиздёж", "пиздёт",
        "блять",
        "нахуй", "нахуя", "похуй", "похую",
        "ёб", "ёбнуть", "ёбнул",
        "пиздануть", "пизданул",
        "cock", "fuck", "shit", "bitch", "ass", "cunt", "dick",
    ];
}
