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
dotnet new web -n "$ProjectName.WebApi" -o "src/Presentation/Api"

# Application
dotnet new classlib -n "$ProjectName.UseCases" -o "src/Application/UseCases"

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
Remove-Item "src/Presentation/Controllers/Class1.cs" -Force -ErrorAction SilentlyContinue
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
dotnet sln add src/Presentation/Controllers
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
dotnet add src/Presentation/Controllers reference src/Domain
dotnet add src/Presentation/Controllers reference src/Application/Commands
dotnet add src/Presentation/Controllers reference src/Application/Queries
dotnet add src/Presentation/Controllers reference src/Application/Models
# IoC depends on all Application projects + Infrastructure + Domain
dotnet add src/Presentation/IoC reference src/Application/UseCases
dotnet add src/Presentation/IoC reference src/Application/Commands
dotnet add src/Presentation/IoC reference src/Application/Models
dotnet add src/Presentation/IoC reference src/Application/Queries
dotnet add src/Presentation/IoC reference src/Application/Validators
dotnet add src/Presentation/IoC reference src/Presentation/Controllers
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
"@ | Set-Content "src/Presentation/Controllers/GlobalUsings.cs"

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
global using $ProjectName.WebApi.Configurations;
global using $ProjectName.WebApi.Middleware;
global using $ProjectName.Domain.Options;

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
COPY src/Presentation/Api/$ProjectName.WebApi.csproj src/Presentation/Api/
COPY src/Application/UseCases/$ProjectName.UseCases.csproj src/Application/UseCases/
COPY src/Application/Commands/$ProjectName.Commands.csproj src/Application/Commands/
COPY src/Presentation/Controllers/$ProjectName.Controllers.csproj src/Presentation/Controllers/
COPY src/Domain/$ProjectName.Domain.csproj src/Domain/
COPY src/Infrastructure/DataSource/$ProjectName.DataSource.csproj src/Infrastructure/DataSource/
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
# CLEAN ARCHITECTURE DOC (Tío Bob)
# =========================
Write-Host "Writing documentation/ArchitectureGuide.md..."
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
    /Controllers                    <-- Adaptadores HTTP (ASP.NET Controllers)
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
Presentation/Controllers        (endpoint que expone el caso de uso)
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
├── Presentation
│   └── Controllers/Orders/
│       └── OrdersController.cs         ← endpoint
├── Infrastructure
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
   OrdersController        (Presentation/Controllers/Orders)
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
    (Join-Path (Get-Location) 'documentation/ArchitectureGuide.md'),
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
Write-Host "Powered by David Vázquez Palestino" -ForegroundColor DarkGray