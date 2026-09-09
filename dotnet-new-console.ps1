# =========================================================================
#  new-console.ps1
#  Powered by David Vazquez Palestino
# =========================================================================

# ============================================
# 1. INFORMACION BASICA DEL PROYECTO
# ============================================
$ProjectName = Read-Host "Nombre del proyecto"

Write-Host "Creating Console project: $ProjectName"

# Root
New-Item -ItemType Directory -Path $ProjectName | Out-Null
Set-Location $ProjectName

# Solution (.slnx format for solution folders support)
$slnxContent = @"
<Solution>
  <SolutionLayout>
    <RootFolder Name="$ProjectName" />
  </SolutionLayout>
</Solution>
"@
$slnxContent | Set-Content "$ProjectName.slnx"

# =========================
# CREATE PROJECTS (Hexagonal Architecture)
# =========================
# Cada proyecto vive dentro de su propia subcarpeta para que bin/obj queden aislados
# y la carpeta-capa (Application, Infrastructure, etc.) pueda alojar proyectos hermanos.

# Domain
dotnet new classlib -n "$ProjectName.Domain" -o "src/Domain"

# Application
dotnet new classlib -n "$ProjectName.UseCases" -o "src/Application/UseCases"

# Infrastructure
dotnet new classlib -n "$ProjectName.Infrastructure" -o "src/Infrastructure"

# IoC
dotnet new classlib -n "$ProjectName.IoC" -o "src/Presentation/IoC"

# Console (Presentation layer)
dotnet new console -n "$ProjectName.Console" -o "src/Presentation/Console"

# =========================
# ADD TO SOLUTION
# =========================
dotnet sln add src/Domain
dotnet sln add src/Application/UseCases
dotnet sln add src/Infrastructure
dotnet sln add src/Presentation/IoC
dotnet sln add src/Presentation/Console

# =========================
# PROJECT REFERENCES
# =========================
# Application depends on Domain
dotnet add src/Application/UseCases reference src/Domain

# Infrastructure depends on Application and Domain (implements ports)
dotnet add src/Infrastructure reference src/Application/UseCases
dotnet add src/Infrastructure reference src/Domain

# IoC composes all layers
dotnet add src/Presentation/IoC reference src/Application/UseCases
dotnet add src/Presentation/IoC reference src/Infrastructure
dotnet add src/Presentation/IoC reference src/Domain

# Console depends only on IoC
dotnet add src/Presentation/Console reference src/Presentation/IoC

# =========================
# ADD PACKAGES
# =========================
# Application
dotnet add src/Application/UseCases package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Application/UseCases package Microsoft.Extensions.Options
dotnet add src/Application/UseCases package DependencyInjection.ReflectionExtensions

# Infrastructure
dotnet add src/Infrastructure package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Infrastructure package DependencyInjection.ReflectionExtensions

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
Remove-Item "src/Application/UseCases/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Infrastructure/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Presentation/IoC/Class1.cs" -Force -ErrorAction SilentlyContinue


# Remove <Nullable>enable</Nullable> from every generated .csproj
Get-ChildItem -Path 'src' -Recurse -Filter *.csproj | ForEach-Object {
    $c = Get-Content -Raw -Path $_.FullName
    $n = $c -replace '(?m)^[ \t]*<Nullable>\s*enable\s*</Nullable>[ \t]*\r?\n', ''
    if ($n -ne $c) { Set-Content -Path $_.FullName -Value $n -NoNewline }
}

# =========================
# CREATE BASE FOLDERS (Vertical Slice)
# =========================
$sampleFeature = "Greeting"

# Domain structure (por feature)
New-Item -ItemType Directory -Path "src/Domain/Entities/$sampleFeature" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Domain/Ports/$sampleFeature" -Force | Out-Null

# Application structure (por feature / acción)
New-Item -ItemType Directory -Path "src/Application/UseCases/UseCases/$sampleFeature" -Force | Out-Null
New-Item -ItemType Directory -Path "src/Application/UseCases/Options" -Force | Out-Null

# Infrastructure structure (por feature)
New-Item -ItemType Directory -Path "src/Infrastructure/$sampleFeature" -Force | Out-Null

# Keep feature folders visible in Visual Studio Solution Explorer
"" | Set-Content "src/Domain/Entities/$sampleFeature/.gitkeep"
"" | Set-Content "src/Domain/Ports/$sampleFeature/.gitkeep"
"" | Set-Content "src/Application/UseCases/UseCases/$sampleFeature/.gitkeep"
"" | Set-Content "src/Infrastructure/$sampleFeature/.gitkeep"

# =========================
# CREATE BASIC FILES
# =========================

# appsettings.json
Out-File -FilePath "src/Presentation/Console/appsettings.json" -InputObject @'
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
'@

# appsettings.Development.json
Out-File -FilePath "src/Presentation/Console/appsettings.Development.json" -InputObject @'
{
    "EnvironmentOptions": {
        "EnvironmentName": "Development"
    },
    "Logging": {
        "LogLevel": {
            "Default": "Debug"
        }
    }
}
'@

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
namespace $ProjectName.Domain.Ports.Greeting
{
    public interface IGreetingPort
    {
        string GetGreeting(string name);
    }
}
"@ | Set-Content "src/Domain/Ports/Greeting/IGreetingPort.cs"

# Domain GlobalUsings
@"
global using $ProjectName.Domain.Ports.Greeting;
"@ | Set-Content "src/Domain/GlobalUsings.cs"

# Application use case interface
@"
namespace $ProjectName.UseCases.UseCases.Greeting
{
    public interface IGreetingUseCase
    {
        string Execute(string name);
    }
}
"@ | Set-Content "src/Application/UseCases/UseCases/Greeting/IGreetingUseCase.cs"

# Application service / use case (hexagonal architecture)
@"
namespace $ProjectName.UseCases.UseCases.Greeting
{
    public class GreetingUseCase(IGreetingPort greetingPort, IOptions<EnvironmentOptions> options) : IGreetingUseCase
    {
        public string Execute(string name)
        {
            string env = options.Value.EnvironmentName;
            return greetingPort.GetGreeting($"{name} ({env})");
        }
    }
}
"@ | Set-Content "src/Application/UseCases/UseCases/Greeting/GreetingUseCase.cs"



# Infrastructure adapter (hexagonal architecture)
@"
namespace $ProjectName.Infrastructure.Greeting
{
    public class ConsoleGreetingAdapter : IGreetingPort
    {
        public string GetGreeting(string name) => $"Hello, {name}! Welcome to the hexagonal console app.";
    }
}
"@ | Set-Content "src/Infrastructure/Greeting/ConsoleGreetingAdapter.cs"

# Application Options
@"
namespace $ProjectName.UseCases.Options
{
    public class EnvironmentOptions
    {
        public const string SectionKey = nameof(EnvironmentOptions);
        public string EnvironmentName { get; set; } = "Production";
    }
}
"@ | Set-Content "src/Application/UseCases/Options/EnvironmentOptions.cs"

# Application GlobalUsings
@"
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Options;
global using $ProjectName.Domain.Ports.Greeting;
global using $ProjectName.UseCases.Options;
"@ | Set-Content "src/Application/UseCases/GlobalUsings.cs"

# Infrastructure DependencyContainer
@"
namespace $ProjectName.Infrastructure
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddInfrastructure(this IServiceCollection services)
        {  
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Infrastructure/DependencyContainer.cs"

# Infrastructure GlobalUsings
@"
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Options;
global using $ProjectName.Domain.Ports.Greeting;
global using $ProjectName.UseCases.Options;
global using $ProjectName.UseCases.UseCases.Greeting;
"@ | Set-Content "src/Infrastructure/GlobalUsings.cs"

# Application DependencyContainer
@"
namespace $ProjectName.UseCases
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddUseCases(this IServiceCollection services)
        {  
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Application/UseCases/DependencyContainer.cs"

# IoC DependencyContainer
@"
namespace $ProjectName.IoC
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddIoC(this IServiceCollection services, IConfiguration configuration)
        {
            services.Configure<EnvironmentOptions>(configuration.GetSection(EnvironmentOptions.SectionKey));
            services.AddInfrastructure()
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
global using $ProjectName.Infrastructure;
global using $ProjectName.Domain.Ports.Greeting;
global using $ProjectName.UseCases;
global using $ProjectName.UseCases.Options;
global using $ProjectName.UseCases.UseCases.Greeting;
"@ | Set-Content "src/Presentation/IoC/GlobalUsings.cs"

# Console Program.cs (Generic Host + DI + appsettings + Hexagonal Architecture)
@"
using $ProjectName.IoC;
using $ProjectName.UseCases.UseCases.Greeting;

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

IGreetingUseCase useCase = host.Services.GetRequiredService<IGreetingUseCase>();
string name = args.Length > 0 ? args[0] : "World";
System.Console.WriteLine(useCase.Execute(name));
"@ | Set-Content "src/Presentation/Console/Program.cs"

# Console GlobalUsings
@"
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Hosting;
global using $ProjectName.IoC;
global using $ProjectName.UseCases.UseCases.Greeting;
"@ | Set-Content "src/Presentation/Console/GlobalUsings.cs"

# Git ignore
dotnet new gitignore

# =========================
# DOCUMENTATION
# =========================
Write-Host "Writing documentation/README.md..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "documentation" -Force | Out-Null
$readme = @'
# $ProjectName

Aplicación de consola con Clean Architecture y Vertical Slice Architecture.

## Arquitectura

Este proyecto combina:
- **Clean Architecture**: Capas concéntricas donde el dominio es el centro
- **Vertical Slice Architecture**: Código organizado por features (casos de uso)
- **Hexagonal Architecture**: Puertos (interfaces) y adaptadores (implementaciones)

## Estructura del Proyecto

```text
src/
├── Domain/                    # Dominio y reglas de negocio (Ports)
├── Application/UseCases/      # Casos de uso (UseCases)
├── Infrastructure/           # Implementaciones (Adapters)
├── Presentation/IoC/          # Inyección de dependencias
└── Presentation/Console/      # Aplicación de consola
```

## Configuración

Edita los archivos `appsettings.json` para configurar:
- Variables de entorno
- Configuración de logging

## Ejecutar

```bash
dotnet run --project src/Presentation/Console
```

O con argumentos:
```bash
dotnet run --project src/Presentation/Console -- "TuNombre"
```

## Build

```bash
dotnet build
```

## Git - Subir al repositorio

```bash
# Inicializar repositorio (si no existe)
git init

# Agregar todos los archivos
git add .

# Hacer commit inicial
git commit -m "Initial commit - Clean Architecture Console setup"

# Agregar repositorio remoto (reemplaza con tu URL)
git remote add origin https://github.com/tu-usuario/tu-repositorio.git

# Subir al repositorio (primera vez)
git push -u origin main

# O si usas master como rama principal
git push -u origin master
```

---
Powered by David Vazquez Palestino
'@
$readmeContent = $readme -replace '\$ProjectName', $ProjectName
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
    foreach ($docPath in @('documentation/README.md')) {
        $hasFile = @($folder.File) | Where-Object { $_ -and $_.Path -eq $docPath } | Select-Object -First 1
        if (-not $hasFile) {
            $file = $slnx.CreateElement('File')
            $file.SetAttribute('Path', $docPath)
            [void]$folder.AppendChild($file)
        }
    }
    $slnx.Save((Resolve-Path $slnxFile))
}

# =========================
# BUILD
# =========================
dotnet build

Write-Host "Console project created successfully!"
Write-Host "Powered by David Vazquez Palestino" -ForegroundColor DarkGray
