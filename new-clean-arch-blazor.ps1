# =========================================================================
#  new-clean-arch-blazor.ps1
#  Powered by David Vázquez Palestino
# =========================================================================

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
Write-Host "Writing documentation/ArchitectureGuide.md..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "documentation" -Force | Out-Null
@'
> Solución generada con el script `new-clean-arch-blazor.ps1` desde PowerShell:
>
> ```powershell
> .\new-clean-arch-blazor.ps1 -ProjectName <NombreProyecto> [-OutputPath <ruta>]
> ```

# Clean Architecture para Blazor WebAssembly — Tío Bob

Este documento resume las reglas de la **Arquitectura Limpia** propuestas por
Robert C. Martin ("Uncle Bob") adaptadas a una aplicación **Blazor WebAssembly**.
A diferencia de un backend, aquí no hay base de datos local ni endpoints HTTP
propios; el frontend consume una API remota y su arquitectura se organiza para
mantener el dominio y la lógica de aplicación libres de detalles de UI,
HTTP o framework.

---

## 1. Objetivos

Una arquitectura limpia en el frontend busca producir aplicaciones que sean:

- **Independientes de frameworks**: Blazor es una herramienta de entrega, no
  una restricción arquitectónica.
- **Testeables**: las reglas de negocio y los view-models se prueban sin
  renderizar componentes ni lanzar el navegador.
- **Independientes de la UI**: los componentes pueden cambiar (Razor, MAUI,
  consola) sin afectar al resto del sistema.
- **Independientes del origen de datos**: cambiar la API remota, agregar
  almacenamiento local o usar GraphQL es un cambio en Infrastructure.
- **Independientes de agentes externos**: el dominio no sabe que existe
  `HttpClient`, Blazor o la API remota.

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

Contiene las **reglas de negocio empresariales** del problema que la app
resuelve. Son las más estables y no dependen de nada externo.

- `Entities/`: objetos con identidad y comportamiento (p. ej. `Order`, `User`).
- `ValueObjects/`: objetos inmutables definidos por sus valores
  (p. ej. `Money`, `Email`).
- `Enums/`: enumeraciones de negocio.
- `Interfaces/`: **puertos** que expresan lo que el dominio necesita
  (p. ej. `IOrderWebApi`). La implementación vive en capas externas.

### 2.2 Application (Casos de uso / ViewModels)

Orquesta el dominio para cumplir **reglas de negocio de aplicación**.

- `ViewModels/`: casos de uso concretos expuestos como ViewModels que la UI
  puede invocar (p. ej. `CreateOrderViewModel`).
- `Validators/`: reglas de validación de entrada usando FluentValidation.
- `Interfaces/`: puertos que la aplicación necesita (p. ej. `IApiClient`).

Esta capa **no conoce** detalles de infraestructura ni de Blazor.

### 2.3 Infrastructure (Adaptadores)

Implementa los puertos definidos por Domain y Application. Aquí viven los
**detalles técnicos** del frontend.

- `WebApi/`: adaptador HTTP que consume la API remota usando `HttpClient`.
- `Options/`: configuración como la `BaseUrl` de la API.
- `LocalStorage/`: adaptador para `localStorage` del navegador, si aplica.
- `Adapters/`: integraciones con servicios externos (SignalR, gRPC, etc.).

### 2.4 Presentation (UI / Entrega)

Punto de entrada al sistema Blazor.

- `Client/`: host Blazor WebAssembly (`Program.cs`, `wwwroot`,
  `launchSettings.json`).
- `Views/`: Razor Class Library con componentes, layouts y páginas
  ruteables.
- `IoC/`: composición raíz donde se registran servicios y se inyectan
  implementaciones concretas.

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
ViewModel necesita llamar a la API remota), aplicamos el **Principio de
Inversión de Dependencias (DIP)**:

1. La capa interna **define una interfaz** (puerto):
   `Application/Interfaces/IOrderWebApi`.
2. La capa externa **implementa** esa interfaz:
   `Infrastructure/WebApi/OrderWebApi`.
3. En el arranque (`Program.cs` / IoC) se inyecta la implementación concreta.

Así, en tiempo de compilación las dependencias apuntan hacia adentro,
aunque en tiempo de ejecución el flujo de control cruce hacia afuera
hasta la API remota.

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

### 4.1 Flujo de una interacción de usuario

En esta app Blazor una acción del usuario viaja de afuera hacia adentro y
regresa:

```
Usuario / Navegador
   │
   ▼
Presentation/Views              (componentes .razor, layouts, páginas)
   │
   ▼
Presentation/IoC                (registro de servicios, composición)
   │
   ▼
Application/ViewModels          (orquestador del caso de uso)
   │
   ▼
Application/Validators  ─┐      (valida entrada de usuario)
                         │
                         ▼
Infrastructure/WebApi    (HttpClient hacia API remota)
   │
   ▼
Domain                          (entidades, VOs, reglas invariantes)
```

Reglas prácticas de esta ruta:

- **Componentes** no llaman directamente a `HttpClient`; invocan un
  `ViewModel` (o un servicio de aplicación definido por interfaz).
- **ViewModels** orquestan validación, transformación y llamadas al puerto
  de infraestructura.
- **Validators** contienen solo reglas de entrada de usuario; no acceden
  a la red.
- **Infrastructure/WebApi** es el único lugar que conoce la URL, los
  verbos HTTP y el formato JSON de la API remota.
- El flujo de retorno mapea los datos a entidades de dominio o DTOs antes
  de mostrarlos en el componente.

---

## 5. Beneficios prácticos

- **Cambios localizados**: cambiar Bootstrap por MudBlazor, o agregar
  almacenamiento local, no obliga a reescribir reglas de negocio.
- **Tests rápidos**: Domain, Validators y ViewModels se prueban sin
  renderizar componentes ni depender de `HttpClient`.
- **Reemplazo de tecnología**: cambiar REST por gRPC o SignalR es un cambio
  en Infrastructure.
- **Claridad de intención**: el código de negocio se lee como negocio, no
  como *plumbing* técnico de Blazor.

---

## 6. Antipatrones a evitar

- Referenciar `System.Net.Http` o `HttpClient` desde `Domain` o
  `Application`.
- Poner lógica de negocio directamente en componentes `.razor`
  (`@code { ... }` que crece indefinidamente).
- Usar `NavigationManager`, `IJSRuntime` o `HttpClient` dentro de
  ViewModels en lugar de recibirlos por puertos.
- Exponer modelos de la API directamente en la UI sin pasar por el dominio
  o un DTO de aplicación.
- Interfaces de servicio remoto definidas en Infrastructure en lugar de
  Application (rompe la inversión).

---

## 7. Features (organización del día a día)

Aunque la solución está partida por **capas**, el trabajo diario se
organiza por **features**: cada caso de uso atraviesa varias capas y
todas sus piezas viven en carpetas **con el mismo nombre**.

```
FEATURE: CreateOrder
─────────────────────────────────────────────────────────────

/src
├── Domain
│   ├── Entities/Orders/
│   │   └── Order.cs
│   └── Interfaces/Orders/
│       └── IOrderWebApi.cs             ← puerto
│
├── Application
│   ├── ViewModels/Orders/
│   │   └── CreateOrderViewModel.cs     ← orquesta el caso de uso
│   └── Validators/Orders/
│       └── CreateOrderValidator.cs
│
├── Infrastructure
│   └── WebApi/Orders/
│       └── OrderWebApi.cs              ← implementa el puerto (HttpClient)
│
├── Presentation
│   └── Views/Pages/Orders/
│       └── CreateOrder.razor           ← UI / formulario
│
└── tests/UnitTests/Orders/CreateOrder/
    ├── CreateOrderViewModelTests.cs
    └── CreateOrderValidatorTests.cs


FLUJO DE LA FEATURE (interacción del usuario)
─────────────────────────────────────────────────────────────

   Usuario envía formulario "Crear pedido"
          │
          ▼
   CreateOrder.razor      (Presentation/Views/Pages/Orders)
          │
          ▼
   CreateOrderViewModel   (Application/ViewModels/Orders)
          │      ▲
          │      │ valida
          │  CreateOrderValidator
          ▼
   IOrderWebApi           (Domain/Interfaces/Orders)  ── puerto
          │
          ▼
   OrderWebApi            (Infrastructure/WebApi/Orders)
          │
          ▼
   API remota             (fuera de esta solución)
          │
          ▼
   Order                  (Domain/Entities/Orders)


REGLA DE ORO
─────────────────────────────────────────────────────────────
  Toda pieza de una feature vive en carpetas con el MISMO nombre
  (aquí: "Orders" + "CreateOrder"). Si tienes que buscar por
  toda la solución para encontrarla, la feature está mal ubicada.

---

## 8. Lecturas recomendadas

- Robert C. Martin — *Clean Architecture* (2017).
- Alistair Cockburn — *Hexagonal Architecture* (Ports & Adapters).
- Jeffrey Palermo — *Onion Architecture*.
- Vaughn Vernon — *Implementing Domain-Driven Design*.
- Microsoft — *Blazor WebAssembly documentation*.
```
'@ | Set-Variable -Name ArchitectureMd
[System.IO.File]::WriteAllText(
    (Join-Path (Get-Location) 'documentation/ArchitectureGuide.md'),
    $ArchitectureMd,
    (New-Object System.Text.UTF8Encoding($true))
)

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
'@ | Set-Variable -Name WcagMd
[System.IO.File]::WriteAllText(
    (Join-Path (Get-Location) 'documentation/WCAG.md'),
    $WcagMd,
    (New-Object System.Text.UTF8Encoding($true))
)

# =========================
# BEST PRACTICES DOC (C#)
# =========================
Write-Host "Writing documentation/BuenasPracticasCSharp.md..." -ForegroundColor Yellow
@'
# Buenas Prácticas de Codificación en C# / .NET

> Recopilación de las mejores recomendaciones extraídas del documento
> *"Estándares de Codificación en C# y Buenas Prácticas de Programación"* (canaldenegocio.com — Alberto Fernández).
> Reorganizado, resumido y priorizado para uso práctico.

---

## 1. Convenciones de Nombres

- **PascalCase** para clases, métodos, propiedades y namespaces.
- **camelCase** para variables locales y parámetros.
- Prefijo **`I`** para interfaces (`IEntity`, `IRepository`).
- Prefijo **`_`** solo para campos privados (variables globales/miembro de clase).
- **No usar** notación húngara (`m_sNombre`, `nEdad`).
- **No usar** abreviaturas: preferir `direccion` a `dir`, `salario` a `sal`.
- **No usar** nombres de un solo carácter, salvo contadores de bucle (`i`, `j`).
- Prefijo **`Is`** para booleanos (`IsValid`, `IsActive`) — coherente con el BCL.
- Métodos con formato **`<Verbo><Descripción>`** en inglés (`GetClientes()`, `AddCliente()`) para agrupación óptima en IntelliSense.
- Namespaces con patrón: `<Compañía>.<Producto>.<Módulo>.<Submódulo>`.
- El **nombre del archivo debe coincidir con la clase** (`HolaMundo.cs`).
- Una clase por archivo.

---

## 2. Formato y Estilo

- Usar **tabuladores** (o 4 espacios) consistentes.
- Llaves `{}` en **línea separada** (estilo Allman), no en la misma línea del `if`/`for`.
- Un espacio antes/después de paréntesis y operadores.
- Una línea en blanco entre métodos.
- Separar bloques lógicos con una línea en blanco.
- Usar `#region` para agrupar: *Private Fields*, *Properties*, *Constructors*, *Public Methods*, etc.
- Privados arriba, públicos abajo.

---

## 3. Métodos y Diseño

- Métodos **cortos**: idealmente entre 1 y 25 líneas. Si crece, refactorizar.
- **Una responsabilidad por método** (SRP).
- Nombres autoexplicativos: si el nombre es obvio, sobra la documentación.
- Máximo **4–5 parámetros**. Si son más, crear una clase/DTO.
- Evitar archivos con más de **1000 líneas** — candidatos a refactor.
- Evitar métodos y propiedades públicas innecesarias. Usar `internal` cuando aplique.
- No definir campos públicos: exponer **propiedades** en su lugar.

---

## 4. Tipos y Valores

- Usar los alias de C# (`int`, `string`, `object`) en lugar de `Int32`, `String`, `Object`.
- **Preferir tipos explícitos frente a `var`**. Solo aceptable cuando el tipo es literalmente obvio en la misma línea (por ejemplo `new StringBuilder()`), en LINQ con tipos anónimos o en tuplas. El código debe leerse sin necesidad de pasar el mouse por encima.
  ```csharp
  // ❌ Poco claro
  var result = repository.GetActive();

  // ✅ Explícito
  IReadOnlyList<Customer> result = repository.GetActive();
  ```
- Usar `string.Empty` en lugar de `""`.
- Usar **`enum`** para valores discretos — no strings ni magic numbers.
- **No hardcodear** números o cadenas: usar constantes, `appsettings` o recursos (`.resx`).
- Comparar strings normalizando caso (`ToLower()`, `ToUpper()`, o mejor `string.Equals(a, b, StringComparison.OrdinalIgnoreCase)`).
- Usar **`StringBuilder`** dentro de bucles con concatenación.
- Declarar variables **cerca de su primer uso**, una por línea.

---

## 5. Control de Flujo y Robustez

- **Siempre validar valores inesperados**: incluir `else` final con excepción, no asumir binariedad.
- Si un método retorna colección, devolver **colección vacía** — nunca `null`.
- Evitar variables globales. Pasar dependencias por parámetros.
- Los **event handlers no contienen lógica**: delegan en un método, lo que permite reutilización.
- **No invocar `Button.Click()`** programáticamente para reutilizar lógica — llamar al método directamente.
- Nunca hardcodear rutas o letras de unidad (`C:\`, `Z:\`). Usar rutas relativas al ejecutable.

---

## 6. Manejo de Excepciones

### Filosofía
- Las excepciones son para **situaciones excepcionales**, no para flujo de control esperable.
- Errores de negocio *esperados* (validación, `NotFound`, conflictos) → preferir **Result pattern** (`Result<T>`, `OneOf`, `ErrorOr`, etc.) o `TryXxx` en lugar de lanzar.
- Errores *inesperados* (fallos de infraestructura, bugs) → excepciones + captura global.

### Reglas de captura
- **Nunca** `catch { }` vacío. Como mínimo, loguear con `ILogger`.
- Capturar **tipos específicos** (`SqlException`, `HttpRequestException`, `OperationCanceledException`, `DbUpdateConcurrencyException`…), no `Exception` genérica.
- **Re-lanzar con `throw;`**, nunca `throw ex;` (destruye el stack trace).
- No envolver todos los métodos en `try/catch`: dejar propagar y centralizar la captura.
- Bloques `try/catch` **pequeños y focalizados** — no envolver 100 líneas.
- Cerrar recursos con `using` / `await using` en lugar de `try/finally` manual.
- Usar `when` para filtros condicionales: `catch (SqlException ex) when (ex.Number == 2601)`.

### Manejo global (.NET 8+)

La recomendación actual es usar **`IExceptionHandler`** + **`AddProblemDetails()`** — sustituye a los middlewares manuales de excepciones.

```csharp
// Handler tipado, testeable e inyectable
public sealed class GlobalExceptionHandler(ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext context,
        Exception exception,
        CancellationToken cancellationToken)
    {
        logger.LogError(exception, "Unhandled exception {TraceId}", context.TraceIdentifier);

        (int status, string title) = exception switch
        {
            ValidationException     => (StatusCodes.Status400BadRequest,   "Validation failed"),
            KeyNotFoundException    => (StatusCodes.Status404NotFound,     "Resource not found"),
            UnauthorizedAccessException => (StatusCodes.Status401Unauthorized, "Unauthorized"),
            _                       => (StatusCodes.Status500InternalServerError, "Unexpected error")
        };

        context.Response.StatusCode = status;
        await context.Response.WriteAsJsonAsync(new ProblemDetails
        {
            Status = status,
            Title  = title,
            Type   = $"https://httpstatuses.io/{status}",
            Instance = context.Request.Path
        }, cancellationToken);

        return true;
    }
}

// Registro
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddProblemDetails();

app.UseExceptionHandler();
app.UseStatusCodePages();
```

Ventajas frente al middleware manual:
- Compone con el pipeline nativo (`UseExceptionHandler` + `AddProblemDetails`).
- Permite **encadenar** varios handlers (`AddExceptionHandler<A>()` + `AddExceptionHandler<B>()`).
- Integración automática con `ProblemDetails` para 4xx/5xx sin escribir JSON a mano.

### ProblemDetails (RFC 9457)

Es el formato **estándar** para errores HTTP en .NET moderno (`Microsoft.AspNetCore.Mvc.ProblemDetails`).

- Devolver siempre `application/problem+json` en errores.
- Campos obligatorios: `type`, `title`, `status`. Opcionales: `detail`, `instance`, extensiones.
- **No exponer detalles sensibles** (stack traces, connection strings, mensajes internos) en producción.
- Incluir `traceId` (correlación) como extensión para debugging:
  ```csharp
  builder.Services.AddProblemDetails(options =>
  {
      options.CustomizeProblemDetails = ctx =>
          ctx.ProblemDetails.Extensions["traceId"] = ctx.HttpContext.TraceIdentifier;
  });
  ```
- En 400 (validación) usar `ValidationProblemDetails` con la colección `errors`.

### Logging estructurado
- Usar `ILogger<T>` con **plantillas de mensaje**, no interpolación:
  ```csharp
  logger.LogError(ex, "Fallo al procesar pedido {OrderId} para {UserId}", orderId, userId);
  ```
- Nunca loguear datos sensibles (contraseñas, tokens, PII sin enmascarar).
- Correlacionar con `Activity.Current?.TraceId` u `OpenTelemetry` para trazabilidad distribuida.

### Errores transitorios
- Usar **Polly** (o `AddStandardResilienceHandler()` de `Microsoft.Extensions.Http.Resilience`) para *retry*, *circuit breaker* y *timeout* en llamadas HTTP/DB.
- Distinguir excepciones **transitorias** (reintentables) de **permanentes** (no reintentar).

### Mensajes al usuario vs logs
- **Al usuario**: mensajes cortos, claros y accionables ("No pudimos completar tu pedido. Intenta de nuevo.").
- **En logs**: excepción completa, contexto (`{@Request}`, `{UserId}`, `{TraceId}`), sin exponer secretos.
- En `Development` puede devolverse `detail` con el mensaje; en `Production` **jamás** stack traces.

---

## 7. API REST (endpoints)

> Aplica tanto a APIs que expongas (BFF, minimal APIs en Blazor Server) como a cómo consumir APIs de terceros de forma correcta.

### Recursos y URLs
- Los endpoints representan **recursos**, no acciones. Usar **sustantivos en plural** y en **minúsculas**: `/customers`, `/orders/{id}`.
- **Nunca verbos** en la URL: `GET /orders` (✅), no `GET /getOrders` (❌). El verbo lo indica el método HTTP.
- **kebab-case** para segmentos compuestos: `/order-items`, `/purchase-orders`.
- Recursos anidados con moderación (máx. 2 niveles): `/customers/{id}/orders` ✅. Para relaciones más profundas, exponer un recurso propio.
- **camelCase** en los cuerpos JSON (convención por defecto de `System.Text.Json` en .NET).

### Métodos HTTP
| Método | Uso | Idempotente | Body |
|--------|-----|-------------|------|
| `GET` | Leer recurso o colección | Sí | No |
| `POST` | Crear recurso o acción no idempotente | No | Sí |
| `PUT` | Reemplazar el recurso completo | Sí | Sí |
| `PATCH` | Modificación parcial (JSON Patch / Merge Patch) | Depende | Sí |
| `DELETE` | Eliminar recurso | Sí | Opcional |

### Códigos de estado
| Código | Cuándo usarlo |
|--------|---------------|
| `200 OK` | GET/PUT/PATCH con respuesta |
| `201 Created` | POST que crea recurso — incluir header `Location: /customers/{id}` |
| `202 Accepted` | Petición aceptada para procesamiento asíncrono |
| `204 No Content` | Éxito sin cuerpo (DELETE, PUT sin representación) |
| `400 Bad Request` | Payload inválido, sintácticamente mal formado |
| `401 Unauthorized` | Sin credenciales o inválidas |
| `403 Forbidden` | Autenticado pero sin permiso |
| `404 Not Found` | Recurso inexistente |
| `409 Conflict` | Estado inconsistente (versión concurrente, duplicado) |
| `422 Unprocessable Entity` | Payload válido pero reglas de negocio no cumplen |
| `429 Too Many Requests` | Rate limiting excedido |
| `500 Internal Server Error` | Error inesperado |

### Versionado
- Versionar desde el día uno. Estilos aceptados:
  - **URL**: `/api/v1/customers` — el más explícito y usado.
  - **Header**: `Api-Version: 1`.
  - **Media type**: `Accept: application/vnd.company.v1+json`.
- Usar el paquete oficial `Asp.Versioning.Http` (antes `Microsoft.AspNetCore.Mvc.Versioning`).
- Nunca romper contratos de una versión publicada; ante cambios incompatibles, subir mayor.

### Paginación, filtros y ordenamiento
- Paginación por query string: `?page=1&pageSize=20`. Limitar `pageSize` (ej. máx. 100).
- Devolver metadata en la respuesta:
  ```json
  {
    "items": [ ... ],
    "page": 1,
    "pageSize": 20,
    "totalItems": 137,
    "totalPages": 7
  }
  ```
- Filtros: `?status=active&createdAfter=2026-01-01`.
- Ordenamiento: `?sort=createdAt,-name` (`-` = descendente).

### Errores
- Devolver siempre **`ProblemDetails`** (RFC 9457) con `Content-Type: application/problem+json`. Ver sección 6.
- En 400 usar `ValidationProblemDetails` con la colección `errors`.

### DTOs y contratos
- **No exponer entidades de dominio** directamente en respuestas HTTP. Usar DTOs.
- Modelos de entrada distintos de los de salida cuando la forma no coincide (`CreateCustomerRequest` vs `CustomerResponse`).
- Validar la entrada con FluentValidation o `DataAnnotations` en el DTO, no en la entidad.

### Idempotencia y concurrencia
- Para POST críticos (pagos, cobros), aceptar header **`Idempotency-Key`** y garantizar que reintentos con el mismo key producen el mismo resultado.
- Usar **`ETag`** + `If-Match` / `If-None-Match` para caching y control de concurrencia optimista.

### Documentación
- **OpenAPI/Swagger obligatorio**. Anotar cada endpoint con `[ProducesResponseType]`, resumen y ejemplos.
- Publicar la spec en `/swagger` (desarrollo) y opcionalmente en producción con auth.

### Seguridad
- **HTTPS** siempre. Redirigir HTTP → HTTPS.
- Autenticación con **JWT Bearer** o **OAuth 2.0 / OpenID Connect**.
- Autorización por políticas (`[Authorize(Policy = "...")]`), no por roles hardcodeados dispersos.
- Habilitar **CORS** solo para los orígenes necesarios — nunca `AllowAnyOrigin` en producción con credenciales.
- **Rate limiting** (`AddRateLimiter` en .NET 7+).
- Nunca exponer IDs internos secuenciales que revelen conteo o permitan enumeración; considerar GUIDs o hashids.

---

## 8. Blazor

### Componentes
- **Un componente = una responsabilidad**. Si un `.razor` supera ~200 líneas o mezcla varias vistas, dividir en subcomponentes.
- Separar markup y lógica en **code-behind** (`MiComponente.razor` + `MiComponente.razor.cs` con `partial class`) cuando la lógica supera unas pocas líneas.
- Parámetros públicos con `[Parameter]`; parámetros de cascada con `[CascadingParameter]`; nunca mutar parámetros de entrada desde el propio componente.
- Preferir **componentes tontos** (presentacionales) + **componentes contenedor** (con lógica y llamadas a servicios).
- Usar `EventCallback<T>` para notificar al padre — nunca `Action`/`Func` directos (rompen re-render automático).

### Estado y renderizado
- Preferir **estado local** al componente. Compartir estado solo mediante **servicios inyectados** (`Scoped`/`Singleton` según hosting model) o `CascadingValue`.
- Llamar a `StateHasChanged()` **solo cuando sea necesario** — los `EventCallback` y el binding lo disparan automáticamente.
- Marcar `ShouldRender()` en componentes muy frecuentes para evitar re-renders costosos.
- Elegir el **modo de render correcto**: `InteractiveServer`, `InteractiveWebAssembly`, `InteractiveAuto` o `Static SSR`. No mezclar sin criterio — impacta latencia, tamaño de payload y consumo de memoria.

### Ciclo de vida
- Preferir versiones `Async` (`OnInitializedAsync`, `OnParametersSetAsync`) para no bloquear el hilo de render.
- **No** hacer llamadas HTTP ni acceso a datos en el constructor — usar `OnInitializedAsync`.
- Implementar `IDisposable` / `IAsyncDisposable` cuando el componente se suscribe a eventos, `Timer`s o servicios reactivos.

### Formularios y validación
- Usar `EditForm` + `DataAnnotationsValidator` para casos simples.
- Para reglas complejas, integrar **FluentValidation** mediante un `ValidatorComponent` propio.
- Mostrar errores con `ValidationSummary` o `ValidationMessage For=...`.

### JS Interop
- Minimizar el uso de `IJSRuntime`. Si un componente lo requiere, encapsular la lógica en un servicio JS módulo (`import()`).
- **Liberar recursos** JS en `DisposeAsync`: importar el módulo una vez, mantener la referencia y llamar `dispose()` al desmontar.
- Nunca ejecutar JS dinámicamente con datos del usuario (riesgo XSS).

### Estilos y assets
- **CSS aislado por componente** (`MiComponente.razor.css`) — evita fugas de estilos globales.
- Estilos globales solo en `wwwroot/css/app.css` y hojas de diseño (Tailwind, Bootstrap, MudBlazor, etc.).
- Cargar librerías grandes de terceros vía **CDN** o mediante **lazy loading de assemblies** (`BlazorWebAssemblyLoadAllGlobalizationData=false`, `LazyAssemblyLoader`).
- Habilitar **compresión Brotli/GZip** para reducir el payload inicial (crítico en WebAssembly).

### Manejo de errores
- Envolver árboles de componentes con **`<ErrorBoundary>`** para aislar fallos y mostrar UI de fallback.
- Registrar errores no capturados con `ILogger` inyectado — nunca solo `Console.WriteLine`.

### Accesibilidad
- Toda UI debe cumplir **WCAG 2.2** — ver `WCAG.md` para el detalle.

---

## 9. Comentarios

- Comentarios **útiles**, no redundantes. El buen código se autoexplica.
- Usar `//` o `///` (nunca `/* */`).
- Documentar lógica **compleja o no obvia** — no lo trivial.
- Usar `// TODO:` para tareas pendientes rastreables por VS.
- Habilitar **generación de XML docs** (`GenerateDocumentationFile` en el `.csproj`) para APIs públicas.
- Revisar ortografía y gramática de los comentarios.

---

## 10. Versionado y Ciclo de Vida

| Fase | Nomenclatura | Descripción |
|------|--------------|-------------|
| Alpha | `0.0.x` | En desarrollo, no operativo |
| Beta | `b1.0` | Funcionalidades completas, en testing interno |
| Release Candidate | `rc1.0` | Pasó todos los tests, en pre-producción |
| Release | `1.0` | Producto final en producción |
| Patch | `1.1` | Correcciones o mejoras menores en producción |

Seguir **SemVer** (`MAJOR.MINOR.PATCH`) para librerías públicas.

---

## 11. Revisiones de Código (Sprint / Retrospectiva)

- **Peer Review** — cada archivo revisado por otro miembro del equipo.
- **Architect Review** — el arquitecto valida los módulos críticos.
- **Group Review** — revisión grupal periódica de fragmentos aleatorios.

> *"Los programas deben ser escritos para que los lean las personas, y sólo incidentalmente para que los ejecute la máquina."* — Abelson & Sussman

---

## Referencias
- Documento original: *Estándares de Codificación en C# y Buenas Prácticas de Programación* — Alberto Fernández (canaldenegocio.com).
- [Framework Design Guidelines (Microsoft Docs)](https://learn.microsoft.com/dotnet/standard/design-guidelines/).
- [C# Coding Conventions (Microsoft Docs)](https://learn.microsoft.com/dotnet/csharp/fundamentals/coding-style/coding-conventions).
'@ | Set-Variable -Name BestPracticesCSharpMd
[System.IO.File]::WriteAllText(
    (Join-Path (Get-Location) 'documentation/BuenasPracticasCSharp.md'),
    $BestPracticesCSharpMd,
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
    foreach ($docPath in @('documentation/ArchitectureGuide.md', 'documentation/WCAG.md', 'documentation/BuenasPracticasCSharp.md')) {
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
Write-Host "  src/Presentation/Client/                   ($ProjectName.Web - Blazor Web Assembly)"           -ForegroundColor Gray
Write-Host "  src/Domain/                   ($ProjectName.Domain - Entities, Interfaces)"        -ForegroundColor Gray
Write-Host "  src/Application/ViewModels/   ($ProjectName.ViewModels - Use Cases, Services)"     -ForegroundColor Gray
Write-Host "  src/Application/Validators/   ($ProjectName.Validators - FluentValidation)"        -ForegroundColor Gray
Write-Host "  src/Infrastructure/WebApi/    ($ProjectName.WebApi - External Services, HTTP)"     -ForegroundColor Gray
Write-Host "  src/Presentation/Views/                    ($ProjectName.Views - Razor Components, Layouts)"    -ForegroundColor Gray
Write-Host "  src/Presentation/IoC/                      ($ProjectName.IoC - Dependency Injection)"           -ForegroundColor Gray
Write-Host ""
Write-Host "Powered by David Vázquez Palestino" -ForegroundColor DarkGray