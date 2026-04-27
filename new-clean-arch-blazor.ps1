param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "."
)

$ErrorActionPreference = "Stop"

if ($OutputPath -ne ".") {
    Set-Location $OutputPath
}

Write-Host "Creating Clean Architecture solution: $ProjectName" -ForegroundColor Cyan

New-Item -ItemType Directory -Path $ProjectName -Force | Out-Null
Set-Location $ProjectName

New-Item -ItemType Directory -Path "src" -Force | Out-Null

dotnet new sln -n $ProjectName

Write-Host "Creating Blazor Web Assembly project..." -ForegroundColor Yellow
dotnet new blazorwasm -n "$ProjectName.Web" -o "src/Client" --no-https

Write-Host "Removing Shared folder from Client..." -ForegroundColor Yellow
Remove-Item "src/Client/Shared" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Creating Class Library (Domain)..." -ForegroundColor Yellow
dotnet new classlib -n "$ProjectName.Domain" -o "src/Domain"

Write-Host "Creating Class Library (Application)..." -ForegroundColor Yellow
dotnet new classlib -n "$ProjectName.Application" -o "src/Application"

Write-Host "Creating Class Library (Infrastructure)..." -ForegroundColor Yellow
dotnet new classlib -n "$ProjectName.Infrastructure" -o "src/Infrastructure"

Write-Host "Creating Class Library (IoC)..." -ForegroundColor Yellow
dotnet new classlib -n "$ProjectName.IoC" -o "src/IoC"

Write-Host "Creating Class Library (Validators)..." -ForegroundColor Yellow
dotnet new classlib -n "$ProjectName.Validators" -o "src/Validators"

Write-Host "Creating Class Library (Views)..." -ForegroundColor Yellow
dotnet new razorclasslib -n "$ProjectName.Views" -o "src/Views"

Write-Host "Removing default Class1.cs files..." -ForegroundColor Yellow
Remove-Item "src/Domain/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Application/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Infrastructure/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/IoC/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Validators/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Views/Component1.razor" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Views/Component1.razor.css" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Views/ExampleJsInterop.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Client/App.razor" -Force -ErrorAction SilentlyContinue

Remove-Item -Path "src/Client/Layout" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "src/Client/Pages" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Creating folder structure..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "src/Domain/Interfaces" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Domain/Entities" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Domain/ValueObjects" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Domain/Enums" -Force | Out-Null
"" | Set-Content "src/Domain/Interfaces/.gitkeep"
"" | Set-Content "src/Domain/Entities/.gitkeep"
"" | Set-Content "src/Domain/ValueObjects/.gitkeep"
"" | Set-Content "src/Domain/Enums/.gitkeep"
New-Item -ItemType Directory -Path "src/Views/Layout" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Views/Pages" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Infrastructure/Options" -Force | Out-Null

Write-Host "Adding projects to solution..." -ForegroundColor Yellow
dotnet sln add src/Client
dotnet sln add src/Domain
dotnet sln add src/Application
dotnet sln add src/Infrastructure
dotnet sln add src/IoC
dotnet sln add src/Validators
dotnet sln add src/Views

Write-Host "Adding project references..." -ForegroundColor Yellow
dotnet add src/Application reference src/Domain
dotnet add src/Validators reference src/Domain
dotnet add src/Infrastructure reference src/Application
dotnet add src/Infrastructure reference src/Domain
dotnet add src/IoC reference src/Application
dotnet add src/IoC reference src/Domain
dotnet add src/IoC reference src/Infrastructure
dotnet add src/IoC reference src/Validators
dotnet add src/IoC reference src/Views
dotnet add src/Client reference src/IoC
dotnet add src/Client reference src/Views
dotnet add src/Views reference src/Domain
dotnet add src/Views reference src/Application

Write-Host "Adding NuGet packages..." -ForegroundColor Yellow
dotnet add src/Application package DependencyInjection.ReflectionExtensions
dotnet add src/Application package FluentValidation
dotnet add src/Validators package DependencyInjection.ReflectionExtensions
dotnet add src/Validators package FluentValidation
dotnet add src/Infrastructure package DependencyInjection.ReflectionExtensions
dotnet add src/IoC package DependencyInjection.ReflectionExtensions
dotnet add src/IoC package FluentValidation
dotnet add src/IoC package Microsoft.Extensions.Configuration.Abstractions

Write-Host "Creating GlobalUsings files..." -ForegroundColor Yellow

# Domain GlobalUsings
@"
"@ | Set-Content "src/Domain/GlobalUsings.cs"

# Application GlobalUsings
@"
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
global using System.Reflection;

"@ | Set-Content "src/Application/GlobalUsings.cs"

# Application DependencyContainer
@"
namespace $ProjectName.Application
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddApplication(this IServiceCollection services)
        {  
            services.AddCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Application/DependencyContainer.cs"

# DependencyContainers
# Infrastructure DependencyContainer
@"
namespace $ProjectName.Infrastructure
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddInfrastructure(this IServiceCollection services)
        {  
           services.AddCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Infrastructure/DependencyContainer.cs"

# Validators DependencyContainer
@"
namespace $ProjectName.Validators
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddValidators(this IServiceCollection services)
        {  
            services.AddCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Validators/DependencyContainer.cs"

# IoC DependencyContainer
@"
namespace $ProjectName.IoC
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddIoC(this IServiceCollection services, IConfiguration configuration)
        {
            services.Configure<ApiOptions>(configuration.GetSection(ApiOptions.SectionKey));

            services.AddApplication()
                    .AddValidators()
                    .AddInfrastructure();
            return services;
        }
    }
}
"@ | Set-Content "src/IoC/DependencyContainer.cs"

# Infrastructure Options
# ApiOptions class in Infrastructure
@"
namespace $ProjectName.Infrastructure.Options
{
    public class ApiOptions
    {
        public const string SectionKey = nameof(ApiOptions);
        public string BaseUrl { get; set; }
    }
}
"@ | Set-Content "src/Infrastructure/Options/ApiOptions.cs"

# Infrastructure GlobalUsings
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
global using $ProjectName.Infrastructure.Options;
"@ | Set-Content "src/Infrastructure/GlobalUsings.cs"

# Validators GlobalUsings
@"
global using System.Reflection;
global using Microsoft.Extensions.DependencyInjection;
global using DevKit.Injection.Extensions;
global using FluentValidation;
"@ | Set-Content "src/Validators/GlobalUsings.cs"

# IoC GlobalUsings
@"
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Configuration;
global using FluentValidation;
global using $ProjectName.Application;
global using $ProjectName.Infrastructure;
global using $ProjectName.Infrastructure.Options;
global using $ProjectName.Validators;
"@ | Set-Content "src/IoC/GlobalUsings.cs"

# Client GlobalUsings
@"
global using $ProjectName.IoC;
global using $ProjectName.Views;
global using Microsoft.AspNetCore.Components.Web;
global using Microsoft.AspNetCore.Components.WebAssembly.Hosting;

"@ | Set-Content "src/Client/GlobalUsings.cs"

# Client Program.cs update
@"

WebAssemblyHostBuilder builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");

builder.Services.AddIoC(builder.Configuration);

await builder.Build().RunAsync();
"@ | Set-Content "src/Client/Program.cs"

# Client appsettings.json
@"
{
  "ApiOptions": {
    "BaseUrl": "https://localhost:5001"
  }
}
"@ | Set-Content "src/Client/wwwroot/appsettings.json"

Remove-Item "src/Client/App.razor" -Force -ErrorAction SilentlyContinue

# Client Index.razor update
New-Item -ItemType Directory -Path "src/Client/Pages" -Force | Out-Null
@"
@page "/"

<PageTitle>Index</PageTitle>

<h1>Hello, world!</h1>

Welcome to your new app.

"@ | Set-Content "src/Client/Pages/Index.razor"

# Client _Imports.razor update
@"
@using Microsoft.AspNetCore.Components.Web
"@ | Set-Content "src/Client/_Imports.razor"

# Client index.html update
$content = Get-Content "src/Client/wwwroot/index.html" -Raw
$content = $content -replace "<link href=`"$ProjectName.Web.styles.css`" rel=`"stylesheet`" />", @"
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet" />
<link href="$ProjectName.Web.styles.css" rel="stylesheet" />
<link href="_content/$ProjectName.Views/css/icons-custom.css" rel="stylesheet" />
<link href="_content/$ProjectName.Views/css/hero-logo.css" rel="stylesheet" />
"@

$content | Set-Content "src/Client/wwwroot/index.html"

# Views _Imports.razor
@"
@using Microsoft.AspNetCore.Components
@using Microsoft.Extensions.DependencyInjection
@using System.Net.Http.Json
@using Microsoft.AspNetCore.Components.Web
@using $ProjectName.Views.Layout
@using Microsoft.AspNetCore.Components.Routing

"@ | Set-Content "src/Views/_Imports.razor"

# App.razor in Views root
@"
<Router AppAssembly="@typeof(App).Assembly">
    <Found Context="routeData">
        <RouteView RouteData="@routeData" />
        <FocusOnNavigate RouteData="@routeData" Selector="h1" />
    </Found>
    <NotFound>
        <PageTitle>Not found</PageTitle>
        <p role="alert">Sorry, there's nothing at this address.</p>
    </NotFound>
</Router>

"@ | Set-Content "src/Views/App.razor"

# NotFound.razor in Views/Pages
@"
<p>Sorry, there's nothing at this address.</p>
"@ | Set-Content "src/Views/Pages/NotFound.razor"

# MainLayout.razor in Views/Layout
@"
@inherits LayoutComponentBase
<div class="page">
    <div class="sidebar">
        <NavMenu />
    </div>

    <main>
        <div class="top-row px-4">
            <a href="https://learn.microsoft.com/aspnet/core/" target="_blank">About</a>
        </div>

        <article class="content px-4">
            @Body
        </article>
    </main>
</div>

"@ | Set-Content "src/Views/Layout/MainLayout.razor"

# NavMenu.razor in Views/Layout
@"
<div class="top-row ps-3 navbar navbar-dark">
    <div class="container-fluid">
        <a class="navbar-brand" href="">$ProjectName.Web</a>
        <button title="Navigation menu" class="navbar-toggler" @onclick="ToggleNavMenu">
            <span class="navbar-toggler-icon"></span>
        </button>
    </div>
</div>

<div class="@NavMenuCssClass nav-scrollable" @onclick="ToggleNavMenu">
    <nav class="nav flex-column">
        <div class="nav-item px-3">
            <NavLink class="nav-link" href="" Match="NavLinkMatch.All">
                <span class="bi bi-house-door-fill-nav-menu" aria-hidden="true"></span> Home
            </NavLink>
        </div>
        <div class="nav-item px-3">
            <NavLink class="nav-link" href="counter">
                <span class="bi bi-plus-square-fill-nav-menu" aria-hidden="true"></span> Counter
            </NavLink>
        </div>
        <div class="nav-item px-3">
            <NavLink class="nav-link" href="weather">
                <span class="bi bi-list-nested-nav-menu" aria-hidden="true"></span> Weather
            </NavLink>
        </div>
    </nav>
</div>

@code {
    private bool collapseNavMenu = true;

    private string? NavMenuCssClass => collapseNavMenu ? "collapse" : null;

    private void ToggleNavMenu()
    {
        collapseNavMenu = !collapseNavMenu;
    }
}

"@ | Set-Content "src/Views/Layout/NavMenu.razor"
Write-Host "Restoring packages..." -ForegroundColor Yellow
dotnet restore

Write-Host "Solution created successfully!" -ForegroundColor Green

Set-Location ..

Write-Host "`nProject Structure:" -ForegroundColor White
Write-Host "  $ProjectName.Web/          (Blazor Web Assembly)" -ForegroundColor Gray
Write-Host "  $ProjectName.Domain/       (Entities + Interfaces/)" -ForegroundColor Gray
Write-Host "  $ProjectName.Application/  (Use Cases, Services)" -ForegroundColor Gray
Write-Host "  $ProjectName.Validators/   (FluentValidation)" -ForegroundColor Gray
Write-Host "  $ProjectName.Infrastructure/ (Data, External Services)" -ForegroundColor Gray
Write-Host "  $ProjectName.Views/        (View Models, DTOs)" -ForegroundColor Gray
Write-Host "  $ProjectName.IoC/          (Dependency Injection Orchestrator)" -ForegroundColor Gray