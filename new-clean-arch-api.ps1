# =========================================================================
#  new-clean-arch-api.ps1
#  Powered by David Vázquez Palestino
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
dotnet new web -n "$ProjectName.Api" -o "src/Presentation/Api"

# Application
dotnet new classlib -n "$ProjectName.UseCases" -o "src/Application/UseCases"

# Application sub-projects (separate projects)
dotnet new classlib -n "$ProjectName.Commands" -o "src/Application/Commands"
dotnet new classlib -n "$ProjectName.Models" -o "src/Application/Models"
dotnet new classlib -n "$ProjectName.Queries" -o "src/Application/Queries"
dotnet new classlib -n "$ProjectName.Validators" -o "src/Application/Validators"
dotnet new classlib -n "$ProjectName.Controllers" -o "src/Infrastructure/Controllers"

# IoC Project at same level as Application
dotnet new classlib -n "$ProjectName.IoC" -o "src/Presentation/IoC"

# Domain
dotnet new classlib -n "$ProjectName.Domain" -o "src/Domain"

# Infrastructure
dotnet new classlib -n "$ProjectName.DataSource" -o "src/Infrastructure/DataSource"

# Tests (xUnit.net v3)
# Asegurar que la plantilla xunit3 esté disponible (paquete xunit.v3.templates)
$templateList = dotnet new list xunit3 2>&1 | Out-String
if ($templateList -notmatch "(?m)^\s*xunit3\b") {
    Write-Host "Instalando plantillas de xUnit.net v3 (xunit.v3.templates)..."
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

# Remove default Class1.cs files
Remove-Item "src/Application/UseCases/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Application/Commands/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Application/Models/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Application/Queries/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Infrastructure/Controllers/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Presentation/IoC/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Domain/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Application/Validators/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Infrastructure/DataSource/Class1.cs" -Force -ErrorAction SilentlyContinue
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
dotnet sln add src/Application/UseCases
dotnet sln add src/Application/Commands
dotnet sln add src/Application/Models
dotnet sln add src/Application/Queries
dotnet sln add src/Application/Validators
dotnet sln add src/Infrastructure/Controllers
dotnet sln add src/Presentation/IoC
dotnet sln add src/Domain
dotnet sln add src/Infrastructure/DataSource
dotnet sln add tests/UnitTests

# =========================
# PROJECT REFERENCES
# =========================

# Application sub-projects depend on Domain
dotnet add src/Application/UseCases reference src/Domain
dotnet add src/Application/Commands reference src/Domain
dotnet add src/Application/Models reference src/Domain
dotnet add src/Application/Queries reference src/Domain
dotnet add src/Application/Validators reference src/Domain

# Controllers depend on Application layer projects
dotnet add src/Infrastructure/Controllers reference src/Domain
dotnet add src/Infrastructure/Controllers reference src/Application/Commands
dotnet add src/Infrastructure/Controllers reference src/Application/Queries
dotnet add src/Infrastructure/Controllers reference src/Application/Models
# IoC depends on all Application projects + Infrastructure + Domain
dotnet add src/Presentation/IoC reference src/Application/UseCases
dotnet add src/Presentation/IoC reference src/Application/Commands
dotnet add src/Presentation/IoC reference src/Application/Models
dotnet add src/Presentation/IoC reference src/Application/Queries
dotnet add src/Presentation/IoC reference src/Application/Validators
dotnet add src/Presentation/IoC reference src/Infrastructure/Controllers
dotnet add src/Presentation/IoC reference src/Infrastructure/DataSource
dotnet add src/Presentation/IoC reference src/Domain

# Infrastructure depends only on Domain (implements interfaces defined there)
dotnet add src/Infrastructure/DataSource reference src/Domain

# API depends on IoC
dotnet add src/Presentation/Api reference src/Presentation/IoC

# Tests
dotnet add tests/UnitTests reference src/Application/UseCases
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

dotnet add src/Infrastructure/Controllers package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Infrastructure/Controllers package DependencyInjection.ReflectionExtensions

# Controllers needs ASP.NET Core framework reference (ControllerBase, [ApiController], etc.)
$controllersCsproj = "src/Infrastructure/Controllers/$ProjectName.Controllers.csproj"
[xml]$controllersXml = Get-Content $controllersCsproj
if (-not ($controllersXml.Project.ItemGroup | Where-Object { $_.FrameworkReference.Include -eq "Microsoft.AspNetCore.App" })) {
    $itemGroup = $controllersXml.CreateElement("ItemGroup")
    $frameworkRef = $controllersXml.CreateElement("FrameworkReference")
    $frameworkRef.SetAttribute("Include", "Microsoft.AspNetCore.App")
    $itemGroup.AppendChild($frameworkRef) | Out-Null
    $controllersXml.Project.AppendChild($itemGroup) | Out-Null
    $controllersXml.Save((Resolve-Path $controllersCsproj))
}

# Application
dotnet add src/Application/UseCases package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Application/UseCases package DependencyInjection.ReflectionExtensions

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
dotnet add src/Infrastructure/DataSource package Microsoft.EntityFrameworkCore
dotnet add src/Infrastructure/DataSource package Microsoft.EntityFrameworkCore.SqlServer
dotnet add src/Infrastructure/DataSource package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Infrastructure/DataSource package DependencyInjection.ReflectionExtensions

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
New-Item -ItemType Directory -Path "src/Domain/Options"
New-Item -ItemType Directory -Path "src/Infrastructure/DataSource/Options" -Force

# Keep domain folders visible in Visual Studio Solution Explorer
"" | Set-Content "src/Domain/Entities/.gitkeep"
"" | Set-Content "src/Domain/ValueObjects/.gitkeep"
"" | Set-Content "src/Domain/Enums/.gitkeep"
"" | Set-Content "src/Domain/Interfaces/.gitkeep"
"" | Set-Content "src/Domain/Options/.gitkeep"

# API structure

New-Item -ItemType Directory -Path "src/Presentation/Api/Middleware" -Force
New-Item -ItemType Directory -Path "src/Presentation/Api/Configurations" -Force
New-Item -ItemType Directory -Path "src/Presentation/Api/Properties" -Force

# launchSettings.json (puertos determinísticos por proyecto para evitar choques)
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
        "SecurityKey": "1234567890ABCDEFGHIJKLMNÑOPQRSTU",
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
        "SecurityKey": "1234567890ABCDEFGHIJKLMNÑOPQRSTU",
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

# DependencyContainer class in Application Project
@"

namespace $ProjectName.UseCases
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
"@ | Set-Content "src/Application/UseCases/DependencyContainer.cs"

# GlobalUsings Application
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Application/UseCases/GlobalUsings.cs"

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

namespace $ProjectName.DataSource
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
"@ | Set-Content "src/Infrastructure/DataSource/DependencyContainer.cs"

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

            services.AddUseCases()
                        .AddCommands()
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

"@ | Set-Content "src/Infrastructure/DataSource/GlobalUsings.cs"

# GlobalUsings class in IoC Project
@"
global using $ProjectName.UseCases;
global using $ProjectName.Commands;
global using $ProjectName.DataSource;
global using $ProjectName.Queries;
global using $ProjectName.Validators;
global using $ProjectName.Domain.Options;
global using $ProjectName.DataSource.Options;
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
"@ | Set-Content "src/Infrastructure/Controllers/GlobalUsings.cs"

# GlobalUsings Domain
@"

"@ | Set-Content "src/Domain/GlobalUsings.cs"

# DataBaseOptions class in Infrastructure
@"

namespace $ProjectName.DataSource.Options
{
    public class DataBaseOptions
    {
        public const string SectionKey = nameof(DataBaseOptions);
        public string DefaultConnection { get; set; } 
    }
}
"@ | Set-Content "src/Infrastructure/DataSource/Options/DataBaseOptions.cs"

# EnvironmentOptions class in Domain
@"

namespace $ProjectName.Domain.Options
{
    public class EnvironmentOptions
    {
        public const string SectionKey = nameof(EnvironmentOptions);
        public string EnvironmentName { get; set; } 
    }
}
"@ | Set-Content "src/Domain/Options/EnvironmentOptions.cs"

# GlobalUsings Api
@"
global using Microsoft.AspNetCore.Builder;
global using Microsoft.AspNetCore.Http;
global using Microsoft.Extensions.DependencyInjection;
global using System.Text.Json.Serialization;
global using $ProjectName.IoC;
global using Microsoft.OpenApi;
global using Microsoft.AspNetCore.Mvc;
global using $ProjectName.Api.Configurations;
global using $ProjectName.Api.Middleware;
global using $ProjectName.Domain.Options;

"@ | Set-Content "src/Presentation/Api/GlobalUsings.cs"

# GlobalUsings Tests
@"
global using FluentAssertions;
global using Xunit;
"@ | Set-Content "tests/UnitTests/GlobalUsings.cs"

# API Configuration files
@"

namespace $ProjectName.Api.Configurations
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

namespace $ProjectName.Api.Configurations
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

namespace $ProjectName.Api.Middleware
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
                // Configurar información base de la respuesta
                HttpResponse response = context.Response;
                // Si la respuesta ya comenzó, no es seguro modificar headers/body
                if (response.HasStarted)
                {
                    logger.Error(exception, "La respuesta ya comenzó. El error no se devuelve al cliente. {TraceId}", context.TraceIdentifier);
                    throw; // Permitir que el servidor termine la conexión según corresponda
                }

                response.ContentType = "application/json";

                // Mapear tipos de excepciones conocidas a códigos de estado apropiados
                int statusCode = exception switch
                {
                    UnauthorizedAccessException => StatusCodes.Status401Unauthorized,
                    KeyNotFoundException => StatusCodes.Status404NotFound,
                    ArgumentException => StatusCodes.Status400BadRequest,
                    _ => StatusCodes.Status500InternalServerError
                };

                // Evitar exponer detalles sensibles/internos en respuestas al cliente
                // Mantener la información detallada solo en los logs
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
                // Registrar la excepción completa con contexto estructurado; NO incluir configuración sensible en la respuesta
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
COPY src/Presentation/Api/$ProjectName.Api.csproj src/Presentation/Api/
COPY src/Application/UseCases/$ProjectName.UseCases.csproj src/Application/UseCases/
COPY src/Application/Commands/$ProjectName.Commands.csproj src/Application/Commands/
COPY src/Infrastructure/Controllers/$ProjectName.Controllers.csproj src/Infrastructure/Controllers/
COPY src/Domain/$ProjectName.Domain.csproj src/Domain/
COPY src/Infrastructure/DataSource/$ProjectName.DataSource.csproj src/Infrastructure/DataSource/
COPY src/Presentation/IoC/$ProjectName.IoC.csproj src/Presentation/IoC/
COPY src/Application/Models/$ProjectName.Models.csproj src/Application/Models/
COPY src/Application/Queries/$ProjectName.Queries.csproj src/Application/Queries/
COPY src/Application/Validators/$ProjectName.Validators.csproj src/Application/Validators/
RUN dotnet restore src/Presentation/Api/$ProjectName.Api.csproj
COPY . .
WORKDIR /src/src/Presentation/Api
RUN dotnet build $ProjectName.Api.csproj -c `${Configuration} -o /app/build

FROM build AS publish
ARG Configuration=Release
RUN dotnet publish $ProjectName.Api.csproj -c `${Configuration} -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "$ProjectName.Api.dll"]

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
# CLEAN ARCHITECTURE DOC (Tío Bob)
# =========================
Write-Host "Writing documentation/Architecture.md..."
New-Item -ItemType Directory -Path "documentation" -Force | Out-Null
@'
> Solución generada con el script `new-clean-arch-api.ps1` desde PowerShell:
>
> ```powershell
> .\new-clean-arch-api.ps1 -ProjectName <NombreProyecto>
> ```

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
    /Api                                ASP.NET Core Minimal API
      /Configurations                     Configuración de servicios y middleware
      /Middleware                         Middlewares (ErrorHandler, etc.)
      /Properties                         launchSettings.json
    /IoC                                Composición raíz (Dependency Injection)
  /Application
    /UseCases                       <-- Casos de uso (orquestación)
    /Commands                       <-- Comandos (write side)
    /Queries                        <-- Consultas (read side)
    /Models                         <-- DTOs / modelos de aplicación
    /Validators                     <-- Reglas de validación (FluentValidation)
    /Interfaces                     <-- Interfaces de aplicación (puertos)
  /Domain
    /Entities                     <-- Entidades de dominio
    /ValueObjects                 <-- Objetos de valor
    /Enums
    /Options                          Options tipados de dominio
    /Interfaces                   <-- Interfaces de dominio (puertos)
  /Infrastructure
    /Controllers                    <-- Adaptadores HTTP (ASP.NET Controllers)
    /DataSource                     <-- Persistencia (EF Core, repositorios)
      /Options                          Cadenas de conexión, opciones de BD
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

### 4.1 Flujo de una petición

En esta API una petición HTTP viaja de afuera hacia adentro y regresa:

```
Cliente HTTP
   │
   ▼
Presentation/Api                (routing, middlewares, ProblemDetails)
   │
   ▼
Infrastructure/Controllers      (endpoint que expone el caso de uso)
   │
   ▼
Application/UseCases            (orquestador del caso de uso)
   │
   ▼
Application/Commands  ─┐        (mutan estado — write side)
Application/Queries   ─┤        (leen estado — read side)
                       │
                       ▼
Infrastructure/DataSource       (EF Core, repos, servicios externos)
   │
   ▼
Domain                          (entidades, VOs, reglas invariantes)
```

Reglas prácticas de esta ruta:

- **Controllers** no llaman directamente a `DataSource`; sólo invocan un
  `UseCase` (o directamente un `Command`/`Query` si no hay orquestación).
- **UseCases** orquestan uno o más `Command`/`Query` y aplican políticas
  transversales (autorización, transacción, telemetría, logging).
- **Commands** cambian estado (`Create`, `Update`, `Delete`) y devuelven
  el resultado mínimo necesario.
- **Queries** sólo leen; nunca mutan estado.
- **DataSource / Adapters externos** son los únicos que hablan con la BD,
  APIs externas, colas o caché.
- El flujo de retorno recorre la ruta en sentido inverso, mapeando a DTOs
  (`Application/Models`) antes de salir por el `Controller`.

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

---

## 8. Features (organización del día a día)

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
│       └── IOrderRepository.cs         ← puerto
│
├── Application
│   ├── Commands/Orders/CreateOrder/
│   │   ├── CreateOrderCommand.cs       ← input
│   │   ├── CreateOrderHandler.cs       ← lógica
│   │   └── CreateOrderResult.cs        ← output
│   ├── Validators/Orders/
│   │   └── CreateOrderValidator.cs
│   └── Models/Orders/
│       └── OrderDto.cs
│
├── Infrastructure
│   ├── Controllers/Orders/
│   │   └── OrdersController.cs         ← endpoint
│   └── DataSource/Orders/
│       └── OrderRepository.cs          ← implementa el puerto
│
└── tests/UnitTests/Orders/CreateOrder/
    ├── CreateOrderHandlerTests.cs
    └── CreateOrderValidatorTests.cs


FLUJO DE LA FEATURE (una petición HTTP)
─────────────────────────────────────────────────────────────

   HTTP POST /api/orders
          │
          ▼
   OrdersController        (Infrastructure/Controllers/Orders)
          │
          ▼
   CreateOrderHandler      (Application/Commands/Orders/CreateOrder)
          │      ▲
          │      │ valida
          │  CreateOrderValidator
          ▼
   IOrderRepository        (Domain/Interfaces/Orders)  ── puerto
          │
          ▼
   OrderRepository         (Infrastructure/DataSource/Orders)
          │
          ▼
   Order                   (Domain/Entities/Orders)


REGLA DE ORO
─────────────────────────────────────────────────────────────
  Toda pieza de una feature vive en carpetas con el MISMO nombre
  (aquí: "Orders" + "CreateOrder"). Si tienes que buscar por
  toda la solución para encontrarla, la feature está mal ubicada.
```
'@ | Set-Variable -Name ArchitectureMd
[System.IO.File]::WriteAllText(
    (Join-Path (Get-Location) 'documentation/Architecture.md'),
    $ArchitectureMd,
    (New-Object System.Text.UTF8Encoding($true))
)

# =========================
# BEST PRACTICES DOC (C#)
# =========================
Write-Host "Writing documentation/BuenasPracticasCSharp.md..."
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

> Las convenciones de nombres para base de datos se tratan en `BuenasPracticasBaseDeDatos.md`.

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

## 7. Comentarios

- Comentarios **útiles**, no redundantes. El buen código se autoexplica.
- Usar `//` o `///` (nunca `/* */`).
- Documentar lógica **compleja o no obvia** — no lo trivial.
- Usar `// TODO:` para tareas pendientes rastreables por VS.
- Habilitar **generación de XML docs** (`GenerateDocumentationFile` en el `.csproj`) para APIs públicas.
- Revisar ortografía y gramática de los comentarios.

---

## 8. Versionado y Ciclo de Vida

| Fase | Nomenclatura | Descripción |
|------|--------------|-------------|
| Alpha | `0.0.x` | En desarrollo, no operativo |
| Beta | `b1.0` | Funcionalidades completas, en testing interno |
| Release Candidate | `rc1.0` | Pasó todos los tests, en pre-producción |
| Release | `1.0` | Producto final en producción |
| Patch | `1.1` | Correcciones o mejoras menores en producción |

Seguir **SemVer** (`MAJOR.MINOR.PATCH`) para librerías públicas.

---

## 9. Revisiones de Código (Sprint / Retrospectiva)

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

# =========================
# BEST PRACTICES DOC (Base de Datos)
# =========================
Write-Host "Writing documentation/BuenasPracticasBaseDeDatos.md..."
@'
# Buenas Prácticas de Base de Datos

> Recopilación de recomendaciones extraídas del documento
> *"Estándares de Codificación en C# y Buenas Prácticas de Programación"* (canaldenegocio.com — Alberto Fernández),
> complementadas con prácticas actuales para .NET / SQL Server.

---

## 1. Convenciones de Nombres

### Objetos de base de datos
| Objeto | Prefijo | Ejemplo |
|--------|---------|---------|
| Tabla | *(sin prefijo)* | `Customers` |
| Vista | `VW_` | `VW_MonthlySales` |
| Stored Procedure | `SP_` | `SP_GetActiveCustomers` |
| Función | `FN_` | `FN_CalculateAge` |
| Trigger | `TR_` | `TR_Customers_AfterUpdate` |
| Índice | `IDX_` / `IX_` | `IDX_Customers_Email` |
| Foreign Key | `FK_` | `FK_Orders_Customer` |
| Primary Key | `PK_` | `PK_Customers` |

> **NUNCA usar `sp_` (minúsculas) como prefijo de Stored Procedures.**
> SQL Server reconoce `sp_` como *System Stored Procedure* y lo buscará primero en la BBDD `master`, degradando el rendimiento. Usar `SP_` (mayúsculas) es seguro.

### Convenciones para EF Core (migraciones limpias)
- **Tablas en plural**, coincidiendo con el nombre del `DbSet<T>` (`Customers`, `Orders`, `Users`). Es lo que EF Core genera **por defecto** y produce migraciones elegantes sin sobrescribir nombres.
- **PascalCase** en tablas y columnas (`CreatedAt`, no `created_at` ni `CREATED_AT`).
- Evitar `[Table("...")]` y `ToTable("...")` salvo que exista un motivo fuerte (integración con schema existente, nombre reservado, cambio de esquema). Cuanta menos configuración manual, más limpio el modelo.
- Nombrar el `DbSet` en plural: `public DbSet<Customer> Customers { get; set; }`.
- Usar el schema por defecto (`dbo`) salvo agrupación lógica real (`auth.Users`, `billing.Invoices`).

### Nombres descriptivos
- Usar nombres completos y en el mismo idioma en toda la base (preferentemente inglés por alineación con el código C#).
- Evitar abreviaturas crípticas (`CLI`, `FACCLI`).
- Tablas en **plural** de forma consistente (`Customers`, `Orders`) — alineado con EF Core.

### Compatibilidad con sistemas legacy (COBOL, AS/400, RPG…)
Cuando haya que puentear tablas con nombres históricos, usar **Pair Name** — nombre moderno + guion bajo + nombre original:

```
Customers_CLI
CustomerInvoices_FACCLI
```

Esto facilita el rastreo bidireccional durante migraciones o integraciones sin arrastrar prefijos como `tbl_` al modelo nuevo.

---

## 2. Diseño de Tablas

### Columnas de auditoría (recomendadas en toda tabla transaccional)
| Columna | Tipo | Propósito |
|---------|------|-----------|
| `CreatedAt` | `DATETIME2` | Fecha de creación del registro |
| `CreatedBy` | `NVARCHAR` / `INT` | Usuario o proceso que lo creó |
| `ModifiedAt` | `DATETIME2` | Última modificación |
| `ModifiedBy` | `NVARCHAR` / `INT` | Usuario o proceso que modificó |
| `IsDeleted` | `BIT` | Baja lógica |
| `DeletedAt` | `DATETIME2` NULL | Fecha de baja lógica |
| `Notes` | `NVARCHAR(MAX)` NULL | "Post-it" del DBA — observaciones libres |

### Baja lógica antes que física
- **No eliminar físicamente** los registros de primeras. Marcarlos con `IsDeleted = 1`.
- Programar un proceso periódico (**Data Garbage Collection**) que:
  - Depura definitivamente registros antiguos, o
  - Los mueve a tablas históricas (`CustomersHistory`, `OrdersHistory`).
- Interceptar `DELETE` con **triggers** que conviertan la operación en un `UPDATE` de `IsDeleted`, o restringir permisos de `DELETE` a nivel de BBDD.
- En EF Core, aplicar un **query filter global** para excluir borrados lógicos:
  ```csharp
  modelBuilder.Entity<Customer>().HasQueryFilter(c => !c.IsDeleted);
  ```

### Claves e integridad
- **Toda tabla debe tener clave primaria** — preferentemente artificial (`INT IDENTITY` o `UNIQUEIDENTIFIER`).
- Definir **claves foráneas explícitas** con `ON DELETE`/`ON UPDATE` claros.
- Añadir `CHECK CONSTRAINTS` para reglas de dominio (rangos, enumerados, formatos).
- Usar `NOT NULL` por defecto; permitir `NULL` solo cuando el negocio lo requiera.

### Tipos de datos
- Preferir tipos **específicos** al tamaño mínimo necesario:
  - `DATE` en lugar de `DATETIME` cuando no importa la hora.
  - `DATETIME2` en lugar de `DATETIME` (más precisión, mismo o menor tamaño).
  - `NVARCHAR(n)` con `n` acotado — evitar `NVARCHAR(MAX)` por defecto.
  - `DECIMAL(p,s)` para dinero — nunca `FLOAT` ni `REAL`.
- Evitar `TEXT`, `NTEXT`, `IMAGE` (deprecados) — usar `NVARCHAR(MAX)`, `VARBINARY(MAX)`.

---

## 3. Consultas y Rendimiento

### La lógica de datos, cerca del motor
- Las **consultas complejas** viven en **Stored Procedures** o **Vistas**, no en el código de la aplicación.
- Reglas de negocio de alto volumen de datos → **Stored Procedures**.
- Agregaciones y proyecciones repetidas → **Vistas** (o *Indexed Views*).
- Reservar la lógica en C# para reglas de dominio, no para transformaciones masivas.

### Índices
- Indexar columnas usadas en `WHERE`, `JOIN`, `ORDER BY`, `GROUP BY`.
- **No indexar todo** — cada índice tiene coste en escritura y almacenamiento.
- Revisar planes de ejecución (`SET SHOWPLAN_XML ON`, DMVs).
- Usar índices **filtrados** para subconjuntos frecuentes.
- Considerar índices **columnstore** en tablas de reporting/analítica.

### Consultas
- `SELECT` explícito de columnas — **nunca `SELECT *`** en producción.
- `WHERE` con condiciones **sargables** (evitar funciones sobre columnas indexadas).
- Paginar con `OFFSET ... FETCH NEXT` en lugar de traer todo y filtrar en cliente.
- Evitar cursores; preferir operaciones basadas en conjuntos.

---

## 4. Seguridad

### SQL Injection — línea roja
**NUNCA** concatenar strings para construir SQL:

```csharp
// PROHIBIDO — vulnerable a SQL Injection
string sql = "SELECT * FROM Customers WHERE Name = '" + name + "'";
command.CommandText = sql;
```

Siempre parametrizar:

```csharp
// ADO.NET con parámetros
command.CommandText = "SELECT * FROM Customers WHERE Name = @Name";
command.Parameters.Add("@Name", SqlDbType.NVarChar).Value = name;

// EF Core (parametriza automáticamente)
Customer customer = await ctx.Customers.FirstOrDefaultAsync(c => c.Name == name);

// Dapper (parametriza automáticamente)
Customer customer = await conn.QueryFirstOrDefaultAsync<Customer>(
    "SELECT * FROM Customers WHERE Name = @Name",
    new { Name = name });
```

### Principio de mínimo privilegio
- La aplicación se conecta con un usuario **sin permisos de DDL** (`CREATE`, `ALTER`, `DROP`).
- Otorgar únicamente los permisos necesarios (`SELECT`, `INSERT`, `UPDATE` sobre objetos específicos).
- Preferir acceso vía **Stored Procedures** y `GRANT EXECUTE` — evita permisos directos sobre tablas.
- Nunca usar `sa` ni cuentas administrativas desde la aplicación.

### Cadenas de conexión y secretos
- **Nunca** hardcodear connection strings ni credenciales.
- Almacenar en:
  - `appsettings.{Environment}.json` (excluido de git).
  - **Azure Key Vault**, AWS Secrets Manager, HashiCorp Vault.
  - User Secrets en desarrollo (`dotnet user-secrets`).
- Preferir **Managed Identity** o autenticación integrada frente a usuario/contraseña.
- Encriptar el canal (`Encrypt=True;TrustServerCertificate=False`).

---

## 5. Transacciones y ACID

Todo diseño transaccional debe respetar **ACID**:

| Propiedad | Descripción |
|-----------|-------------|
| **Atomicity** | La operación se ejecuta completa o no se ejecuta. Ante fallo, rollback total. |
| **Consistency** | Solo se completan operaciones que respetan reglas e integridad. |
| **Isolation** | Las transacciones concurrentes no se afectan entre sí. |
| **Durability** | Una vez confirmada, la operación persiste incluso ante fallo del sistema. |

### Recomendaciones prácticas
- Transacciones **cortas**: abrir, operar, cerrar. Nunca abrir una transacción y esperar input de usuario.
- Elegir el **nivel de aislamiento** adecuado (`READ COMMITTED`, `SNAPSHOT`, `SERIALIZABLE`) según el escenario.
- Usar `TransactionScope` o `IDbContextTransaction` (EF Core) para transacciones distribuidas o de múltiples repositorios.
- Manejar deadlocks con **retry policies** (por ejemplo, [Polly](https://www.pollydocs.org/)).

---

## 6. Acceso a Datos desde .NET

Orden de preferencia moderno:

1. **Entity Framework Core** — ORM estándar en .NET moderno. Excelente para CRUD, escenarios de dominio, migraciones.
2. **Dapper** — micro-ORM cuando el rendimiento y control fino de SQL son críticos.
3. **ADO.NET a pelo** — solo para casos muy específicos o interoperabilidad legacy.

### Reglas generales
- **Cerrar conexiones** siempre — usar `using` / `await using`.
- Capturar excepciones de BBDD en la capa de datos, **loguear** (comando, parámetros seguros — nunca datos sensibles, connection string sin credenciales) y **re-lanzar** con `throw;`.
- Nunca acceder a la BBDD desde la capa de UI/presentación — siempre a través de repositorios o servicios de aplicación.
- Preferir **async/await** (`ExecuteAsync`, `ToListAsync`, etc.) — libera hilos del thread pool.

### Migraciones
- Versionar el esquema con **EF Core Migrations**, **DbUp**, **Flyway** o **Liquibase**.
- Los cambios de esquema van en el mismo commit/PR que el código que los usa.
- Todo cambio de esquema debe ser **reversible** (`Down`).

---

## 7. Middleware y Estrategia Multi-BBDD

- Cuando existan múltiples motores de datos (SQL Server, Oracle, DB2, AS/400…), designar **una BBDD como middleware/canónica** y consolidar accesos a través de ella.
- **SQL Server** es un excelente middleware para el ecosistema .NET.
- Encapsular otras plataformas mediante:
  - **Linked Servers** o **PolyBase** (SQL Server).
  - Vistas materializadas sincronizadas periódicamente.
  - Procesos ETL / CDC (Change Data Capture).
- Para lógica que requiera máximo rendimiento y control, considerar **integración CLR** en SQL Server (funciones/procedimientos en .NET dentro del motor).

---

## 8. Anti-patrones a evitar

- **Cacheitis** — cachear todo por defecto. Cachear solo con métricas que lo justifiquen.
- **`SELECT *`** en producción.
- **N+1 queries** — ejecutar una consulta por cada iteración de un bucle. Usar `Include` (EF), `JOIN` o consultas por lotes.
- **Lógica de negocio en triggers** — difícil de depurar y mantener. Reservar triggers para auditoría o integridad estricta.
- **Concatenación de SQL** — SQL Injection asegurada.
- **DELETE físico** sin plan de retención.
- **Transacciones largas** que bloquean recursos.
- **Dependencia del orden de inserción** — usar claves y constraints, no supuestos.

---

## 9. Observabilidad

- Habilitar **logging de consultas lentas** (SQL Server: *Query Store*, DMVs, Extended Events).
- Monitorizar deadlocks, waits, tamaños de tabla e índice.
- Rastrear operaciones desde la aplicación con **OpenTelemetry** / Application Insights, correlacionando con el motor.
- Alertas sobre crecimiento anómalo de tablas, degradación de planes de ejecución.

---

## Referencias
- Documento original: *Estándares de Codificación en C# y Buenas Prácticas de Programación* — Alberto Fernández (canaldenegocio.com).
- [SQL Server — Best Practices (Microsoft Docs)](https://learn.microsoft.com/sql/sql-server/).
- [Entity Framework Core Documentation](https://learn.microsoft.com/ef/core/).
- [Dapper](https://github.com/DapperLib/Dapper).
- [OWASP SQL Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html).
'@ | Set-Variable -Name BestPracticesDbMd
[System.IO.File]::WriteAllText(
    (Join-Path (Get-Location) 'documentation/BuenasPracticasBaseDeDatos.md'),
    $BestPracticesDbMd,
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
    foreach ($docPath in @('documentation/Architecture.md', 'documentation/BuenasPracticasCSharp.md', 'documentation/BuenasPracticasBaseDeDatos.md')) {
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
Write-Host "Powered by David Vázquez Palestino" -ForegroundColor DarkGray