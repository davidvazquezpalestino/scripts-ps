# =========================================================================
#  new-clean-arch-api.ps1
#  Powered by David Vazquez Palestino
# =========================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName
)

# =========================
# COMPUTE PORTS (deterministic per project name)
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

$HttpPort  = Get-DeterministicPort -Name $ProjectName -Base 5000 -Range 1000
$HttpsPort = Get-DeterministicPort -Name $ProjectName -Base 7000 -Range 1000

# Puertos del host para los contenedores Docker (4 instancias consecutivas por proyecto).
# Se usa el mismo hash determinista para que cada proyecto tenga puertos distintos
# y no siempre sean los mismos al levantarlo.
$DockerBasePort = Get-DeterministicPort -Name $ProjectName -Base 8000 -Range 990
$DockerPort1 = $DockerBasePort
$DockerPort2 = $DockerBasePort + 1
$DockerPort3 = $DockerBasePort + 2
$DockerPort4 = $DockerBasePort + 3

Write-Host "Creating Clean Architecture solution: $ProjectName"
Write-Host "  HTTP  -> http://localhost:$HttpPort"
Write-Host "  HTTPS -> https://localhost:$HttpsPort"
Write-Host "  Docker host ports -> $DockerPort1, $DockerPort2, $DockerPort3, $DockerPort4"

# Root
New-Item -ItemType Directory -Path $ProjectName
Set-Location $ProjectName

# Solution
dotnet new sln -n "$ProjectName"

# Folders
New-Item -ItemType Directory -Path "src"
New-Item -ItemType Directory -Path "tests"

# =========================
# CREATE PROJECTS
# =========================
# Cada proyecto vive dentro de su propia subcarpeta para que bin/obj queden aislados
# y la carpeta-capa (Application, Infrastructure, etc.) pueda alojar proyectos hermanos.

# API
dotnet new web -n "$ProjectName.WebApi" -o "src/Presentation/Api"

# Application sub-projects (separate projects)
dotnet new classlib -n "$ProjectName.Commands" -o "src/Application/Commands"
dotnet new classlib -n "$ProjectName.Models" -o "src/Application/Models"
dotnet new classlib -n "$ProjectName.Queries" -o "src/Application/Queries"
dotnet new classlib -n "$ProjectName.Validators" -o "src/Application/Validators"
dotnet new classlib -n "$ProjectName.Controllers" -o "src/Presentation/Controllers"

# IoC Project at same level as Application
dotnet new classlib -n "$ProjectName.IoC" -o "src/Presentation/IoC"

# Domain
dotnet new classlib -n "$ProjectName.Domain" -o "src/Domain"

# Infrastructure
dotnet new classlib -n "$ProjectName.DataBase" -o "src/Infrastructure/DataBase"

# Tests (xUnit.net v3)
# Asegurar que la plantilla xunit3 est� disponible (paquete xunit.v3.templates)
$templateList = dotnet new list xunit3 2>&1 | Out-String
if ($templateList -notmatch "(?m)^\s*xunit3\b") {
    Write-Host "Instalando plantillas de xUnit.net v3 (xunit.v3.templates)..."
    dotnet new install xunit.v3.templates
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Fall� la instalaci�n de xunit.v3.templates. No se puede crear el proyecto de pruebas."
        exit 1
    }
}
dotnet new xunit3 -n "$ProjectName.UnitTests" -o "tests/UnitTests"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path "tests/UnitTests")) {
    Write-Error "No se pudo crear el proyecto tests/UnitTests con la plantilla xunit3."
    exit 1
}

# Remove default Class1.cs files
Remove-Item "src/Application/Commands/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Application/Models/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Application/Queries/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Presentation/Controllers/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Presentation/IoC/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Domain/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Application/Validators/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Infrastructure/DataBase/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "tests/UnitTests/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "tests/UnitTests/UnitTest1.cs" -Force -ErrorAction SilentlyContinue

# Remove <Nullable>enable</Nullable> from every generated .csproj
Get-ChildItem -Path 'src','tests' -Recurse -Filter *.csproj | ForEach-Object {
    $c = Get-Content -Raw -Path $_.FullName
    $n = $c -replace '(?m)^[ \t]*<Nullable>\s*enable\s*</Nullable>[ \t]*\r?\n', ''
    if ($n -ne $c) { Set-Content -Path $_.FullName -Value $n -NoNewline }
}

# =========================
# ADD TO SOLUTION
# =========================

dotnet sln add src/Presentation/Api
dotnet sln add src/Application/Commands
dotnet sln add src/Application/Models
dotnet sln add src/Application/Queries
dotnet sln add src/Application/Validators
dotnet sln add src/Presentation/Controllers
dotnet sln add src/Presentation/IoC
dotnet sln add src/Domain
dotnet sln add src/Infrastructure/DataBase
dotnet sln add tests/UnitTests

# =========================
# PROJECT REFERENCES
# =========================

# Application sub-projects depend on Domain
dotnet add src/Application/Commands reference src/Domain
dotnet add src/Application/Models reference src/Domain
dotnet add src/Application/Queries reference src/Domain
dotnet add src/Application/Validators reference src/Domain

# Controllers depend on Application layer projects
dotnet add src/Presentation/Controllers reference src/Domain
dotnet add src/Presentation/Controllers reference src/Application/Commands
dotnet add src/Presentation/Controllers reference src/Application/Queries
dotnet add src/Presentation/Controllers reference src/Application/Models
# IoC depends on all Application projects + Infrastructure + Domain
dotnet add src/Presentation/IoC reference src/Application/Commands
dotnet add src/Presentation/IoC reference src/Application/Models
dotnet add src/Presentation/IoC reference src/Application/Queries
dotnet add src/Presentation/IoC reference src/Application/Validators
dotnet add src/Presentation/IoC reference src/Presentation/Controllers
dotnet add src/Presentation/IoC reference src/Infrastructure/DataBase
dotnet add src/Presentation/IoC reference src/Domain

# Infrastructure depends only on Domain (implements interfaces defined there)
dotnet add src/Infrastructure/DataBase reference src/Domain

# API depends on IoC
dotnet add src/Presentation/Api reference src/Presentation/IoC

# Tests
dotnet add tests/UnitTests reference src/Domain

# =========================
# ADD PACKAGES
# =========================

# Application sub-projects
dotnet add src/Application/Commands package FluentValidation
dotnet add src/Application/Commands package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Application/Commands package DependencyInjection.ReflectionExtensions

dotnet add src/Application/Models package FluentValidation
dotnet add src/Application/Models package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Application/Models package DependencyInjection.ReflectionExtensions

dotnet add src/Application/Queries package FluentValidation
dotnet add src/Application/Queries package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Application/Queries package DependencyInjection.ReflectionExtensions

dotnet add src/Application/Validators package FluentValidation
dotnet add src/Application/Validators package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Application/Validators package DependencyInjection.ReflectionExtensions

dotnet add src/Presentation/Controllers package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Presentation/Controllers package DependencyInjection.ReflectionExtensions

# Controllers needs ASP.NET Core framework reference (ControllerBase, [ApiController], etc.)
$controllersCsproj = "src/Presentation/Controllers/$ProjectName.Controllers.csproj"
[xml]$controllersXml = Get-Content $controllersCsproj
if (-not ($controllersXml.Project.ItemGroup | Where-Object { $_.FrameworkReference.Include -eq "Microsoft.AspNetCore.App" })) {
    $itemGroup = $controllersXml.CreateElement("ItemGroup")
    $frameworkRef = $controllersXml.CreateElement("FrameworkReference")
    $frameworkRef.SetAttribute("Include", "Microsoft.AspNetCore.App")
    $itemGroup.AppendChild($frameworkRef) | Out-Null
    $controllersXml.Project.AppendChild($itemGroup) | Out-Null
    $controllersXml.Save((Resolve-Path $controllersCsproj))
}

# IoC
dotnet add src/Presentation/IoC package Microsoft.Extensions.DependencyInjection
dotnet add src/Presentation/IoC package Microsoft.EntityFrameworkCore
dotnet add src/Presentation/IoC package Microsoft.EntityFrameworkCore.SqlServer
dotnet add src/Presentation/IoC package FluentValidation
dotnet add src/Presentation/IoC package DependencyInjection.ReflectionExtensions
dotnet add src/Presentation/IoC package Serilog
dotnet add src/Presentation/IoC package Serilog.Settings.Configuration
dotnet add src/Presentation/IoC package CoreJsonWebToken
dotnet add src/Presentation/IoC package DevKit.ExecutionEngine.Redis

# Infrastructure
dotnet add src/Infrastructure/DataBase package Microsoft.EntityFrameworkCore
dotnet add src/Infrastructure/DataBase package Microsoft.EntityFrameworkCore.SqlServer
dotnet add src/Infrastructure/DataBase package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Infrastructure/DataBase package DependencyInjection.ReflectionExtensions

# API
dotnet add src/Presentation/Api package Microsoft.EntityFrameworkCore.Design
dotnet add src/Presentation/Api package Scalar.AspNetCore
dotnet add src/Presentation/Api package Serilog
dotnet add src/Presentation/Api package Serilog.Extensions.Hosting
dotnet add src/Presentation/Api package Serilog.Sinks.Console
dotnet add src/Presentation/Api package Swashbuckle.AspNetCore

# Tests
dotnet add tests/UnitTests package FluentAssertions

# =========================
# CREATE BASE FOLDERS
# =========================

# Domain structure
New-Item -ItemType Directory -Path "src/Domain/Entities"
New-Item -ItemType Directory -Path "src/Domain/ValueObjects"
New-Item -ItemType Directory -Path "src/Domain/Enums"
New-Item -ItemType Directory -Path "src/Domain/Interfaces"
New-Item -ItemType Directory -Path "src/Infrastructure/DataBase/Options" -Force

# Keep domain folders visible in Visual Studio Solution Explorer
"" | Set-Content "src/Domain/Entities/.gitkeep"
"" | Set-Content "src/Domain/ValueObjects/.gitkeep"
"" | Set-Content "src/Domain/Enums/.gitkeep"
"" | Set-Content "src/Domain/Interfaces/.gitkeep"

# API structure

New-Item -ItemType Directory -Path "src/Presentation/Api/Middleware" -Force
New-Item -ItemType Directory -Path "src/Presentation/Api/Configurations" -Force
New-Item -ItemType Directory -Path "src/Presentation/Api/Properties" -Force

# launchSettings.json (puertos determin�sticos por proyecto para evitar choques)
@"
{
  "`$schema": "https://json.schemastore.org/launchsettings.json",
  "profiles": {
    "http": {
      "commandName": "Project",
      "launchBrowser": true,
      "launchUrl": "swagger",
      "applicationUrl": "http://localhost:$HttpPort",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    },
    "https": {
      "commandName": "Project",
      "launchBrowser": true,
      "launchUrl": "swagger",
      "applicationUrl": "https://localhost:$HttpsPort;http://localhost:$HttpPort",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    }
  }
}
"@ | Set-Content "src/Presentation/Api/Properties/launchSettings.json"

# appsettings.json
@"
{
    "EnvironmentOptions": {
        "EnvironmentName": "Production" /*Development, Staging, Production*/
    }
}
"@ | Set-Content "src/Presentation/Api/appsettings.json"

# appsettings.Development.json
@"
{
    "DataBaseOptions": {
        "DefaultConnection": "Server=[Server];Database=[Database];User Id=sa;Password=[Password];MultipleActiveResultSets=true;encrypt=false;"
    },
    "JwtOptions": {
        "SecurityKey": "1234567890ABCDEFGHIJKLMN�OPQRSTU",
        "ValidIssuer": "empresa",
        "ValidAudience": "empresa",
        "ExpireInMinutes": 1440
    },
    "RedisOptions": {
        "ConnectionRedis": "[Server],password=[Password]",
        "Environment": "Development",
        "DiasCache": 1
    },
    "AllowedHosts": "*"
}
"@ | Set-Content "src/Presentation/Api/appsettings.Development.json"

# appsettings.Production.json
@"
{
    "DataBaseOptions": {
        "DefaultConnection": "Server=[Server];Database=[Database];User Id=sa;Password=[Password];MultipleActiveResultSets=true;encrypt=false;"
    },
    "JwtOptions": {
        "SecurityKey": "1234567890ABCDEFGHIJKLMN�OPQRSTU",
        "ValidIssuer": "empresa",
        "ValidAudience": "empresa",
        "ExpireInMinutes": 1440
    },
    "RedisOptions": {
        "ConnectionRedis": "[Server],password=[Password]",
        "Environment": "Production",
        "DiasCache": 1
    },
    "AllowedHosts": "*"
}
"@ | Set-Content "src/Presentation/Api/appsettings.Production.json"

# CREATE BASIC FILES
# =========================

# DependencyContainer class in Commands Project
@"

namespace $ProjectName.Commands
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddCommands(this IServiceCollection services)
        {  
            services.AddCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Application/Commands/DependencyContainer.cs"

# GlobalUsings Commands
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Application/Commands/GlobalUsings.cs"

# DependencyContainer class in Queries Project
@"

namespace $ProjectName.Queries
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddQueries(this IServiceCollection services)
        {  
            services.AddCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Application/Queries/DependencyContainer.cs"

# GlobalUsings Queries
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Application/Queries/GlobalUsings.cs"

# DependencyContainers

# DependencyContainer class in Validators Project
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

# DependencyContainer class in Infrastructure Project
@"

namespace $ProjectName.DataBase
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
"@ | Set-Content "src/Infrastructure/DataBase/DependencyContainer.cs"

# DependencyContainer class in IoC Project
@"

namespace $ProjectName.IoC
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddIoC(this IServiceCollection services, IConfiguration configuration)
        {
            services.Configure<EnvironmentOptions>(configuration.GetSection(EnvironmentOptions.SectionKey));
            services.Configure<DataBaseOptions>(configuration.GetSection(DataBaseOptions.SectionKey));
            services.Configure<RedisOptions>(configuration.GetSection(RedisOptions.SectionKey));
            services.AddJwtServices(options => configuration.GetSection(JwtOptions.SectionKey).Bind(options));
            services.AddRedisCache();

            services.AddCommands()
                        .AddQueries()
                        .AddValidators()
                        .AddInfrastructure()
                        .AddSerilog(configuration);            
            return services;
        }

        public static IServiceCollection AddSerilog(this IServiceCollection services, IConfiguration configuration)
        {
            services.AddSingleton<ILogger>(new LoggerConfiguration()
                .MinimumLevel.Debug()
                .ReadFrom.Configuration(configuration)
                .CreateLogger());
            return services;
        }
    }
}
"@ | Set-Content "src/Presentation/IoC/DependencyContainer.cs"

# GlobalUsings

# GlobalUsings Validators
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Application/Validators/GlobalUsings.cs"

# GlobalUsings Infrastructure
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Infrastructure/DataBase/GlobalUsings.cs"

# GlobalUsings class in IoC Project
@"
global using $ProjectName.Commands;
global using $ProjectName.DataBase;
global using $ProjectName.Queries;
global using $ProjectName.Validators;
global using $ProjectName.DataBase.Options;
global using Serilog;
global using Microsoft.AspNetCore.Builder;
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using DevKit.JWT.Extensions;
global using DevKit.JWT.Options;
global using DevKit.ExecutionEngine.Redis;
global using DevKit.ExecutionEngine.Redis.Options;

"@ | Set-Content "src/Presentation/IoC/GlobalUsings.cs"

# GlobalUsings Controllers
@"
global using Microsoft.AspNetCore.Mvc;
global using Microsoft.AspNetCore.Http;
"@ | Set-Content "src/Presentation/Controllers/GlobalUsings.cs"

# GlobalUsings Domain
@"

"@ | Set-Content "src/Domain/GlobalUsings.cs"

# DataBaseOptions class in Infrastructure
@"

namespace $ProjectName.DataBase.Options
{
    public class DataBaseOptions
    {
        public const string SectionKey = nameof(DataBaseOptions);
        public string DefaultConnection { get; set; } 
    }
}
"@ | Set-Content "src/Infrastructure/DataBase/Options/DataBaseOptions.cs"

# EnvironmentOptions class in Infrastructure
@"

namespace $ProjectName.DataBase.Options
{
    public class EnvironmentOptions
    {
        public const string SectionKey = nameof(EnvironmentOptions);
        public string EnvironmentName { get; set; } 
    }
}
"@ | Set-Content "src/Infrastructure/DataBase/Options/EnvironmentOptions.cs"

# GlobalUsings Api
@"
global using Microsoft.AspNetCore.Builder;
global using Microsoft.AspNetCore.Http;
global using Microsoft.Extensions.DependencyInjection;
global using System.Text.Json.Serialization;
global using $ProjectName.IoC;
global using Microsoft.OpenApi;
global using Microsoft.AspNetCore.Mvc;
global using $ProjectName.WebApi.Configurations;
global using $ProjectName.WebApi.Middleware;
global using $ProjectName.DataBase.Options;

"@ | Set-Content "src/Presentation/Api/GlobalUsings.cs"

# GlobalUsings Tests
@"
global using FluentAssertions;
global using Xunit;
"@ | Set-Content "tests/UnitTests/GlobalUsings.cs"

# API Configuration files
@"

namespace $ProjectName.WebApi.Configurations
{
    public static class MiddlewaresConfiguration
    {
        public static WebApplication ConfigureWebApiMiddlewares(this WebApplication app)
        {
            app.UseSwagger();
            app.UseSwaggerUI(c =>
            {
                c.SwaggerEndpoint("v1/swagger.json", "API v1");
            });
            app.MapHealthChecks("/health");
            app.UseMiddleware<ErrorHandlerMiddleware>();
            app.UseRouting();
            app.MapControllers();
            return app;
        }
    }
}
"@ | Set-Content "src/Presentation/Api/Configurations/MiddlewaresConfiguration.cs"
@"

namespace $ProjectName.WebApi.Configurations
{
    public static class ServicesConfiguration
    {
        public static WebApplication ConfigureWebApiServices(this WebApplicationBuilder app)
        {
            app.Configuration.AddJsonFile(
                $"appsettings.{app.Configuration.GetSection(EnvironmentOptions.SectionKey)
                    .Get<EnvironmentOptions>()?.EnvironmentName ?? app.Environment.EnvironmentName}.json",
                optional: true,
                reloadOnChange: true);

            app.Services.AddControllers().AddJsonOptions(options =>
                options.JsonSerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull);

            app.Services.AddEndpointsApiExplorer();
            app.Services.AddSwaggerGen(c =>
            {
                c.SwaggerDoc("v1", new OpenApiInfo
                {
                    Title = "API",
                    Version = "v1",
                    Description = "Clean Architecture API"
                });
            });
            app.Services.AddIoC(app.Configuration);
            app.Services.AddHttpClient();
            app.Services.AddAuthorization();
            app.Services.AddHealthChecks();
            
            return app.Build();
        }
    }
}
"@ | Set-Content "src/Presentation/Api/Configurations/ServicesConfiguration.cs"

@"

namespace $ProjectName.WebApi.Middleware
{
    public class ErrorHandlerMiddleware(RequestDelegate next, Serilog.ILogger logger)
    {
        public async Task Invoke(HttpContext context)
        {
            try
            {
                await next(context);
            }
            catch (Exception exception)
            {
                // Configurar informaci�n base de la respuesta
                HttpResponse response = context.Response;
                // Si la respuesta ya comenz�, no es seguro modificar headers/body
                if (response.HasStarted)
                {
                    logger.Error(exception, "La respuesta ya comenz�. El error no se devuelve al cliente. {TraceId}", context.TraceIdentifier);
                    throw; // Permitir que el servidor termine la conexi�n seg�n corresponda
                }

                response.ContentType = "application/json";

                // Mapear tipos de excepciones conocidas a c�digos de estado apropiados
                int statusCode = exception switch
                {
                    UnauthorizedAccessException => StatusCodes.Status401Unauthorized,
                    KeyNotFoundException => StatusCodes.Status404NotFound,
                    ArgumentException => StatusCodes.Status400BadRequest,
                    _ => StatusCodes.Status500InternalServerError
                };

                // Evitar exponer detalles sensibles/internos en respuestas al cliente
                // Mantener la informaci�n detallada solo en los logs
                ProblemDetails problemDetails = new ProblemDetails
                {
                    Status = statusCode,
                    Title = statusCode == StatusCodes.Status500InternalServerError ? "Unexpected error" : "Request error",
                    Type = statusCode switch
                    {
                        StatusCodes.Status401Unauthorized => "https://httpstatuses.io/401",
                        StatusCodes.Status404NotFound => "https://httpstatuses.io/404",
                        StatusCodes.Status400BadRequest => "https://httpstatuses.io/400",
                        _ => "https://httpstatuses.io/500"
                    },
                    Detail = exception.Message,
                    Instance = $"{context.Request.Path} {context.Request.Method} "
                };
                // Registrar la excepci�n completa con contexto estructurado; NO incluir configuraci�n sensible en la respuesta
                logger.Error(exception, "Error occurred with details {@ProblemDetails}", problemDetails);

                response.StatusCode = statusCode;
                await context.Response.WriteAsJsonAsync(problemDetails, CancellationToken.None);
            }
        }
    }
}
"@ | Set-Content "src/Presentation/Api/Middleware/ErrorHandlerMiddleware.cs"

# Minimal API starter
@"

WebApplication.CreateBuilder(args)
    .ConfigureWebApiServices()
    .ConfigureWebApiMiddlewares()
    .Run();
"@ | Set-Content "src/Presentation/Api/Program.cs"

# Dockerfile
@"
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG Configuration=Release
WORKDIR /src
COPY src/Presentation/Api/$ProjectName.WebApi.csproj src/Presentation/Api/
COPY src/Application/Commands/$ProjectName.Commands.csproj src/Application/Commands/
COPY src/Presentation/Controllers/$ProjectName.Controllers.csproj src/Presentation/Controllers/
COPY src/Domain/$ProjectName.Domain.csproj src/Domain/
COPY src/Infrastructure/DataBase/$ProjectName.DataBase.csproj src/Infrastructure/DataBase/
COPY src/Presentation/IoC/$ProjectName.IoC.csproj src/Presentation/IoC/
COPY src/Application/Models/$ProjectName.Models.csproj src/Application/Models/
COPY src/Application/Queries/$ProjectName.Queries.csproj src/Application/Queries/
COPY src/Application/Validators/$ProjectName.Validators.csproj src/Application/Validators/
RUN dotnet restore src/Presentation/Api/$ProjectName.WebApi.csproj
COPY . .
WORKDIR /src/src/Presentation/Api
RUN dotnet build $ProjectName.WebApi.csproj -c `${Configuration} -o /app/build

FROM build AS publish
ARG Configuration=Release
RUN dotnet publish $ProjectName.WebApi.csproj -c `${Configuration} -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "$ProjectName.WebApi.dll"]

#docker build -f src/Presentation/Api/Dockerfile -t "$($ProjectName.ToLower())-api:latest" .
#docker container rm -f "$($ProjectName.ToLower())-api"
#docker run -d --name "$($ProjectName.ToLower())-api" -p $($DockerPort1):8080 "$($ProjectName.ToLower())-api:latest"

"@ | Set-Content "src/Presentation/Api/Dockerfile"

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
    displayName: Deploy API __PROJECT_NAME__
    inputs:
        sshEndpoint: UbuntuServer
        runOptions: inline
        inline: |
            cd /var/www/__PROJECT_DIR__/__PROJECT_NAME__
            chmod +x src/Presentation/Api/deploy.sh
            ./src/Presentation/Api/deploy.sh
        failOnStdErr: false
'@ | Set-Content "src/Presentation/Api/azure-pipelines.yml"

$projectDirName = "api-$($ProjectName.ToLower())"
$projectSlug = $ProjectName.ToLower().Replace('.', '-').Replace('_', '-')
$azurePipelinesContent = Get-Content -Raw "src/Presentation/Api/azure-pipelines.yml"
$azurePipelinesContent = $azurePipelinesContent.Replace("__PROJECT_DIR__", $projectDirName).Replace("__PROJECT_NAME__", $ProjectName)
$azurePipelinesContent | Set-Content "src/Presentation/Api/azure-pipelines.yml"

# deploy.sh
@'
#!/bin/bash
set -e

BASE_DIR="/var/www/__PROJECT_DIR__"
APP_DIR="$BASE_DIR/__PROJECT_NAME__"
IMAGE_NAME="webapi-__PROJECT_SLUG__"
BRANCH="main"
TZ="America/Mexico_City"
REPO_URL="https://davidvazquezpalestino.visualstudio.com/__PROJECT_NAME__/_git/__PROJECT_NAME__"

echo "====================================="
echo "Deploy API __PROJECT_NAME__ (simple)"
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
docker build -t $IMAGE_NAME .

# 3. Detener y eliminar contenedores existentes
echo "Eliminando contenedores previos..."
docker rm -f webapi-__PROJECT_SLUG__1 webapi-__PROJECT_SLUG__2 webapi-__PROJECT_SLUG__3 webapi-__PROJECT_SLUG__4 || true

# 4. Levantar nuevas instancias
echo "Levantando contenedores..."
docker run -d -e TZ=$TZ -p __DOCKER_PORT_1__:8080 --name webapi-__PROJECT_SLUG__1 $IMAGE_NAME
docker run -d -e TZ=$TZ -p __DOCKER_PORT_2__:8080 --name webapi-__PROJECT_SLUG__2 $IMAGE_NAME
docker run -d -e TZ=$TZ -p __DOCKER_PORT_3__:8080 --name webapi-__PROJECT_SLUG__3 $IMAGE_NAME
docker run -d -e TZ=$TZ -p __DOCKER_PORT_4__:8080 --name webapi-__PROJECT_SLUG__4 $IMAGE_NAME

echo "====================================="
echo "Deploy finalizado correctamente"
echo "====================================="
'@ | Set-Content "src/Presentation/Api/deploy.sh"

$deployScriptContent = Get-Content -Raw "src/Presentation/Api/deploy.sh"
$deployScriptContent = $deployScriptContent.Replace("__PROJECT_DIR__", $projectDirName).Replace("__PROJECT_NAME__", $ProjectName).Replace("__PROJECT_SLUG__", $projectSlug).Replace("__DOCKER_PORT_1__", "$DockerPort1").Replace("__DOCKER_PORT_2__", "$DockerPort2").Replace("__DOCKER_PORT_3__", "$DockerPort3").Replace("__DOCKER_PORT_4__", "$DockerPort4")
$deployScriptContent | Set-Content "src/Presentation/Api/deploy.sh"

# =========================
# CLEAN ARCHITECTURE DOC
# =========================
Write-Host "Writing documentation/ArchitectureGuide.md..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "documentation" -Force | Out-Null
@'

# Guía de arquitectura — ASP.NET Core Web API

Esta plantilla combina dos ideas: **Clean Architecture** (Robert C. Martin,
"Uncle Bob") y **Vertical Slice Architecture** (Jimmy Bogard).

- **Clean Architecture** organiza el código en capas concéntricas para que
  el dominio y la lógica de aplicación no dependan de frameworks, UI,
  base de datos o agentes externos.
- **Vertical Slice Architecture** organiza el código por **features**
  (casos de uso) en lugar de por tipo de archivo. Cada feature agrupa
  todo lo necesario: modelos, reglas, validaciones, repositorios,
  controladores y tests.

> **Regla mnemotécnica:** primero capas (Clean), después rebanadas
> verticales (Vertical Slice).

---

## 1. ¿Qué problema resuelve?

Sin una guía, las APIs .NET suelen terminar con:

- Lógica de negocio dentro de los controladores.
- `DbContext` o `SqlConnection` esparcido por toda la aplicación.
- Carpetas enormes de `Services`, `Models`, `Controllers`, etc.,
  desconectadas.
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
│  Presentation (UI / API)                                │
│  Controllers, Minimal APIs, middlewares, swagger...     │  ← capa externa
├─────────────────────────────────────────────────────────┤
│  Infrastructure (adaptadores)                           │
│  EF Core, repositorios, APIs externas, colas...         │  ← detalles técnicos
├─────────────────────────────────────────────────────────┤
│  Application (casos de uso)                             │
│  Commands, queries, handlers, validaciones, DTOs...     │  ← orquestación
├─────────────────────────────────────────────────────────┤
│  Domain (reglas de negocio)                             │
│  Entidades, value objects, interfaces de puertos...     │  ← centro
└─────────────────────────────────────────────────────────┘
```

> **Regla:** las flechas de dependencia apuntan hacia abajo. La capa de
> arriba puede conocer a la de abajo, pero nunca al revés.

### 2.1 Domain — el centro

Contiene las reglas de negocio puras. No conoce ASP.NET Core, EF Core,
HTTP, JSON, etc.

- `Entities/`: objetos con identidad (`Order`, `User`).
- `ValueObjects/`: objetos inmutables (`Email`, `Money`).
- `Enums/`: enumeraciones de negocio.
- `Interfaces/`: **puertos** que expresan lo que el dominio necesita,
  p. ej. `IOrderRepository`, `IEmailSender`.

**Regla:** si tienes que importar `Microsoft.EntityFrameworkCore` aquí,
algo está mal.

### 2.2 Application — los casos de uso

Orquesta el dominio para resolver una necesidad concreta del usuario.

- `Commands/`: comandos que mutan estado (`CreateOrderCommand`).
- `Queries/`: consultas que leen estado (`GetOrderByIdQuery`).
- `Models/`: DTOs y modelos de transporte entre capas.
- `Validators/`: reglas de validación de entrada con FluentValidation.
- `Interfaces/`: puertos que la aplicación necesita (`IUnitOfWork`).

Un handler no sabe que existe `DbContext`; solo conoce interfaces.

### 2.3 Infrastructure — los adaptadores

Implementa los puertos de Domain y Application.

- `DataBase/`: EF Core, repositorios, migraciones, opciones.
- `Adapters/`: APIs externas, colas de mensajes, servicios de correo, etc.

Es la única capa que conoce conexiones de base de datos, ORM y APIs
externas.

### 2.4 Presentation — la entrega

Punto de entrada de la API.

- `Api/`: host ASP.NET Core, middlewares, configuraciones, Program.cs.
- `Controllers/`: controladores que exponen endpoints HTTP.
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

Ejemplo: crear un pedido necesita persistirlo en base de datos.

1. `Domain/Interfaces/Orders/IOrderRepository.cs` define el puerto.
2. `Infrastructure/DataBase/Orders/OrderRepository.cs` implementa el puerto.
3. `Application/Commands/Orders/CreateOrder/CreateOrderHandler.cs` depende
   de `IOrderRepository`.
4. `Presentation/IoC/DependencyContainer.cs` registra la implementación.
5. `Presentation/Controllers/Orders/OrdersController.cs` expone el endpoint.

La interfaz pertenece a la capa interna; la implementación, a la externa.
Así las dependencias apuntan hacia adentro, aunque el flujo de control
vaya hacia la base de datos.

---

## 4. Organización por features (Vertical Slice)

Además de las capas, el código se organiza por **features**. Cada feature
es un caso de uso completo que agrupa todos sus archivos.

No hay una carpeta `Features` a nivel raíz. En su lugar, cada feature usa
subcarpetas con el mismo nombre dentro de cada capa.

### Ejemplo: CreateOrder

```
src
├── Domain
│   ├── Entities/Orders/
│   │   └── Order.cs
│   └── Interfaces/Orders/
│       └── IOrderRepository.cs
├── Application
│   ├── Commands/Orders/CreateOrder/
│   │   ├── CreateOrderCommand.cs
│   │   ├── CreateOrderHandler.cs
│   │   └── CreateOrderResult.cs
│   ├── Queries/Orders/GetOrderById/
│   │   ├── GetOrderByIdQuery.cs
│   │   └── GetOrderByIdHandler.cs
│   ├── Models/Orders/
│   │   └── OrderDto.cs
│   └── Validators/Orders/
│       └── CreateOrderValidator.cs
├── Infrastructure
│   └── DataBase/Orders/
│       └── OrderRepository.cs
└── Presentation
    └── Controllers/Orders/
        └── OrdersController.cs

tests/UnitTests/Orders/CreateOrder
├── CreateOrderHandlerTests.cs
└── CreateOrderValidatorTests.cs
```

**Regla de oro:** si necesitas buscar por toda la solución para encontrar
los archivos de una feature, la organización está mal.

---

## 5. Estructura de carpetas de esta plantilla

```
/scripts-ps
  new-clean-arch-api.ps1             ← punto de entrada

/{ProjectName}
  /src
    /Presentation
      /Api                             ASP.NET Core Web API host
        /Configurations
        /Middleware
        /Properties
      /Controllers                     Adaptadores HTTP
      /IoC                             Composición de dependencias
    /Application
      /Commands                        Comandos (write side)
      /Queries                         Consultas (read side)
      /Models                          DTOs
      /Validators                      Reglas de validación
    /Domain
      /Entities
      /ValueObjects
      /Enums
      /Interfaces
    /Infrastructure
      /DataBase                        Persistencia (EF Core, repositorios)
        /Options
  /tests
    /UnitTests
  /documentation
    ArchitectureGuide.md
```

Referencias entre proyectos:

| Proyecto        | Referencia a                       |
|-----------------|------------------------------------|
| Domain          | *(ninguna)*                        |
| Application     | Domain                             |
| Infrastructure  | Domain                             |
| Controllers     | Application                        |
| IoC             | Application, Infrastructure        |
| Api             | Controllers, IoC                   |
| UnitTests       | Domain, Application, Validators    |

---

## 6. Flujo de una petición HTTP

```
Cliente HTTP
   │
   ▼
Presentation/Api                (routing, middlewares, swagger)
   │
   ▼
Presentation/Controllers        (endpoint que expone el caso de uso)
   │
   ▼
Application/Commands o Queries  (handler del caso de uso)
   │
   ▼
Application/Validators          (valida entrada)
   │
   ▼
Domain/Interfaces               (puerto)
   │
   ▼
Infrastructure/DataBase         (EF Core, repositorios)
   │
   ▼
Domain/Entities                 (reglas de negocio)
```

Reglas prácticas:

- Los **Controllers** no llaman directamente a `DataBase`; solo invocan
  un `Command` o `Query`.
- Los **Commands** mutan estado (`Create`, `Update`, `Delete`) y
  devuelven el resultado mínimo necesario.
- Los **Queries** solo leen; nunca mutan estado.
- Los **Validators** no acceden a la base de datos.
- **Infrastructure** es el único lugar que habla con la BD, APIs externas,
  colas o caché.
- El flujo de retorno mapea entidades a DTOs (`Application/Models`) antes
  de salir por el Controller.

---

## 7. ¿Cómo añadir una nueva feature?

Sigue estos pasos para mantener el orden de capas y Vertical Slice:

1. **Domain:** define entidades, value objects e interfaces de puertos.
   - `Domain/Interfaces/{Feature}/I{Feature}Repository.cs`
   - `Domain/Entities/{Feature}/{Entity}.cs`

2. **Application:** crea el comando/consulta, handler, validator y DTOs.
   - `Application/Commands/{Feature}/{Action}/{Action}Command.cs`
   - `Application/Commands/{Feature}/{Action}/{Action}Handler.cs`
   - `Application/Commands/{Feature}/{Action}/{Action}Result.cs`
   - `Application/Validators/{Feature}/{Action}Validator.cs`
   - `Application/Models/{Feature}/{Entity}Dto.cs`

3. **Infrastructure:** implementa el puerto.
   - `Infrastructure/DataBase/{Feature}/{Entity}Repository.cs`

4. **Presentation:** crea el endpoint.
   - `Presentation/Controllers/{Feature}/{Feature}sController.cs`

5. **IoC:** registra la implementación si la inyección automática no la
   encuentra.

6. **Tests:** prueba el handler y el validator sin levantar la API ni la
   base de datos real.

> **Tip:** si una feature es muy pequeña, puedes agruparla en una sola
> carpeta por capa (`Auth/`) en lugar de crear una carpeta por acción.

---

## 8. Antipatrones a evitar

- ❌ Lógica de negocio en controladores o endpoints.
- ❌ Usar `DbContext`, `SqlConnection` o `HttpClient` dentro de handlers.
- ❌ Definir interfaces de repositorios en Infrastructure.
- ❌ Exponer entidades de dominio directamente como respuesta HTTP.
- ❌ Crear carpetas genéricas grandes como `Services/`, `Models/`,
  `Helpers/` fuera de una feature.
- ❌ Repositorios genéricos (`IRepository<T>`): cada agregado expone su
  propio puerto (`IOrderRepository`) e implementación (`OrderRepository`).
- ❌ Clases concretas sin interfaz (excepto validadores): cada servicio,
  repositorio o adaptador debe declarar su interfaz en la capa interna.

---

## 9. Beneficios de esta combinación

- **Cambios localizados:** una feature vive junta; tocarla no rompe otras.
- **Testabilidad:** Domain y Application se prueban sin infraestructura.
- **Sustituibilidad:** cambiar EF Core por Dapper, SQL Server por Postgres,
  o REST por gRPC es un cambio en una capa externa.
- **Escalabilidad cognitiva:** un desarrollador solo necesita entender la
  feature que está tocando.

---

## 10. Lecturas recomendadas

- Robert C. Martin — *Clean Architecture* (2017).
- Jimmy Bogard — *Vertical Slice Architecture*.
- Alistair Cockburn — *Hexagonal Architecture* (Ports & Adapters).
- Jeffrey Palermo — *Onion Architecture*.
- Vaughn Vernon — *Implementing Domain-Driven Design*.
- Microsoft — *ASP.NET Core documentation*.
```
'@ | Set-Content "documentation/ArchitectureGuide.md"

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
    foreach ($docPath in @('documentation/ArchitectureGuide.md')) {
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

Write-Host "Clean Architecture solution created successfully!"
Write-Host "Powered by David Vazquez Palestino" -ForegroundColor DarkGray