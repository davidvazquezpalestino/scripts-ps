# =========================================================================
#  new-clean-arch-blazor.ps1
#  Powered by David Vázquez Palestino
# =========================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "."
)

$ErrorActionPreference = "Stop"

# ============================================
# 1. INFORMACION BASICA DEL PROYECTO
# ============================================
$ProjectName = Read-Host "Nombre del proyecto"

# =========================
# COMPUTE PORT (deterministic per project name)
# =========================
function Get-DeterministicPort {
    param(
        [string]$Name,
        [int]$Base,
        [int]$Range = 1000
    )
    $hash = 0
    foreach ($c in $Name.ToCharArray()) {
        $hash = ($hash * 31 + [int]$c)
        # Mantener dentro de Int32 evitando overflow
        $hash = $hash -band 0x7FFFFFFF
    }
    return $Base + ($hash % $Range)
}

$HttpPort = Get-DeterministicPort -Name $ProjectName -Base 5000 -Range 1000

# Puertos del host para los contenedores Docker (4 instancias consecutivas por proyecto).
# Se usa el mismo hash determinista para que cada proyecto tenga puertos distintos
# y no siempre sean los mismos al levantarlo.
$DockerBasePort = Get-DeterministicPort -Name $ProjectName -Base 9000 -Range 990
$DockerPort1 = $DockerBasePort
$DockerPort2 = $DockerBasePort + 1
$DockerPort3 = $DockerBasePort + 2
$DockerPort4 = $DockerBasePort + 3

if ($OutputPath -ne "." -and -not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}
if ($OutputPath -ne ".") {
    Set-Location $OutputPath
}

Write-Host "Creating Clean Architecture solution: $ProjectName" -ForegroundColor Cyan
Write-Host "  HTTP -> http://localhost:$HttpPort" -ForegroundColor Cyan
Write-Host "  Docker host ports -> $DockerPort1, $DockerPort2, $DockerPort3, $DockerPort4" -ForegroundColor Cyan

New-Item -ItemType Directory -Path $ProjectName -Force | Out-Null
Set-Location $ProjectName

New-Item -ItemType Directory -Path "src" -Force | Out-Null
New-Item -ItemType Directory -Path "tests" -Force | Out-Null

dotnet new sln -n "$ProjectName"

Write-Host "Creating Blazor Web Assembly project..." -ForegroundColor Yellow
dotnet new blazorwasm -n "$ProjectName.Web" -o "src/Presentation/Client" --no-https

Write-Host "Writing launchSettings.json with deterministic port ($HttpPort)..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "src/Presentation/Client/Properties" -Force | Out-Null
@"
{
  "`$schema": "https://json.schemastore.org/launchsettings.json",
  "profiles": {
    "http": {
      "commandName": "Project",
      "launchBrowser": true,
       "inspectUri": "{wsProtocol}://{url.hostname}:{url.port}/_framework/debug/ws-proxy?browser={browserInspectUri}",
       "applicationUrl": "http://localhost:$HttpPort",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    }
  }
}
"@ | Set-Content "src/Presentation/Client/Properties/launchSettings.json"

Write-Host "Removing Shared folder from Client..." -ForegroundColor Yellow
Remove-Item "src/Presentation/Client/Shared" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Creating Class Library (Domain)..." -ForegroundColor Yellow
dotnet new classlib -n "$ProjectName.Domain" -o "src/Domain"

Write-Host "Creating Class Library (ViewModels)..." -ForegroundColor Yellow
dotnet new classlib -n "$ProjectName.ViewModels" -o "src/Application/ViewModels"

Write-Host "Creating Class Library (Infrastructure)..." -ForegroundColor Yellow
dotnet new classlib -n "$ProjectName.WebApi" -o "src/Infrastructure/WebApi"

Write-Host "Creating Class Library (IoC)..." -ForegroundColor Yellow
dotnet new classlib -n "$ProjectName.IoC" -o "src/Presentation/IoC"

Write-Host "Creating Class Library (Validators)..." -ForegroundColor Yellow
dotnet new classlib -n "$ProjectName.Validators" -o "src/Application/Validators"

Write-Host "Creating Class Library (Views)..." -ForegroundColor Yellow
dotnet new razorclasslib -n "$ProjectName.Views" -o "src/Presentation/Views"

Write-Host "Creating Unit Tests project (xUnit v3)..." -ForegroundColor Yellow
# Asegurar que la plantilla xunit3 esté disponible (paquete xunit.v3.templates)
$templateList = dotnet new list xunit3 2>&1 | Out-String
if ($templateList -notmatch "(?m)^\s*xunit3\b") {
    Write-Host "Instalando plantillas de xUnit.net v3 (xunit.v3.templates)..." -ForegroundColor Yellow
    dotnet new install xunit.v3.templates
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Falló la instalación de xunit.v3.templates. No se puede crear el proyecto de pruebas."
        exit 1
    }
}
# Detectar el TFM que usa el SDK activo leyéndolo del csproj de Domain
# (creado con "dotnet new classlib", que sigue el default del SDK). Así,
# cuando el SDK avance (net11.0, net12.0, ...), el proyecto de pruebas se
# alinea automáticamente sin tocar el script.
$domainCsproj = "src/Domain/$ProjectName.Domain.csproj"
$defaultTfm = $null
if (Test-Path $domainCsproj) {
    $domainCsprojContent = Get-Content -Raw -Path $domainCsproj
    $tfmMatch = [regex]::Match($domainCsprojContent, '<TargetFramework>\s*(net\d+\.\d+)\s*</TargetFramework>')
    if ($tfmMatch.Success) {
        $defaultTfm = $tfmMatch.Groups[1].Value
    }
}
if (-not $defaultTfm) {
    # Fallback: derivar el TFM desde la versión mayor del SDK activo (p. ej. 10.0.100 -> net10.0).
    $sdkVersion = (dotnet --version 2>$null).Trim()
    if ($sdkVersion -match '^(\d+)\.') {
        $defaultTfm = "net$($matches[1]).0"
    } else {
        $defaultTfm = 'net10.0'
    }
}
Write-Host "Using target framework: $defaultTfm" -ForegroundColor Yellow

dotnet new xunit3 -n "$ProjectName.UnitTests" -o "tests/UnitTests" -f $defaultTfm
if ($LASTEXITCODE -ne 0 -or -not (Test-Path "tests/UnitTests")) {
    Write-Error "No se pudo crear el proyecto tests/UnitTests con la plantilla xunit3."
    exit 1
}

# La plantilla xunit3 (xunit.v3.templates) fija net8.0 por defecto y algunas
# versiones ignoran el flag -f. Forzamos el TFM detectado en el .csproj para
# alinear el proyecto de pruebas con el resto de la solución.
$unitTestsCsproj = "tests/UnitTests/$ProjectName.UnitTests.csproj"
if (Test-Path $unitTestsCsproj) {
    $csprojContent = Get-Content -Raw -Path $unitTestsCsproj
    $updatedCsproj = $csprojContent -replace '<TargetFramework>\s*net\d+\.\d+\s*</TargetFramework>', "<TargetFramework>$defaultTfm</TargetFramework>"
    if ($updatedCsproj -ne $csprojContent) {
        Set-Content -Path $unitTestsCsproj -Value $updatedCsproj -NoNewline
    }
}

Write-Host "Removing default Class1.cs files..." -ForegroundColor Yellow
Remove-Item "src/Domain/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Application/ViewModels/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Infrastructure/WebApi/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Presentation/IoC/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Application/Validators/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Presentation/Views/Component1.razor" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Presentation/Views/Component1.razor.css" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Presentation/Views/ExampleJsInterop.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Presentation/Client/App.razor" -Force -ErrorAction SilentlyContinue
Remove-Item "tests/UnitTests/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "tests/UnitTests/UnitTest1.cs" -Force -ErrorAction SilentlyContinue

Remove-Item -Path "src/Presentation/Client/Layout" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "src/Presentation/Client/Pages" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "src/Presentation/Client/wwwroot/lib/bootstrap" -Recurse -Force -ErrorAction SilentlyContinue

# Remove <Nullable>enable</Nullable> from every generated .csproj
Get-ChildItem -Path 'src','tests' -Recurse -Filter *.csproj | ForEach-Object {
    $c = Get-Content -Raw -Path $_.FullName
    $n = $c -replace '(?m)^[ \t]*<Nullable>\s*enable\s*</Nullable>[ \t]*\r?\n', ''
    if ($n -ne $c) { Set-Content -Path $_.FullName -Value $n -NoNewline }
}

Write-Host "Creating folder structure..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "src/Domain/Interfaces" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Domain/Entities" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Domain/ValueObjects" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Domain/Enums" -Force | Out-Null
"" | Set-Content "src/Domain/Interfaces/.gitkeep"
"" | Set-Content "src/Domain/Entities/.gitkeep"
"" | Set-Content "src/Domain/ValueObjects/.gitkeep"
"" | Set-Content "src/Domain/Enums/.gitkeep"
New-Item -ItemType Directory -Path "src/Presentation/Views/Layout" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Presentation/Views/Pages" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Presentation/Views/Shared/Components" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Presentation/Views/Shared/Helper" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Infrastructure/WebApi/Options" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Domain/Interfaces/Auth" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Infrastructure/WebApi/Auth" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Domain/ValueObjects/Auth" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Presentation/Views/Shared/Auth" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Application/ViewModels/Auth" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Application/ViewModels/Base" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Domain/Shared/Errors" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Infrastructure/WebApi/Handlers" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Application/ViewModels/Options" -Force | Out-Null

Write-Host "Adding projects to solution..." -ForegroundColor Yellow
dotnet sln add src/Presentation/Client
dotnet sln add src/Domain
dotnet sln add src/Application/ViewModels
dotnet sln add src/Infrastructure/WebApi
dotnet sln add src/Presentation/IoC
dotnet sln add src/Application/Validators
dotnet sln add src/Presentation/Views
dotnet sln add tests/UnitTests

Write-Host "Adding project references..." -ForegroundColor Yellow
dotnet add src/Application/ViewModels reference src/Domain
dotnet add src/Application/Validators reference src/Domain
dotnet add src/Infrastructure/WebApi reference src/Domain
dotnet add src/Presentation/IoC reference src/Application/ViewModels
dotnet add src/Presentation/IoC reference src/Domain
dotnet add src/Presentation/IoC reference src/Infrastructure/WebApi
dotnet add src/Presentation/IoC reference src/Application/Validators
dotnet add src/Presentation/IoC reference src/Presentation/Views
dotnet add src/Presentation/Views reference src/Application/ViewModels
dotnet add src/Presentation/Client reference src/Presentation/IoC
dotnet add src/Presentation/Client reference src/Presentation/Views
dotnet add src/Presentation/Views reference src/Domain
dotnet add tests/UnitTests reference src/Domain
dotnet add tests/UnitTests reference src/Application/ViewModels
dotnet add tests/UnitTests reference src/Application/Validators

Write-Host "Adding NuGet packages..." -ForegroundColor Yellow
dotnet add src/Application/ViewModels package DependencyInjection.ReflectionExtensions
dotnet add src/Application/ViewModels package FluentValidation
dotnet add src/Application/Validators package DependencyInjection.ReflectionExtensions
dotnet add src/Application/Validators package FluentValidation
dotnet add src/Infrastructure/WebApi package DependencyInjection.ReflectionExtensions
dotnet add src/Presentation/IoC package DependencyInjection.ReflectionExtensions
dotnet add src/Presentation/IoC package FluentValidation
dotnet add src/Presentation/IoC package Microsoft.Extensions.Configuration.Abstractions
dotnet add src/Presentation/IoC package Microsoft.Extensions.Http
dotnet add src/Presentation/Views package Microsoft.AspNetCore.Components.Authorization
dotnet add src/Presentation/Views package LeaderAnalytics.LeaderPivot.Blazor
dotnet add src/Presentation/Client package LeaderAnalytics.LeaderPivot.Blazor
dotnet add src/Infrastructure/WebApi package Microsoft.JSInterop
dotnet add tests/UnitTests package FluentAssertions

Write-Host "Creating GlobalUsings files..." -ForegroundColor Yellow

# Domain GlobalUsings
@"
global using System.Collections.Generic;
"@ | Set-Content "src/Domain/GlobalUsings.cs"

# Application (ViewModels) GlobalUsings
@"
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
global using System.ComponentModel;
global using System.Reflection;
global using System.Runtime.CompilerServices;
global using $ProjectName.Domain.Interfaces.Auth;
global using $ProjectName.Domain.Shared.Errors;
global using $ProjectName.ViewModels.Base;

"@ | Set-Content "src/Application/ViewModels/GlobalUsings.cs"

# Application (ViewModels) DependencyContainer
@"
namespace $ProjectName.ViewModels
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddViewModels(this IServiceCollection services)
        {  
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Application/ViewModels/DependencyContainer.cs"

# DependencyContainers
# Infrastructure DependencyContainer
@"
namespace $ProjectName.WebApi
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddInfrastructure(this IServiceCollection services)
        {  
            services.AddTransient<GlobalExceptionHandler>();
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Infrastructure/WebApi/DependencyContainer.cs"

# Validators DependencyContainer
@"
namespace $ProjectName.Validators
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddValidators(this IServiceCollection services)
        {  
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Application/Validators/DependencyContainer.cs"

# IoC DependencyContainer
@"
namespace $ProjectName.IoC
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddIoC(this IServiceCollection services, IConfiguration configuration, string apiBaseUrl)
        {
            services.Configure<ApiOptions>(configuration.GetSection(ApiOptions.SectionKey));

            services.AddSingleton<$ProjectName.Views.Layout.NavMenuStateService>();

            services.AddViewModels()
                    .AddValidators()
                    .AddInfrastructure();

            services.AddAuthorizationCore();
            services.AddCascadingAuthenticationState();
            services.AddScoped<IJwtTokenService, JwtTokenService>();
            services.AddScoped<AuthenticationStateProvider, JwtAuthenticationStateProvider>();

            services.AddHttpClient("ApiClient", client =>
            {
                client.BaseAddress = new Uri(apiBaseUrl);
                client.Timeout = TimeSpan.FromSeconds(30);
            }).AddHttpMessageHandler<GlobalExceptionHandler>();

            services.AddScoped(sp =>
            {
                IHttpClientFactory factory = sp.GetRequiredService<IHttpClientFactory>();
                return factory.CreateClient("ApiClient");
            });

            return services;
        }
    }
}
"@ | Set-Content "src/Presentation/IoC/DependencyContainer.cs"

# Infrastructure Options
# ApiOptions class in Infrastructure
@"
namespace $ProjectName.WebApi.Options
{
    public class ApiOptions
    {
        public const string SectionKey = nameof(ApiOptions);
        public string BaseUrl { get; set; }
    }
}
"@ | Set-Content "src/Infrastructure/WebApi/Options/ApiOptions.cs"

# Infrastructure GlobalUsings
@"
global using System.Collections.Generic;
global using System.Linq;
global using System.Net;
global using System.Net.Http.Json;
global using System.Reflection;
global using System.Text;
global using System.Text.Json;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.JSInterop;
global using $ProjectName.WebApi.Handlers;
global using $ProjectName.WebApi.Options;
global using $ProjectName.Domain.Interfaces.Auth;
global using $ProjectName.Domain.Shared.Errors;
global using $ProjectName.Domain.ValueObjects.Auth;
"@ | Set-Content "src/Infrastructure/WebApi/GlobalUsings.cs"

# Validators GlobalUsings
@"
global using System.Reflection;
global using Microsoft.Extensions.DependencyInjection;
global using DevKit.Injection.Extensions;
global using FluentValidation;
"@ | Set-Content "src/Application/Validators/GlobalUsings.cs"

# IoC GlobalUsings
@"
global using Microsoft.AspNetCore.Components.Authorization;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Configuration;
global using FluentValidation;
global using $ProjectName.ViewModels;
global using $ProjectName.WebApi;
global using $ProjectName.WebApi.Auth;
global using $ProjectName.WebApi.Handlers;
global using $ProjectName.WebApi.Options;
global using $ProjectName.Validators;
global using $ProjectName.Domain.Interfaces.Auth;
global using $ProjectName.Views.Shared.Auth;
"@ | Set-Content "src/Presentation/IoC/GlobalUsings.cs"

# Client GlobalUsings
@"
global using $ProjectName.IoC;
global using $ProjectName.Views;
global using $ProjectName.WebApi.Handlers;
global using Microsoft.AspNetCore.Components.Web;
global using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Presentation/Client/GlobalUsings.cs"

# Tests GlobalUsings
@"
global using FluentAssertions;
global using Xunit;
"@ | Set-Content "tests/UnitTests/GlobalUsings.cs"

# Client Program.cs update
@"

WebAssemblyHostBuilder builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");

string apiBaseUrl = builder.Configuration["ApiOptions:BaseUrl"] ?? builder.HostEnvironment.BaseAddress;
builder.Services.AddIoC(builder.Configuration, apiBaseUrl);

await builder.Build().RunAsync();
"@ | Set-Content "src/Presentation/Client/Program.cs"

# Client appsettings.json
@"
{
  "ApiOptions": {
    "BaseUrl": "https://localhost:5001"
  }
}
"@ | Set-Content "src/Presentation/Client/wwwroot/appsettings.json"

Remove-Item "src/Presentation/Client/App.razor" -Force -ErrorAction SilentlyContinue

# Index.razor lives in the Views assembly so the Router (AppAssembly = typeof(App).Assembly) can discover it.
@"
@page "/"
@attribute [Authorize]

<PageTitle>Index</PageTitle>

<div class="w-full px-4 md:px-6">
    <div class="bg-white rounded-lg shadow-sm border border-gray-200 my-6">
        <div class="px-4 py-3 border-b border-gray-200 bg-blue-600 text-white rounded-t-lg flex items-center">
            <i class="bi bi-hand-thumbs-up-fill mr-2"></i>
            <h5 class="mb-0 text-lg font-medium">¡Hola, mundo!</h5>
        </div>
        <div class="p-6">
            <p class="text-lg text-gray-700">
                Bienvenido a <strong>$ProjectName</strong>, una app Blazor recién salida del horno
                y con la Regla de la Dependencia apuntando religiosamente hacia adentro.
                <i class="bi bi-bullseye text-red-600"></i>
            </p>

            <ul class="list-none mb-4 space-y-1 text-gray-700">
                <li><i class="bi bi-cup-hot-fill text-yellow-500"></i> Café: <em>opcional pero recomendado</em>.</li>
                <li><i class="bi bi-layers-fill text-green-600"></i> Capas: como una cebolla, pero sin llorar (Onion Architecture approved).</li>
                <li><i class="bi bi-shield-lock-fill text-gray-600"></i> Domain no sabe que existe la base de datos. Y así queremos que siga.</li>
                <li><i class="bi bi-bug-fill text-red-600"></i> Si compila a la primera, revisa que no estés soñando.</li>
            </ul>

            <div class="p-4 rounded-md bg-cyan-50 text-cyan-700 flex items-center mb-0" role="alert">
                <i class="bi bi-info-circle-fill mr-2"></i>
                <span class="text-sm">Borra esta página cuando decidas escribir código de verdad.
                Mientras tanto, disfruta del silencio productivo.</span>
            </div>
        </div>
        <div class="px-6 py-3 bg-gray-50 border-t border-gray-200 rounded-b-lg text-gray-500 flex items-center">
            <i class="bi bi-tools mr-2"></i>
            <span class="text-sm">Generado con <code>new-clean-arch-blazor.ps1</code> · Clean Architecture · Tío Bob approved</span>
        </div>
    </div>
</div>

"@ | Set-Content "src/Presentation/Views/Pages/Index.razor"

# Index.razor.cs code-behind
@"
namespace $ProjectName.Views.Pages;

[Authorize]
public partial class Index : ComponentBase
{
}
"@ | Set-Content "src/Presentation/Views/Pages/Index.razor.cs"

# LoginRequest in Application/ViewModels/Auth
@"
namespace $ProjectName.ViewModels.Auth
{
    public class LoginRequest
    {
        public string UserEmail { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
    }
}
"@ | Set-Content "src/Application/ViewModels/Auth/LoginRequest.cs"

# RegisterRequest in Application/ViewModels/Auth
@"
namespace $ProjectName.ViewModels.Auth
{
    public class RegisterRequest
    {
        public string UserName { get; set; } = string.Empty;
        public string UserEmail { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
    }
}
"@ | Set-Content "src/Application/ViewModels/Auth/RegisterRequest.cs"

# IAuthService in Domain
@"
namespace $ProjectName.Domain.Interfaces.Auth
{
    public interface IAuthService
    {
        Task<string> LoginAsync(string userEmail, string password, CancellationToken cancellationToken = default);
        Task LogoutAsync();
    }
}
"@ | Set-Content "src/Domain/Interfaces/Auth/IAuthService.cs"

# UserSessionInfo in Domain/ValueObjects/Auth
@"
namespace $ProjectName.Domain.ValueObjects.Auth
{
    public class UserSessionInfo
    {
        public string UserId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public IReadOnlyList<string> Roles { get; set; } = Array.Empty<string>();
        public bool IsExpired { get; set; }
    }
}
"@ | Set-Content "src/Domain/ValueObjects/Auth/UserSessionInfo.cs"

# IJwtTokenService in Domain
@"
namespace $ProjectName.Domain.Interfaces.Auth
{
    public interface IJwtTokenService
    {
        event EventHandler TokenChanged;
        Task<string> GetTokenAsync(CancellationToken cancellationToken = default);
        Task SetTokenAsync(string token, CancellationToken cancellationToken = default);
        Task ClearTokenAsync(CancellationToken cancellationToken = default);
        Task<ValueObjects.Auth.UserSessionInfo> GetUserSessionAsync(CancellationToken cancellationToken = default);
    }
}
"@ | Set-Content "src/Domain/Interfaces/Auth/IJwtTokenService.cs"

# JwtTokenService in Infrastructure/WebApi/Auth
@"
namespace $ProjectName.WebApi.Auth
{
    public class JwtTokenService(IJSRuntime jsRuntime) : IJwtTokenService
    {
        private const string TokenKey = "auth_token";

        public event EventHandler TokenChanged;

        public async Task<string> GetTokenAsync(CancellationToken cancellationToken = default)
        {
            return await jsRuntime.InvokeAsync<string>("localStorage.getItem", cancellationToken, TokenKey).ConfigureAwait(false);
        }

        public async Task SetTokenAsync(string token, CancellationToken cancellationToken = default)
        {
            await jsRuntime.InvokeVoidAsync("localStorage.setItem", cancellationToken, TokenKey, token).ConfigureAwait(false);
            OnTokenChanged();
        }

        public async Task ClearTokenAsync(CancellationToken cancellationToken = default)
        {
            await jsRuntime.InvokeVoidAsync("localStorage.removeItem", cancellationToken, TokenKey).ConfigureAwait(false);
            OnTokenChanged();
        }

        public async Task<UserSessionInfo> GetUserSessionAsync(CancellationToken cancellationToken = default)
        {
            string token = await GetTokenAsync(cancellationToken).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(token))
            {
                return new UserSessionInfo { IsExpired = true };
            }

            try
            {
                string[] parts = token.Split('.');
                if (parts.Length != 3)
                {
                    return new UserSessionInfo { IsExpired = true };
                }

                string payload = Base64UrlDecode(parts[1]);
                using JsonDocument document = JsonDocument.Parse(payload);
                JsonElement root = document.RootElement;

                UserSessionInfo session = new UserSessionInfo
                {
                    UserId = GetString(root, "sub") ?? GetString(root, "nameid") ?? string.Empty,
                    Name = GetString(root, "name") ?? GetString(root, "unique_name") ?? string.Empty,
                    Email = GetString(root, "email") ?? string.Empty
                };

                if (root.TryGetProperty("exp", out JsonElement expProperty) && expProperty.TryGetInt64(out long exp))
                {
                    session.IsExpired = DateTimeOffset.UtcNow >= DateTimeOffset.FromUnixTimeSeconds(exp);
                }

                List<string> roles = new List<string>();
                if (root.TryGetProperty("roles", out JsonElement rolesProperty) && rolesProperty.ValueKind == JsonValueKind.Array)
                {
                    foreach (JsonElement role in rolesProperty.EnumerateArray())
                    {
                        if (role.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(role.GetString()))
                        {
                            roles.Add(role.GetString()!);
                        }
                    }
                }
                else if (root.TryGetProperty("role", out JsonElement roleProperty) && roleProperty.ValueKind == JsonValueKind.String)
                {
                    string role = roleProperty.GetString();
                    if (!string.IsNullOrWhiteSpace(role))
                    {
                        roles.Add(role);
                    }
                }
                session.Roles = roles;

                return session;
            }
            catch
            {
                return new UserSessionInfo { IsExpired = true };
            }
        }

        private static string GetString(JsonElement element, string propertyName)
        {
            if (element.TryGetProperty(propertyName, out JsonElement property)
                && property.ValueKind == JsonValueKind.String)
            {
                return property.GetString();
            }

            return null;
        }

        private static string Base64UrlDecode(string input)
        {
            string padded = input.Length % 4 == 0
                ? input
                : input + new string('=', 4 - input.Length % 4);
            string base64 = padded.Replace('-', '+').Replace('_', '/');
            return Encoding.UTF8.GetString(Convert.FromBase64String(base64));
        }

        private void OnTokenChanged()
        {
            TokenChanged?.Invoke(this, EventArgs.Empty);
        }
    }
}
"@ | Set-Content "src/Infrastructure/WebApi/Auth/JwtTokenService.cs"

# AuthWebApi in Infrastructure/WebApi
@"
namespace $ProjectName.WebApi.Auth
{
    public class AuthWebApi(HttpClient httpClient, IJwtTokenService tokenService) : IAuthService
    {
        public async Task<string> LoginAsync(string userEmail, string password, CancellationToken cancellationToken = default)
        {
            // TODO: Implementar llamada real a la API
            // var response = await httpClient.PostAsJsonAsync("api/auth/login", new { userEmail, password }, cancellationToken);
            // response.EnsureSuccessStatusCode();
            // var token = await response.Content.ReadAsStringAsync(cancellationToken);

            // Token simulado mientras no haya backend real.
            string header = Base64UrlEncode(JsonSerializer.Serialize(new { alg = "none", typ = "JWT" }));
            string payload = Base64UrlEncode(JsonSerializer.Serialize(new
            {
                sub = Guid.NewGuid().ToString(),
                name = userEmail.Split('@')[0],
                email = userEmail,
                exp = DateTimeOffset.UtcNow.AddHours(8).ToUnixTimeSeconds(),
                roles = new[] { "User" }
            }));
            string token = $"{header}.{payload}.signature";

            await tokenService.SetTokenAsync(token, cancellationToken).ConfigureAwait(false);
            return token;
        }

        public async Task LogoutAsync()
        {
            await tokenService.ClearTokenAsync().ConfigureAwait(false);
        }

        private static string Base64UrlEncode(string value)
        {
            return Convert.ToBase64String(Encoding.UTF8.GetBytes(value))
                .TrimEnd('=')
                .Replace('+', '-')
                .Replace('/', '_');
        }
    }
}
"@ | Set-Content "src/Infrastructure/WebApi/Auth/AuthWebApi.cs"

# GlobalExceptionHandler in Infrastructure/WebApi/Handlers
@"
namespace $ProjectName.WebApi.Handlers
{
    public class GlobalExceptionHandler : DelegatingHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            HttpResponseMessage response;
            try
            {
                response = await base.SendAsync(request, cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
            {
                throw new GlobalApplicationException(
                    userMessage: $"La solicitud tardó demasiado tiempo. Intenta nuevamente. {exception.Message}",
                    kind: ErrorKind.Timeout,
                    statusCode: (int)HttpStatusCode.RequestTimeout,
                    isRetryable: true,
                    innerException: exception);
            }
            catch (HttpRequestException exception)
            {
                throw new GlobalApplicationException(
                    userMessage: $"No fue posible conectar con el servicio. Verifica tu conexión e intenta nuevamente. {exception.Message}",
                    kind: ErrorKind.Network,
                    statusCode: exception.StatusCode is null ? null : (int)exception.StatusCode.Value,
                    isRetryable: true,
                    innerException: exception);
            }

            if (response.IsSuccessStatusCode)
            {
                return response;
            }

            string body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            int statusCode = (int)response.StatusCode;
            string message = BuildMessage(response.StatusCode, body);
            bool isTransient = response.StatusCode is HttpStatusCode.RequestTimeout
                or HttpStatusCode.TooManyRequests
                or HttpStatusCode.BadGateway
                or HttpStatusCode.ServiceUnavailable
                or HttpStatusCode.GatewayTimeout
                || statusCode >= 500;

            response.Dispose();

            throw new GlobalApplicationException(
                userMessage: message,
                kind: MapErrorKind(statusCode),
                statusCode: statusCode,
                isRetryable: isTransient);
        }

        private static string BuildMessage(HttpStatusCode statusCode, string responseBody)
        {
            string apiMessage = TryGetApiMessage(responseBody);
            if (!string.IsNullOrWhiteSpace(apiMessage))
            {
                return apiMessage;
            }

            return statusCode switch
            {
                HttpStatusCode.BadRequest => "La solicitud contiene información inválida.",
                HttpStatusCode.Unauthorized => "Tu sesión ha expirado o no es válida. Inicia sesión nuevamente.",
                HttpStatusCode.Forbidden => "No tienes permisos para realizar esta acción.",
                HttpStatusCode.NotFound => "No se encontró el recurso solicitado.",
                HttpStatusCode.Conflict => "La operación no pudo completarse porque existe un conflicto con la información actual.",
                HttpStatusCode.UnprocessableEntity => "No fue posible procesar la información enviada.",
                HttpStatusCode.TooManyRequests => "Se realizaron demasiadas solicitudes. Espera un momento e intenta nuevamente.",
                HttpStatusCode.BadGateway or HttpStatusCode.ServiceUnavailable or HttpStatusCode.GatewayTimeout =>
                    "El servicio no está disponible temporalmente. Intenta nuevamente más tarde.",
                _ when (int)statusCode >= 500 =>
                    "El servicio presentó un error inesperado. Intenta nuevamente más tarde.",
                _ => $"La solicitud no pudo completarse (código {(int)statusCode})."
            };
        }

        private static string TryGetApiMessage(string responseBody)
        {
            if (string.IsNullOrWhiteSpace(responseBody))
            {
                return null;
            }

            try
            {
                using JsonDocument document = JsonDocument.Parse(responseBody);
                JsonElement root = document.RootElement;
                if (root.ValueKind != JsonValueKind.Object)
                {
                    return null;
                }

                foreach (string propertyName in new[] { "detail", "message", "error", "title" })
                {
                    if (root.TryGetProperty(propertyName, out JsonElement property)
                        && property.ValueKind == JsonValueKind.String
                        && !string.IsNullOrWhiteSpace(property.GetString()))
                    {
                        return property.GetString();
                    }
                }

                if (root.TryGetProperty("errors", out JsonElement errors)
                    && errors.ValueKind == JsonValueKind.Object)
                {
                    List<string> messages = [];
                    foreach (JsonProperty error in errors.EnumerateObject())
                    {
                        if (error.Value.ValueKind == JsonValueKind.Array)
                        {
                            messages.AddRange(error.Value.EnumerateArray()
                                .Where(item => item.ValueKind == JsonValueKind.String)
                                .Select(item => item.GetString())
                                .Where(item => !string.IsNullOrWhiteSpace(item)));
                        }
                    }

                    return string.Join(" ", messages.Take(3));
                }
            }
            catch (JsonException)
            {
            }

            return null;
        }

        private static ErrorKind MapErrorKind(int statusCode)
        {
            return statusCode switch
            {
                401 => ErrorKind.Unauthorized,
                403 => ErrorKind.Forbidden,
                404 => ErrorKind.NotFound,
                408 => ErrorKind.Timeout,
                409 => ErrorKind.Conflict,
                429 => ErrorKind.Server,
                >= 500 => ErrorKind.Server,
                _ => ErrorKind.Unexpected
            };
        }
    }
}
"@ | Set-Content "src/Infrastructure/WebApi/Handlers/GlobalExceptionHandler.cs"

# ErrorKind in Domain/Shared/Errors
@"
namespace $ProjectName.Domain.Shared.Errors
{
    public enum ErrorKind
    {
        Unknown,
        Network,
        Timeout,
        Unauthorized,
        Forbidden,
        NotFound,
        Conflict,
        Validation,
        Server,
        Unexpected
    }
}
"@ | Set-Content "src/Domain/Shared/Errors/ErrorKind.cs"

# GlobalApplicationException in Domain/Shared/Errors
@"
namespace $ProjectName.Domain.Shared.Errors
{
    public class GlobalApplicationException(
        string userMessage,
        ErrorKind kind,
        int? statusCode = null,
        bool isRetryable = false,
        Exception innerException = null) : Exception(userMessage, innerException)
    {
        public string UserMessage { get; } = userMessage;
        public ErrorKind Kind { get; } = kind;
        public int? StatusCode { get; } = statusCode;
        public bool IsRetryable { get; } = isRetryable;
    }
}
"@ | Set-Content "src/Domain/Shared/Errors/GlobalApplicationException.cs"

# ViewModelBase in Application/ViewModels/Base
@"
namespace $ProjectName.ViewModels.Base
{
    public class ViewModelBase(int pageSize = 25) : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;

        /// <summary>
        /// Indica si el ViewModel está ejecutando una operación asíncrona.
        /// </summary>
        public bool IsLoading
        {
            get;
            set
            {
                if (field == value)
                {
                    return;
                }

                field = value;
                OnPropertyChanged();
            }
        }

        /// <summary>
        /// Obtiene la información estructurada del último error procesado por el ViewModel.
        /// </summary>
        public GlobalApplicationException Error
        {
            get;
            protected set
            {
                if (Equals(field, value))
                {
                    return;
                }

                field = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(ErrorMessage));
            }
        }

        /// <summary>
        /// Obtiene el mensaje seguro para el usuario del último error procesado.
        /// </summary>
        public string ErrorMessage => Error?.UserMessage;

        /// <summary>
        /// Obtiene o establece el número de la página actual. La primera página es 1.
        /// </summary>
        public virtual int CurrentPage
        {
            get;
            set
            {
                if (field == value)
                {
                    return;
                }

                field = value;
                OnPropertyChanged();
            }
        } = 1;

        /// <summary>
        /// Obtiene o establece la cantidad de elementos solicitados por página.
        /// </summary>
        public virtual int PageSize
        {
            get;
            set
            {
                if (field == value)
                {
                    return;
                }

                field = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(PageCount));
            }
        } = pageSize;

        /// <summary>
        /// Obtiene o establece la cantidad total de elementos disponibles.
        /// </summary>
        public virtual int TotalCount
        {
            get;
            set
            {
                if (field == value)
                {
                    return;
                }

                field = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(PageCount));
            }
        }

        /// <summary>
        /// Obtiene la cantidad total de páginas informada por el origen de datos.
        /// </summary>
        public int TotalPages
        {
            get;
            protected set
            {
                if (field == value)
                {
                    return;
                }

                field = value;
                OnPropertyChanged();
            }
        }

        /// <summary>
        /// Obtiene la cantidad de páginas calculada a partir de <see cref="TotalCount"/>
        /// y <see cref="PageSize"/>.
        /// </summary>
        public virtual int PageCount => (int)Math.Ceiling((double)TotalCount / PageSize);

        protected void ClearError() => Error = null;

        protected void HandleException(Exception exception, Action resetData = null)
        {
            resetData?.Invoke();

            Error = exception is GlobalApplicationException applicationException
                ? applicationException
                : new GlobalApplicationException(
                    "Ocurrió un error inesperado. Intenta nuevamente.",
                    ErrorKind.Unexpected);
        }

        protected static ErrorKind MapErrorKind(int? statusCode)
        {
            if (statusCode is null)
            {
                return ErrorKind.Unexpected;
            }

            return statusCode.Value switch
            {
                401 => ErrorKind.Unauthorized,
                403 => ErrorKind.Forbidden,
                404 => ErrorKind.NotFound,
                408 => ErrorKind.Timeout,
                409 => ErrorKind.Conflict,
                429 => ErrorKind.Server,
                >= 500 => ErrorKind.Server,
                _ => ErrorKind.Unexpected
            };
        }

        protected void OnPropertyChanged([CallerMemberName] string propertyName = "") =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
"@ | Set-Content "src/Application/ViewModels/Base/ViewModelBase.cs"

# ILoginViewModel in Application/ViewModels/Auth
@"
namespace $ProjectName.ViewModels.Auth
{
    public interface ILoginViewModel
    {
        LoginRequest Request { get; set; }
        bool IsLoading { get; set; }
        string ErrorMessage { get; }

        Task<string> SubmitAsync();
        Task LogoutAsync();
    }
}
"@ | Set-Content "src/Application/ViewModels/Auth/ILoginViewModel.cs"

# LoginViewModel in Application/ViewModels/Auth
@"
namespace $ProjectName.ViewModels.Auth
{
    public class LoginViewModel(IAuthService authService) : ViewModelBase(), ILoginViewModel
    {
        public LoginRequest Request { get; set; } = new();

        public async Task<string> SubmitAsync()
        {
            IsLoading = true;
            ClearError();

            try
            {
                return await authService.LoginAsync(Request.UserEmail, Request.Password);
            }
            catch (Exception ex)
            {
                HandleException(ex);
                return null;
            }
            finally
            {
                IsLoading = false;
            }
        }

        public async Task LogoutAsync()
        {
            IsLoading = true;
            try
            {
                await authService.LogoutAsync();
            }
            finally
            {
                IsLoading = false;
            }
        }
    }
}
"@ | Set-Content "src/Application/ViewModels/Auth/LoginViewModel.cs"

# Login.razor in Views/Pages
@"
@page "/login"
@inject ILoginViewModel ViewModel
@inject NavigationManager Navigation

<PageTitle>Iniciar sesión</PageTitle>

<div class="flex flex-col flex-1 justify-center items-center w-full pt-8 pb-6">
    <div class="bg-white rounded-lg shadow-sm border border-blue-600 p-6" style="max-width: 420px; width: 100%;">
        <div class="text-center mb-4">
            <span class="inline-flex items-center justify-center rounded-full bg-blue-600 bg-opacity-10 text-blue-600 mb-2"
                  style="width: 56px; height: 56px;">
                <i class="bi bi-person-lock text-2xl" aria-hidden="true"></i>
            </span>
            <h1 class="text-xl font-semibold mb-0">Iniciar sesión</h1>
            <p class="text-gray-500 text-sm mb-0">$ProjectName</p>
        </div>

        <EditForm Model="@ViewModel.Request" OnValidSubmit="@SubmitAsync" FormName="loginForm">
            <div class="mb-4">
                <label for="loginEmail" class="block text-sm font-semibold text-gray-700 mb-1.5">User Email</label>
                <div class="relative">
                    <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                        <i class="bi bi-envelope text-gray-400" aria-hidden="true"></i>
                    </div>
                    <InputText id="loginEmail"
                               type="email"
                               class="block w-full pl-10 pr-4 py-3 bg-gray-50 border border-gray-300 rounded-lg text-gray-900 placeholder-gray-400 text-sm transition duration-200 ease-in-out focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-500/20 focus:outline-none disabled:opacity-60 disabled:cursor-not-allowed"
                               placeholder="nombre@empresa.com"
                               @bind-Value="ViewModel.Request.UserEmail"
                               disabled="@ViewModel.IsLoading" />
                </div>
            </div>

            <div class="mb-4">
                <label for="loginPassword" class="block text-sm font-semibold text-gray-700 mb-1.5">Password</label>
                <div class="relative flex">
                    <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                        <i class="bi bi-lock text-gray-400" aria-hidden="true"></i>
                    </div>
                    <InputText id="loginPassword"
                               type="@LoginPasswordType"
                               class="block w-full pl-10 pr-12 py-3 bg-gray-50 border border-gray-300 rounded-lg text-gray-900 placeholder-gray-400 text-sm transition duration-200 ease-in-out focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-500/20 focus:outline-none disabled:opacity-60 disabled:cursor-not-allowed"
                               placeholder="••••••••"
                               @bind-Value="ViewModel.Request.Password"
                               disabled="@ViewModel.IsLoading" />
                    <button type="button"
                            class="absolute inset-y-0 right-0 px-3 flex items-center justify-center text-gray-500 hover:text-blue-600 transition duration-200 rounded-r-lg"
                            @onclick="ToggleLoginPasswordVisibility"
                            tabindex="-1"
                            title="@(IsLoginPasswordVisible ? "Ocultar contraseña" : "Mostrar contraseña")"
                            aria-label="@(IsLoginPasswordVisible ? "Ocultar contraseña" : "Mostrar contraseña")">
                        <i class="bi @(IsLoginPasswordVisible ? "bi-eye-slash" : "bi-eye")" aria-hidden="true"></i>
                    </button>
                </div>
            </div>

            @if (!string.IsNullOrEmpty(ViewModel.ErrorMessage))
            {
                <div class="bg-red-50 text-red-700 p-4 rounded-md flex items-start gap-2 py-2" role="alert">
                    <i class="bi bi-exclamation-triangle-fill" aria-hidden="true"></i>
                    <span class="text-sm">@ViewModel.ErrorMessage</span>
                </div>
            }

            <button type="submit"
                    class="inline-flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 text-white bg-blue-600 hover:bg-blue-700 focus:ring-blue-500 w-full flex justify-center items-center gap-2"
                    disabled="@ViewModel.IsLoading">
                @if (ViewModel.IsLoading)
                {
                    <span class="animate-spin h-4 w-4 border-2 border-current border-t-transparent rounded-full" role="status" aria-hidden="true"></span>
                    <span>Iniciando sesión...</span>
                }
                else
                {
                    <span>Iniciar sesión</span>
                }
            </button>
        </EditForm>

        <div class="mt-3 text-center">
            <a href="registro" class="text-blue-600 hover:text-blue-800 underline text-sm">¿No tienes cuenta? Regístrate</a>
        </div>
    </div>
</div>
"@ | Set-Content "src/Presentation/Views/Pages/Login.razor"

# Login.razor.cs code-behind
@"
namespace $ProjectName.Views.Pages;

public partial class Login : ComponentBase
{
    private bool IsLoginPasswordVisible { get; set; }
    private string LoginPasswordType => IsLoginPasswordVisible ? "text" : "password";

    private async Task SubmitAsync()
    {
        string token = await ViewModel.SubmitAsync();
        if (!string.IsNullOrWhiteSpace(token))
        {
            Navigation.NavigateTo("/");
        }
    }

    private void ToggleLoginPasswordVisibility()
    {
        IsLoginPasswordVisible = !IsLoginPasswordVisible;
    }
}
"@ | Set-Content "src/Presentation/Views/Pages/Login.razor.cs"

# Register.razor in Views/Pages
@"
@page "/registro"
@inject NavigationManager Navigation

<PageTitle>Registro de usuario</PageTitle>

<div class="flex flex-col justify-center items-center w-full px-4 pt-8 pb-6">
    <div class="bg-white rounded-lg shadow-sm w-full p-6" style="max-width: 420px; background: linear-gradient(135deg, #ffffff 0%, #f8f9fa 100%); border: 1px solid #0d6efd;">
        <div class="text-center mb-4">
            <span class="inline-flex items-center justify-center rounded-full bg-green-600 bg-opacity-10 text-green-600 mb-2"
                  style="width: 56px; height: 56px;">
                <i class="bi bi-person-plus text-2xl" aria-hidden="true"></i>
            </span>
            <h1 class="text-xl font-semibold mb-0">Crear cuenta</h1>
            <p class="text-gray-500 text-sm mb-0">$ProjectName</p>
        </div>

        <EditForm Model="@RegisterRequest" OnValidSubmit="@SubmitAsync" FormName="registerForm">
            <div class="mb-4">
                <label for="registerName" class="block text-sm font-semibold text-gray-700 mb-1.5">Nombre</label>
                <div class="relative">
                    <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                        <i class="bi bi-person text-gray-400" aria-hidden="true"></i>
                    </div>
                    <InputText id="registerName"
                               type="text"
                               class="block w-full pl-10 pr-4 py-3 bg-gray-50 border border-gray-300 rounded-lg text-gray-900 placeholder-gray-400 text-sm transition duration-200 ease-in-out focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-500/20 focus:outline-none disabled:opacity-60 disabled:cursor-not-allowed"
                               placeholder="Tu nombre"
                               @bind-Value="RegisterRequest.UserName"
                               disabled="@IsLoading" />
                </div>
            </div>

            <div class="mb-4">
                <label for="registerEmail" class="block text-sm font-semibold text-gray-700 mb-1.5">Correo electrónico</label>
                <div class="relative">
                    <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                        <i class="bi bi-envelope text-gray-400" aria-hidden="true"></i>
                    </div>
                    <InputText id="registerEmail"
                               type="email"
                               class="block w-full pl-10 pr-4 py-3 bg-gray-50 border border-gray-300 rounded-lg text-gray-900 placeholder-gray-400 text-sm transition duration-200 ease-in-out focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-500/20 focus:outline-none disabled:opacity-60 disabled:cursor-not-allowed"
                               placeholder="nombre@empresa.com"
                               @bind-Value="RegisterRequest.UserEmail"
                               disabled="@IsLoading" />
                </div>
            </div>

            <div class="mb-4">
                <label for="registerPassword" class="block text-sm font-semibold text-gray-700 mb-1.5">Contraseña</label>
                <div class="relative flex">
                    <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                        <i class="bi bi-lock text-gray-400" aria-hidden="true"></i>
                    </div>
                    <InputText id="registerPassword"
                               type="@RegisterPasswordType"
                               class="block w-full pl-10 pr-12 py-3 bg-gray-50 border border-gray-300 rounded-lg text-gray-900 placeholder-gray-400 text-sm transition duration-200 ease-in-out focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-500/20 focus:outline-none disabled:opacity-60 disabled:cursor-not-allowed"
                               placeholder="••••••••"
                               @bind-Value="RegisterRequest.Password"
                               disabled="@IsLoading" />
                    <button type="button"
                            class="absolute inset-y-0 right-0 px-3 flex items-center justify-center text-gray-500 hover:text-blue-600 transition duration-200 rounded-r-lg"
                            @onclick="ToggleRegisterPasswordVisibility"
                            tabindex="-1"
                            title="@(IsRegisterPasswordVisible ? "Ocultar contraseña" : "Mostrar contraseña")"
                            aria-label="@(IsRegisterPasswordVisible ? "Ocultar contraseña" : "Mostrar contraseña")">
                        <i class="bi @(IsRegisterPasswordVisible ? "bi-eye-slash" : "bi-eye")" aria-hidden="true"></i>
                    </button>
                </div>
            </div>

            <div class="mb-4">
                <label for="registerConfirmPassword" class="block text-sm font-semibold text-gray-700 mb-1.5">Confirmar contraseña</label>
                <div class="relative flex">
                    <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                        <i class="bi bi-lock text-gray-400" aria-hidden="true"></i>
                    </div>
                    <InputText id="registerConfirmPassword"
                               type="@ConfirmPasswordType"
                               class="block w-full pl-10 pr-12 py-3 bg-gray-50 border border-gray-300 rounded-lg text-gray-900 placeholder-gray-400 text-sm transition duration-200 ease-in-out focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-500/20 focus:outline-none disabled:opacity-60 disabled:cursor-not-allowed"
                               placeholder="••••••••"
                               @bind-Value="ConfirmPassword"
                               disabled="@IsLoading" />
                    <button type="button"
                            class="absolute inset-y-0 right-0 px-3 flex items-center justify-center text-gray-500 hover:text-blue-600 transition duration-200 rounded-r-lg"
                            @onclick="ToggleConfirmPasswordVisibility"
                            tabindex="-1"
                            title="@(IsConfirmPasswordVisible ? "Ocultar contraseña" : "Mostrar contraseña")"
                            aria-label="@(IsConfirmPasswordVisible ? "Ocultar contraseña" : "Mostrar contraseña")">
                        <i class="bi @(IsConfirmPasswordVisible ? "bi-eye-slash" : "bi-eye")" aria-hidden="true"></i>
                    </button>
                </div>
            </div>

            @if (!string.IsNullOrEmpty(Message))
            {
                <div class="@(IsSuccess ? "bg-green-50 text-green-700" : "bg-red-50 text-red-700") p-4 rounded-md flex items-start gap-2 py-2" role="alert">
                    <i class="bi @(IsSuccess ? "bi-check-circle-fill" : "bi-exclamation-triangle-fill")" aria-hidden="true"></i>
                    <span class="text-sm">@Message</span>
                </div>
            }

            <button type="submit"
                    class="inline-flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 text-white bg-green-600 hover:bg-green-700 focus:ring-green-500 w-full flex justify-center items-center gap-2"
                    disabled="@IsLoading">
                @if (IsLoading)
                {
                    <span class="animate-spin h-4 w-4 border-2 border-current border-t-transparent rounded-full" role="status" aria-hidden="true"></span>
                    <span>Registrando...</span>
                }
                else
                {
                    <span>Registrarse</span>
                }
            </button>
        </EditForm>

        <div class="mt-3 text-center">
            <a href="login" class="text-blue-600 hover:text-blue-800 underline text-sm">¿Ya tienes cuenta? Inicia sesión</a>
        </div>
    </div>
</div>
"@ | Set-Content "src/Presentation/Views/Pages/Register.razor"

# Register.razor.cs code-behind
@"
namespace $ProjectName.Views.Pages;

public partial class Register : ComponentBase
{
    private RegisterRequest RegisterRequest { get; set; } = new();
    private string ConfirmPassword { get; set; } = string.Empty;
    private bool IsLoading { get; set; }
    private bool IsSuccess { get; set; }
    private string Message { get; set; }

    private bool IsRegisterPasswordVisible { get; set; }
    private string RegisterPasswordType => IsRegisterPasswordVisible ? "text" : "password";

    private bool IsConfirmPasswordVisible { get; set; }
    private string ConfirmPasswordType => IsConfirmPasswordVisible ? "text" : "password";

    private async Task SubmitAsync()
    {
        IsLoading = true;
        Message = null;
        IsSuccess = false;

        try
        {
            if (RegisterRequest.Password != ConfirmPassword)
            {
                Message = "Las contraseñas no coinciden.";
                return;
            }

            // TODO: Llamar al servicio de registro real
            await Task.Delay(500);
            IsSuccess = true;
            Message = "Registro exitoso. Redirigiendo al inicio de sesión...";
            Navigation.NavigateTo("/login");
        }
        catch (Exception ex)
        {
            Message = ex.Message;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private void ToggleRegisterPasswordVisibility()
    {
        IsRegisterPasswordVisible = !IsRegisterPasswordVisible;
    }

    private void ToggleConfirmPasswordVisibility()
    {
        IsConfirmPasswordVisible = !IsConfirmPasswordVisible;
    }
}
"@ | Set-Content "src/Presentation/Views/Pages/Register.razor.cs"

# Client _Imports.razor update
@"
@using Microsoft.AspNetCore.Components.Web
"@ | Set-Content "src/Presentation/Client/_Imports.razor"

# Client index.html update
$content = Get-Content "src/Presentation/Client/wwwroot/index.html" -Raw
$content = $content -replace "<link href=`"$ProjectName.Web.styles.css`" rel=`"stylesheet`" />", @"
<script src="https://cdn.tailwindcss.com"></script>
<link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet" />
<link href="_content/LeaderAnalytics.LeaderPivot.Blazor/leader-pivot.css" rel="stylesheet" />
"@

$content | Set-Content "src/Presentation/Client/wwwroot/index.html"

# Replace default app.css with a Tailwind-only version.
$appCssPath = "src/Presentation/Client/wwwroot/css/app.css"
@"
html, body {
    font-family: 'Segoe UI', sans-serif;
    font-size: 14px;
}

h1:focus {
    outline: none;
}

code {
    color: #c02d76;
}

#blazor-error-ui {
    color-scheme: light only;
    background: lightyellow;
    bottom: 0;
    box-shadow: 0 -1px 2px rgba(0, 0, 0, 0.2);
    box-sizing: border-box;
    display: none;
    left: 0;
    padding: 0.6rem 1.25rem 0.7rem 1.25rem;
    position: fixed;
    width: 100%;
    z-index: 1000;
}

    #blazor-error-ui .dismiss {
        cursor: pointer;
        position: absolute;
        right: 0.75rem;
        top: 0.5rem;
    }

.blazor-error-boundary {
    background: url(data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNTYiIGhlaWdodD0iNDkiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgeG1sbnM6eGxpbms9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkveGxpbmsiIG92ZXJmbG93PSJoaWRkZW4iPjxkZWZzPjxjbGlwUGF0aCBpZD0iY2xpcDAiPjxyZWN0IHg9IjIzNSIgeT0iNTEiIHdpZHRoPSI1NiIgaGVpZ2h0PSI0OSIvPjwvY2xpcFBhdGg+PC9kZWZzPjxnIGNsaXAtcGF0aD0idXJsKCNjbGlwMCkiIHRyYW5zZm9ybT0idHJhbnNsYXRlKC0yMzUgLTUxKSI+PHBhdGggZD0iTTI2My41MDYgNTFDMjY0LjcxNyA1MSAyNjUuODEzIDUxLjQ4MzcgMjY2LjYwNiA1Mi4yNjU4TDI2Ny4wNTIgNTIuNzk4NyAyNjcuNTM5IDUzLjYyODMgMjkwLjE4NSA5Mi4xODMxIDI5MC41NDUgOTIuNzk1IDI5MC42NTYgOTIuOTk2QzI5MC44NzcgOTMuNTEzIDI5MSA5NC4wODE1IDI5MSA5NC42NzgyIDI5MSA5Ny4wNjUxIDI4OS4wMzggOTkgMjg2LjYxNyA5OUwyNDAuMzgzIDk5QzIzNy45NjMgOTkgMjM2IDk3LjA2NTEgMjM2IDk0LjY3ODIgMjM2IDk0LjM3OTkgMjM2LjAzMSA5NC4wODg2IDIzNi4wODkgOTMuODA3MkwyMzYuMzM4IDkzLjAxNjIgMjM2Ljg1OCA5Mi4xMzE0IDI1OS40NzMgNTMuNjI5NCAyNTkuOTYxIDUyLjc5ODUgMjYwLjQwNyA1Mi4yNjU4QzI2MS4yIDUxLjQ4MzcgMjYyLjI5NiA1MSAyNjMuNTA2IDUxWk0yNjMuNTg2IDY2LjAxODNDMjYwLjczNyA2Ni4wMTgzIDI1OS4zMTMgNjcuMTI0NSAyNTkuMzEzIDY5LjMzNyAyNTkuMzEzIDY5LjYxMDIgMjU5LjMzMiA2OS44NjA4IDI1OS4zNzEgNzAuMDg4N0wyNjEuNzk1IDg0LjAxNjEgMjY1LjM4IDg0LjAxNjEgMjY3LjgyMSA2OS43NDc1QzI2Ny44NiA2OS43MzA5IDI2Ny44NzkgNjkuNTg3NyAyNjcuODc5IDY5LjMxNzkgMjY3Ljg3OSA2Ny4xMTgyIDI2Ni40NDggNjYuMDE4MyAyNjMuNTg2IDY2LjAxODNaTTI2My41NzYgODYuMDU0N0MyNjEuMDQ5IDg2LjA1NDcgMjU5Ljc4NiA4Ny4zMDA1IDI1OS43ODYgODkuNzkyMSAyNTkuNzg2IDkyLjI4MzcgMjYxLjA0OSA5My41Mjk1IDI2My41NzYgOTMuNTI5NSAyNjYuMTE2IDkzLjUyOTUgMjY3LjM4NyA5Mi4yODM3IDI2Ny4zODcgODkuNzkyMSAyNjcuMzg3IDg3LjMwMDUgMjY2LjExNiA4Ni4wNTQ3IDI2My41NzYgODYuMDU0N1oiIGZpbGw9IiNGRkU1MDAiIGZpbGwtcnVsZT0iZXZlbm9kZCIvPjwvZz48L3N2Zz4=) no-repeat 1rem/1.8rem, #b32121;
    padding: 1rem 1rem 1rem 3.7rem;
    color: white;
}

    .blazor-error-boundary::after {
        content: "An error has occurred."
    }

.loading-progress {
    position: absolute;
    display: block;
    width: 8rem;
    height: 8rem;
    inset: 20vh 0 auto 0;
    margin: 0 auto 0 auto;
}

    .loading-progress circle {
        fill: none;
        stroke: #e0e0e0;
        stroke-width: 0.6rem;
        transform-origin: 50% 50%;
        transform: rotate(-90deg);
    }

        .loading-progress circle:last-child {
            stroke: #2563eb;
            stroke-dasharray: calc(3.141 * var(--blazor-load-percentage, 0%) * 0.8), 500%;
            transition: stroke-dasharray 0.05s ease-in-out;
        }

.loading-progress-text {
    position: absolute;
    text-align: center;
    font-weight: bold;
    inset: calc(20vh + 3.25rem) 0 auto 0.2rem;
}

    .loading-progress-text:after {
        content: var(--blazor-load-percentage-text, "Loading");
    }
"@ | Set-Content -Path $appCssPath -NoNewline

# Views _Imports.razor
@"
@using Microsoft.AspNetCore.Components
@using Microsoft.AspNetCore.Components.Forms
@using Microsoft.Extensions.DependencyInjection
@using System.Net.Http.Json
@using Microsoft.AspNetCore.Components.Web
@using $ProjectName.Views.Layout
@using $ProjectName.Views.Shared.Components
@using $ProjectName.Views.Shared.Helper
@using Microsoft.AspNetCore.Components.Routing
@using Microsoft.AspNetCore.Components.Authorization
@using $ProjectName.ViewModels.Auth
@using $ProjectName.Domain.Interfaces.Auth
@using $ProjectName.Views.Shared.Auth
@using LeaderAnalytics.LeaderPivot.Blazor

"@ | Set-Content "src/Presentation/Views/_Imports.razor"

# Views GlobalUsings.cs
@"
global using $ProjectName.Domain.Interfaces.Auth;
global using $ProjectName.Domain.ValueObjects.Auth;
global using $ProjectName.ViewModels.Auth;
global using $ProjectName.Views.Layout;
global using $ProjectName.Views.Shared.Auth;
global using $ProjectName.Views.Shared.Helper;
global using Microsoft.AspNetCore.Components;
global using Microsoft.AspNetCore.Authorization;
global using Microsoft.AspNetCore.Components.Authorization;
global using Microsoft.AspNetCore.Components.Routing;
global using System;
global using System.Collections.Generic;
global using System.Globalization;
global using System.Security.Claims;
global using System.Text;
global using System.Text.Json;
"@ | Set-Content "src/Presentation/Views/GlobalUsings.cs"

# App.razor in Views root
@"
<CascadingAuthenticationState>
    <Router AppAssembly="@typeof(App).Assembly">
        <Found Context="routeData">
            <AuthorizeRouteView RouteData="@routeData" DefaultLayout="@typeof(MainLayout)">
                <NotAuthorized>
                    @if (context.User.Identity?.IsAuthenticated != true)
                    {
                        <RedirectToLogin />
                    }
                    else
                    {
                        <div class="w-full px-4 md:px-6">
                            <div class="bg-yellow-50 text-yellow-700 p-4 rounded-md flex items-center gap-2 my-4" role="alert">
                                <i class="bi bi-exclamation-triangle-fill" aria-hidden="true"></i>
                                <span>No tienes permisos para ver este contenido.</span>
                            </div>
                        </div>
                    }
                </NotAuthorized>
            </AuthorizeRouteView>
            <FocusOnNavigate RouteData="@routeData" Selector="h1" />
        </Found>
        <NotFound>
            <PageTitle>Not found</PageTitle>
            <LayoutView Layout="@typeof(MainLayout)">
                <p role="alert">Sorry, there's nothing at this address.</p>
            </LayoutView>
        </NotFound>
    </Router>
</CascadingAuthenticationState>

"@ | Set-Content "src/Presentation/Views/App.razor"

# RedirectToLogin.razor in Views/Shared/Auth
@"
@inject NavigationManager Navigation

@code {
    protected override void OnInitialized()
    {
        Navigation.NavigateTo("/login", forceLoad: false);
    }
}
"@ | Set-Content "src/Presentation/Views/Shared/Auth/RedirectToLogin.razor"

# JwtAuthenticationStateProvider in Views/Shared/Auth
@"
namespace $ProjectName.Views.Shared.Auth
{
    public class JwtAuthenticationStateProvider : AuthenticationStateProvider
    {
        public JwtAuthenticationStateProvider(IJwtTokenService jwtTokenService) : base()
        {
            _jwtTokenService = jwtTokenService;
            _jwtTokenService.TokenChanged += (_, _) =>
                NotifyAuthenticationStateChanged(GetAuthenticationStateAsync());
        }

        private readonly IJwtTokenService _jwtTokenService;

        public override async Task<AuthenticationState> GetAuthenticationStateAsync()
        {
            UserSessionInfo session = await _jwtTokenService.GetUserSessionAsync().ConfigureAwait(false);

            if (string.IsNullOrWhiteSpace(session.UserId) || session.IsExpired)
            {
                return new AuthenticationState(new ClaimsPrincipal(new ClaimsIdentity()));
            }

            List<Claim> claims = new List<Claim>
            {
                new(ClaimTypes.NameIdentifier, session.UserId),
                new(ClaimTypes.Name, session.Name),
                new(ClaimTypes.Email, session.Email)
            };

            foreach (string role in session.Roles)
            {
                if (string.IsNullOrWhiteSpace(role) == false)
                {
                    claims.Add(new Claim(ClaimTypes.Role, role));
                }
            }

            ClaimsIdentity identity = new ClaimsIdentity(claims, "jwt");
            return new AuthenticationState(new ClaimsPrincipal(identity));
        }
    }
}
"@ | Set-Content "src/Presentation/Views/Shared/Auth/JwtAuthenticationStateProvider.cs"

# NotFound.razor in Views/Pages
@"
<p>Sorry, there's nothing at this address.</p>
"@ | Set-Content "src/Presentation/Views/Pages/NotFound.razor"

# MainLayout.razor in Views/Layout
@"
@inherits LayoutComponentBase
@inject NavMenuStateService NavMenuState

<div class="flex min-h-screen">
    <div class="hidden lg:flex">
        <NavMenu />
    </div>

    <div class="flex flex-col flex-1 min-w-0">
        <TopBar />

        <main id="main-content" class="flex-1 bg-gray-100">
            <article class="p-2 md:p-3">
                @Body
            </article>
        </main>

        <footer class="px-4 md:px-6 py-2 flex flex-wrap items-center gap-2 border-t border-gray-200 bg-white">
            <span class="text-gray-500 text-sm">
                <i class="bi bi-c-circle mr-1" aria-hidden="true"></i>
                @DateTime.Now.Year $ProjectName
            </span>
            <span class="ml-auto inline-flex items-center gap-3">
                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800 border border-gray-200">
                    <i class="bi bi-tag mr-1" aria-hidden="true"></i>v1.0
                </span>
            </span>
        </footer>
    </div>
</div>

<div class="fixed inset-y-0 left-0 z-40 w-64 bg-white shadow-xl transform transition-transform @(NavMenuState.IsOpen ? "translate-x-0" : "-translate-x-full") lg:hidden"
     tabindex="-1"
     aria-labelledby="mobileNavMenuLabel"
     style="visibility: @(NavMenuState.IsOpen ? "visible" : "hidden");">
    <div class="flex items-center justify-between p-4 border-b border-gray-200">
        <h5 class="text-lg font-medium" id="mobileNavMenuLabel">$ProjectName</h5>
        <button type="button"
                class="text-gray-400 hover:text-gray-500"
                @onclick="NavMenuState.CloseOpen"
                aria-label="Cerrar menú">
            <i class="bi bi-x-lg" aria-hidden="true"></i>
        </button>
    </div>
    <div class="p-0">
        <NavMenu />
    </div>
</div>

@if (NavMenuState.IsOpen)
{
    <div class="fixed inset-0 bg-black bg-opacity-50 z-30 lg:hidden"
         @onclick="NavMenuState.CloseOpen">
    </div>
}
"@ | Set-Content "src/Presentation/Views/Layout/MainLayout.razor"

# MainLayout.razor.cs code-behind
@"
namespace $ProjectName.Views.Layout;

public partial class MainLayout : LayoutComponentBase, IDisposable
{
    protected override void OnInitialized()
    {
        NavMenuState.Changed += OnNavMenuStateChanged;
    }

    private async void OnNavMenuStateChanged(object sender, EventArgs e)
    {
        await InvokeAsync(StateHasChanged);
    }

    public void Dispose()
    {
        NavMenuState.Changed -= OnNavMenuStateChanged;
    }
}
"@ | Set-Content "src/Presentation/Views/Layout/MainLayout.razor.cs"

# NavMenu.razor in Views/Layout
@"
@inject NavMenuStateService NavMenuState

<nav class="flex-col bg-white text-gray-900 flex-shrink-0"
        style="min-width: @(NavMenuState.IsCollapsed ? "60px" : "260px");"
     aria-label="Navegación principal">
    <div class="flex items-center justify-between p-3 border-b border-gray-200" style="height: 56px;">
        <a class="inline-flex items-center gap-2 text-gray-900 no-underline font-semibold whitespace-nowrap overflow-hidden @(NavMenuState.IsCollapsed ? "justify-center" : "justify-start")"
           href="" title="$ProjectName">
            <i class="bi bi-box-seam text-2xl" aria-hidden="true"></i>
            <span class="@(NavMenuState.IsCollapsed ? "hidden" : "")">$ProjectName</span>
        </a>
    </div>

    <div class="flex-1 overflow-auto py-2 px-3">
        <ul class="list-none pl-0 mb-0">
            <li class="mb-1">
                <a href="/"
                   class="inline-flex items-center @(NavMenuState.IsCollapsed ? "justify-center" : "justify-start") rounded px-0 text-gray-600 w-full no-underline py-2"
                   @onclick="OnLinkClicked">
                    <i class="bi bi-house-door text-xl" aria-hidden="true"></i>
                    <span class="@(NavMenuState.IsCollapsed ? "hidden" : "") ml-2">Home</span>
                </a>
            </li>
            <li class="mb-1">
                <a href="/"
                   class="inline-flex items-center justify-start rounded px-0 text-gray-600 w-full no-underline py-2"
                   @onclick="OnDashboardClick">
                    <i class="bi bi-speedometer2 text-xl" aria-hidden="true"></i>
                    <span class="@(NavMenuState.IsCollapsed ? "hidden" : "") ml-2">Dashboard</span>
                </a>
                <ul class="list-none pl-3 mb-0 @(NavMenuState.IsCollapsed ? "hidden" : "") @(_isDashboardExpanded ? "" : "hidden")">
                    <li>
                        <a href="/"
                           class="inline-flex items-center justify-start rounded px-0 text-gray-600 w-full no-underline py-2"
                           @onclick="OnLinkClicked">
                            <span class="ml-2">Resumen</span>
                        </a>
                    </li>
                </ul>
            </li>
        </ul>
    </div>
</nav>

"@ | Set-Content "src/Presentation/Views/Layout/NavMenu.razor"

# NavMenu.razor.cs code-behind
@"
namespace $ProjectName.Views.Layout;

public partial class NavMenu : ComponentBase, IDisposable
{
    [Inject] private NavigationManager Navigation { get; set; } = default!;

    private bool _isDashboardExpanded;

    protected override void OnInitialized()
    {
        NavMenuState.Changed += OnStateChanged;
    }

    private async void OnStateChanged(object sender, EventArgs e)
    {
        await InvokeAsync(StateHasChanged);
    }

    private void OnLinkClicked()
    {
        NavMenuState.CloseOpen();
    }

    private async Task OnDashboardClick()
    {
        _isDashboardExpanded = !_isDashboardExpanded;
        Navigation.NavigateTo("/");
        await InvokeAsync(StateHasChanged);
    }

    public void Dispose()
    {
        NavMenuState.Changed -= OnStateChanged;
    }
}
"@ | Set-Content "src/Presentation/Views/Layout/NavMenu.razor.cs"

# NavMenuStateService
@"
namespace $ProjectName.Views.Layout;

public class NavMenuStateService
{
    public bool IsCollapsed { get; private set; }
    public bool IsOpen { get; private set; }

    public event EventHandler Changed;

    public void ToggleCollapsed()
    {
        IsCollapsed = !IsCollapsed;
        NotifyChanged();
    }

    public void SetCollapsed(bool collapsed)
    {
        IsCollapsed = collapsed;
        NotifyChanged();
    }

    public void ToggleOpen()
    {
        IsOpen = !IsOpen;
        NotifyChanged();
    }

    public void SetOpen(bool open)
    {
        IsOpen = open;
        NotifyChanged();
    }

    public void CloseOpen()
    {
        if (IsOpen)
        {
            IsOpen = false;
            NotifyChanged();
        }
    }

    private void NotifyChanged()
    {
        Changed?.Invoke(this, EventArgs.Empty);
    }
}
"@ | Set-Content "src/Presentation/Views/Layout/NavMenuStateService.cs"

# TopBar.razor
@"
@inject NavMenuStateService NavMenuStateService
@inject AuthenticationStateProvider AuthenticationStateProvider
@inject ILoginViewModel ViewModel
@inject NavigationManager Navigation

<header class="flex items-center bg-white px-4 shadow-sm" style="height: 56px;">
    <div class="w-full flex items-center justify-between">
        <div class="flex items-center">
            <button type="button"
                    class="text-gray-900 p-0 mr-3 lg:hidden"
                    @onclick="NavMenuStateService.ToggleOpen"
                    aria-label="Abrir menú"
                    aria-expanded="@NavMenuStateService.IsOpen">
                <i class="bi bi-list text-2xl" aria-hidden="true"></i>
            </button>

            <button type="button"
                    class="text-gray-900 p-0 mr-3 hidden lg:inline-flex"
                    @onclick="NavMenuStateService.ToggleCollapsed"
                    aria-label="Contraer menú"
                    aria-expanded="@(!NavMenuStateService.IsCollapsed)">
                <i class="bi bi-list text-2xl" aria-hidden="true"></i>
            </button>
        </div>

        <div class="flex items-center space-x-4">
            @if (IsAuthenticated)
            {
                <div class="relative">
                    <button class="inline-flex items-center gap-2 text-gray-900"
                            type="button"
                            @onclick="ToggleUserMenu"
                            @onfocusout="OnUserMenuFocusOut"
                            aria-expanded="@IsUserMenuOpen"
                            aria-label="Menú de usuario">
                        <span class="inline-flex items-center justify-center rounded-full bg-gray-800 bg-opacity-10 text-gray-900"
                              style="width: 30px; height: 30px;">
                            <i class="bi bi-person text-base" aria-hidden="true"></i>
                        </span>
                        <span class="truncate hidden sm:inline" style="max-width: 140px;">@UserDisplayName</span>
                    </button>

                    @if (IsUserMenuOpen)
                    {
                        <div class="absolute right-0 mt-2 w-56 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5 border rounded-lg p-2"
                             style="min-width: 240px; max-width: calc(100vw - 1rem); z-index: 1050;"
                             tabindex="-1"
                             @onfocusout="OnUserMenuFocusOut">
                            <div class="px-3 py-2">
                                <div class="font-semibold">@UserDisplayName</div>
                                <div class="text-gray-500 text-sm break-all">@UserEmail</div>
                            </div>
                            <div class="border-t border-gray-100"></div>
                            <button type="button"
                                    class="inline-flex items-center gap-2 rounded-md w-full text-left px-3 py-2 text-gray-800 bg-gray-100 hover:bg-gray-200"
                                    @onclick="SignOutAsync">
                                <i class="bi bi-power" aria-hidden="true"></i>
                                Cerrar sesión
                            </button>
                        </div>
                    }
                </div>
            }
            else
            {
                <div class="inline-flex items-center gap-2">
                    <a href="login" class="text-gray-900 py-0">Iniciar sesión</a>
                    <span class="text-gray-500">|</span>
                    <a href="registro" class="text-gray-900 py-0">Registrarse</a>
                </div>
            }
        </div>
    </div>
</header>

"@ | Set-Content "src/Presentation/Views/Layout/TopBar.razor"

# TopBar.razor.cs
@"
namespace $ProjectName.Views.Layout;

public partial class TopBar : ComponentBase, IDisposable
{
    private bool IsUserMenuOpen { get; set; }
    private ClaimsPrincipal _user = new ClaimsPrincipal(new ClaimsIdentity());

    private bool IsAuthenticated => _user.Identity?.IsAuthenticated ?? false;

    private string UserDisplayName => _user.Identity?.Name is { Length: > 0 } name
        ? name
        : "Usuario";

    private string UserEmail => _user.FindFirst(ClaimTypes.Email)?.Value ?? string.Empty;

    protected override void OnInitialized()
    {
        AuthenticationStateProvider.AuthenticationStateChanged += OnAuthenticationStateChanged;
        Navigation.LocationChanged += OnLocationChanged;
    }

    protected override async Task OnInitializedAsync()
    {
        AuthenticationState authState = await AuthenticationStateProvider.GetAuthenticationStateAsync();
        _user = authState.User;
    }

    private async void OnAuthenticationStateChanged(Task<AuthenticationState> task)
    {
        AuthenticationState authState = await task;
        _user = authState.User;
        await InvokeAsync(StateHasChanged);
    }

    private async void OnLocationChanged(object sender, LocationChangedEventArgs e)
    {
        IsUserMenuOpen = false;
        await InvokeAsync(StateHasChanged);
    }

    public void Dispose()
    {
        AuthenticationStateProvider.AuthenticationStateChanged -= OnAuthenticationStateChanged;
        Navigation.LocationChanged -= OnLocationChanged;
    }

    private async Task OnUserMenuFocusOut()
    {
        await Task.Delay(150);
        IsUserMenuOpen = false;
        await InvokeAsync(StateHasChanged);
    }

    private async Task SignOutAsync()
    {
        IsUserMenuOpen = false;
        await ViewModel.LogoutAsync();
        Navigation.NavigateTo("/login", forceLoad: true);
    }

    private void ToggleUserMenu()
    {
        IsUserMenuOpen = !IsUserMenuOpen;
    }

    private void CollapseUserMenu()
    {
        IsUserMenuOpen = false;
    }
}
"@ | Set-Content "src/Presentation/Views/Layout/TopBar.razor.cs"

# NavMenu.razor.css (no custom CSS — using Tailwind utility classes in NavMenu.razor and MainLayout.razor)
"" | Set-Content "src/Presentation/Views/Layout/NavMenu.razor.css"

# TopBar.razor.css
@"
.topbar .btn-link {
    text-decoration: none;
}

.topbar .btn-link:hover,
.topbar .btn-link:focus {
    color: rgba(0, 0, 0, 0.7) !important;
}
"@ | Set-Content "src/Presentation/Views/Layout/TopBar.razor.css"

# MainLayout.razor.css
@"
/* Empty: layout uses Tailwind utility classes. Keep file if you need component-scoped overrides later. */
"@ | Set-Content "src/Presentation/Views/Layout/MainLayout.razor.css"

# Login.razor.css (no custom CSS — using Tailwind utility classes in Login.razor)
"" | Set-Content "src/Presentation/Views/Pages/Login.razor.css"

# ListComponent.razor.css (scoped styles for table/mobile behavior)
@"
.table-scroll {
    -webkit-overflow-scrolling: touch;
}

.table-scroll table {
    min-width: 640px;
}
"@ | Set-Content "src/Presentation/Views/Shared/Components/ListComponent.razor.css"

# PaginationComponent.razor in Views/Shared/Components
@"
@namespace $ProjectName.Views.Shared.Components

<div class="bg-white border-t border-gray-200 py-2">
    <div class="flex flex-col md:flex-row justify-between items-center gap-2">
        <div class="text-gray-500 text-sm">
            Mostrando @CurrentItemsCount de @TotalCount
            @(TotalCount == 1 ? ItemName : ItemPluralName)
            @if (HasActiveFilters)
            {
                <span>(filtradas)</span>
            }
        </div>
        <div class="flex items-center gap-2">
            <div class="flex text-sm" style="width: auto;">
                <label class="inline-flex items-center px-3 rounded-l-lg border border-r-0 border-gray-300 bg-gray-50 text-gray-500 text-sm" for="pageSizeSelect">Tamaño</label>
                <select class="block w-full rounded-r-lg border-gray-300 bg-gray-50 border text-gray-900 text-sm py-2.5 px-3 transition duration-200 ease-in-out focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-500/20 focus:outline-none disabled:opacity-60 disabled:cursor-not-allowed rounded-l-none" id="pageSizeSelect"
                        value="@PageSize"
                        @onchange="OnPageSizeChange"
                        disabled="@IsLoading"
                        aria-label="Tamaño de página">
                    <option value="10">10</option>
                    <option value="25">25</option>
                    <option value="50">50</option>
                    <option value="100">100</option>
                    <option value="500">500</option>
                    <option value="1000">1000</option>
                </select>
            </div>
            <nav aria-label="Navegación de páginas">
                <ul class="flex -space-x-px text-sm mb-0">
                    <li class="@(CurrentPage == 1 ? "opacity-50 pointer-events-none" : "")">
                        <button class="relative inline-flex items-center px-3 py-2 border border-gray-300 bg-white text-sm font-medium text-gray-700 hover:bg-gray-50" @onclick="FirstPage" disabled="@(CurrentPage == 1)" aria-label="Primera página">
                            <i class="bi bi-chevron-double-left" aria-hidden="true"></i>
                        </button>
                    </li>
                    <li class="@(CurrentPage == 1 ? "opacity-50 pointer-events-none" : "")">
                        <button class="relative inline-flex items-center px-3 py-2 border border-gray-300 bg-white text-sm font-medium text-gray-700 hover:bg-gray-50" @onclick="PreviousPage" disabled="@(CurrentPage == 1)" aria-label="Página anterior">
                            <i class="bi bi-chevron-left" aria-hidden="true"></i>
                        </button>
                    </li>
                    <li class="opacity-50 pointer-events-none">
                        <span class="relative inline-flex items-center px-3 py-2 border border-gray-300 bg-white text-sm font-medium text-gray-700" aria-current="page">Página @CurrentPage de @(Math.Max(1, TotalPages))</span>
                    </li>
                    <li class="@(CurrentPage == TotalPages || TotalPages == 0 ? "opacity-50 pointer-events-none" : "")">
                        <button class="relative inline-flex items-center px-3 py-2 border border-gray-300 bg-white text-sm font-medium text-gray-700 hover:bg-gray-50" @onclick="NextPage" disabled="@(CurrentPage == TotalPages || TotalPages == 0)" aria-label="Página siguiente">
                            <i class="bi bi-chevron-right" aria-hidden="true"></i>
                        </button>
                    </li>
                    <li class="@(CurrentPage == TotalPages || TotalPages == 0 ? "opacity-50 pointer-events-none" : "")">
                        <button class="relative inline-flex items-center px-3 py-2 border border-gray-300 bg-white text-sm font-medium text-gray-700 hover:bg-gray-50" @onclick="LastPage" disabled="@(CurrentPage == TotalPages || TotalPages == 0)" aria-label="Última página">
                            <i class="bi bi-chevron-double-right" aria-hidden="true"></i>
                        </button>
                    </li>
                </ul>
            </nav>
        </div>
    </div>
</div>
"@ | Set-Content "src/Presentation/Views/Shared/Components/PaginationComponent.razor"

# PaginationComponent.razor.cs code-behind
@"
namespace $ProjectName.Views.Shared.Components;

public partial class PaginationComponent
{
    [Parameter] public int CurrentPage { get; set; } = 1;
    [Parameter] public int TotalPages { get; set; } = 1;
    [Parameter] public int TotalCount { get; set; }
    [Parameter] public int CurrentItemsCount { get; set; }
    [Parameter] public int PageSize { get; set; } = 1000;
    [Parameter] public bool IsLoading { get; set; }
    [Parameter] public bool HasActiveFilters { get; set; }
    [Parameter] public string ItemName { get; set; } = "registro";
    [Parameter] public string ItemPluralName { get; set; } = "registros";

    [Parameter] public EventCallback<int> OnPageChanged { get; set; }
    [Parameter] public EventCallback<int> OnPageSizeChanged { get; set; }

    private async Task OnPageSizeChange(ChangeEventArgs e)
    {
        if (int.TryParse(e.Value?.ToString(), out int size))
        {
            await OnPageSizeChanged.InvokeAsync(size);
        }
    }

    private async Task FirstPage() => await OnPageChanged.InvokeAsync(1);
    private async Task PreviousPage() => await OnPageChanged.InvokeAsync(CurrentPage - 1);
    private async Task NextPage() => await OnPageChanged.InvokeAsync(CurrentPage + 1);
    private async Task LastPage() => await OnPageChanged.InvokeAsync(TotalPages);
}
"@ | Set-Content "src/Presentation/Views/Shared/Components/PaginationComponent.razor.cs"

# ListComponent.razor in Views/Shared/Components
@"
@namespace $ProjectName.Views.Shared.Components
@typeparam TItem

@if (IsLoading && UseAbsoluteOverlay == false)
{
    <div class="flex justify-center items-center py-4">
        <div class="animate-spin h-5 w-5 border-2 border-current border-t-transparent rounded-full text-blue-600" role="status" aria-label="Cargando">
            <span class="sr-only">Cargando...</span>
        </div>
        @if (string.IsNullOrEmpty(LoadingMessage) == false)
        {
            <span class="ml-2 text-gray-500">@LoadingMessage</span>
        }
    </div>
}
else if (Items == null || Items.Any() == false)
{
    <div class="text-center text-gray-500 py-4">
        <i class="bi bi-inbox text-4xl block mb-2" aria-hidden="true"></i>
        <span>@EmptyMessage</span>
    </div>
}
else if (IsTableMode)
{
    <div class="overflow-x-auto table-scroll @TableContainerCssClass">
        <table class="min-w-full divide-y divide-gray-200 align-middle mb-0 @TableCssClass">
            @if (TableColumns != null)
            {
                <colgroup>
                    @TableColumns
                </colgroup>
            }
            <thead class="bg-gray-50">
                <tr class="text-sm uppercase text-gray-500">
                    @TableHeader
                </tr>
            </thead>
            <tbody>
                @foreach (TItem item in Items)
                {
                    <tr>
                        @TableRow(item)
                    </tr>
                }
            </tbody>
        </table>
    </div>

    @if (HasMobileView)
    {
        <ul class="divide-y divide-gray-200 border border-gray-200 rounded-md md:hidden p-2 gap-2 @ListGroupCssClass">
            @foreach (TItem item in Items)
            {
                <li class="px-4 py-3 border rounded-lg shadow-sm @ItemCssClass">
                    @MobileItem(item)
                </li>
            }
        </ul>
    }
}
else
{
    <div class="divide-y divide-gray-200 border border-gray-200 rounded-md @ListGroupCssClass">
        @foreach (TItem item in Items)
        {
            <div class="px-4 py-3 hover:bg-gray-50 cursor-pointer @ItemCssClass">
                @ItemTemplate(item)
            </div>
        }
    </div>
}

@if (IsLoading && UseAbsoluteOverlay)
{
    <div class="absolute top-0 left-0 right-0 bottom-0 flex flex-col items-center justify-center gap-2 text-gray-500"
         style="background-color: rgba(255, 255, 255, 0.85); z-index: 10;">
        <div class="animate-spin h-5 w-5 border-2 border-current border-t-transparent rounded-full" role="status" aria-hidden="true"></div>
        @if (string.IsNullOrEmpty(LoadingMessage) == false)
        {
            <span>@LoadingMessage</span>
        }
    </div>
}
"@ | Set-Content "src/Presentation/Views/Shared/Components/ListComponent.razor"

# ListComponent.razor.cs code-behind
@"
namespace $ProjectName.Views.Shared.Components;

public partial class ListComponent<TItem>
{
    [Parameter] public IEnumerable<TItem> Items { get; set; } = Array.Empty<TItem>();
    [Parameter] public RenderFragment<TItem>? ItemTemplate { get; set; }
    [Parameter] public RenderFragment? TableHeader { get; set; }
    [Parameter] public RenderFragment<TItem>? TableRow { get; set; }
    [Parameter] public RenderFragment? TableColumns { get; set; }
    [Parameter] public RenderFragment<TItem>? MobileItem { get; set; }
    [Parameter] public string Title { get; set; } = string.Empty;
    [Parameter] public string EmptyMessage { get; set; } = "No hay elementos para mostrar.";
    [Parameter] public string? LoadingMessage { get; set; }
    [Parameter] public bool IsLoading { get; set; }
    [Parameter] public string ItemCssClass { get; set; } = string.Empty;
    [Parameter] public string TableCssClass { get; set; } = string.Empty;
    [Parameter] public string TableContainerCssClass { get; set; } = string.Empty;
    [Parameter] public string ListGroupCssClass { get; set; } = string.Empty;
    [Parameter] public RenderFragment? Actions { get; set; }
    [Parameter] public bool UseAbsoluteOverlay { get; set; }

    private bool IsTableMode => TableHeader != null && TableRow != null;
    private bool HasMobileView => MobileItem != null;
}
"@ | Set-Content "src/Presentation/Views/Shared/Components/ListComponent.razor.cs"

# SearchSelect.razor in Views/Shared/Components
@"
@namespace $ProjectName.Views.Shared.Components
@implements IDisposable
@typeparam TItem

<div class="mb-4 relative" style="min-width: 0;">
    <label for="@InputId" class="block text-sm font-semibold text-gray-700 mb-1.5">@Label <span class="text-red-600">*</span></label>
    <div class="relative">
        <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
            <i class="bi bi-search text-gray-400" aria-hidden="true"></i>
        </div>
        <input id="@InputId"
               type="search"
               class="block w-full pl-10 @(IsSearching ? "pr-10" : "pr-4") py-3 bg-gray-50 border border-gray-300 rounded-lg text-gray-900 placeholder-gray-400 text-sm transition duration-200 ease-in-out focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-500/20 focus:outline-none disabled:opacity-60 disabled:cursor-not-allowed"
               autocomplete="off"
               placeholder="@Placeholder"
               aria-autocomplete="list"
               aria-controls="@ResultsId"
               aria-expanded="@(SearchResults.Count > 0)"
               value="@SearchTerm"
               @oninput="OnInputAsync"
               disabled="@Disabled" />

        @if (IsSearching)
        {
            <span class="animate-spin h-4 w-4 border-2 border-current border-t-transparent rounded-full absolute right-3 top-1/2 -translate-y-1/2"
                  role="status"
                  aria-label="Searching"></span>
        }
    </div>

    @if (SearchResults.Count > 0)
    {
        <ul id="@ResultsId" class="divide-y divide-gray-200 border border-gray-200 rounded-md absolute w-full shadow-sm mt-1"
            style="z-index: 1050; max-height: min(260px, 50vh); overflow-y: auto; left: 0; right: 0;">
            @foreach (TItem item in SearchResults)
            {
                <li class="px-4 py-3 hover:bg-gray-50 cursor-pointer"
                    style="cursor: pointer;"
                    @onclick="() => SelectServiceAsync(item)"
                    @onclick:stopPropagation="true">
                    <div class="font-semibold break-all">@ItemText(item)</div>
                </li>
            }
        </ul>
    }
</div>
"@ | Set-Content "src/Presentation/Views/Shared/Components/SearchSelect.razor"

# SearchSelect.razor.cs code-behind
@"
namespace $ProjectName.Views.Shared.Components;

public partial class SearchSelect<TItem> : IDisposable
{
    private CancellationTokenSource? SearchCts;

    [Parameter, EditorRequired]
    public string Label { get; set; } = string.Empty;

    [Parameter]
    public string Placeholder { get; set; } = "Type at least 2 characters...";

    [Parameter]
    public string InputId { get; set; } = "searchSelect";

    [Parameter]
    public string ResultsId { get; set; } = "search-select-results";

    [Parameter]
    public string SearchTerm { get; set; } = string.Empty;

    [Parameter]
    public IReadOnlyList<TItem> SearchResults { get; set; } = [];

    [Parameter, EditorRequired]
    public Func<TItem, string> ItemText { get; set; } = item => item?.ToString() ?? string.Empty;

    [Parameter]
    public bool IsSearching { get; set; }

    [Parameter]
    public bool Disabled { get; set; }

    [Parameter, EditorRequired]
    public Func<string, CancellationToken, Task> SearchAsync { get; set; }

    [Parameter, EditorRequired]
    public EventCallback<TItem> ItemSelected { get; set; }

    private async Task OnInputAsync(ChangeEventArgs eventArgs)
    {
        string searchTerm = eventArgs.Value?.ToString() ?? string.Empty;

        SearchCts?.Cancel();
        SearchCts?.Dispose();
        SearchCts = new CancellationTokenSource();

        try
        {
            await Task.Delay(400, SearchCts.Token);
            await SearchAsync(searchTerm, SearchCts.Token);
        }
        catch (OperationCanceledException)
        {
        }
    }

    private async Task SelectServiceAsync(TItem item)
    {
        SearchCts?.Cancel();
        await ItemSelected.InvokeAsync(item);
    }

    public void Dispose()
    {
        SearchCts?.Cancel();
        SearchCts?.Dispose();
    }
}
"@ | Set-Content "src/Presentation/Views/Shared/Components/SearchSelect.razor.cs"

# NumberConverter in Views/Shared/Helper
@"
namespace $ProjectName.Views.Shared.Helper;

public static class NumberConverter
{
    public static string FormatNumber(decimal value, int decimals = 2) => value.ToString($"N{decimals}", CultureInfo.GetCultureInfo("es-MX"));

    public static bool TryParseDecimal(ChangeEventArgs args, out decimal value)
    {
        return TryParseDecimal(args.Value?.ToString(), out value);
    }

    public static bool TryParseDecimal(string value, out decimal decimalValue)
    {
        string capturedValue = value?.Trim() ?? string.Empty;

        if (string.IsNullOrWhiteSpace(capturedValue))
        {
            decimalValue = 0;
            return true;
        }

        return decimal.TryParse(capturedValue, NumberStyles.Number, CultureInfo.InvariantCulture, out decimalValue) ||
                decimal.TryParse(capturedValue, NumberStyles.Number, CultureInfo.CurrentCulture, out decimalValue);
    }
}
"@ | Set-Content "src/Presentation/Views/Shared/Helper/NumberConverter.cs"

# InputDecimal.razor in Views/Shared/Components
@"
@namespace $ProjectName.Views.Shared.Components

<input @key="RenderKey"
       type="text"
         class="@ResolvedCssClass"
       value="@DisplayText"
       @onchange="HandleChange"
       inputmode="@InputMode"
       placeholder="@Placeholder"
       readonly="@ReadOnly"
       disabled="@Disabled"
       @attributes="AdditionalAttributes" />
"@ | Set-Content "src/Presentation/Views/Shared/Components/InputDecimal.razor"

# InputDecimal.razor.cs code-behind
@"
namespace $ProjectName.Views.Shared.Components;

public partial class InputDecimal
{
    [Parameter] public decimal Value { get; set; }
    [Parameter] public EventCallback<decimal> ValueChanged { get; set; }
    [Parameter] public string CssClass { get; set; } = string.Empty;
    [Parameter] public string TextAlignment { get; set; } = "text-end";
    [Parameter] public string InputMode { get; set; } = "decimal";
    [Parameter] public string Placeholder { get; set; } = "0.00";
    [Parameter] public int Decimals { get; set; } = 2;
    [Parameter] public bool ReadOnly { get; set; }
    [Parameter] public bool Disabled { get; set; }
    [Parameter] public double? Min { get; set; }
    [Parameter] public double? Max { get; set; }

    [Parameter(CaptureUnmatchedValues = true)]
    public Dictionary<string, object> AdditionalAttributes { get; set; } = null!;

    private string DisplayText = string.Empty;
    private decimal LastSyncedValue;
    private Guid RenderKey = Guid.NewGuid();

    private string ResolvedCssClass => HasTextAlignmentClass(CssClass)
        ? CssClass
        : string.IsNullOrWhiteSpace(CssClass)
            ? TextAlignment
            : string.IsNullOrWhiteSpace(TextAlignment)
                ? CssClass
                : $"{CssClass} {TextAlignment}";

    protected override void OnParametersSet()
    {
        if (DisplayText.Length == 0 || Value != LastSyncedValue)
        {
            DisplayText = NumberConverter.FormatNumber(Value, Decimals);
            LastSyncedValue = Value;
        }
    }

    private async Task HandleChange(ChangeEventArgs args)
    {
        if (ReadOnly || Disabled)
            return;

        decimal finalValue;

        if (NumberConverter.TryParseDecimal(args.Value?.ToString(), out decimal parsedValue))
        {
            finalValue = Clamp(parsedValue);
        }
        else
        {
            finalValue = Max.HasValue ? (decimal)Max.Value : Value;
        }

        DisplayText = NumberConverter.FormatNumber(finalValue, Decimals);
        LastSyncedValue = finalValue;
        RenderKey = Guid.NewGuid();

        if (finalValue != Value)
        {
            await ValueChanged.InvokeAsync(finalValue);
        }
        else
        {
            StateHasChanged();
        }
    }

    private decimal Clamp(decimal value)
    {
        if (Min.HasValue && value < (decimal)Min.Value)
            return (decimal)Min.Value;

        if (Max.HasValue && value > (decimal)Max.Value)
            return (decimal)Max.Value;

        return value;
    }

    private static bool HasTextAlignmentClass(string cssClass)
    {
        if (string.IsNullOrWhiteSpace(cssClass))
            return false;

        string[] classes = cssClass.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return classes.Contains("text-start") || classes.Contains("text-center") || classes.Contains("text-end");
    }
}
"@ | Set-Content "src/Presentation/Views/Shared/Components/InputDecimal.razor.cs"

# PivotComponent.razor in Views/Shared/Components
@"
@namespace $ProjectName.Views.Shared.Components
@typeparam T where T : class

<div class="space-y-4">
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div class="bg-white rounded-xl border border-gray-200 shadow-sm p-3">
            <div class="flex items-center gap-2 mb-3">
                <i class="bi bi-grid-3x3-gap text-gray-400" aria-hidden="true"></i>
                <span class="text-sm font-semibold text-gray-700">Dimensiones disponibles</span>
                <span class="ml-auto text-xs text-gray-400">Arrastra a Filas o Columnas</span>
            </div>
            <div class="flex flex-wrap gap-2 p-3 rounded-lg bg-gray-50 border border-dashed border-gray-200 min-h-[56px]"
                 @ondrop="SetDimensionAsHidden"
                 @ondragover:preventDefault
                 @ondragenter:preventDefault>
                @foreach (var dim in Dimensions.Where(d => d.IsEnabled == false))
                {
                    <div draggable="true"
                         class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium bg-white text-gray-700 border border-gray-200 shadow-sm hover:border-blue-400 hover:text-blue-600 hover:shadow-md transition-all"
                         style="cursor: grab;"
                         title="Oculto - click para columna"
                         @ondragstart="() => _draggedDimension = dim"
                         @ondrop="SetDimensionAsHidden"
                         @ondragover:preventDefault
                         @onclick="() => ToggleDimension(dim)">
                        <i class="bi bi-grip-vertical text-gray-300" aria-hidden="true"></i>
                        @dim.DisplayValue
                    </div>
                }
                @if (!Dimensions.Any(d => d.IsEnabled == false))
                {
                    <span class="text-xs text-gray-400 italic">Todas las dimensiones están en uso</span>
                }
            </div>
        </div>

        <div class="bg-white rounded-xl border border-gray-200 shadow-sm p-3">
            <div class="flex items-center gap-2 mb-3">
                <i class="bi bi-calculator text-gray-400" aria-hidden="true"></i>
                <span class="text-sm font-semibold text-gray-700">Medidas disponibles</span>
                <span class="ml-auto text-xs text-gray-400">Arrastra a Valores</span>
            </div>
            <div class="flex flex-wrap gap-2 p-3 rounded-lg bg-gray-50 border border-dashed border-gray-200 min-h-[56px]"
                 @ondrop="SetMeasureAsAvailable"
                 @ondragover:preventDefault
                 @ondragenter:preventDefault>
                @foreach (var measure in Measures.Where(m => m.IsEnabled == false))
                {
                    <div draggable="true"
                         class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium bg-white text-gray-700 border border-gray-200 shadow-sm hover:border-cyan-400 hover:text-cyan-600 hover:shadow-md transition-all"
                         style="cursor: grab;"
                         title="Click para agregar a Valores"
                         @ondragstart="() => _draggedMeasure = measure"
                         @ondrop="SetMeasureAsAvailable"
                         @ondragover:preventDefault
                         @onclick="() => ToggleMeasure(measure)">
                        <i class="bi bi-grip-vertical text-gray-300" aria-hidden="true"></i>
                        @measure.DisplayValue
                    </div>
                }
                @if (!Measures.Any(m => m.IsEnabled == false))
                {
                    <span class="text-xs text-gray-400 italic">Todas las medidas están en uso</span>
                }
            </div>
        </div>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="bg-white rounded-xl border-2 border-blue-100 shadow-sm p-3">
            <div class="flex items-center gap-2 mb-3">
                <span class="inline-flex items-center justify-center w-6 h-6 rounded-md bg-blue-100 text-blue-600 text-xs">
                    <i class="bi bi-arrow-down-up" aria-hidden="true"></i>
                </span>
                <span class="text-sm font-semibold text-gray-700">Filas</span>
            </div>
            <div class="flex flex-wrap gap-2 p-3 rounded-lg bg-blue-50/50 border border-dashed border-blue-200 min-h-[56px]"
                 @ondrop="SetDimensionAsRow"
                 @ondragover:preventDefault
                 @ondragenter:preventDefault>
                @foreach (var dim in Dimensions.Where(d => d.IsEnabled && d.IsRow).OrderBy(d => d.Sequence))
                {
                    <div draggable="true"
                         class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium bg-blue-600 text-white shadow-sm hover:bg-blue-700 transition-colors"
                         style="cursor: grab;"
                         title="Fila - arrastra sobre otra fila para reordenar"
                         @ondragstart="() => _draggedDimension = dim"
                         @ondrop="() => OnDimensionDropped(dim)"
                         @ondrop:stopPropagation
                         @ondragover:preventDefault
                         @onclick="() => ToggleDimension(dim)">
                        <i class="bi bi-grip-vertical text-blue-300" aria-hidden="true"></i>
                        @dim.DisplayValue
                    </div>
                }
                @if (!Dimensions.Any(d => d.IsEnabled && d.IsRow))
                {
                    <span class="text-xs text-blue-400 italic">Arrastra dimensiones aquí</span>
                }
            </div>
        </div>

        <div class="bg-white rounded-xl border-2 border-green-100 shadow-sm p-3">
            <div class="flex items-center gap-2 mb-3">
                <span class="inline-flex items-center justify-center w-6 h-6 rounded-md bg-green-100 text-green-600 text-xs">
                    <i class="bi bi-arrow-left-right" aria-hidden="true"></i>
                </span>
                <span class="text-sm font-semibold text-gray-700">Columnas</span>
            </div>
            <div class="flex flex-wrap gap-2 p-3 rounded-lg bg-green-50/50 border border-dashed border-green-200 min-h-[56px]"
                 @ondrop="SetDimensionAsColumn"
                 @ondragover:preventDefault
                 @ondragenter:preventDefault>
                @foreach (var dim in Dimensions.Where(d => d.IsEnabled && d.IsRow == false).OrderBy(d => d.Sequence))
                {
                    <div draggable="true"
                         class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium bg-emerald-500 text-white shadow-sm hover:bg-emerald-600 transition-colors"
                         style="cursor: grab;"
                         title="Columna - arrastra sobre otra columna para reordenar"
                         @ondragstart="() => _draggedDimension = dim"
                         @ondrop="() => OnDimensionDropped(dim)"
                         @ondrop:stopPropagation
                         @ondragover:preventDefault
                         @onclick="() => ToggleDimension(dim)">
                        <i class="bi bi-grip-vertical text-emerald-200" aria-hidden="true"></i>
                        @dim.DisplayValue
                    </div>
                }
                @if (!Dimensions.Any(d => d.IsEnabled && d.IsRow == false))
                {
                    <span class="text-xs text-emerald-500 italic">Arrastra dimensiones aquí</span>
                }
            </div>
        </div>

        <div class="bg-white rounded-xl border-2 border-cyan-100 shadow-sm p-3">
            <div class="flex items-center gap-2 mb-3">
                <span class="inline-flex items-center justify-center w-6 h-6 rounded-md bg-cyan-100 text-cyan-600 text-xs">
                    <i class="bi bi-123" aria-hidden="true"></i>
                </span>
                <span class="text-sm font-semibold text-gray-700">Valores</span>
            </div>
            <div class="flex flex-wrap gap-2 p-3 rounded-lg bg-cyan-50/50 border border-dashed border-cyan-200 min-h-[56px]"
                 @ondrop="SetMeasureAsValue"
                 @ondragover:preventDefault
                 @ondragenter:preventDefault>
                @foreach (var measure in Measures.Where(m => m.IsEnabled).OrderBy(m => m.Sequence))
                {
                    <div draggable="true"
                         class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium bg-cyan-500 text-white shadow-sm hover:bg-cyan-600 transition-colors"
                         style="cursor: grab;"
                         title="Valor - arrastra sobre otro valor para reordenar"
                         @ondragstart="() => _draggedMeasure = measure"
                         @ondrop="() => OnMeasureDropped(measure)"
                         @ondrop:stopPropagation
                         @ondragover:preventDefault
                         @onclick="() => ToggleMeasure(measure)">
                        <i class="bi bi-grip-vertical text-cyan-200" aria-hidden="true"></i>
                        @measure.DisplayValue
                    </div>
                }
                @if (!Measures.Any(m => m.IsEnabled))
                {
                    <span class="text-xs text-cyan-500 italic">Arrastra medidas aquí</span>
                }
            </div>
        </div>
    </div>
</div>

@if (ShowValidationMessage && IsConfigurationValid == false)
{
    <div class="alert alert-info" role="status">
        <i class="bi bi-info-circle mr-2" aria-hidden="true"></i>
        Agrega al menos una dimensión en <strong>Filas</strong> y una en <strong>Columnas</strong> para ver la tabla pivote.
    </div>
}
"@ | Set-Content "src/Presentation/Views/Shared/Components/PivotComponent.razor"

# PivotComponent.razor.cs code-behind
@"
using LeaderAnalytics.LeaderPivot;

namespace $ProjectName.Views.Shared.Components;

public partial class PivotComponent<T> where T : class
{
    [Parameter]
    public List<Dimension<T>> Dimensions { get; set; } = [];

    [Parameter]
    public List<Measure<T>> Measures { get; set; } = [];

    [Parameter]
    public EventCallback OnChanged { get; set; }

    [Parameter]
    public EventCallback<bool> OnConfigurationValidChanged { get; set; }

    [Parameter]
    public bool ShowValidationMessage { get; set; } = true;

    private Dimension<T> _draggedDimension = null;
    private Measure<T> _draggedMeasure = null;

    private bool HasColumnDimension => Dimensions.Any(d => d.IsEnabled && d.IsRow == false);
    private bool HasRowDimension => Dimensions.Any(d => d.IsEnabled && d.IsRow);
    private bool IsConfigurationValid => HasRowDimension && HasColumnDimension;

    private async Task OnDimensionDropped(Dimension<T> target)
    {
        if (_draggedDimension is null || _draggedDimension == target)
        {
            _draggedDimension = null;
            return;
        }

        if (_draggedDimension.IsEnabled && target.IsEnabled && _draggedDimension.IsRow == target.IsRow)
        {
            ReorderDimensionBefore(_draggedDimension, target);
            _draggedDimension = null;
            await NotifyChangeAsync();
            return;
        }

        _draggedDimension = null;
    }

    private async Task OnMeasureDropped(Measure<T> target)
    {
        if (_draggedMeasure is null || _draggedMeasure == target)
        {
            _draggedMeasure = null;
            return;
        }

        if (_draggedMeasure.IsEnabled && target.IsEnabled)
        {
            ReorderMeasureBefore(_draggedMeasure, target);
            _draggedMeasure = null;
            await NotifyChangeAsync();
            return;
        }

        _draggedMeasure = null;
    }

    private async Task SetDimensionAsRow()
    {
        if (_draggedDimension is null)
        {
            return;
        }

        _draggedDimension.IsEnabled = true;
        _draggedDimension.IsRow = true;
        NormalizeDimensionSequences();
        _draggedDimension = null;
        await NotifyChangeAsync();
    }

    private async Task SetDimensionAsColumn()
    {
        if (_draggedDimension is null)
        {
            return;
        }

        _draggedDimension.IsEnabled = true;
        _draggedDimension.IsRow = false;
        NormalizeDimensionSequences();
        _draggedDimension = null;
        await NotifyChangeAsync();
    }

    private async Task SetDimensionAsHidden()
    {
        if (_draggedDimension is null)
        {
            return;
        }

        _draggedDimension.IsEnabled = false;
        NormalizeDimensionSequences();
        _draggedDimension = null;
        await NotifyChangeAsync();
    }

    private async Task SetMeasureAsValue()
    {
        if (_draggedMeasure is null)
        {
            return;
        }

        _draggedMeasure.IsEnabled = true;
        _draggedMeasure = null;
        await NotifyChangeAsync();
    }

    private async Task SetMeasureAsAvailable()
    {
        if (_draggedMeasure is null || _draggedMeasure.IsEnabled == false)
        {
            _draggedMeasure = null;
            return;
        }

        if (Measures.Count(m => m.IsEnabled) <= 1)
        {
            _draggedMeasure = null;
            return;
        }

        _draggedMeasure.IsEnabled = false;
        _draggedMeasure = null;
        await NotifyChangeAsync();
    }

    private async Task ToggleDimension(Dimension<T> dimension)
    {
        if (dimension.IsEnabled)
        {
            if (dimension.IsRow)
            {
                dimension.IsRow = false;
            }
            else
            {
                dimension.IsEnabled = false;
            }
        }
        else
        {
            dimension.IsEnabled = true;
            dimension.IsRow = false;
        }

        NormalizeDimensionSequences();
        await NotifyChangeAsync();
    }

    private async Task ToggleMeasure(Measure<T> measure)
    {
        if (measure.IsEnabled && Measures.Count(m => m.IsEnabled) <= 1)
        {
            return;
        }

        measure.IsEnabled = !measure.IsEnabled;
        await NotifyChangeAsync();
    }

    private void NormalizeDimensionSequences()
    {
        int rowSequence = 0;
        foreach (Dimension<T> dim in Dimensions.Where(d => d.IsEnabled && d.IsRow).OrderBy(d => d.Sequence))
        {
            dim.Sequence = rowSequence++;
        }

        int columnSequence = 0;
        foreach (Dimension<T> dim in Dimensions.Where(d => d.IsEnabled && d.IsRow == false).OrderBy(d => d.Sequence))
        {
            dim.Sequence = columnSequence++;
        }
    }

    private void ReorderDimensionBefore(Dimension<T> dragged, Dimension<T> target)
    {
        var items = Dimensions
            .Where(d => d.IsEnabled && d.IsRow == dragged.IsRow)
            .OrderBy(d => d.Sequence)
            .ToList();

        items.Remove(dragged);
        var targetIndex = items.IndexOf(target);
        if (targetIndex < 0)
        {
            return;
        }

        items.Insert(targetIndex, dragged);

        for (int i = 0; i < items.Count; i++)
        {
            items[i].Sequence = i;
        }
    }

    private void ReorderMeasureBefore(Measure<T> dragged, Measure<T> target)
    {
        var items = Measures
            .Where(m => m.IsEnabled)
            .OrderBy(m => m.Sequence)
            .ToList();

        items.Remove(dragged);
        var targetIndex = items.IndexOf(target);
        if (targetIndex < 0)
        {
            return;
        }

        items.Insert(targetIndex, dragged);

        for (int i = 0; i < items.Count; i++)
        {
            items[i].Sequence = i;
        }
    }

    private async Task NotifyChangeAsync()
    {
        if (OnConfigurationValidChanged.HasDelegate)
        {
            await OnConfigurationValidChanged.InvokeAsync(IsConfigurationValid);
        }

        if (OnChanged.HasDelegate)
        {
            await OnChanged.InvokeAsync();
        }
    }
}
"@ | Set-Content "src/Presentation/Views/Shared/Components/PivotComponent.razor.cs"

# PivotBuilder.cs in Views/Shared/Components
@"
using LeaderAnalytics.LeaderPivot;
using System.ComponentModel;
using System.Reflection;
using System.Text.RegularExpressions;

namespace $ProjectName.Views.Shared.Components;

public partial class PivotBuilder<T>
{
    private readonly List<Dimension<T>> _dimensions = [];
    private readonly List<Measure<T>> _measures = [];
    private readonly Dictionary<string, string> _labels = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _excludedDimensions = [];
    private readonly HashSet<string> _excludedMeasures = [];
    private int _dimensionSequence;
    private int _measureSequence;

    [GeneratedRegex("(?<!^)(?=[A-Z])", RegexOptions.Compiled)]
    private static partial Regex CamelCaseSplitterRegex();

    public static PivotBuilder<T> Create() => new();

    public PivotBuilder<T> WithLabel(string propertyName, string label)
    {
        _labels[propertyName] = label;
        return this;
    }

    public PivotBuilder<T> WithLabels(Dictionary<string, string> labels)
    {
        foreach (KeyValuePair<string, string> item in labels)
        {
            _labels[item.Key] = item.Value;
        }

        return this;
    }

    public PivotBuilder<T> ExcludeDimensions(params string[] propertyNames)
    {
        foreach (var name in propertyNames)
        {
            _excludedDimensions.Add(name);
        }

        return this;
    }

    public PivotBuilder<T> ExcludeMeasures(params string[] propertyNames)
    {
        foreach (var name in propertyNames)
        {
            _excludedMeasures.Add(name);
        }

        return this;
    }

    public PivotBuilder<T> AddStringDimensions()
    {
        foreach (PropertyInfo prop in GetProperties(typeof(string)))
        {
            AddDimension(GetLabel(prop.Name), x => (prop.GetValue(x) as string) ?? "(vacío)");
        }

        return this;
    }

    public PivotBuilder<T> AddDateDimensions(string format = "yyyy-MM")
    {
        foreach (PropertyInfo prop in GetProperties(typeof(DateTime?), typeof(DateTime)))
        {
            AddDimension(GetLabel(prop.Name), x =>
            {
                var value = prop.GetValue(x);
                return value is DateTime date
                    ? date.ToString(format)
                    : "(sin fecha)";
            });
        }

        return this;
    }

    public PivotBuilder<T> AutoDimensions()
    {
        AddStringDimensions();
        AddDateDimensions();
        return this;
    }

    public PivotBuilder<T> AddDecimalMeasures(string format = "{0:N2}")
    {
        foreach (PropertyInfo prop in GetMeasureProperties(typeof(decimal), typeof(decimal?)))
        {
            AddMeasure(GetLabel(prop.Name), x => x.Measure.Sum(item => (decimal)(prop.GetValue(item) ?? 0m)), format);
        }

        return this;
    }

    public PivotBuilder<T> AutoMeasures(string format = "{0:N2}")
    {
        AddDecimalMeasures(format);
        return this;
    }

    public PivotBuilder<T> AddCountMeasure(string label = "Cantidad", bool enabled = true)
    {
        _measures.Add(new()
        {
            DisplayValue = label,
            Aggragate = x => x.Measure.Count(),
            Format = "{0:N0}",
            Sequence = _measureSequence++,
            IsEnabled = enabled
        });

        return this;
    }

    public PivotBuilder<T> SetAsRow(params string[] propertyNames)
    {
        SetAxis(isRow: true, propertyNames);
        return this;
    }

    public PivotBuilder<T> SetAsColumn(params string[] propertyNames)
    {
        SetAxis(isRow: false, propertyNames);
        return this;
    }

    public PivotBuilder<T> EnableMeasure(string propertyName)
    {
        var label = GetLabel(propertyName);
        Measure<T> measure = _measures.FirstOrDefault(m => m.DisplayValue == label)
            ?? throw new InvalidOperationException(`$"No se encontró la medida para '{propertyName}'.");

        measure.IsEnabled = true;
        return this;
    }

    public List<Dimension<T>> BuildDimensions()
    {
        NormalizeDimensionSequences();
        return _dimensions;
    }

    public List<Measure<T>> BuildMeasures() => _measures;

    private void AddDimension(string displayValue, Func<T, string> accessor)
    {
        _dimensions.Add(new()
        {
            DisplayValue = displayValue,
            GroupValue = accessor,
            HeaderValue = accessor,
            IsEnabled = false,
            IsRow = false,
            IsExpanded = true,
            Sequence = _dimensionSequence++,
            IsAscending = true
        });
    }

    private void AddMeasure(string displayValue, Func<IMeasureData<T>, decimal> aggregator, string format)
    {
        _measures.Add(new()
        {
            DisplayValue = displayValue,
            Aggragate = aggregator,
            Format = format,
            Sequence = _measureSequence++,
            IsEnabled = false
        });
    }

    private void SetAxis(bool isRow, params string[] propertyNames)
    {
        int sequence = _dimensions
            .Where(d => d.IsEnabled && d.IsRow == isRow)
            .Select(d => d.Sequence)
            .DefaultIfEmpty(-1)
            .Max() + 1;

        foreach (string propertyName in propertyNames)
        {
            Dimension<T> dimension = FindDimension(propertyName);
            dimension.IsEnabled = true;
            dimension.IsRow = isRow;
            dimension.Sequence = sequence++;
        }

        NormalizeDimensionSequences();
    }

    private Dimension<T> FindDimension(string propertyName)
    {
        var label = GetLabel(propertyName);
        return _dimensions.FirstOrDefault(d => d.DisplayValue == label)
            ?? throw new InvalidOperationException(`$"No se encontró la dimensión para '{propertyName}'.");
    }

    private void NormalizeDimensionSequences()
    {
        int rowSequence = 0;
        foreach (Dimension<T> dim in _dimensions.Where(d => d.IsEnabled && d.IsRow).OrderBy(d => d.Sequence))
        {
            dim.Sequence = rowSequence++;
        }

        int columnSequence = 0;
        foreach (Dimension<T> dim in _dimensions.Where(d => d.IsEnabled && !d.IsRow).OrderBy(d => d.Sequence))
        {
            dim.Sequence = columnSequence++;
        }
    }

    private string GetLabel(string propertyName)
    {
        if (_labels.TryGetValue(propertyName, out var label))
        {
            return label;
        }

        PropertyInfo property = typeof(T).GetProperty(propertyName, BindingFlags.Public | BindingFlags.Instance);
        var displayName = property?.GetCustomAttribute<DisplayNameAttribute>()?.DisplayName;

        if (string.IsNullOrWhiteSpace(displayName) == false)
        {
            return displayName;
        }

        return CamelCaseSplitterRegex().Replace(propertyName, " ");
    }

    private IEnumerable<PropertyInfo> GetProperties(params Type[] types)
    {
        return typeof(T).GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .Where(p => types.Contains(p.PropertyType) && !_excludedDimensions.Contains(p.Name));
    }

    private IEnumerable<PropertyInfo> GetMeasureProperties(params Type[] types)
    {
        return typeof(T).GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .Where(p => types.Contains(p.PropertyType) && !_excludedMeasures.Contains(p.Name));
    }
}
"@ | Set-Content "src/Presentation/Views/Shared/Components/PivotBuilder.cs"

Write-Host "Creating CI/CD files..." -ForegroundColor Yellow

# Dockerfile
@"
# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG Configuration=Release
WORKDIR /src

# Copy project files
COPY src/Presentation/Client/$ProjectName.Web.csproj src/Presentation/Client/
COPY src/Domain/$ProjectName.Domain.csproj src/Domain/
COPY src/Application/ViewModels/$ProjectName.ViewModels.csproj src/Application/ViewModels/
COPY src/Infrastructure/WebApi/$ProjectName.WebApi.csproj src/Infrastructure/WebApi/
COPY src/Presentation/IoC/$ProjectName.IoC.csproj src/Presentation/IoC/
COPY src/Application/Validators/$ProjectName.Validators.csproj src/Application/Validators/
COPY src/Presentation/Views/$ProjectName.Views.csproj src/Presentation/Views/

# Restore dependencies
RUN dotnet restore src/Presentation/Client/$ProjectName.Web.csproj

# Copy all source code
COPY . .

# Publish project
WORKDIR /src/src/Presentation/Client
RUN dotnet publish $ProjectName.Web.csproj -c `$Configuration -o /app/publish

# Final stage (Nginx)
FROM nginx:alpine AS final
WORKDIR /usr/share/nginx/html

# Copy published files
COPY --from=build /app/publish/wwwroot .

# Copy custom nginx configuration
COPY src/Presentation/Client/nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

# Helper commands:
# docker build -f src/Presentation/Client/Dockerfile -t $($ProjectName.ToLower())-web:latest .
# docker container rm -f $($ProjectName.ToLower())-web
# docker run -d --name $($ProjectName.ToLower())-web -p $DockerPort1`:80 $($ProjectName.ToLower())-web:latest
"@ | Set-Content "src/Presentation/Client/Dockerfile"

# nginx.conf
@'
events { }
http {
    include /etc/nginx/mime.types;
    server {
        listen 80;
        root /usr/share/nginx/html;
        index index.html;
        location / {
            try_files $uri $uri/ /index.html;
        }
    }
}
'@ | Set-Content "src/Presentation/Client/nginx.conf"

# azure-pipelines.yml
@'
trigger:
    branches:
        include:
            - main

pool:
    vmImage: ubuntu-latest

steps:
- checkout: none

- task: SSH@0
    displayName: Deploy Web __PROJECT_NAME__
    inputs:
        sshEndpoint: UbuntuServer
        runOptions: inline
        inline: |
            cd /var/www/__PROJECT_DIR__/__PROJECT_NAME__
            chmod +x src/Presentation/Client/deploy.sh
            ./src/Presentation/Client/deploy.sh
        failOnStdErr: false
'@ | Set-Content "src/Presentation/Client/azure-pipelines.yml"

$projectDirName = "web-$($ProjectName.ToLower())"
$projectSlug = $ProjectName.ToLower().Replace('.', '-').Replace('_', '-')
$azurePipelinesContent = Get-Content -Raw "src/Presentation/Client/azure-pipelines.yml"
$azurePipelinesContent = $azurePipelinesContent.Replace("__PROJECT_DIR__", $projectDirName).Replace("__PROJECT_NAME__", $ProjectName)
$azurePipelinesContent | Set-Content "src/Presentation/Client/azure-pipelines.yml"

# deploy.sh
@'
#!/bin/bash
set -e

BASE_DIR="/var/www/__PROJECT_DIR__"
APP_DIR="$BASE_DIR/__PROJECT_NAME__"
IMAGE_NAME="web-__PROJECT_SLUG__"
BRANCH="main"
TZ="America/Mexico_City"
REPO_URL="https://davidvazquezpalestino.visualstudio.com/__PROJECT_NAME__/_git/__PROJECT_NAME__"

echo "====================================="
echo "Deploy Web __PROJECT_NAME__ (simple)"
echo "Rama: $BRANCH"
echo "Timezone: $TZ"
echo "====================================="

# 1. Obtener codigo
if [ ! -d "$APP_DIR/.git" ]; then
    echo "Clonando repositorio..."
    cd "$BASE_DIR"
    git clone -b $BRANCH $REPO_URL
else
    echo "Actualizando repositorio..."
    cd "$APP_DIR"
    git fetch origin
    git checkout $BRANCH
    git reset --hard origin/$BRANCH
fi

# 2. Build de imagen
echo "Construyendo imagen Docker..."
docker build -f src/Presentation/Client/Dockerfile -t $IMAGE_NAME .

# 3. Detener y eliminar contenedores existentes
echo "Eliminando contenedores previos..."
docker rm -f web-__PROJECT_SLUG__1 web-__PROJECT_SLUG__2 web-__PROJECT_SLUG__3 web-__PROJECT_SLUG__4 || true

# 4. Levantar nuevas instancias
echo "Levantando contenedores..."
docker run -d -p __DOCKER_PORT_1__:80 --name web-__PROJECT_SLUG__1 $IMAGE_NAME
docker run -d -p __DOCKER_PORT_2__:80 --name web-__PROJECT_SLUG__2 $IMAGE_NAME
docker run -d -p __DOCKER_PORT_3__:80 --name web-__PROJECT_SLUG__3 $IMAGE_NAME
docker run -d -p __DOCKER_PORT_4__:80 --name web-__PROJECT_SLUG__4 $IMAGE_NAME

echo "====================================="
echo "Deploy finalizado correctamente"
echo "====================================="
'@ | Set-Content "src/Presentation/Client/deploy.sh"

$deployScriptContent = Get-Content -Raw "src/Presentation/Client/deploy.sh"
$deployScriptContent = $deployScriptContent.Replace("__PROJECT_DIR__", $projectDirName).Replace("__PROJECT_NAME__", $ProjectName).Replace("__PROJECT_SLUG__", $projectSlug).Replace("__DOCKER_PORT_1__", "$DockerPort1").Replace("__DOCKER_PORT_2__", "$DockerPort2").Replace("__DOCKER_PORT_3__", "$DockerPort3").Replace("__DOCKER_PORT_4__", "$DockerPort4")
$deployScriptContent | Set-Content "src/Presentation/Client/deploy.sh"

# =========================
# CLEAN ARCHITECTURE DOC (Tío Bob)
# =========================
Write-Host "Writing documentation/architecture-guide.md..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "documentation" -Force | Out-Null
@'


# Guía de arquitectura — Blazor WebAssembly

Esta plantilla combina dos ideas: **Clean Architecture** (Robert C. Martin,
"Uncle Bob") y **Vertical Slice Architecture** (Jimmy Bogard).

- **Clean Architecture** organiza el código en capas concéntricas para que
  el dominio y la lógica de aplicación no dependan de frameworks, UI,
  HTTP o base de datos.
- **Vertical Slice Architecture** organiza el código por **features**
  (casos de uso) en lugar de por tipo de archivo. Cada feature agrupa
  todo lo necesario: modelos, reglas, validaciones, servicios, UI y tests.

> **Regla mnemotécnica:** primero capas (Clean), después rebanadas
> verticales (Vertical Slice).

---

## 1. ¿Qué problema resuelve?

Sin una guía, los proyectos Blazor suelen terminar con:

- Lógica de negocio dentro de los componentes `.razor`.
- `HttpClient` esparcido por toda la aplicación.
- Carpetas enormes de `Services`, `Models`, `Pages`, etc., desconectadas.
- Cambios pequeños que tocan muchos archivos en muchas carpetas.

La combinación de Clean + Vertical Slice evita eso:

- Cada feature es un **corte vertical** que contiene todo lo suyo.
- Dentro de cada feature, las dependencias apuntan hacia el dominio
  (Clean Architecture).
- Puedes añadir, modificar o borrar una feature sin tocar las demás.

---

## 2. Las capas (Clean Architecture)

Imagina un pastel en capas. El centro es lo más importante y lo que menos
cambia; las capas de afuera son detalles técnicos que puedes sustituir.

```
┌─────────────────────────────────────────────────────────┐
│  Presentation (UI)                                      │
│  Componentes .razor, layouts, Blazor, Tailwind CSS...   │  ← capa externa
├─────────────────────────────────────────────────────────┤
│  Infrastructure (adaptadores)                           │
│  HttpClient, localStorage, tokens, opciones...          │  ← detalles técnicos
├─────────────────────────────────────────────────────────┤
│  Application (casos de uso)                             │
│  ViewModels, validaciones, DTOs...                      │  ← orquestación
├─────────────────────────────────────────────────────────┤
│  Domain (reglas de negocio)                             │
│  Entidades, value objects, interfaces de puertos...     │  ← centro
└─────────────────────────────────────────────────────────┘
```

> **Regla:** las flechas de dependencia apuntan hacia abajo. La capa de
> arriba puede conocer a la de abajo, pero nunca al revés.

### 2.1 Domain — el centro

Contiene las reglas de negocio puras. No conoce Blazor, HTTP, JSON, etc.

- `Entities/`: objetos con identidad (`User`, `Order`).
- `ValueObjects/`: objetos inmutables (`Email`, `Money`).
- `Enums/`: enumeraciones de negocio.
- `Interfaces/`: **puertos** que expresan lo que el dominio necesita,
  p. ej. `IAuthService`, `IOrderWebApi`.

**Regla:** si tienes que importar `System.Net.Http` aquí, algo está mal.

### 2.2 Application — los casos de uso

Orquesta el dominio para resolver una necesidad concreta del usuario.

- `ViewModels/`: cada caso de uso expuesto como un ViewModel que la UI
  puede invocar (`LoginViewModel`, `CreateOrderViewModel`).
- `ViewModels/Base/`: clase base reutilizable (`ViewModelBase`) con
    `INotifyPropertyChanged`, manejo de errores (`GlobalApplicationException`) y
  paginación.
- `Validators/`: reglas de validación de entrada con FluentValidation.
- `Interfaces/`: puertos que la aplicación necesita (`IApiClient`).

Un ViewModel no sabe que existe `HttpClient`; solo conoce interfaces.

### 2.3 Infrastructure — los adaptadores

Implementa los puertos de Domain y Application.

- `WebApi/`: adaptador HTTP que consume la API remota.
- `WebApi/Auth/`: estado de autenticación, tokens e implementación de `IAuthService`.
- `WebApi/Handlers/`: `DelegatingHandler`s del pipeline `HttpClient`.
- `Options/`: configuración (`BaseUrl`, keys).

Es la única capa que conoce URLs, verbos HTTP y JSON de la API.

#### Manejo centralizado de errores HTTP

La plantilla incluye `GlobalExceptionHandler` (`DelegatingHandler`) para
unificar el tratamiento de errores de red y respuestas no exitosas de la API
remota. Infrastructure los traduce a `GlobalApplicationException`, que vive
en Domain, por lo que Application no depende de detalles HTTP.

- `GlobalExceptionHandler` intercepta cada solicitud saliente y:
    - Convierte `OperationCanceledException` por timeout en
        `GlobalApplicationException` con `ErrorKind.Timeout`.
    - Convierte `HttpRequestException` (sin conexión, DNS, etc.) en
        `GlobalApplicationException` con `ErrorKind.Network`.
  - Lee el cuerpo de respuestas no exitosas y genera un mensaje amigable.
  - Marca como transientes los errores recuperables (timeouts, 5xx, 429, etc.).
  - Extrae mensajes del payload JSON usando las propiedades comunes
    `detail`, `message`, `error`, `title` o el diccionario `errors`.

- `GlobalApplicationException` expone:
    - `UserMessage`: mensaje localizado y legible para el usuario.
  - `StatusCode`: código de estado HTTP devuelto por la API.
    - `Kind`: clasificación del error (`Network`, `Timeout`, `Validation`, etc.).
    - `IsRetryable`: indica si el error es candidato a reintentos.

Ejemplo de uso en un ViewModel:

```csharp
public async Task<string> SubmitAsync()
{
    try
    {
        return await authService.LoginAsync(email, password);
    }
    catch (GlobalApplicationException ex) when (ex.IsRetryable)
    {
        // Mostrar mensaje de reintento o exponerlo en la UI
        ErrorMessage = ex.UserMessage;
        return null;
    }
    catch (GlobalApplicationException ex)
    {
        ErrorMessage = ex.UserMessage;
        return null;
    }
}
```

### 2.4 Presentation — la entrega

Punto de entrada Blazor.

- `Client/`: host WebAssembly (`Program.cs`, `wwwroot`, `index.html`).
- `Views/`: Razor Class Library con componentes, layouts y páginas.
- `IoC/`: composición raíz donde se registran implementaciones concretas.

---

## 3. Regla de la dependencia

> Las dependencias del código fuente solo pueden apuntar hacia adentro.

```
Presentation   ──►  Application  ──►  Domain
Infrastructure ──►  Application  ──►  Domain
Infrastructure ──►  Domain
```

Nunca al revés:

- ❌ `Domain` no referencia `Application`, `Infrastructure` ni `Presentation`.
- ❌ `Application` no referencia `Infrastructure` ni `Presentation`.
- ✅ `Infrastructure` y `Presentation` sí referencian capas internas.

### 3.1 ¿Cómo se invierte la dependencia?

Ejemplo: el login necesita llamar a una API.

1. `Domain/Interfaces/Auth/IAuthService.cs` define el puerto.
2. `Infrastructure/WebApi/Auth/AuthWebApi.cs` implementa el puerto.
3. `Application/ViewModels/Auth/LoginViewModel.cs` depende de `IAuthService`.
4. `Presentation/IoC/DependencyContainer.cs` registra la implementación.
5. `Presentation/Views/Pages/Login.razor` usa `LoginViewModel`.

La interfaz pertenece a la capa interna; la implementación, a la externa.
Así las dependencias apuntan hacia adentro, aunque el flujo de control
vaya hacia la API.

### 3.2 Autenticación con JWT

La plantilla usa el proveedor de estado de autenticación nativo de Blazor:

1. `Domain/ValueObjects/Auth/UserSessionInfo.cs` describe la sesión.
2. `Domain/Interfaces/Auth/IJwtTokenService.cs` define lectura/escritura
   del token (en este caso, `localStorage`).
3. `Infrastructure/WebApi/Auth/JwtTokenService.cs` implementa el puerto con
   `IJSRuntime`.
4. `Presentation/Views/Shared/Auth/JwtAuthenticationStateProvider.cs`
   hereda de `AuthenticationStateProvider` y genera un `ClaimsPrincipal`
   a partir del token.
5. `Presentation/IoC/DependencyContainer.cs` registra
   `AuthenticationStateProvider` y `IJwtTokenService`.
6. `App.razor` envuelve el router con `<CascadingAuthenticationState>` y
   usa `<AuthorizeRouteView>` para redirigir al login cuando sea necesario.
7. Las páginas protegidas usan `@attribute [Authorize]`.

---

## 4. Organización por features (Vertical Slice)

Además de las capas, el código se organiza por **features**. Cada feature
es un caso de uso completo que agrupa todos sus archivos.

No hay una carpeta `Features` a nivel raíz. En su lugar, cada feature usa
subcarpetas con el mismo nombre dentro de cada capa.

### Ejemplo: Login

```
src
├── Domain
│   ├── ValueObjects/Auth/
│   │   └── UserSessionInfo.cs
│   └── Interfaces/Auth/
│       ├── IAuthService.cs
│       └── IJwtTokenService.cs
├── Application
│   ├── ViewModels/Auth/
│   │   ├── LoginRequest.cs
│   │   ├── LoginViewModel.cs
│   │   └── ILoginViewModel.cs
│   └── Validators/Auth/
│       └── LoginValidator.cs
├── Infrastructure
│   └── WebApi/Auth/
│       ├── AuthWebApi.cs
│       └── JwtTokenService.cs
└── Presentation
    └── Views/
        ├── Pages/
        │   ├── Login.razor
        │   ├── Login.razor.cs
        │   ├── Register.razor
        │   └── Register.razor.cs
        └── Shared/Auth/
            ├── JwtAuthenticationStateProvider.cs
            └── RedirectToLogin.razor

tests/UnitTests/Auth
├── LoginViewModelTests.cs
└── LoginValidatorTests.cs
```

### Ejemplo: CreateOrder (feature típica de negocio)

```
FEATURE: CreateOrder
────────────────────

src
├── Domain
│   ├── Entities/Orders/
│   │   └── Order.cs
│   └── Interfaces/Orders/
│       └── IOrderWebApi.cs
├── Application
│   ├── ViewModels/Orders/
│   │   ├── CreateOrderRequest.cs
│   │   ├── CreateOrderViewModel.cs
│   │   └── ICreateOrderViewModel.cs
│   └── Validators/Orders/
│       └── CreateOrderValidator.cs
├── Infrastructure
│   └── WebApi/Orders/
│       └── OrderWebApi.cs
└── Presentation
    └── Views/Pages/Orders/
        └── CreateOrder.razor

tests/UnitTests/Orders/CreateOrder
├── CreateOrderViewModelTests.cs
└── CreateOrderValidatorTests.cs
```

**Regla de oro:** si necesitas buscar por toda la solución para encontrar
los archivos de una feature, la organización está mal.

---

## 5. Estructura de carpetas de esta plantilla

```
/scripts-ps
  new-clean-arch-blazor.ps1          ← punto de entrada

/{ProjectName}
  /src
    /Presentation
      /Client                          Blazor WebAssembly host
        /Properties
        /wwwroot
      /Views                           Razor Class Library
        /Layout
        /Pages
      /IoC                             Composición de dependencias
    /Domain
      /Entities
      /ValueObjects
      /Enums
      /Interfaces
      /Shared/Errors
    /Application
      /ViewModels
      /Validators
    /Infrastructure
      /WebApi
        /Options
  /tests
    /UnitTests
  /documentation
    architecture-guide.md
    WCAG.md
```

Referencias entre proyectos:

| Proyecto        | Referencia a                       |
|-----------------|------------------------------------|
| Domain          | *(ninguna)*                        |
| Application     | Domain                             |
| Infrastructure  | Application, Domain                |
| Presentation    | Application, Infrastructure, Views |
| Views           | Application, Domain                |
| Client          | IoC, Views                         |
| UnitTests       | Domain, Application, Validators    |

---

## 6. Flujo de una interacción de usuario

```
Usuario / Navegador
   │
   ▼
Presentation/Views              (componentes .razor)
   │
   ▼
Application/ViewModels          (orquestador del caso de uso)
   │
   ▼
Application/Validators          (valida entrada)
   │
   ▼
Domain/Interfaces               (puerto)
   │
   ▼
Infrastructure/WebApi           (HttpClient hacia API remota)
   │
   ▼
API remota
   │
   ▼
Domain/Entities                 (reglas de negocio)
```

Reglas prácticas:

- Los componentes `.razor` no llaman directamente a `HttpClient`.
- Los ViewModels no usan `NavigationManager`, `IJSRuntime` ni `HttpClient`.
- Los Validators no acceden a la red.
- Infrastructure es el único lugar que conoce la API remota.
- El `HttpClient` se registra con `IHttpClientFactory` y el
  `GlobalExceptionHandler` se adjunta como `DelegatingHandler`.
- Los errores HTTP se traducen en Infrastructure a `GlobalApplicationException`;
    los ViewModels los procesan mediante `ViewModelBase.HandleException`.
- Los componentes leen `ViewModel.ErrorMessage` para mostrar mensajes amigables.
- La autenticación usa el patrón nativo de Blazor:
  `AuthenticationStateProvider`, `AuthorizeRouteView`, `[Authorize]` y
  `<CascadingAuthenticationState>`.
- El token JWT se almacena en `localStorage` a través de `IJwtTokenService`.
  `JwtAuthenticationStateProvider` notifica a la UI cuando el token cambia.

---

## 7. ¿Cómo añadir una nueva feature?

Sigue estos pasos para mantener el orden de capas y Vertical Slice:

1. **Domain:** define entidades, value objects e interfaces de puertos.
   - `Domain/Interfaces/{Feature}/I{Feature}Service.cs`
   - `Domain/Entities/{Feature}/{Entity}.cs`

2. **Application:** crea el ViewModel y el Validator.
   - Hereda de `Application/ViewModels/Base/ViewModelBase.cs` si necesitas
     `INotifyPropertyChanged`, manejo de errores o paginación.
   - `Application/ViewModels/{Feature}/{Action}ViewModel.cs`
   - `Application/ViewModels/{Feature}/{Action}Request.cs`
   - `Application/Validators/{Feature}/{Action}Validator.cs`

3. **Infrastructure:** implementa el puerto.
   - `Infrastructure/WebApi/{Feature}/{Feature}WebApi.cs`
   - Si el adaptador necesita un `DelegatingHandler` propio (por ejemplo,
     un header de correlación o reintentos por feature), regístralo en
     `Infrastructure/WebApi/Handlers/` y adjúntalo al `HttpClient` en
     `Program.cs` o en `DependencyContainer`.

4. **Presentation:** crea el componente Razor.
   - `Presentation/Views/Pages/{Feature}/{Action}.razor`
   - `Presentation/Views/Pages/{Feature}/{Action}.razor.cs`

5. **IoC:** registra la implementación si la inyección automática no la
   encuentra.

6. **Tests:** prueba el ViewModel y el Validator sin levantar Blazor ni
   `HttpClient`.

> **Tip:** si una feature es muy pequeña (como Auth), puedes agruparla
> en una sola carpeta por capa (`Auth/`) en lugar de crear una carpeta
> por acción.

---

## 8. Antipatrones a evitar

- ❌ Lógica de negocio en componentes `.razor`.
- ❌ Usar `HttpClient`, `NavigationManager` o `IJSRuntime` dentro de
  ViewModels.
- ❌ Definir interfaces de servicios externos en Infrastructure.
- ❌ Crear carpetas genéricas grandes como `Services/`, `Models/`,
  `Helpers/` fuera de una feature.
- ❌ Compartir request/response DTOs entre features sin necesidad.
- ❌ Duplicar lógica de `INotifyPropertyChanged` en cada ViewModel; usa
  `ViewModelBase`.

---

## 9. Beneficios de esta combinación

- **Cambios localizados:** una feature vive junta; tocarla no rompe otras.
- **Testabilidad:** Domain, Validators y ViewModels se prueban sin Blazor.
- **Sustituibilidad:** cambiar REST por gRPC, Tailwind CSS por MudBlazor o
  WebAssembly por MAUI es un cambio en una capa externa.
- **Escalabilidad cognitiva:** un desarrollador solo necesita entender la
  feature que está tocando.

---

## 10. Lecturas recomendadas

- Robert C. Martin — *Clean Architecture* (2017).
- Jimmy Bogard — *Vertical Slice Architecture*.
- Alistair Cockburn — *Hexagonal Architecture* (Ports & Adapters).
- Jeffrey Palermo — *Onion Architecture*.
- Vaughn Vernon — *Implementing Domain-Driven Design*.
- Microsoft — *Blazor WebAssembly documentation*.
```
'@ | Set-Content "documentation/architecture-guide.md"

# =========================
# WCAG 2.2 DOC (Accesibilidad)
# =========================
Write-Host "Writing documentation/WCAG.md..." -ForegroundColor Yellow
@'
> Resumen práctico de la [Quick Reference oficial de WCAG 2.2](https://www.w3.org/WAI/WCAG22/quickref/)
> del W3C. Pensado como chuleta para desarrolladores Blazor: qué mirar antes
> de hacer merge y qué no romper por accidente.

# WCAG 2.2 — Lo Importante en una Página (bueno, en varias)

**WCAG** = *Web Content Accessibility Guidelines*. Es el estándar
internacional para hacer contenido web accesible a personas con
discapacidad (visual, auditiva, motriz, cognitiva, etc.). La versión
vigente es **WCAG 2.2** (publicada en octubre de 2023).

---

## 1. Los 4 Principios (POUR)

Toda la norma se organiza alrededor de estos cuatro principios. Si algo
no encaja aquí, no es WCAG.

| # | Principio         | Idea en una línea                                                         |
|---|-------------------|---------------------------------------------------------------------------|
| 1 | **Perceivable**   | Los usuarios deben poder **percibir** la información (verla, oírla, leerla). |
| 2 | **Operable**      | Los usuarios deben poder **operar** la interfaz (teclado, ratón, gestos). |
| 3 | **Understandable**| La información y la operación deben ser **comprensibles**.                |
| 4 | **Robust**        | El contenido debe ser **robusto** para agentes actuales y futuros (incluida la tecnología de asistencia). |

Regla mnemotécnica: **POUR** (perceivable, operable, understandable, robust).
Si tu página no es POUR, no es accesible. Fin.

---

## 2. Niveles de conformidad

Cada criterio de éxito (SC = *Success Criterion*) tiene un nivel:

- **A**    → mínimo imprescindible. Si no lo cumples, hay usuarios que
  literalmente no pueden usar el sitio.
- **AA**   → nivel objetivo habitual (legislación europea EN 301 549,
  ADA en EE. UU., normativas de gobierno en muchos países).
- **AAA**  → nivel avanzado; no siempre alcanzable para todo el contenido,
  pero deseable donde aplique.

> **Regla práctica**: apunta a **WCAG 2.2 nivel AA** en todos los proyectos
> nuevos, salvo que un cliente exija AAA (raro).

---

## 3. Principio 1 — Perceivable

### 1.1 Text Alternatives
- **1.1.1 Non-text Content (A)**: toda imagen, icono o media no textual
  necesita un `alt` (o equivalente). Iconos decorativos → `alt=""` o
  `aria-hidden="true"`.

### 1.2 Time-based Media
- **1.2.1–1.2.5 (A/AA)**: audio/vídeo necesita **subtítulos**,
  **transcripciones** y/o **descripciones de audio**.
- Subtítulos también en directo (1.2.4 AA).

### 1.3 Adaptable
- **1.3.1 Info and Relationships (A)**: usa HTML semántico (`<nav>`,
  `<header>`, `<main>`, `<label for>`, `<th scope>`), no simules estructura
  con `<div>` y CSS.
- **1.3.2 Meaningful Sequence (A)**: el orden del DOM debe tener sentido
  leído linealmente (así lo leen los lectores de pantalla).
- **1.3.4 Orientation (AA)**: no bloquees la app a *portrait* o
  *landscape* salvo que sea imprescindible.
- **1.3.5 Identify Input Purpose (AA)**: usa `autocomplete="email"`,
  `"name"`, `"tel"`, etc., en los inputs.

### 1.4 Distinguishable
- **1.4.1 Use of Color (A)**: el color **no puede ser el único** canal de
  información (nada de "los errores en rojo" sin icono o texto).
- **1.4.3 Contrast (Minimum) (AA)**: contraste **4.5:1** para texto
  normal, **3:1** para texto grande (≥18pt o ≥14pt bold).
- **1.4.4 Resize Text (AA)**: el texto se puede ampliar al **200%** sin
  perder contenido o funcionalidad. Usa `rem`/`em`, no `px` fijos.
- **1.4.10 Reflow (AA)**: sin scroll horizontal a **320 CSS pixels** de
  ancho (mobile-first, diseño responsivo real).
- **1.4.11 Non-text Contrast (AA)**: controles (botones, bordes de
  inputs, iconos funcionales) con contraste **≥3:1**.
- **1.4.12 Text Spacing (AA)**: el diseño debe aguantar sin romperse si
  el usuario cambia `line-height`, `letter-spacing`, `word-spacing`,
  `paragraph-spacing`.
- **1.4.13 Content on Hover or Focus (AA)**: tooltips y popovers deben
  ser **descartables**, **hoverables** y **persistentes** (no se cierran
  al mover el ratón hacia ellos).

---

## 4. Principio 2 — Operable

### 2.1 Keyboard Accessible
- **2.1.1 Keyboard (A)**: **todo** debe poder hacerse solo con teclado.
- **2.1.2 No Keyboard Trap (A)**: nunca atrapes el foco en un componente
  sin salida (`Tab` y `Shift+Tab` siempre deben poder salir).
- **2.1.4 Character Key Shortcuts (A)**: si implementas atajos de tecla
  única (`s`, `k`, etc.), permite desactivarlos o remapearlos.

### 2.2 Enough Time
- **2.2.1 Timing Adjustable (A)**: si hay límite de tiempo, el usuario
  puede desactivarlo, extenderlo o ajustarlo (excepciones: subastas,
  tiempo real).
- **2.2.2 Pause, Stop, Hide (A)**: contenido en movimiento, parpadeante
  o auto-actualizado > 5 s → botón de pausa/parar/ocultar.

### 2.3 Seizures
- **2.3.1 Three Flashes or Below Threshold (A)**: nada que parpadee más
  de **3 veces por segundo** (previene ataques de fotosensibilidad).

### 2.4 Navigable
- **2.4.1 Bypass Blocks (A)**: enlace **"Saltar al contenido"** al inicio.
- **2.4.2 Page Titled (A)**: `<title>` descriptivo y único por página.
- **2.4.3 Focus Order (A)**: el orden de tabulación debe seguir un flujo
  lógico.
- **2.4.4 Link Purpose (In Context) (A)**: nada de `<a>click aquí</a>`.
  El texto del enlace debe indicar su destino/propósito.
- **2.4.6 Headings and Labels (AA)**: `<h1>…<h6>` y `<label>` claros.
- **2.4.7 Focus Visible (AA)**: **nunca** elimines `:focus` sin poner
  algo mejor. El indicador de foco debe verse siempre.
- **2.4.11 Focus Not Obscured (Minimum) (AA)** (novedad 2.2): el
  elemento con foco no debe quedar totalmente tapado por barras
  fijas, banners de cookies, etc.

### 2.5 Input Modalities
- **2.5.1 Pointer Gestures (A)**: cualquier gesto multi-punto o de
  trayectoria (pinch, swipe) debe tener alternativa de un solo toque.
- **2.5.3 Label in Name (A)**: el nombre accesible (`aria-label`,
  etc.) debe **contener** el texto visible del control (importante para
  reconocimiento de voz).
- **2.5.7 Dragging Movements (AA)** (novedad 2.2): toda acción por
  arrastre debe poder hacerse también sin arrastrar (con clics/pulsaciones).
- **2.5.8 Target Size (Minimum) (AA)** (novedad 2.2): áreas táctiles
  **≥ 24×24 CSS pixels**, con excepciones bien definidas.

---

## 5. Principio 3 — Understandable

### 3.1 Readable
- **3.1.1 Language of Page (A)**: `<html lang="es">` (o el que toque).
  **Sí, ese atributo**. Sí, siempre.
- **3.1.2 Language of Parts (AA)**: partes en otro idioma → `lang="…"`
  en el elemento (ej. citas en inglés dentro de un texto en español).

### 3.2 Predictable
- **3.2.1 On Focus (A)**: recibir foco **no** debe cambiar el contexto
  (nada de submits al enfocar).
- **3.2.2 On Input (A)**: cambiar un `select`/`checkbox` **no** debe
  navegar o enviar sin avisar antes.
- **3.2.3 Consistent Navigation (AA)**: la navegación debe estar en el
  mismo sitio en todas las páginas.
- **3.2.4 Consistent Identification (AA)**: mismos componentes → mismo
  nombre y mismo icono en todo el sitio.
- **3.2.6 Consistent Help (A)** (novedad 2.2): si ofreces ayuda
  (contacto, chat, FAQ), debe aparecer en la **misma posición
  relativa** en todas las páginas donde exista.

### 3.3 Input Assistance
- **3.3.1 Error Identification (A)**: si detectas un error de entrada,
  identifícalo **con texto** (no solo con color/borde rojo).
- **3.3.2 Labels or Instructions (A)**: todo input necesita `<label>`
  o instrucción clara.
- **3.3.3 Error Suggestion (AA)**: cuando puedas, sugiere cómo
  corregir el error.
- **3.3.4 Error Prevention (Legal, Financial, Data) (AA)**: acciones
  con consecuencias legales/financieras → **confirmación** o
  posibilidad de deshacer/revisar.
- **3.3.7 Redundant Entry (A)** (novedad 2.2): no pidas dos veces el
  mismo dato en el mismo proceso (o autocompléticalo).
- **3.3.8 Accessible Authentication (Minimum) (AA)** (novedad 2.2): no
  obligues a resolver puzzles cognitivos (recordar contraseñas,
  descifrar imágenes) sin ofrecer alternativa. Permite pegar
  contraseñas, autocompletar, usar gestores.

---

## 6. Principio 4 — Robust

### 4.1 Compatible
- **4.1.2 Name, Role, Value (A)**: todo componente de UI debe exponer
  **nombre**, **rol** y **estado** a la tecnología de asistencia. Usa
  controles HTML nativos siempre que puedas; si haces componentes
  custom, aplica ARIA correctamente.
- **4.1.3 Status Messages (AA)**: mensajes como "guardado",
  "cargando", "3 resultados" deben ser anunciados sin mover el foco.
  Usa `aria-live="polite"` o `role="status"`/`role="alert"`.

> ℹ️ En WCAG 2.2 el criterio **4.1.1 Parsing fue eliminado** (los
> parsers HTML modernos ya lo cubren). No pierdas tiempo con él.

---

## 7. Novedades WCAG 2.2 (checklist rápido)

Añadidos frente a 2.1:

- **2.4.11 Focus Not Obscured (Minimum) — AA**
- **2.4.12 Focus Not Obscured (Enhanced) — AAA**
- **2.4.13 Focus Appearance — AAA**
- **2.5.7 Dragging Movements — AA**
- **2.5.8 Target Size (Minimum) — AA**
- **3.2.6 Consistent Help — A**
- **3.3.7 Redundant Entry — A**
- **3.3.8 Accessible Authentication (Minimum) — AA**
- **3.3.9 Accessible Authentication (Enhanced) — AAA**

Eliminado: **4.1.1 Parsing**.

---

## 8. Traducción a Blazor (aplicación práctica)

Recomendaciones para esta solución (Blazor WebAssembly + Tailwind CSS):

- **HTML semántico**: prefiere `<button>` frente a `<div @onclick>`. Los
  `NavLink`, `EditForm`, `InputText`, etc., ya emiten HTML correcto —
  úsalos.
- **`<label>` para todo `<input>`**: en formularios Blazor, usa
  `<label for="id">` + `<InputText id="id" />` o envuelve el input dentro
  del `<label>`.
- **Foco tras navegación**: `FocusOnNavigate` (ya presente en `App.razor`)
  mueve el foco al `<h1>` de cada página tras navegar — no lo quites.
- **Mensajes de estado**: para "guardado", "error", "cargando…" usa un
  contenedor con `role="status"` o `aria-live="polite"`.
- **Errores de validación**: `ValidationMessage` y `ValidationSummary`
  son accesibles; asegúrate de asociarlos visualmente al campo y de que
  el mensaje se lea (no solo se pinte rojo).
- **Modales/diálogos**: si haces uno custom, gestiona el foco (atrápalo
  dentro mientras esté abierto, devuélvelo al abrir/cerrar), usa
  `role="dialog"` y `aria-modal="true"`.
- **Iconos**: si el icono es decorativo, ponle
  `aria-hidden="true"`. Si transmite significado, dale texto alternativo
  (`<span class="sr-only">Guardar</span>` o `aria-label`).
- **Contraste**: revisa los colores del tema Tailwind CSS con herramientas
  como *WebAIM Contrast Checker* o el panel *Accessibility* de DevTools.
- **Zoom / reflow**: prueba la app al 200% de zoom y a 320px de ancho.
- **Teclado**: navega toda la app **sin ratón**. Si te atascas, algo
  está mal.
- **Idioma**: `wwwroot/index.html` → `<html lang="es">` (ajusta según
  el idioma real del contenido).

---

## 9. Herramientas útiles

- **axe DevTools** (extensión de Chrome/Edge/Firefox): auditoría rápida.
- **Lighthouse** (integrado en DevTools): puntuación de accesibilidad.
- **WAVE** ([wave.webaim.org](https://wave.webaim.org)): revisión visual.
- **NVDA** (Windows) / **VoiceOver** (macOS/iOS) / **TalkBack**
  (Android): probar con lector de pantalla real.
- **Accessibility Insights for Web** (Microsoft): guiado, muy completo.
- **Contrast Checker** de WebAIM: verificar ratios de color.

> ⚠️ Ninguna herramienta automática detecta más del ~30% de los
> problemas de accesibilidad. La revisión manual con teclado y lector
> de pantalla es **imprescindible**.

---

## 10. Referencias

- [How to Meet WCAG (Quick Reference) — W3C](https://www.w3.org/WAI/WCAG22/quickref/)
- [WCAG 2.2 Recommendation](https://www.w3.org/TR/WCAG22/)
- [Understanding WCAG 2.2](https://www.w3.org/WAI/WCAG22/Understanding/)
- [ARIA Authoring Practices Guide (APG)](https://www.w3.org/WAI/ARIA/apg/)
- [WAI — Web Accessibility Initiative](https://www.w3.org/WAI/)
'@ | Set-Content "documentation/WCAG.md"

# README.md
Write-Host "Writing documentation/README.md..." -ForegroundColor Yellow
$readme = @'
# $ProjectName

Aplicación Blazor WebAssembly con Clean Architecture y Vertical Slice Architecture.

## Arquitectura

Este proyecto combina:
- **Clean Architecture**: Capas concéntricas donde el dominio es el centro
- **Vertical Slice Architecture**: Código organizado por features (casos de uso)

Para más detalles, consulta [architecture-guide.md](architecture-guide.md).

## Estructura del Proyecto

```text
src/
├── Domain/                    # Dominio y reglas de negocio
├── Application/ViewModels/   # ViewModels y modelos de aplicación
├── Application/Validators/   # Validaciones con FluentValidation
├── Infrastructure/WebApi/    # Servicios externos, HTTP clients
├── Presentation/Client/      # Blazor WebAssembly
├── Presentation/Views/       # Componentes Razor, Layouts
└── Presentation/IoC/         # Inyección de dependencias
```

## Configuración

Edita los archivos `appsettings.json` para configurar:
- API base URL
- Configuración de autenticación
- Configuración de logging

## Ejecutar

```bash
dotnet run --project src/Presentation/Client
```

La aplicación estará disponible en http://localhost:$HttpPort

## Tests

```bash
dotnet test
```

## Contribuir

Para conocer el flujo de trabajo con Git, convenciones de commits y el checklist antes de hacer push, consulta [CONTRIBUTING.md](CONTRIBUTING.md).

---
Powered by David Vázquez Palestino
'@
$readmeContent = $readme -replace '\$ProjectName', $ProjectName
$readmeContent = $readmeContent -replace '\$HttpPort', $HttpPort
$readmeContent | Set-Content "documentation/README.md"

# CONTRIBUTING.md
Write-Host "Writing documentation/CONTRIBUTING.md..." -ForegroundColor Yellow
$contributing = @'
# Guía de contribución — $ProjectName

Este documento describe el flujo de trabajo con Git, las convenciones de commits y el checklist que seguimos antes de subir cambios.

## Configuración inicial de Git

```bash
# Configurar identidad
git config --global user.name "Tu Nombre"
git config --global user.email "tu@email.com"

# Ver configuración
git config --list
```

## Flujo de ramas (GitHub Flow)

Usamos un modelo simple basado en ramas de corta duración:

1. `main` siempre debe estar en estado desplegable.
2. Cada cambio nace en una rama `feature/`, `fix/` o `docs/`.
3. Se abre un Pull Request antes de fusionar.
4. Se mergea solo después de revisión y checks exitosos.

```bash
# Actualizar la rama principal
git checkout main
git pull origin main

# Crear una rama de trabajo
git checkout -b feature/nombre-descriptivo

# Hacer cambios y commits
git add .
git commit -m "feat: descripción clara del cambio"

# Subir la rama
git push -u origin feature/nombre-descriptivo
```

## Convención de commits

Seguimos [Conventional Commits](https://www.conventionalcommits.org/) para mantener un historial legible y facilitar la generación de changelogs.

| Tipo      | Uso                                                   |
|-----------|-------------------------------------------------------|
| `feat`    | Nueva funcionalidad                                   |
| `fix`     | Corrección de un bug                                  |
| `docs`    | Cambios en documentación                              |
| `style`   | Formato, espacios, punto y coma                       |
| `refactor`| Reestructuración de código sin cambiar comportamiento |
| `test`    | Agregar o corregir tests                              |
| `chore`   | Tareas de mantenimiento, dependencias, etc.           |

Ejemplos:

```bash
git commit -m "feat(auth): agregar login con JWT"
git commit -m "fix(api): corregir manejo de timeouts"
git commit -m "docs(readme): actualizar instrucciones de ejecución"
```

## Comandos útiles

```bash
# Ver estado
git status

# Ver cambios antes de commitear
git diff

# Ver historial
git log --oneline --graph --decorate

# Descartar cambios locales no deseados
git checkout -- nombre-del-archivo

# Actualizar la rama actual con lo último de main
git pull origin main

# Resolver conflictos durante un merge
git status
# editar archivos en conflicto
git add .
git commit -m "merge: resolver conflictos con main"
```

## Checklist antes de hacer push

- [ ] El proyecto compila (`dotnet build`).
- [ ] Los tests pasan (`dotnet test`).
- [ ] No hay warnings que introduzcan deuda técnica.
- [ ] El mensaje de commit sigue la convención.
- [ ] La rama está actualizada con `main`.
- [ ] Se actualizó la documentación si el cambio lo requiere.
- [ ] Se revisó el diff antes de subir.

## Estilo de código

El repositorio incluye un archivo `.editorconfig`. Asegúrate de que tu editor lo respete para mantener la consistencia en:

- Indentación con 4 espacios en C# y Razor.
- Indentación con 2 espacios en JSON, YAML y similares.
- UTF-8 como codificación.
- Líneas finales normalizadas según el tipo de archivo.

---
Powered by David Vázquez Palestino
'@
$contributingContent = $contributing -replace '\$ProjectName', $ProjectName
$contributingContent | Set-Content "documentation/CONTRIBUTING.md"

# Register documentation folder as a Solution Folder in the .slnx file
$slnxFile = "$ProjectName.slnx"
if (Test-Path $slnxFile) {
    [xml]$slnx = Get-Content $slnxFile -Raw
    $root = $slnx.DocumentElement
    $folder = @($root.Folder) | Where-Object { $_ -and $_.Name -eq '/documentation/' } | Select-Object -First 1
    if (-not $folder) {
        $folder = $slnx.CreateElement('Folder')
        $folder.SetAttribute('Name', '/documentation/')
        [void]$root.AppendChild($folder)
    }
    foreach ($docPath in @('documentation/README.md', 'documentation/architecture-guide.md', 'documentation/WCAG.md', 'documentation/CONTRIBUTING.md')) {
        $hasFile = @($folder.File) | Where-Object { $_ -and $_.Path -eq $docPath } | Select-Object -First 1
        if (-not $hasFile) {
            $file = $slnx.CreateElement('File')
            $file.SetAttribute('Path', $docPath)
            [void]$folder.AppendChild($file)
        }
    }
    $slnx.Save((Resolve-Path $slnxFile))
}

# Git ignore
dotnet new gitignore

# .gitattributes
Write-Host "Writing .gitattributes..." -ForegroundColor Yellow
@'
* text=auto
*.cs text eol=crlf
*.razor text eol=crlf
*.cshtml text eol=crlf
*.css text eol=crlf
*.scss text eol=crlf
*.js text eol=crlf
*.ts text eol=crlf
*.json text eol=crlf
*.xml text eol=crlf
*.yml text eol=lf
*.yaml text eol=lf
*.sh text eol=lf
*.dockerfile text eol=lf
Dockerfile text eol=lf
'@ | Set-Content ".gitattributes"

# .editorconfig
Write-Host "Writing .editorconfig..." -ForegroundColor Yellow
@'
root = true

[*]
charset = utf-8
end_of_line = crlf
insert_final_newline = true
trim_trailing_whitespace = true

[*.cs]
indent_style = space
indent_size = 4

[*.razor]
indent_style = space
indent_size = 4

[*.{json,yml,yaml}]
indent_style = space
indent_size = 2

[*.md]
trim_trailing_whitespace = false

[*.{sh,bash}]
end_of_line = lf
'@ | Set-Content ".editorconfig"

Write-Host "Restoring packages..." -ForegroundColor Yellow
dotnet restore

Write-Host "Solution created successfully!" -ForegroundColor Green

Set-Location ..

Write-Host "`nProject Structure:" -ForegroundColor White
Write-Host "  src/Presentation/Client/      ($ProjectName.Web - Blazor Web Assembly)"           -ForegroundColor Gray
Write-Host "  src/Domain/                   ($ProjectName.Domain - Entities, Interfaces)"        -ForegroundColor Gray
Write-Host "  src/Application/ViewModels/   ($ProjectName.ViewModels - Use Cases, Services)"     -ForegroundColor Gray
Write-Host "  src/Application/Validators/   ($ProjectName.Validators - FluentValidation)"        -ForegroundColor Gray
Write-Host "  src/Infrastructure/WebApi/    ($ProjectName.WebApi - External Services, HTTP)"     -ForegroundColor Gray
Write-Host "  src/Presentation/Views/       ($ProjectName.Views - Razor Components, Layouts)"    -ForegroundColor Gray
Write-Host "  src/Presentation/IoC/         ($ProjectName.IoC - Dependency Injection)"           -ForegroundColor Gray
Write-Host ""
Write-Host "Powered by David Vazquez Palestino" -ForegroundColor DarkGray
