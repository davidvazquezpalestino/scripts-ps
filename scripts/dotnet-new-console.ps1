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
# CREATE PROJECTS (Clean Architecture — tío Bob)
# =========================
# Cada proyecto vive dentro de su propia subcarpeta para que bin/obj queden aislados
# y la carpeta-capa (UseCases, Adapters, Frameworks, etc.) pueda alojar proyectos hermanos.

# Entities (capa central: reglas de negocio de empresa)
dotnet new classlib -n "$ProjectName.Entities" -o "src/Entities"

# UseCases (reglas de aplicación)
dotnet new classlib -n "$ProjectName.UseCases" -o "src/UseCases"

# Adapters (implementaciones de puertos: gateways, presenters)
dotnet new classlib -n "$ProjectName.Adapters" -o "src/Adapters"

# IoC (composición raíz, capa Frameworks & Drivers)
dotnet new classlib -n "$ProjectName.IoC" -o "src/Frameworks/IoC"

# Console (UI, capa Frameworks & Drivers)
dotnet new console -n "$ProjectName.Console" -o "src/Frameworks/Console"

# =========================
# ADD TO SOLUTION
# =========================
dotnet sln add src/Entities
dotnet sln add src/UseCases
dotnet sln add src/Adapters
dotnet sln add src/Frameworks/IoC
dotnet sln add src/Frameworks/Console

# =========================
# PROJECT REFERENCES
# =========================
# UseCases depend on Entities
dotnet add src/UseCases reference src/Entities

# Adapters depend on UseCases and Entities (implement ports)
dotnet add src/Adapters reference src/UseCases
dotnet add src/Adapters reference src/Entities

# IoC composes all layers
dotnet add src/Frameworks/IoC reference src/UseCases
dotnet add src/Frameworks/IoC reference src/Adapters
dotnet add src/Frameworks/IoC reference src/Entities

# Console depends only on IoC
dotnet add src/Frameworks/Console reference src/Frameworks/IoC

# =========================
# ADD PACKAGES
# =========================
# UseCases
dotnet add src/UseCases package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/UseCases package Microsoft.Extensions.Options
dotnet add src/UseCases package DependencyInjection.ReflectionExtensions

# Adapters
dotnet add src/Adapters package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Adapters package DependencyInjection.ReflectionExtensions

# IoC
dotnet add src/Frameworks/IoC package Microsoft.Extensions.Hosting
dotnet add src/Frameworks/IoC package Microsoft.Extensions.Configuration
dotnet add src/Frameworks/IoC package Microsoft.Extensions.Configuration.Json
dotnet add src/Frameworks/IoC package Microsoft.Extensions.Configuration.EnvironmentVariables
dotnet add src/Frameworks/IoC package Microsoft.Extensions.Configuration.Binder
dotnet add src/Frameworks/IoC package Microsoft.Extensions.DependencyInjection
dotnet add src/Frameworks/IoC package Microsoft.Extensions.Options.ConfigurationExtensions
dotnet add src/Frameworks/IoC package DependencyInjection.ReflectionExtensions

# Console
dotnet add src/Frameworks/Console package Microsoft.Extensions.Hosting

# =========================
# REMOVE DEFAULT CLASS1.cs
# =========================
Remove-Item "src/Entities/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/UseCases/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Adapters/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Frameworks/IoC/Class1.cs" -Force -ErrorAction SilentlyContinue


# Remove <Nullable>enable</Nullable> from every generated .csproj
Get-ChildItem -Path 'src' -Recurse -Filter *.csproj | ForEach-Object {
    $c = Get-Content -Raw -Path $_.FullName
    $n = $c -replace '(?m)^[ \t]*<Nullable>\s*enable\s*</Nullable>[ \t]*\r?\n', ''
    if ($n -ne $c) { Set-Content -Path $_.FullName -Value $n -NoNewline }
}

# =========================
# CREATE BASIC FILES
# =========================

# appsettings.json
Out-File -FilePath "src/Frameworks/Console/appsettings.json" -InputObject @'
{
    "Logging": {
        "LogLevel": {
            "Default": "Information",
            "Microsoft": "Warning"
        }
    }
}
'@

# appsettings.Development.json
Out-File -FilePath "src/Frameworks/Console/appsettings.Development.json" -InputObject @'
{
    "Logging": {
        "LogLevel": {
            "Default": "Debug"
        }
    }
}
'@

# Configure csproj to copy appsettings on build
$csprojPath = "src/Frameworks/Console/$ProjectName.Console.csproj"
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

# UseCases GlobalUsings
@"
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
"@ | Set-Content "src/UseCases/GlobalUsings.cs"

# Adapters DependencyContainer
@"
namespace $ProjectName.Adapters
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddAdapters(this IServiceCollection services)
        {  
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Adapters/DependencyContainer.cs"

# Adapters GlobalUsings
@"
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
"@ | Set-Content "src/Adapters/GlobalUsings.cs"

# UseCases DependencyContainer
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
"@ | Set-Content "src/UseCases/DependencyContainer.cs"

# IoC DependencyContainer
@"
namespace $ProjectName.IoC
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddIoC(this IServiceCollection services)
        {
            services.AddAdapters()
                    .AddUseCases();
            return services;
        }
    }
}
"@ | Set-Content "src/Frameworks/IoC/DependencyContainer.cs"

# IoC GlobalUsings
@"
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using $ProjectName.Adapters;
global using $ProjectName.UseCases;
"@ | Set-Content "src/Frameworks/IoC/GlobalUsings.cs"

# Console Program.cs (Generic Host + DI + appsettings + Clean Architecture)
@"
using $ProjectName.IoC;

IHostBuilder builder = Host.CreateDefaultBuilder(args)
    .ConfigureAppConfiguration((context, config) =>
    {
        config.AddJsonFile("appsettings.json", optional: false, reloadOnChange: true);
        config.AddEnvironmentVariables();
    })
    .ConfigureServices((_, services) =>
    {
        services.AddIoC();
    });

using IHost host = builder.Build();
"@ | Set-Content "src/Frameworks/Console/Program.cs"

# Console GlobalUsings
@"
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Hosting;
global using $ProjectName.IoC;
"@ | Set-Content "src/Frameworks/Console/GlobalUsings.cs"

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
├── Entities/                  # Reglas de negocio de empresa (capa central, puertos)
├── UseCases/                  # Reglas de aplicación (casos de uso)
├── Adapters/                  # Implementaciones de puertos (gateways, presenters)
├── Frameworks/IoC/            # Composición raíz (inyección de dependencias)
└── Frameworks/Console/        # Aplicación de consola (UI)
```

## Configuración

Edita los archivos `appsettings.json` para configurar:
- Variables de entorno
- Configuración de logging

## Ejecutar

```bash
dotnet run --project src/Frameworks/Console
```

O con argumentos:
```bash
dotnet run --project src/Frameworks/Console -- "TuNombre"
```

## Build

```bash
dotnet build
```

## Contribuir

Para conocer el flujo de trabajo con Git, convenciones de commits y el checklist antes de hacer push, consulta [CONTRIBUTING.md](CONTRIBUTING.md).

---
Powered by David Vazquez Palestino
'@
$readmeContent = $readme -replace '\$ProjectName', $ProjectName
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
Powered by David Vazquez Palestino
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
    foreach ($docPath in @('documentation/README.md', 'documentation/CONTRIBUTING.md')) {
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
