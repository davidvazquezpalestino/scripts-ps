param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "."
)

$ErrorActionPreference = "Stop"

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
dotnet new xunit3 -n "$ProjectName.UnitTests" -o "tests/UnitTests"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path "tests/UnitTests")) {
    Write-Error "No se pudo crear el proyecto tests/UnitTests con la plantilla xunit3."
    exit 1
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
New-Item -ItemType Directory -Path "src/Infrastructure/WebApi/Options" -Force | Out-Null

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

"@ | Set-Content "src/Application/ViewModels/GlobalUsings.cs"

# Application (ViewModels) DependencyContainer
@"
namespace $ProjectName.ViewModels
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddViewModels(this IServiceCollection services)
        {  
            services.AddCurrentAssembly();
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
           services.AddCurrentAssembly();
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
            services.AddCurrentAssembly();
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
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
global using $ProjectName.WebApi.Options;
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

<PageTitle>Index — 100% Clean Architecture (o eso dice el README)</PageTitle>

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

"@ | Set-Content "src/Presentation/Views/Pages/Index.razor"

# Client _Imports.razor update
@"
@using Microsoft.AspNetCore.Components.Web
"@ | Set-Content "src/Presentation/Client/_Imports.razor"

# Client index.html update
$content = Get-Content "src/Presentation/Client/wwwroot/index.html" -Raw
$content = $content -replace "<link href=`"$ProjectName.Web.styles.css`" rel=`"stylesheet`" />", @"
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet" />
<link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet" />
<link href="$ProjectName.Web.styles.css" rel="stylesheet" />
<link href="_content/$ProjectName.Views/css/icons-custom.css" rel="stylesheet" />
<link href="_content/$ProjectName.Views/css/hero-logo.css" rel="stylesheet" />
"@

# Inject Bootstrap JS bundle before </body> (idempotent)
if ($content -notmatch 'bootstrap\.bundle\.min\.js') {
    $content = $content -replace '</body>', @'
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
'@
}

$content | Set-Content "src/Presentation/Client/wwwroot/index.html"

# Views _Imports.razor
@"
@using Microsoft.AspNetCore.Components
@using Microsoft.Extensions.DependencyInjection
@using System.Net.Http.Json
@using Microsoft.AspNetCore.Components.Web
@using $ProjectName.Views.Layout
@using Microsoft.AspNetCore.Components.Routing

"@ | Set-Content "src/Presentation/Views/_Imports.razor"

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

"@ | Set-Content "src/Presentation/Views/App.razor"

# NotFound.razor in Views/Pages
@"
<p>Sorry, there's nothing at this address.</p>
"@ | Set-Content "src/Presentation/Views/Pages/NotFound.razor"

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

"@ | Set-Content "src/Presentation/Views/Layout/MainLayout.razor"

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

"@ | Set-Content "src/Presentation/Views/Layout/NavMenu.razor"

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
# VS CODE: Startup config (F5 -> Web)
# =========================
Write-Host "Creating .vscode/launch.json and tasks.json (F5 -> $ProjectName.Web)..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path ".vscode" -Force | Out-Null

@"
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Launch $ProjectName.Web",
      "type": "blazorwasm",
      "request": "launch",
      "cwd": "`${workspaceFolder}/src/Presentation/Client",
      "url": "http://localhost:$HttpPort",
      "preLaunchTask": "build"
    }
  ]
}
"@ | Set-Content ".vscode/launch.json"

@"
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "command": "dotnet",
      "type": "process",
      "args": [
        "build",
        "`${workspaceFolder}/src/Presentation/Client/$ProjectName.Web.csproj",
        "/property:GenerateFullPaths=true",
        "/consoleloggerparameters:NoSummary"
      ],
      "problemMatcher": "`$msCompile",
      "group": {
        "kind": "build",
        "isDefault": true
      }
    },
    {
      "label": "run",
      "command": "dotnet",
      "type": "process",
      "args": [
        "run",
        "--project",
        "`${workspaceFolder}/src/Presentation/Client/$ProjectName.Web.csproj"
      ],
      "problemMatcher": "`$msCompile"
    }
  ]
}
"@ | Set-Content ".vscode/tasks.json"

# =========================
# CLEAN ARCHITECTURE DOC (Tío Bob)
# =========================
Write-Host "Writing documentation/Architecture.md..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "documentation" -Force | Out-Null
@'
# Clean Architecture (Arquitectura Limpia) — Tío Bob

Este documento resume las reglas de la **Arquitectura Limpia** propuestas por
Robert C. Martin ("Uncle Bob") en su libro *Clean Architecture: A Craftsman's
Guide to Software Structure and Design*. La estructura de esta solución sigue
estas reglas.

---

## 1. Objetivos

Una arquitectura limpia busca producir sistemas que sean:

- **Independientes de frameworks**: el framework es una herramienta, no una
  restricción arquitectónica.
- **Testeables**: las reglas de negocio se pueden probar sin UI, base de
  datos, servidor web ni ningún elemento externo.
- **Independientes de la UI**: la UI puede cambiar (web, consola, móvil) sin
  afectar al resto del sistema.
- **Independientes de la base de datos**: se puede cambiar SQL Server por
  Mongo, Postgres, un archivo, etc.
- **Independientes de agentes externos**: las reglas de negocio no saben
  nada del mundo exterior.

---

## 2. Las capas

La arquitectura se organiza en **círculos concéntricos**. Cuanto más al
centro, más general y estable; cuanto más afuera, más concreto y volátil.

```
        ┌───────────────────────────────────────────┐
        │            Presentation / UI              │  ← Frameworks & Drivers
        │  ┌─────────────────────────────────────┐  │
        │  │          Infrastructure             │  │  ← Interface Adapters
        │  │  ┌───────────────────────────────┐  │  │
        │  │  │        Application            │  │  │  ← Use Cases
        │  │  │  ┌─────────────────────────┐  │  │  │
        │  │  │  │        Domain           │  │  │  │  ← Entities
        │  │  │  └─────────────────────────┘  │  │  │
        │  │  └───────────────────────────────┘  │  │
        │  └─────────────────────────────────────┘  │
        └───────────────────────────────────────────┘
```

### 2.1 Domain (Entidades)

Contiene las **reglas de negocio empresariales**. Son las más estables y no
dependen de nada externo.

- `Entities/`: objetos con identidad y comportamiento (p. ej. `Order`, `User`).
- `ValueObjects/`: objetos inmutables definidos por sus valores
  (p. ej. `Money`, `Email`).
- `Services/`: lógica de dominio que no encaja naturalmente en una entidad.
- `Interfaces/`: **puertos** que expresan lo que el dominio necesita
  (p. ej. `IOrderRepository`). La implementación vive en capas externas.

### 2.2 Application (Casos de uso)

Orquesta el dominio para cumplir **reglas de negocio de aplicación**.

- `UseCases/`: casos de uso concretos (p. ej. `CreateOrderUseCase`).
- `DTOs/`: objetos de transporte de datos entre capas.
- `Interfaces/`: puertos que la aplicación necesita (p. ej. `IEmailSender`).

Esta capa **no conoce** detalles de infraestructura ni de UI.

### 2.3 Infrastructure (Adaptadores)

Implementa los puertos definidos por Domain y Application. Aquí viven los
**detalles técnicos**.

- `Persistence/`: contexto de base de datos, migraciones, configuración ORM.
- `Repositories/`: implementaciones de `IOrderRepository`, etc.
- `Adapters/`: integraciones con servicios externos (Mailchimp, Stripe,
  APIs, colas de mensajes...).

### 2.4 Presentation (UI / Entrega)

Punto de entrada al sistema.

- `Controllers/`: endpoints Web API, controladores MVC, handlers.
- `Views/`: vistas Razor, Blazor, plantillas.
- `Models/`: view-models específicos de la UI.

---

## 3. La Regla de la Dependencia (⚠️ regla clave)

> **Las dependencias del código fuente sólo pueden apuntar hacia adentro.**

Esto significa:

- Nada en un círculo interno puede saber algo sobre un círculo externo.
- En particular, **el nombre de algo declarado en un círculo externo no
  debe ser mencionado por el código de un círculo interno**: ni clases, ni
  funciones, ni variables, ni ninguna otra entidad nombrada.

Aplicado a las carpetas:

```
Presentation  ──►  Application  ──►  Domain
Infrastructure ─►  Application  ──►  Domain
Infrastructure ─►  Domain
```

Nunca al revés:

- ❌ `Domain` **no** referencia `Application`, `Infrastructure` ni `Presentation`.
- ❌ `Application` **no** referencia `Infrastructure` ni `Presentation`.
- ✔ `Infrastructure` y `Presentation` sí pueden referenciar capas internas.

### 3.1 ¿Cómo se invierte la dependencia?

Cuando una capa interna necesita algo de una capa externa (por ejemplo, el
caso de uso necesita persistir un pedido), aplicamos el **Principio de
Inversión de Dependencias (DIP)**:

1. La capa interna **define una interfaz** (puerto):
   `Application/Interfaces/IOrderRepository`.
2. La capa externa **implementa** esa interfaz:
   `Infrastructure/Repositories/OrderRepository`.
3. En el arranque (composición) se inyecta la implementación concreta.

Así, en tiempo de compilación las dependencias apuntan hacia adentro,
aunque en tiempo de ejecución el flujo de control cruce hacia afuera.

---

## 4. Estructura de carpetas de esta solución

```
/src
  /Presentation                     <-- Capa de presentación
    /Client                             Blazor WebAssembly (host de la app)
      /Properties                         launchSettings.json
      /wwwroot                            Estáticos, appsettings.json, index.html
    /Views                              Razor Class Library (componentes reutilizables)
      /Layout                             MainLayout, NavMenu
      /Pages                              Páginas ruteables
    /IoC                                Composición raíz (Dependency Injection)
  /Domain
    /Entities                       <-- Entidades de dominio
    /ValueObjects                   <-- Objetos de valor
    /Enums
    /Interfaces                     <-- Interfaces de dominio (puertos)
  /Application
    /ViewModels                     <-- ViewModels / casos de uso
    /Validators                     <-- Reglas de validación (FluentValidation)
    /Interfaces                     <-- Interfaces de aplicación (puertos)
  /Infrastructure
    /WebApi                         <-- Adaptador HTTP hacia la API remota
      /Options                          BaseUrl y opciones del cliente HTTP
/tests
  /UnitTests                        <-- Pruebas unitarias (xUnit v3)
```

Referencias entre proyectos (en .NET, `dotnet add reference`):

| Proyecto        | Referencia a                       |
|-----------------|------------------------------------|
| Domain          | *(ninguna)*                        |
| Application     | Domain                             |
| Infrastructure  | Application, Domain                |
| Presentation    | Application (y Infra sólo para DI) |

---

## 5. Beneficios prácticos

- **Cambios localizados**: tocar la UI o la base de datos no obliga a
  reescribir reglas de negocio.
- **Tests rápidos**: Domain y Application se prueban sin infraestructura.
- **Reemplazo de tecnología**: cambiar EF Core por Dapper, o REST por gRPC,
  es un cambio en Infrastructure/Presentation.
- **Claridad de intención**: el código de negocio se lee como negocio, no
  como *plumbing* técnico.

---

## 6. Antipatrones a evitar

- Referenciar `Microsoft.EntityFrameworkCore` desde `Domain` o `Application`.
- Poner atributos `[HttpGet]`, `[Route]` en entidades de dominio.
- Exponer entidades de dominio directamente como respuesta HTTP (usar DTOs).
- Casos de uso que instancian `new SqlConnection(...)` en vez de recibir
  un puerto.
- Interfaces "de repositorio" definidas en Infrastructure en lugar de en
  Domain/Application (rompe la inversión).

---

## 7. Lecturas recomendadas

- Robert C. Martin — *Clean Architecture* (2017).
- Alistair Cockburn — *Hexagonal Architecture* (Ports & Adapters).
- Jeffrey Palermo — *Onion Architecture*.
- Vaughn Vernon — *Implementing Domain-Driven Design*.
'@ | Set-Variable -Name ArchitectureMd
[System.IO.File]::WriteAllText(
    (Join-Path (Get-Location) 'documentation/Architecture.md'),
    $ArchitectureMd,
    (New-Object System.Text.UTF8Encoding($true))
)

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
    $hasFile = @($folder.File) | Where-Object { $_ -and $_.Path -eq 'documentation/Architecture.md' } | Select-Object -First 1
    if (-not $hasFile) {
        $file = $slnx.CreateElement('File')
        $file.SetAttribute('Path', 'documentation/Architecture.md')
        [void]$folder.AppendChild($file)
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
Write-Host "  src/Presentation/Client/                   ($ProjectName.Web - Blazor Web Assembly)"           -ForegroundColor Gray
Write-Host "  src/Domain/                   ($ProjectName.Domain - Entities, Interfaces)"        -ForegroundColor Gray
Write-Host "  src/Application/ViewModels/   ($ProjectName.ViewModels - Use Cases, Services)"     -ForegroundColor Gray
Write-Host "  src/Application/Validators/   ($ProjectName.Validators - FluentValidation)"        -ForegroundColor Gray
Write-Host "  src/Infrastructure/WebApi/    ($ProjectName.WebApi - External Services, HTTP)"     -ForegroundColor Gray
Write-Host "  src/Presentation/Views/                    ($ProjectName.Views - Razor Components, Layouts)"    -ForegroundColor Gray
Write-Host "  src/Presentation/IoC/                      ($ProjectName.IoC - Dependency Injection)"           -ForegroundColor Gray