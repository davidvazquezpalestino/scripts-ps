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
New-Item -ItemType Directory -Path "src/Infrastructure/WebApi/Options" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Domain/Interfaces/Auth" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Infrastructure/WebApi/Auth" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Application/ViewModels/Auth" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Infrastructure/WebApi/Services" -Force | Out-Null
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
dotnet add tests/UnitTests package FluentAssertions

Write-Host "Creating GlobalUsings files..." -ForegroundColor Yellow

# Domain GlobalUsings
@"
"@ | Set-Content "src/Domain/GlobalUsings.cs"

# Application (ViewModels) GlobalUsings
@"
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
global using System.Reflection;
global using $ProjectName.Domain.Interfaces.Auth;

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
            services.AddSingleton<TokenService>();
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
        public static IServiceCollection AddIoC(this IServiceCollection services, IConfiguration configuration)
        {
            services.Configure<ApiOptions>(configuration.GetSection(ApiOptions.SectionKey));

            services.AddSingleton<$ProjectName.Views.Layout.NavMenuStateService>();

            services.AddViewModels()
                    .AddValidators()
                    .AddInfrastructure();
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
global using System.Net.Http.Json;
global using System.Reflection;
global using System.Text;
global using System.Text.Json;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
global using $ProjectName.WebApi.Options;
global using $ProjectName.Domain.Interfaces.Auth;
global using $ProjectName.WebApi.Services;
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
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Configuration;
global using FluentValidation;
global using $ProjectName.ViewModels;
global using $ProjectName.WebApi;
global using $ProjectName.WebApi.Options;
global using $ProjectName.Validators;
"@ | Set-Content "src/Presentation/IoC/GlobalUsings.cs"

# Client GlobalUsings
@"
global using $ProjectName.IoC;
global using $ProjectName.Views;
global using Microsoft.AspNetCore.Components.Web;
global using Microsoft.AspNetCore.Components.WebAssembly.Hosting;

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

var apiBaseUrl = builder.Configuration["ApiOptions:BaseUrl"] ?? builder.HostEnvironment.BaseAddress;
builder.Services.AddScoped(_ => new HttpClient { BaseAddress = new Uri(apiBaseUrl) });

builder.Services.AddIoC(builder.Configuration);

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
@inject IAuthState AuthState
@inject NavigationManager Navigation

<PageTitle>Index — 100% Clean Architecture (o eso dice el README)</PageTitle>

<div class="container-fluid px-3 px-md-4">
<div class="card shadow-sm my-4">
    <div class="card-header d-flex align-items-center bg-primary text-white">
        <i class="bi bi-hand-thumbs-up-fill me-2"></i>
        <h5 class="mb-0">¡Hola, mundo!</h5>
    </div>
    <div class="card-body">
        <p class="lead">
            Bienvenido a <strong>$ProjectName</strong>, una app Blazor recién salida del horno
            y con la Regla de la Dependencia apuntando religiosamente hacia adentro.
            <i class="bi bi-bullseye text-danger"></i>
        </p>

        <ul class="list-unstyled mb-3">
            <li><i class="bi bi-cup-hot-fill text-warning"></i> Café: <em>opcional pero recomendado</em>.</li>
            <li><i class="bi bi-layers-fill text-success"></i> Capas: como una cebolla, pero sin llorar (Onion Architecture approved).</li>
            <li><i class="bi bi-shield-lock-fill text-secondary"></i> Domain no sabe que existe la base de datos. Y así queremos que siga.</li>
            <li><i class="bi bi-bug-fill text-danger"></i> Si compila a la primera, revisa que no estés soñando.</li>
        </ul>

        <div class="alert alert-info d-flex align-items-center mb-0" role="alert">
            <i class="bi bi-info-circle-fill me-2"></i>
            <small>Borra esta página cuando decidas escribir código de verdad.
            Mientras tanto, disfruta del silencio productivo.</small>
        </div>
    </div>
    <div class="card-footer text-muted d-flex align-items-center">
        <i class="bi bi-tools me-2"></i>
        <small>Generado con <code>new-clean-arch-blazor.ps1</code> · Clean Architecture · Tío Bob approved</small>
    </div>
</div>
</div>

"@ | Set-Content "src/Presentation/Views/Pages/Index.razor"

# Index.razor.cs code-behind
@"
namespace $ProjectName.Views.Pages;

public partial class Index : ComponentBase
{
    protected override void OnInitialized()
    {
        if (!AuthState.IsAuthenticated)
        {
            Navigation.NavigateTo("/login");
        }
    }
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
        Task<string?> LoginAsync(string userEmail, string password, CancellationToken cancellationToken = default);
        void Logout();
    }
}
"@ | Set-Content "src/Domain/Interfaces/Auth/IAuthService.cs"

# IAuthState in Domain
@"
namespace $ProjectName.Domain.Interfaces.Auth
{
    public interface IAuthState
    {
        string? Token { get; }
        string? UserEmail { get; }
        bool IsAuthenticated { get; }
        event EventHandler? AuthenticationStateChanged;

        void SetToken(string token, string userEmail);
        void Clear();
    }
}
"@ | Set-Content "src/Domain/Interfaces/Auth/IAuthState.cs"

# TokenService in Infrastructure/WebApi/Services
@"
namespace $ProjectName.WebApi.Services
{
    public class TokenService
    {
        public string GenerateToken(string userEmail)
        {
            // TODO: Reemplazar por JWT real firmado en backend.
            // Token simulado: base64 de un payload JSON con el correo y expiración.
            var payload = new
            {
                email = userEmail,
                exp = DateTimeOffset.UtcNow.AddHours(8).ToUnixTimeSeconds()
            };
            var json = JsonSerializer.Serialize(payload);
            return Convert.ToBase64String(Encoding.UTF8.GetBytes(json));
        }
    }
}
"@ | Set-Content "src/Infrastructure/WebApi/Services/TokenService.cs"

# AuthState in Infrastructure/WebApi/Auth
@"
namespace $ProjectName.WebApi.Auth
{
    public class AuthState : IAuthState
    {
        public string? Token { get; private set; }
        public string? UserEmail { get; private set; }
        public bool IsAuthenticated => !string.IsNullOrWhiteSpace(Token);

        public event EventHandler? AuthenticationStateChanged;

        public void SetToken(string token, string userEmail)
        {
            Token = token;
            UserEmail = userEmail;
            OnAuthenticationStateChanged();
        }

        public void Clear()
        {
            Token = null;
            UserEmail = null;
            OnAuthenticationStateChanged();
        }

        private void OnAuthenticationStateChanged()
        {
            AuthenticationStateChanged?.Invoke(this, EventArgs.Empty);
        }
    }
}
"@ | Set-Content "src/Infrastructure/WebApi/Auth/AuthState.cs"

# AuthWebApi in Infrastructure/WebApi
@"
namespace $ProjectName.WebApi.Auth
{
    public class AuthWebApi(HttpClient httpClient, IAuthState authState, TokenService tokenService) : IAuthService
    {
        public async Task<string?> LoginAsync(string userEmail, string password, CancellationToken cancellationToken = default)
        {
            // TODO: Implementar llamada real a la API
            // var response = await httpClient.PostAsJsonAsync("api/auth/login", new { userEmail, password }, cancellationToken);
            // response.EnsureSuccessStatusCode();

            var token = tokenService.GenerateToken(userEmail);
            authState.SetToken(token, userEmail);
            return token;
        }

        public void Logout() => authState.Clear();
    }
}
"@ | Set-Content "src/Infrastructure/WebApi/Auth/AuthWebApi.cs"

# ILoginViewModel in Application/ViewModels/Auth
@"
namespace $ProjectName.ViewModels.Auth
{
    public interface ILoginViewModel
    {
        LoginRequest Request { get; set; }
        bool IsLoading { get; set; }
        string? ErrorMessage { get; set; }

        Task<string?> SubmitAsync();
        Task LogoutAsync();
    }
}
"@ | Set-Content "src/Application/ViewModels/Auth/ILoginViewModel.cs"

# LoginViewModel in Application/ViewModels/Auth
@"
namespace $ProjectName.ViewModels.Auth
{
    public class LoginViewModel(IAuthService authService, IAuthState authState) : ILoginViewModel
    {
        public LoginRequest Request { get; set; } = new();
        public bool IsLoading { get; set; }
        public string? ErrorMessage { get; set; }

        public async Task<string?> SubmitAsync()
        {
            IsLoading = true;
            ErrorMessage = null;

            try
            {
                return await authService.LoginAsync(Request.UserEmail, Request.Password);
            }
            catch (Exception ex)
            {
                ErrorMessage = ex.Message;
                return null;
            }
            finally
            {
                IsLoading = false;
            }
        }

        public Task LogoutAsync()
        {
            authService.Logout();
            return Task.CompletedTask;
        }
    }
}
"@ | Set-Content "src/Application/ViewModels/Auth/LoginViewModel.cs"

# Login.razor in Views/Pages
@"
@page "/login"
@inject ILoginViewModel ViewModel
@inject IAuthState AuthState
@inject NavigationManager Navigation

<PageTitle>Iniciar sesión</PageTitle>

<div class="d-flex flex-column justify-content-center align-items-center w-100 pt-4 pt-lg-5">
    <div class="card shadow-sm border-primary" style="max-width: 420px; width: 100%;">
        <div class="card-body p-4">
            <div class="text-center mb-4">
                <span class="d-inline-flex align-items-center justify-content-center rounded-circle bg-primary bg-opacity-10 text-primary mb-2"
                      style="width: 56px; height: 56px;">
                    <i class="bi bi-person-lock fs-3" aria-hidden="true"></i>
                </span>
                <h1 class="h4 mb-0">Iniciar sesión</h1>
                <p class="text-muted small mb-0">$ProjectName</p>
            </div>

            <EditForm Model="@ViewModel.Request" OnValidSubmit="@SubmitAsync" FormName="loginForm">
                <div class="mb-3">
                    <label for="loginEmail" class="form-label">User Email</label>
                    <InputText id="loginEmail"
                               type="email"
                               class="form-control"
                               placeholder="nombre@empresa.com"
                               @bind-Value="ViewModel.Request.UserEmail"
                               disabled="@ViewModel.IsLoading" />
                </div>

                <div class="mb-3">
                    <label for="loginPassword" class="form-label">Password</label>
                    <div class="input-group">
                        <InputText id="loginPassword"
                                   type="@LoginPasswordType"
                                   class="form-control"
                                   placeholder="••••••••"
                                   @bind-Value="ViewModel.Request.Password"
                                   disabled="@ViewModel.IsLoading" />
                        <button type="button"
                                class="btn btn-outline-secondary"
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
                    <div class="alert alert-danger d-flex align-items-start gap-2 py-2" role="alert">
                        <i class="bi bi-exclamation-triangle-fill" aria-hidden="true"></i>
                        <span class="small">@ViewModel.ErrorMessage</span>
                    </div>
                }

                <button type="submit"
                        class="btn btn-primary w-100 d-flex justify-content-center align-items-center gap-2"
                        disabled="@ViewModel.IsLoading">
                    @if (ViewModel.IsLoading)
                    {
                        <span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span>
                        <span>Iniciando sesión...</span>
                    }
                    else
                    {
                        <span>Iniciar sesión</span>
                    }
                </button>
            </EditForm>

            <div class="mt-3 text-center">
                <a href="registro" class="text-decoration-none small">¿No tienes cuenta? Regístrate</a>
            </div>
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
        var token = await ViewModel.SubmitAsync();
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

<div class="d-flex flex-column justify-content-center align-items-center w-100 px-3 py-4">
    <div class="card shadow-sm w-100" style="max-width: 420px; background: linear-gradient(135deg, #ffffff 0%, #f8f9fa 100%); border: 1px solid #0d6efd;">
        <div class="card-body p-4">
            <div class="text-center mb-4">
                <span class="d-inline-flex align-items-center justify-content-center rounded-circle bg-success bg-opacity-10 text-success mb-2"
                      style="width: 56px; height: 56px;">
                    <i class="bi bi-person-plus fs-3" aria-hidden="true"></i>
                </span>
                <h1 class="h4 mb-0">Crear cuenta</h1>
                <p class="text-muted small mb-0">$ProjectName</p>
            </div>

            <EditForm Model="@RegisterRequest" OnValidSubmit="@SubmitAsync" FormName="registerForm">
                <div class="mb-3">
                    <label for="registerName" class="form-label">Nombre</label>
                    <InputText id="registerName"
                               type="text"
                               class="form-control"
                               placeholder="Tu nombre"
                               @bind-Value="RegisterRequest.UserName"
                               disabled="@IsLoading" />
                </div>

                <div class="mb-3">
                    <label for="registerEmail" class="form-label">Correo electrónico</label>
                    <InputText id="registerEmail"
                               type="email"
                               class="form-control"
                               placeholder="nombre@empresa.com"
                               @bind-Value="RegisterRequest.UserEmail"
                               disabled="@IsLoading" />
                </div>

                <div class="mb-3">
                    <label for="registerPassword" class="form-label">Contraseña</label>
                    <div class="input-group">
                        <InputText id="registerPassword"
                                   type="@RegisterPasswordType"
                                   class="form-control"
                                   placeholder="••••••••"
                                   @bind-Value="RegisterRequest.Password"
                                   disabled="@IsLoading" />
                        <button type="button"
                                class="btn btn-outline-secondary"
                                @onclick="ToggleRegisterPasswordVisibility"
                                tabindex="-1"
                                title="@(IsRegisterPasswordVisible ? "Ocultar contraseña" : "Mostrar contraseña")"
                                aria-label="@(IsRegisterPasswordVisible ? "Ocultar contraseña" : "Mostrar contraseña")">
                            <i class="bi @(IsRegisterPasswordVisible ? "bi-eye-slash" : "bi-eye")" aria-hidden="true"></i>
                        </button>
                    </div>
                </div>

                <div class="mb-3">
                    <label for="registerConfirmPassword" class="form-label">Confirmar contraseña</label>
                    <div class="input-group">
                        <InputText id="registerConfirmPassword"
                                   type="@ConfirmPasswordType"
                                   class="form-control"
                                   placeholder="••••••••"
                                   @bind-Value="ConfirmPassword"
                                   disabled="@IsLoading" />
                        <button type="button"
                                class="btn btn-outline-secondary"
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
                    <div class="alert @(IsSuccess ? "alert-success" : "alert-danger") d-flex align-items-start gap-2 py-2" role="alert">
                        <i class="bi @(IsSuccess ? "bi-check-circle-fill" : "bi-exclamation-triangle-fill")" aria-hidden="true"></i>
                        <span class="small">@Message</span>
                    </div>
                }

                <button type="submit"
                        class="btn btn-success w-100 d-flex justify-content-center align-items-center gap-2"
                        disabled="@IsLoading">
                    @if (IsLoading)
                    {
                        <span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span>
                        <span>Registrando...</span>
                    }
                    else
                    {
                        <span>Registrarse</span>
                    }
                </button>
            </EditForm>

            <div class="mt-3 text-center">
                <a href="login" class="text-decoration-none small">¿Ya tienes cuenta? Inicia sesión</a>
            </div>
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
    private string? Message { get; set; }

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
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet" />
<link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet" />
"@

# Inject Bootstrap JS bundle before </body> (idempotent)
if ($content -notmatch 'bootstrap\.bundle\.min\.js') {
    $content = $content -replace '</body>', @'
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
'@
}

$content | Set-Content "src/Presentation/Client/wwwroot/index.html"

# Update default app.css font stack
$appCssPath = "src/Presentation/Client/wwwroot/css/app.css"
if (Test-Path $appCssPath) {
    $appCssContent = Get-Content -Raw -Path $appCssPath
    $appCssContent = $appCssContent -replace "(?m)^html,\s*body\s*\{\s*[\r\n]+\s*font-family:\s*'Helvetica Neue',\s*Helvetica,\s*Arial,\s*sans-serif;\s*[\r\n]+\s*\}", "html, body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    font-size: 14px;
}"
    if ($appCssContent -ne (Get-Content -Raw -Path $appCssPath)) {
        $appCssContent | Set-Content -Path $appCssPath -NoNewline
    }
}

# Views _Imports.razor
@"
@using Microsoft.AspNetCore.Components
@using Microsoft.AspNetCore.Components.Forms
@using Microsoft.Extensions.DependencyInjection
@using System.Net.Http.Json
@using Microsoft.AspNetCore.Components.Web
@using $ProjectName.Views.Layout
@using $ProjectName.Views.Shared.Components
@using Microsoft.AspNetCore.Components.Routing
@using $ProjectName.ViewModels.Auth
@using $ProjectName.Domain.Interfaces.Auth

"@ | Set-Content "src/Presentation/Views/_Imports.razor"

# Views GlobalUsings.cs
@"
global using $ProjectName.Domain.Interfaces.Auth;
global using $ProjectName.ViewModels.Auth;
global using $ProjectName.Views.Layout;
global using Microsoft.AspNetCore.Components;
global using Microsoft.AspNetCore.Components.Routing;
global using System;
global using System.Collections.Generic;
global using System.Text;
global using System.Text.Json;
"@ | Set-Content "src/Presentation/Views/GlobalUsings.cs"

# App.razor in Views root
@"
<Router AppAssembly="@typeof(App).Assembly">
    <Found Context="routeData">
        <RouteView RouteData="@routeData" DefaultLayout="@typeof(MainLayout)" />
        <FocusOnNavigate RouteData="@routeData" Selector="h1" />
    </Found>
    <NotFound>
        <PageTitle>Not found</PageTitle>
        <LayoutView Layout="@typeof(MainLayout)">
            <p role="alert">Sorry, there's nothing at this address.</p>
        </LayoutView>
    </NotFound>
</Router>

"@ | Set-Content "src/Presentation/Views/App.razor"

# NotFound.razor in Views/Pages
@"
<p>Sorry, there's nothing at this address.</p>
"@ | Set-Content "src/Presentation/Views/Pages/NotFound.razor"

# MainLayout.razor in Views/Layout
@"
@inherits LayoutComponentBase
@inject NavMenuStateService NavMenuState

<div class="d-flex min-vh-100">
    <NavMenu />

    <div class="d-flex flex-column flex-fill min-vw-0">
        <TopBar />

        <main id="main-content" class="flex-fill bg-light">
            <article class="p-3">
                @Body
            </article>
        </main>

        <footer class="px-3 px-md-4 py-2 d-flex flex-wrap align-items-center gap-2 border-top bg-white">
            <span class="text-muted small">
                <i class="bi bi-c-circle me-1" aria-hidden="true"></i>
                @DateTime.Now.Year $ProjectName
            </span>
            <span class="ms-auto d-inline-flex align-items-center gap-3">
                <span class="badge rounded-pill text-bg-light border">
                    <i class="bi bi-tag me-1" aria-hidden="true"></i>v1.0
                </span>
            </span>
        </footer>
    </div>
</div>

<div class="offcanvas offcanvas-start d-lg-none @(NavMenuState.IsOpen ? "show" : "")"
     tabindex="-1"
     aria-labelledby="mobileNavMenuLabel"
     style="visibility: @(NavMenuState.IsOpen ? "visible" : "hidden");">
    <div class="offcanvas-header border-bottom">
        <h5 class="offcanvas-title" id="mobileNavMenuLabel">$ProjectName</h5>
        <button type="button"
                class="btn-close text-reset"
                @onclick="NavMenuState.CloseOpen"
                aria-label="Cerrar menú">
        </button>
    </div>
    <div class="offcanvas-body p-0">
        <NavMenu />
    </div>
</div>
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

    private async void OnNavMenuStateChanged(object? sender, EventArgs e)
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
@inject NavigationManager Navigation

<nav class="d-none d-lg-flex flex-column bg-white text-dark flex-shrink-0"
     style="width: @(NavMenuState.IsCollapsed ? "60px" : "260px");"
     aria-label="Navegación principal">
    <div class="d-flex align-items-center justify-content-between p-3 border-bottom border-dark border-opacity-10" style="height: 56px;">
        <a class="d-inline-flex align-items-center gap-2 text-dark text-decoration-none fw-semibold text-nowrap overflow-hidden"
           href="" title="$ProjectName">
            <i class="bi bi-box-seam fs-4" aria-hidden="true"></i>
            <span class="@(NavMenuState.IsCollapsed ? "d-none" : "")">$ProjectName</span>
        </a>
    </div>

    <div class="flex-fill overflow-auto py-2 px-3">
        <ul class="list-unstyled ps-0 mb-0">
            <li class="mb-1">
                <a href="/"
                   class="btn btn-toggle d-inline-flex align-items-center justify-content-center rounded px-0 text-secondary w-100 text-decoration-none"
                   @onclick="OnLinkClicked">
                    <i class="bi bi-house-door fs-5" aria-hidden="true"></i>
                    <span class="@(NavMenuState.IsCollapsed ? "d-none" : "") ms-2">Home</span>
                </a>
            </li>
            <li class="mb-1">
                <a href="/"
                   class="btn btn-toggle d-inline-flex align-items-center justify-content-center rounded px-0 text-secondary w-100 text-decoration-none"
                   @onclick="OnLinkClicked">
                    <i class="bi bi-speedometer2 fs-5" aria-hidden="true"></i>
                    <span class="@(NavMenuState.IsCollapsed ? "d-none" : "") ms-2">Dashboard</span>
                </a>
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
    protected override void OnInitialized()
    {
        NavMenuState.Changed += OnStateChanged;
    }

    private async void OnStateChanged(object? sender, EventArgs e)
    {
        await InvokeAsync(StateHasChanged);
    }

    private void OnLinkClicked()
    {
        NavMenuState.CloseOpen();
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

    public event EventHandler? Changed;

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
@inject IAuthState AuthState
@inject ILoginViewModel ViewModel
@inject NavigationManager Navigation

<header class="navbar navbar-expand bg-white px-3 shadow-sm" style="height: 56px;">
    <div class="container-fluid">
        <div class="d-flex align-items-center">
            <button type="button"
                    class="btn btn-link nav-link text-dark p-0 me-3 d-lg-none"
                    @onclick="NavMenuStateService.ToggleOpen"
                    aria-label="Abrir menú"
                    aria-expanded="@NavMenuStateService.IsOpen">
                <i class="bi bi-list fs-4" aria-hidden="true"></i>
            </button>

            <button type="button"
                    class="btn btn-link nav-link text-dark p-0 me-3 d-none d-lg-inline-flex"
                    @onclick="NavMenuStateService.ToggleCollapsed"
                    aria-label="Contraer menú"
                    aria-expanded="@(!NavMenuStateService.IsCollapsed)">
                <i class="bi bi-list fs-4" aria-hidden="true"></i>
            </button>
        </div>

        <div class="ms-auto navbar-nav">
            @if (IsAuthenticated)
            {
                <div class="nav-item dropdown">
                    <button class="btn btn-link nav-link dropdown-toggle d-inline-flex align-items-center gap-2 text-dark"
                            type="button"
                            @onclick="ToggleUserMenu"
                            @onfocusout="OnUserMenuFocusOut"
                            aria-expanded="@IsUserMenuOpen"
                            aria-label="Menú de usuario">
                        <span class="d-inline-flex align-items-center justify-content-center rounded-circle bg-dark bg-opacity-10 text-dark"
                              style="width: 30px; height: 30px;">
                            <i class="bi bi-person fs-6" aria-hidden="true"></i>
                        </span>
                        <span class="text-truncate d-none d-sm-inline" style="max-width: 140px;">@UserDisplayName</span>
                    </button>

                    @if (IsUserMenuOpen)
                    {
                        <div class="dropdown-menu dropdown-menu-end shadow-sm border rounded-3 p-2 show"
                             style="min-width: 240px; position: absolute; z-index: 1050; right: 0;"
                             tabindex="-1"
                             @onfocusout="OnUserMenuFocusOut">
                            <div class="px-3 py-2">
                                <div class="fw-semibold">@UserDisplayName</div>
                                <div class="text-muted small text-break">@UserEmail</div>
                                @if (!string.IsNullOrEmpty(SessionExpiry))
                                {
                                    <div class="text-muted mt-1 small">
                                        <i class="bi bi-clock-history me-1" aria-hidden="true"></i>
                                        @SessionExpiry
                                    </div>
                                }
                            </div>
                            <div class="dropdown-divider"></div>
                            <button type="button"
                                    class="dropdown-item btn btn-light d-inline-flex align-items-center gap-2 rounded-2 w-100 text-start"
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
                <div class="nav-item d-inline-flex align-items-center gap-2">
                    <a href="login" class="nav-link text-dark py-0">Iniciar sesión</a>
                    <span class="text-muted">|</span>
                    <a href="registro" class="nav-link text-dark py-0">Registrarse</a>
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
    private EventHandler? _authStateChangedHandler;

    private bool IsAuthenticated => AuthState.IsAuthenticated;

    private string UserDisplayName => AuthState.UserEmail is { Length: > 0 } email
        ? (email.IndexOf('@') is > 0 and var at ? email[..at] : email)
        : "Usuario";

    private string UserEmail => AuthState.UserEmail ?? string.Empty;

    private string SessionExpiry => GetSessionExpiryFromToken();

    protected override void OnInitialized()
    {
        _authStateChangedHandler = (_, __) => StateHasChanged();
        AuthState.AuthenticationStateChanged += _authStateChangedHandler;
        Navigation.LocationChanged += OnLocationChanged;
    }

    private async void OnLocationChanged(object? sender, LocationChangedEventArgs e)
    {
        IsUserMenuOpen = false;
        await InvokeAsync(StateHasChanged);
    }

    public void Dispose()
    {
        if (_authStateChangedHandler != null)
            AuthState.AuthenticationStateChanged -= _authStateChangedHandler;
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

    private string GetSessionExpiryFromToken()
    {
        var token = AuthState.Token;
        if (string.IsNullOrWhiteSpace(token))
            return string.Empty;

        try
        {
            var json = Encoding.UTF8.GetString(Convert.FromBase64String(token));
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("exp", out var expProperty) && expProperty.TryGetInt64(out var exp))
            {
                var expiry = DateTimeOffset.FromUnixTimeSeconds(exp).ToLocalTime();
                return $"Expira: {expiry:HH:mm}";
            }
        }
        catch
        {
            // Ignorar errores de decodificación.
        }

        return string.Empty;
    }
}
"@ | Set-Content "src/Presentation/Views/Layout/TopBar.razor.cs"

# NavMenu.razor.css (no custom CSS — using Bootstrap utility classes in NavMenu.razor and MainLayout.razor)
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
/* Empty: layout uses Bootstrap utility classes. Keep file if you need component-scoped overrides later. */
"@ | Set-Content "src/Presentation/Views/Layout/MainLayout.razor.css"

# Login.razor.css (no custom CSS — using Bootstrap utility classes in Login.razor)
"" | Set-Content "src/Presentation/Views/Pages/Login.razor.css"

# PaginationComponent.razor in Views/Shared/Components
@"
@namespace $ProjectName.Views.Shared.Components

<div class="card-footer bg-white border-top py-2">
    <div class="d-flex flex-column flex-md-row justify-content-between align-items-center gap-2">
        <div class="text-muted small">
            Mostrando @CurrentItemsCount de @TotalCount
            @(TotalCount == 1 ? ItemName : ItemPluralName)
            @if (HasActiveFilters)
            {
                <span>(filtradas)</span>
            }
        </div>
        <div class="d-flex align-items-center gap-2">
            <div class="input-group input-group-sm" style="width: auto;">
                <label class="input-group-text bg-white" for="pageSizeSelect">Tamaño</label>
                <select class="form-select form-select-sm" id="pageSizeSelect"
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
                <ul class="pagination pagination-sm mb-0">
                    <li class="page-item @(CurrentPage == 1 ? "disabled" : "")">
                        <button class="page-link" @onclick="FirstPage" disabled="@(CurrentPage == 1)" aria-label="Primera página">
                            <i class="bi bi-chevron-double-left" aria-hidden="true"></i>
                        </button>
                    </li>
                    <li class="page-item @(CurrentPage == 1 ? "disabled" : "")">
                        <button class="page-link" @onclick="PreviousPage" disabled="@(CurrentPage == 1)" aria-label="Página anterior">
                            <i class="bi bi-chevron-left" aria-hidden="true"></i>
                        </button>
                    </li>
                    <li class="page-item disabled">
                        <span class="page-link" aria-current="page">Página @CurrentPage de @(Math.Max(1, TotalPages))</span>
                    </li>
                    <li class="page-item @(CurrentPage == TotalPages || TotalPages == 0 ? "disabled" : "")">
                        <button class="page-link" @onclick="NextPage" disabled="@(CurrentPage == TotalPages || TotalPages == 0)" aria-label="Página siguiente">
                            <i class="bi bi-chevron-right" aria-hidden="true"></i>
                        </button>
                    </li>
                    <li class="page-item @(CurrentPage == TotalPages || TotalPages == 0 ? "disabled" : "")">
                        <button class="page-link" @onclick="LastPage" disabled="@(CurrentPage == TotalPages || TotalPages == 0)" aria-label="Última página">
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

@if (IsLoading)
{
    <div class="d-flex justify-content-center align-items-center py-4">
        <div class="spinner-border text-primary" role="status" aria-label="Cargando">
            <span class="visually-hidden">Cargando...</span>
        </div>
    </div>
}
else if (Items == null || !Items.Any())
{
    <div class="text-center text-muted py-4">
        <i class="bi bi-inbox fs-1 d-block mb-2" aria-hidden="true"></i>
        <span>@EmptyMessage</span>
    </div>
}
else
{
    <div class="list-group">
        @foreach (var item in Items)
        {
            <div class="list-group-item list-group-item-action @ItemCssClass">
                @ItemTemplate(item)
            </div>
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
    [Parameter] public RenderFragment<TItem> ItemTemplate { get; set; } = _ => new RenderFragment(builder => { });
    [Parameter] public string Title { get; set; } = string.Empty;
    [Parameter] public string EmptyMessage { get; set; } = "No hay elementos para mostrar.";
    [Parameter] public bool IsLoading { get; set; }
    [Parameter] public string ItemCssClass { get; set; } = string.Empty;
    [Parameter] public RenderFragment? Actions { get; set; }
}
"@ | Set-Content "src/Presentation/Views/Shared/Components/ListComponent.razor.cs"

Write-Host "Creating CI/CD files..." -ForegroundColor Yellow

# Dockerfile
@"
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG Configuration=Release
WORKDIR /src
COPY src/Presentation/Client/$ProjectName.Web.csproj src/Presentation/Client/
COPY src/Domain/$ProjectName.Domain.csproj src/Domain/
COPY src/Application/ViewModels/$ProjectName.ViewModels.csproj src/Application/ViewModels/
COPY src/Infrastructure/WebApi/$ProjectName.WebApi.csproj src/Infrastructure/WebApi/
COPY src/Presentation/IoC/$ProjectName.IoC.csproj src/Presentation/IoC/
COPY src/Application/Validators/$ProjectName.Validators.csproj src/Application/Validators/
COPY src/Presentation/Views/$ProjectName.Views.csproj src/Presentation/Views/
RUN dotnet restore src/Presentation/Client/$ProjectName.Web.csproj
COPY . .
WORKDIR /src/src/Presentation/Client
RUN dotnet publish $ProjectName.Web.csproj -c `${Configuration} -o /app/publish

FROM nginx:alpine AS final
WORKDIR /usr/share/nginx/html
COPY --from=build /app/publish/wwwroot .
COPY src/Presentation/Client/nginx.conf /etc/nginx/nginx.conf
EXPOSE 80

#docker build -f src/Presentation/Client/Dockerfile -t "$($ProjectName.ToLower())-web:latest" .
#docker container rm -f "$($ProjectName.ToLower())-web"
#docker run -d --name "$($ProjectName.ToLower())-web" -p $($DockerPort1):80 "$($ProjectName.ToLower())-web:latest"
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
│  Componentes .razor, layouts, Blazor, bootstrap...      │  ← capa externa
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
- `Validators/`: reglas de validación de entrada con FluentValidation.
- `Interfaces/`: puertos que la aplicación necesita (`IApiClient`).

Un ViewModel no sabe que existe `HttpClient`; solo conoce interfaces.

### 2.3 Infrastructure — los adaptadores

Implementa los puertos de Domain y Application.

- `WebApi/`: adaptador HTTP que consume la API remota.
- `Options/`: configuración (`BaseUrl`, keys).
- `Auth/`, `LocalStorage/`, etc.: otros adaptadores técnicos.

Es la única capa que conoce URLs, verbos HTTP y JSON de la API.

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
│   ├── Entities/Auth/           (opcional: User, Session)
│   └── Interfaces/Auth/
│       ├── IAuthService.cs
│       └── IAuthState.cs
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
│       ├── AuthState.cs
│       └── TokenService.cs
└── Presentation
    └── Views/Pages/
        ├── Login.razor
        ├── Login.razor.cs
        ├── Register.razor
        └── Register.razor.cs

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

---

## 7. ¿Cómo añadir una nueva feature?

Sigue estos pasos para mantener el orden de capas y Vertical Slice:

1. **Domain:** define entidades, value objects e interfaces de puertos.
   - `Domain/Interfaces/{Feature}/I{Feature}Service.cs`
   - `Domain/Entities/{Feature}/{Entity}.cs`

2. **Application:** crea el ViewModel y el Validator.
   - `Application/ViewModels/{Feature}/{Action}ViewModel.cs`
   - `Application/ViewModels/{Feature}/{Action}Request.cs`
   - `Application/Validators/{Feature}/{Action}Validator.cs`

3. **Infrastructure:** implementa el puerto.
   - `Infrastructure/WebApi/{Feature}/{Feature}WebApi.cs`

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

---

## 9. Beneficios de esta combinación

- **Cambios localizados:** una feature vive junta; tocarla no rompe otras.
- **Testabilidad:** Domain, Validators y ViewModels se prueban sin Blazor.
- **Sustituibilidad:** cambiar REST por gRPC, Bootstrap por MudBlazor o
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

Recomendaciones para esta solución (Blazor WebAssembly + Bootstrap):

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
- **Iconos Bootstrap Icons**: si el icono es decorativo, ponle
  `aria-hidden="true"`. Si transmite significado, dale texto alternativo
  (`<span class="visually-hidden">Guardar</span>` o `aria-label`).
- **Contraste**: revisa los colores del tema Bootstrap con herramientas
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

## Git - Subir al repositorio

```bash
# Inicializar repositorio (si no existe)
git init

# Agregar todos los archivos
git add .

# Hacer commit inicial
git commit -m "Initial commit - Clean Architecture Blazor setup"

# Agregar repositorio remoto (reemplaza con tu URL)
git remote add origin https://github.com/tu-usuario/tu-repositorio.git

# Subir al repositorio (primera vez)
git push -u origin main

# O si usas master como rama principal
git push -u origin master
```

---
Powered by David Vázquez Palestino
'@
$readmeContent = $readme -replace '\$ProjectName', $ProjectName
$readmeContent = $readmeContent -replace '\$HttpPort', $HttpPort
$readmeContent | Set-Content "documentation/README.md"

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
    foreach ($docPath in @('documentation/README.md', 'documentation/architecture-guide.md', 'documentation/WCAG.md')) {
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
