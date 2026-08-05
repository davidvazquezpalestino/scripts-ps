# =========================================================================
#  new-console.ps1
#  Powered by David Vazquez Palestino
# =========================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName
)

Write-Host "Creating Console project: $ProjectName"

# Root
New-Item -ItemType Directory -Path $ProjectName | Out-Null
Set-Location $ProjectName

# Solution
dotnet new sln -n "$ProjectName"

# =========================
# CREATE PROJECTS (Hexagonal Architecture)
# =========================
# Cada proyecto vive dentro de su propia subcarpeta para que bin/obj queden aislados
# y la carpeta-capa (Application, Infrastructure, etc.) pueda alojar proyectos hermanos.

# Domain
dotnet new classlib -n "$ProjectName.Domain" -o "src/Domain"

# Application
dotnet new classlib -n "$ProjectName.Services" -o "src/Application/Services"

# Infrastructure
dotnet new classlib -n "$ProjectName.Adapters" -o "src/Infrastructure/Adapters"

# IoC
dotnet new classlib -n "$ProjectName.IoC" -o "src/Presentation/IoC"

# Console (Presentation layer)
dotnet new console -n "$ProjectName.Console" -o "src/Presentation/Console"

# =========================
# ADD TO SOLUTION
# =========================
dotnet sln add src/Domain
dotnet sln add src/Application/Services
dotnet sln add src/Infrastructure/Adapters
dotnet sln add src/Presentation/IoC
dotnet sln add src/Presentation/Console

# =========================
# PROJECT REFERENCES
# =========================
# Application depends on Domain
dotnet add src/Application/Services reference src/Domain

# Infrastructure depends on Application and Domain (implements ports)
dotnet add src/Infrastructure/Adapters reference src/Application/Services
dotnet add src/Infrastructure/Adapters reference src/Domain

# IoC composes all layers
dotnet add src/Presentation/IoC reference src/Application/Services
dotnet add src/Presentation/IoC reference src/Infrastructure/Adapters
dotnet add src/Presentation/IoC reference src/Domain

# Console depends only on IoC
dotnet add src/Presentation/Console reference src/Presentation/IoC

# =========================
# ADD PACKAGES
# =========================
# Application
dotnet add src/Application/Services package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Application/Services package Microsoft.Extensions.Options
dotnet add src/Application/Services package DependencyInjection.ReflectionExtensions

# Infrastructure
dotnet add src/Infrastructure/Adapters package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Infrastructure/Adapters package DependencyInjection.ReflectionExtensions

# IoC
dotnet add src/Presentation/IoC package Microsoft.Extensions.Hosting
dotnet add src/Presentation/IoC package Microsoft.Extensions.Configuration
dotnet add src/Presentation/IoC package Microsoft.Extensions.Configuration.Json
dotnet add src/Presentation/IoC package Microsoft.Extensions.Configuration.EnvironmentVariables
dotnet add src/Presentation/IoC package Microsoft.Extensions.Configuration.Binder
dotnet add src/Presentation/IoC package Microsoft.Extensions.DependencyInjection
dotnet add src/Presentation/IoC package Microsoft.Extensions.Options.ConfigurationExtensions
dotnet add src/Presentation/IoC package DependencyInjection.ReflectionExtensions

# Console
dotnet add src/Presentation/Console package Microsoft.Extensions.Hosting

# =========================
# REMOVE DEFAULT CLASS1.cs
# =========================
Remove-Item "src/Domain/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Application/Services/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Infrastructure/Adapters/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Presentation/IoC/Class1.cs" -Force -ErrorAction SilentlyContinue

# Remove <Nullable>enable</Nullable> from every generated .csproj
Get-ChildItem -Path 'src' -Recurse -Filter *.csproj | ForEach-Object {
    $c = Get-Content -Raw -Path $_.FullName
    $n = $c -replace '(?m)^[ \t]*<Nullable>\s*enable\s*</Nullable>[ \t]*\r?\n', ''
    if ($n -ne $c) { Set-Content -Path $_.FullName -Value $n -NoNewline }
}

# =========================
# CREATE BASE FOLDERS
# =========================
New-Item -ItemType Directory -Path "src/Domain/Entities" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Domain/Ports" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Application/Services/UseCases" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Application/Services/Options" -Force | Out-Null

# Keep folders visible in Visual Studio Solution Explorer
"" | Set-Content "src/Domain/Entities/.gitkeep"
"" | Set-Content "src/Domain/Ports/.gitkeep"

# =========================
# CREATE BASIC FILES
# =========================

# appsettings.json
@"
{
    "EnvironmentOptions": {
        "EnvironmentName": "Production"
    },
    "Logging": {
        "LogLevel": {
            "Default": "Information",
            "Microsoft": "Warning"
        }
    }
}
"@ | Set-Content "src/Presentation/Console/appsettings.json"

# appsettings.Development.json
@"
{
    "Logging": {
        "LogLevel": {
            "Default": "Debug"
        }
    }
}
"@ | Set-Content "src/Presentation/Console/appsettings.Development.json"

# Configure csproj to copy appsettings on build
$csprojPath = "src/Presentation/Console/$ProjectName.Console.csproj"
[xml]$csprojXml = Get-Content $csprojPath
$itemGroup = $csprojXml.CreateElement("ItemGroup")
foreach ($file in @("appsettings.json", "appsettings.Development.json")) {
    $none = $csprojXml.CreateElement("None")
    $none.SetAttribute("Update", $file)
    $copy = $csprojXml.CreateElement("CopyToOutputDirectory")
    $copy.InnerText = "PreserveNewest"
    $none.AppendChild($copy) | Out-Null
    $itemGroup.AppendChild($none) | Out-Null
}
$csprojXml.Project.AppendChild($itemGroup) | Out-Null
$csprojXml.Save((Resolve-Path $csprojPath))

# Domain port (hexagonal architecture)
@"
namespace $ProjectName.Domain.Ports
{
    public interface IGreetingService
    {
        string GetGreeting(string name);
    }
}
"@ | Set-Content "src/Domain/Ports/IGreetingService.cs"

# Domain GlobalUsings
@"
global using $ProjectName.Domain.Ports;
"@ | Set-Content "src/Domain/GlobalUsings.cs"

# Application use case interface
@"
namespace $ProjectName.Services.UseCases
{
    public interface IGreetingUseCase
    {
        string Execute(string name);
    }
}
"@ | Set-Content "src/Application/Services/UseCases/IGreetingUseCase.cs"

# Application service / use case (hexagonal architecture)
@"
namespace $ProjectName.Services.UseCases
{
    public class GreetingUseCase(IGreetingService greetingService, IOptions<EnvironmentOptions> options) : IGreetingUseCase
    {
        public string Execute(string name)
        {
            var env = options.Value.EnvironmentName;
            return greetingService.GetGreeting($"{name} ({env})");
        }
    }
}
"@ | Set-Content "src/Application/Services/UseCases/GreetingUseCase.cs"



# Infrastructure adapter (hexagonal architecture)
@"
namespace $ProjectName.Adapters
{
    public class ConsoleGreetingAdapter : IGreetingService
    {
        public string GetGreeting(string name) => $"Hello, {name}! Welcome to the hexagonal console app.";
    }
}
"@ | Set-Content "src/Infrastructure/Adapters/ConsoleGreetingAdapter.cs"

# Application Options
@"
namespace $ProjectName.Services.Options
{
    public class EnvironmentOptions
    {
        public const string SectionKey = nameof(EnvironmentOptions);
        public string EnvironmentName { get; set; } = "Production";
    }
}
"@ | Set-Content "src/Application/Services/Options/EnvironmentOptions.cs"

# Application GlobalUsings
@"
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Options;
global using $ProjectName.Domain.Ports;
global using $ProjectName.Services.Options;
"@ | Set-Content "src/Application/Services/GlobalUsings.cs"

# Infrastructure DependencyContainer
@"
namespace $ProjectName.Adapters
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddAdapters(this IServiceCollection services)
        {  
            services.AddCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Infrastructure/Adapters/DependencyContainer.cs"

# Infrastructure GlobalUsings
@"
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Options;
global using $ProjectName.Domain.Ports;
global using $ProjectName.Services.Options;
global using $ProjectName.Services.UseCases;
"@ | Set-Content "src/Infrastructure/Adapters/GlobalUsings.cs"

# Application DependencyContainer
@"
namespace $ProjectName.Services
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddUseCases(this IServiceCollection services)
        {  
            services.AddCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Application/Services/DependencyContainer.cs"

# IoC DependencyContainer
@"
namespace $ProjectName.IoC
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddIoC(this IServiceCollection services, IConfiguration configuration)
        {
            services.Configure<EnvironmentOptions>(configuration.GetSection(EnvironmentOptions.SectionKey));
            services.AddAdapters()
                    .AddUseCases();
            return services;
        }
    }
}
"@ | Set-Content "src/Presentation/IoC/DependencyContainer.cs"

# IoC GlobalUsings
@"
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using $ProjectName.Adapters;
global using $ProjectName.Domain.Ports;
global using $ProjectName.Services.Options;
global using $ProjectName.Services.UseCases;
"@ | Set-Content "src/Presentation/IoC/GlobalUsings.cs"

# Console Program.cs (Generic Host + DI + appsettings + Hexagonal Architecture)
@"
using $ProjectName.IoC;
using $ProjectName.Services.UseCases;

IHostBuilder builder = Host.CreateDefaultBuilder(args)
    .ConfigureAppConfiguration((context, config) =>
    {
        config.AddJsonFile("appsettings.json", optional: false, reloadOnChange: true);
        config.AddEnvironmentVariables();
    })
    .ConfigureServices((context, services) =>
    {
        services.AddIoC(context.Configuration);
    });

using IHost host = builder.Build();

var useCase = host.Services.GetRequiredService<IGreetingUseCase>();
var name = args.Length > 0 ? args[0] : "World";
System.Console.WriteLine(useCase.Execute(name));
"@ | Set-Content "src/Presentation/Console/Program.cs"

# Console GlobalUsings
@"
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Hosting;
global using $ProjectName.IoC;
global using $ProjectName.Services.UseCases;
"@ | Set-Content "src/Presentation/Console/GlobalUsings.cs"

# Git ignore
dotnet new gitignore

# =========================
# BUILD
# =========================
dotnet build

Write-Host "Console project created successfully!"
Write-Host "Powered by David Vazquez Palestino" -ForegroundColor DarkGray
