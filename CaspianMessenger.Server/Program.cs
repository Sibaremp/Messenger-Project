using System.Text;
using CaspianMessenger.Server.Data;
using CaspianMessenger.Server.Helpers;
using CaspianMessenger.Server.Hubs;
using CaspianMessenger.Server.Middleware;
using CaspianMessenger.Server.Services;
using FirebaseAdmin;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using Microsoft.IdentityModel.Tokens;
using Serilog;

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

var builder = WebApplication.CreateBuilder(args);

builder.Host.UseSerilog((context, services, configuration) => configuration
    .ReadFrom.Configuration(context.Configuration)
    .ReadFrom.Services(services)
    .WriteTo.Console());

// Database
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("Default"),
        o => o.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery)));

// Authentication
var jwtKey = builder.Configuration["Jwt:Key"]!;
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey)),
            ValidateIssuer = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidateAudience = true,
            ValidAudience = builder.Configuration["Jwt:Audience"],
            ValidateLifetime = true
        };
        // Allow JWT via query string for SignalR; also validate session is still active
        options.Events = new JwtBearerEvents
        {
            OnMessageReceived = context =>
            {
                var token = context.Request.Query["access_token"];
                var path = context.HttpContext.Request.Path;
                if (!string.IsNullOrEmpty(token) && path.StartsWithSegments("/hub"))
                    context.Token = token;
                return Task.CompletedTask;
            },
            OnTokenValidated = async context =>
            {
                var token = context.SecurityToken as System.IdentityModel.Tokens.Jwt.JwtSecurityToken;
                if (token == null) return;

                // Admin tokens are not tracked in the sessions table — skip the check
                if (token.Claims.Any(c => c.Type == "role" && c.Value == "admin"))
                    return;

                var sessionService = context.HttpContext.RequestServices.GetRequiredService<SessionService>();
                var tokenHash = TokenHashHelper.ComputeSha256(token.RawData);
                var isActive = await sessionService.IsSessionActiveAsync(tokenHash);
                if (!isActive)
                    context.Fail("Session terminated");
            }
        };
    });

builder.Services.AddAuthorization(options =>
{
    // RequireRole works with both the mapped ClaimTypes.Role and the raw "role" claim
    options.AddPolicy("AdminOnly", policy =>
        policy.RequireRole("admin"));
});

// SignalR
builder.Services.AddSignalR();

// CORS
var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? ["*"];
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        if (allowedOrigins.Contains("*"))
            policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod();
        else
            policy.WithOrigins(allowedOrigins).AllowAnyHeader().AllowAnyMethod().AllowCredentials();
    });
});

// Services
builder.Services.AddMemoryCache();
builder.Services.AddScoped<JwtHelper>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<SessionService>();
builder.Services.AddScoped<ChatService>();
builder.Services.AddScoped<MessageService>();
builder.Services.AddScoped<FileService>();
builder.Services.AddScoped<NotificationService>();
builder.Services.AddScoped<PollService>();
builder.Services.AddScoped<ImportService>();
builder.Services.AddSingleton<CallService>();
builder.Services.AddSingleton<FcmService>();
builder.Services.AddSingleton<ProfanityFilter>();
builder.Services.AddSingleton<EncryptionService>();
builder.Services.AddHostedService<PollAutoCloseService>();
builder.Services.AddHostedService<SessionCleanupService>();
builder.Services.AddHostedService<VideoThumbnailMigrationService>();
builder.Services.AddHostedService<ChatAutoCreateService>();

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.AddSecurityDefinition("Bearer", new Microsoft.OpenApi.Models.OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = Microsoft.OpenApi.Models.SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = Microsoft.OpenApi.Models.ParameterLocation.Header
    });
    c.AddSecurityRequirement(new Microsoft.OpenApi.Models.OpenApiSecurityRequirement
    {
        {
            new Microsoft.OpenApi.Models.OpenApiSecurityScheme
            {
                Reference = new Microsoft.OpenApi.Models.OpenApiReference
                {
                    Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            []
        }
    });
});

var app = builder.Build();

// ── Auto-migrate on startup (Docker / CI friendly) ────────────────────────────
// Runs only pending migrations; safe to call every start.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    try
    {
        db.Database.Migrate();
        Log.Information("Database migrations applied successfully");
    }
    catch (Exception ex)
    {
        Log.Fatal(ex, "Failed to apply database migrations — cannot start");
        throw;
    }
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseSerilogRequestLogging();
app.UseCors();
app.UseAuthentication();
app.UseMiddleware<SessionActivityMiddleware>();
app.UseAuthorization();

// Serve uploaded files: expose {ContentRoot}/uploads at /uploads
app.UseStaticFiles();

var uploadsBase = builder.Configuration["FileStorage:BasePath"] ?? "./uploads";
var uploadsFullPath = Path.Combine(app.Environment.ContentRootPath, uploadsBase.TrimStart('.', '/', '\\'));
Directory.CreateDirectory(uploadsFullPath);
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(uploadsFullPath),
    RequestPath = "/uploads"
});

app.MapControllers();
app.MapHub<ChatHub>("/hub/chat");
app.MapHub<CallsHub>("/hub/calls");

app.Run();
