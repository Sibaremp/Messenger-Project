using System.Data;
using System.Text;
using System.Text.Json;
using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Models;
using ExcelDataReader;
using Microsoft.EntityFrameworkCore;

namespace CaspianMessenger.Server.Services;

public class ImportService(AppDbContext db, ILogger<ImportService> logger)
{
    // ── Public entry point ────────────────────────────────────────────────────

    public async Task<(int Added, int Skipped)> ImportPeopleAsync(IFormFile file)
    {
        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        return ext switch
        {
            ".json"          => await ImportFromJsonAsync(file),
            ".xlsx" or ".xls" => await ImportFromExcelAsync(file),
            _ => throw new InvalidOperationException($"Unsupported file format: {ext}")
        };
    }

    // ── JSON ──────────────────────────────────────────────────────────────────

    private async Task<(int Added, int Skipped)> ImportFromJsonAsync(IFormFile file)
    {
        using var stream = file.OpenReadStream();
        var dtos = await JsonSerializer.DeserializeAsync<List<PersonImportDto>>(stream,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        if (dtos == null || dtos.Count == 0) return (0, 0);
        return await PersistPeopleAsync(dtos);
    }

    // ── Excel (.xlsx / .xls) ──────────────────────────────────────────────────

    private async Task<(int Added, int Skipped)> ImportFromExcelAsync(IFormFile file)
    {
        // ExcelDataReader requires this for .xls encoding support
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);

        using var stream = file.OpenReadStream();
        using var reader = ExcelReaderFactory.CreateReader(stream);

        var dataSet = reader.AsDataSet(new ExcelDataSetConfiguration
        {
            UseColumnDataType = false,
            ConfigureDataTable = _ => new ExcelDataTableConfiguration { UseHeaderRow = true }
        });

        if (dataSet.Tables.Count == 0) return (0, 0);

        var table = dataSet.Tables[0];
        var dtos  = new List<PersonImportDto>();

        // Build column name → index map (case-insensitive)
        var colMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        for (var c = 0; c < table.Columns.Count; c++)
            colMap[table.Columns[c].ColumnName] = c;

        string? GetCell(DataRow row, params string[] names)
        {
            foreach (var n in names)
                if (colMap.TryGetValue(n, out var idx) && row[idx] is string s && !string.IsNullOrWhiteSpace(s))
                    return s.Trim();
            return null;
        }

        foreach (DataRow row in table.Rows)
        {
            var firstName = GetCell(row, "firstName", "Имя");
            var lastName  = GetCell(row, "lastName",  "Фамилия");
            var role      = GetCell(row, "role",      "Роль");

            if (string.IsNullOrWhiteSpace(firstName) ||
                string.IsNullOrWhiteSpace(lastName)  ||
                string.IsNullOrWhiteSpace(role))
                continue;

            dtos.Add(new PersonImportDto
            {
                FirstName  = firstName,
                LastName   = lastName,
                MiddleName = GetCell(row, "middleName", "Отчество"),
                Role       = role,
                Group      = GetCell(row, "group", "Группа")
            });
        }

        return await PersistPeopleAsync(dtos);
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    private async Task<(int Added, int Skipped)> PersistPeopleAsync(List<PersonImportDto> dtos)
    {
        // Load existing keys for deduplication (lastName+firstName+middleName, case-insensitive)
        var existingKeys = await db.People
            .Select(p => (p.LastName.ToLower() + "|" + p.FirstName.ToLower() + "|" + (p.MiddleName ?? "").ToLower()))
            .ToHashSetAsync();

        int added = 0, skipped = 0;

        foreach (var dto in dtos)
        {
            var key = dto.LastName.Trim().ToLower()   + "|" +
                      dto.FirstName.Trim().ToLower()  + "|" +
                      (dto.MiddleName ?? "").Trim().ToLower();

            if (existingKeys.Contains(key)) { skipped++; continue; }

            db.People.Add(new Person
            {
                FirstName  = dto.FirstName.Trim(),
                LastName   = dto.LastName.Trim(),
                MiddleName = string.IsNullOrWhiteSpace(dto.MiddleName) ? null : dto.MiddleName.Trim(),
                Role       = NormalizeRole(dto.Role),
                Group      = string.IsNullOrWhiteSpace(dto.Group) ? null : dto.Group.Trim()
            });

            existingKeys.Add(key);
            added++;
        }

        if (added > 0) await db.SaveChangesAsync();

        logger.LogInformation("Import: added={Added}, skipped={Skipped}", added, skipped);
        return (added, skipped);
    }

    private static string NormalizeRole(string raw)
    {
        var r = raw.Trim().ToLowerInvariant();
        // Принимаем "teacher", "teatcher" (частая опечатка) и русские варианты
        if (r.StartsWith("teach") || r.StartsWith("teatch") ||
            r is "преподаватель" or "п" or "пр")
            return "teacher";
        return "student";
    }
}

public class PersonImportDto
{
    public string FirstName  { get; set; } = string.Empty;
    public string LastName   { get; set; } = string.Empty;
    public string? MiddleName { get; set; }
    public string Role       { get; set; } = "student";
    public string? Group     { get; set; }
}
