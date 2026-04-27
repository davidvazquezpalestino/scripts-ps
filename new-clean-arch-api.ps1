param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName
)

Write-Host "Creating Clean Architecture solution: $ProjectName"

# Root
New-Item -ItemType Directory -Path $ProjectName
Set-Location $ProjectName

# Solution
dotnet new sln -n $ProjectName

# Folders
New-Item -ItemType Directory -Path "src"
New-Item -ItemType Directory -Path "tests"

# =========================
# CREATE PROJECTS
# =========================

# API
dotnet new web -n "$ProjectName.Api" -o "src/Api"

# Application
dotnet new classlib -n "$ProjectName.Application" -o "src/Application"

# Application sub-projects (separate projects)
dotnet new classlib -n "$ProjectName.Commands" -o "src/Commands"
dotnet new classlib -n "$ProjectName.Models" -o "src/Models"
dotnet new classlib -n "$ProjectName.Queries" -o "src/Queries"
dotnet new classlib -n "$ProjectName.Validators" -o "src/Validators"
dotnet new classlib -n "$ProjectName.Controllers" -o "src/Controllers"

# IoC Project at same level as Application
dotnet new classlib -n "$ProjectName.IoC" -o "src/IoC"

# Domain
dotnet new classlib -n "$ProjectName.Domain" -o "src/Domain"

# Infrastructure
dotnet new classlib -n "$ProjectName.Infrastructure" -o "src/Infrastructure"

# Tests
dotnet new xunit -n "$ProjectName.UnitTests" -o "tests/UnitTests"
dotnet new xunit -n "$ProjectName.IntegrationTests" -o "tests/IntegrationTests"

# Remove default Class1.cs files
Remove-Item "src/Application/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Commands/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Models/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Queries/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Controllers/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/IoC/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Domain/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Validators/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Infrastructure/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "tests/UnitTests/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "tests/IntegrationTests/Class1.cs" -Force -ErrorAction SilentlyContinue

# =========================
# ADD TO SOLUTION
# =========================

dotnet sln add src/Api
dotnet sln add src/Application
dotnet sln add src/Commands
dotnet sln add src/Models
dotnet sln add src/Queries
dotnet sln add src/Validators
dotnet sln add src/Controllers
dotnet sln add src/IoC
dotnet sln add src/Domain
dotnet sln add src/Infrastructure
dotnet sln add tests/UnitTests
dotnet sln add tests/IntegrationTests

# =========================
# PROJECT REFERENCES
# =========================

# Application sub-projects depend on Domain
dotnet add src/Commands reference src/Domain
dotnet add src/Models reference src/Domain
dotnet add src/Queries reference src/Domain
dotnet add src/Validators reference src/Domain

dotnet add src/Controllers reference src/Domain
# IoC depends on all Application projects + Infrastructure + Domain
dotnet add src/IoC reference src/Application
dotnet add src/IoC reference src/Commands
dotnet add src/IoC reference src/Models
dotnet add src/IoC reference src/Queries
dotnet add src/IoC reference src/Validators
dotnet add src/IoC reference src/Controllers
dotnet add src/IoC reference src/Infrastructure
dotnet add src/IoC reference src/Domain

# Infrastructure depends on Application + Domain
dotnet add src/Infrastructure reference src/Application
dotnet add src/Infrastructure reference src/Domain

# API depends on IoC
dotnet add src/Api reference src/IoC

# Tests
dotnet add tests/UnitTests reference src/Application
dotnet add tests/UnitTests reference src/Domain

dotnet add tests/IntegrationTests reference src/Api

# =========================
# ADD PACKAGES
# =========================

# Application sub-projects
dotnet add src/Commands package FluentValidation
dotnet add src/Commands package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Commands package DependencyInjection.ReflectionExtensions

dotnet add src/Models package FluentValidation
dotnet add src/Models package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Models package DependencyInjection.ReflectionExtensions

dotnet add src/Queries package FluentValidation
dotnet add src/Queries package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Queries package DependencyInjection.ReflectionExtensions

dotnet add src/Validators package FluentValidation
dotnet add src/Validators package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Validators package DependencyInjection.ReflectionExtensions

dotnet add src/Controllers package FluentValidation
dotnet add src/Controllers package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Controllers package DependencyInjection.ReflectionExtensions

# Application
dotnet add src/Application package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Application package DependencyInjection.ReflectionExtensions

# IoC
dotnet add src/IoC package Microsoft.Extensions.DependencyInjection
dotnet add src/IoC package Microsoft.EntityFrameworkCore
dotnet add src/IoC package Microsoft.EntityFrameworkCore.SqlServer
dotnet add src/IoC package FluentValidation
dotnet add src/IoC package DependencyInjection.ReflectionExtensions
dotnet add src/IoC package Serilog
dotnet add src/IoC package Serilog.Settings.Configuration
dotnet add src/IoC package CoreJsonWebToken
dotnet add src/IoC package DevKit.ExecutionEngine.Redis

# Infrastructure
dotnet add src/Infrastructure package Microsoft.EntityFrameworkCore
dotnet add src/Infrastructure package Microsoft.EntityFrameworkCore.SqlServer
dotnet add src/Infrastructure package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/Infrastructure package DependencyInjection.ReflectionExtensions

# API
dotnet add src/Api package Microsoft.EntityFrameworkCore.Design
dotnet add src/Api package Scalar.AspNetCore
dotnet add src/Api package Serilog
dotnet add src/Api package Serilog.Extensions.Hosting
dotnet add src/Api package Serilog.Sinks.Console
dotnet add src/Api package Swashbuckle.AspNetCore

# Tests
dotnet add tests/UnitTests package FluentAssertions
dotnet add tests/IntegrationTests package FluentAssertions
dotnet add tests/IntegrationTests package Microsoft.AspNetCore.Mvc.Testing

# =========================
# CREATE BASE FOLDERS
# =========================

# Domain structure
New-Item -ItemType Directory -Path "src/Domain/Entities"
New-Item -ItemType Directory -Path "src/Domain/ValueObjects"
New-Item -ItemType Directory -Path "src/Domain/Enums"
New-Item -ItemType Directory -Path "src/Domain/Interfaces"
New-Item -ItemType Directory -Path "src/Domain/Options"

# Keep domain folders visible in Visual Studio Solution Explorer
"" | Set-Content "src/Domain/Entities/.gitkeep"
"" | Set-Content "src/Domain/ValueObjects/.gitkeep"
"" | Set-Content "src/Domain/Enums/.gitkeep"
"" | Set-Content "src/Domain/Interfaces/.gitkeep"
"" | Set-Content "src/Domain/Options/.gitkeep"

# API structure

New-Item -ItemType Directory -Path "src/Api/Middleware" -Force
New-Item -ItemType Directory -Path "src/Api/Configurations" -Force
New-Item -ItemType Directory -Path "src/Api/Properties" -Force

# launchSettings.json
@"
{
  "profiles": {
    "$ProjectName.Api": {
      "commandName": "Project",
      "launchBrowser": true,
      "launchUrl": "swagger",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    }
  }
}
"@ | Set-Content "src/Api/Properties/launchSettings.json"

# appsettings.json
@"
{
    "EnvironmentOptions": {
        "EnvironmentName": "Production" /*Development, Staging, Production*/
    }
}
"@ | Set-Content "src/Api/appsettings.json"

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
"@ | Set-Content "src/Api/appsettings.Development.json"

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
"@ | Set-Content "src/Api/appsettings.Production.json"

# CREATE BASIC FILES
# =========================

# DependencyContainer class in Application Project
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

# GlobalUsings Application
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Application/GlobalUsings.cs"

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
"@ | Set-Content "src/Commands/DependencyContainer.cs"

# GlobalUsings Commands
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Commands/GlobalUsings.cs"

# DependencyContainer class in Models Project
@"

namespace $ProjectName.Models
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddModels(this IServiceCollection services)
        {  
            services.AddCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Models/DependencyContainer.cs"

# GlobalUsings Models
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Models/GlobalUsings.cs"

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
"@ | Set-Content "src/Queries/DependencyContainer.cs"

# GlobalUsings Queries
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Queries/GlobalUsings.cs"

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
"@ | Set-Content "src/Validators/DependencyContainer.cs"

# DependencyContainer class in Infrastructure Project
@"
using System.Reflection;

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

            services.AddApplication()
                        .AddCommands()
                        .AddModels()
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
"@ | Set-Content "src/IoC/DependencyContainer.cs"

# GlobalUsings

# GlobalUsings Validators
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Validators/GlobalUsings.cs"

# GlobalUsings Infrastructure
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Infrastructure/GlobalUsings.cs"

# GlobalUsings class in IoC Project
@"
global using $ProjectName.Application;
global using $ProjectName.Commands;
global using $ProjectName.Infrastructure;
global using $ProjectName.Models;
global using $ProjectName.Queries;
global using $ProjectName.Validators;
global using $ProjectName.Domain.Options;
global using Serilog;
global using Microsoft.AspNetCore.Builder;
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using DevKit.JWT.Extensions;
global using DevKit.JWT.Options;
global using DevKit.ExecutionEngine.Redis;
global using DevKit.ExecutionEngine.Redis.Options;

"@ | Set-Content "src/IoC/GlobalUsings.cs"

# GlobalUsings Controllers
@"
"@ | Set-Content "src/Controllers/GlobalUsings.cs"

# GlobalUsings Domain
@"

"@ | Set-Content "src/Domain/GlobalUsings.cs"

# DataBaseOptions class in Domain
@"

namespace $ProjectName.Domain.Options
{
    public class DataBaseOptions
    {
        public const string SectionKey = nameof(DataBaseOptions);
        public string DefaultConnection { get; set; } 
    }
}
"@ | Set-Content "src/Domain/Options/DataBaseOptions.cs"

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

"@ | Set-Content "src/Api/GlobalUsings.cs"

# GlobalUsings Tests
@"
global using FluentAssertions;
global using Xunit;
"@ | Set-Content "tests/UnitTests/GlobalUsings.cs"

@"
global using FluentAssertions;
global using Xunit;
"@ | Set-Content "tests/IntegrationTests/GlobalUsings.cs"

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
"@ | Set-Content "src/Api/Configurations/MiddlewaresConfiguration.cs"
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
"@ | Set-Content "src/Api/Configurations/ServicesConfiguration.cs"

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
"@ | Set-Content "src/Api/Middleware/ErrorHandlerMiddleware.cs"

# Minimal API starter
@"

WebApplication.CreateBuilder(args)
    .ConfigureWebApiServices()
    .ConfigureWebApiMiddlewares()
    .Run();
"@ | Set-Content "src/Api/Program.cs"

# Dockerfile
@"
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG Configuration=Release
WORKDIR /src
COPY src/Api/$ProjectName.Api.csproj src/Api/
COPY src/Application/$ProjectName.Application.csproj src/Application/
COPY src/Commands/$ProjectName.Commands.csproj src/Commands/
COPY src/Controllers/$ProjectName.Controllers.csproj src/Controllers/
COPY src/Domain/$ProjectName.Domain.csproj src/Domain/
COPY src/Infrastructure/$ProjectName.Infrastructure.csproj src/Infrastructure/
COPY src/IoC/$ProjectName.IoC.csproj src/IoC/
COPY src/Models/$ProjectName.Models.csproj src/Models/
COPY src/Queries/$ProjectName.Queries.csproj src/Queries/
COPY src/Validators/$ProjectName.Validators.csproj src/Validators/
RUN dotnet restore src/Api/$ProjectName.Api.csproj
COPY . .
WORKDIR /src/src/Api
RUN dotnet build $ProjectName.Api.csproj -c `${Configuration} -o /app/build

FROM build AS publish
ARG Configuration=Release
RUN dotnet publish $ProjectName.Api.csproj -c `${Configuration} -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "$ProjectName.Api.dll"]

#docker build -f src/Api/Dockerfile -t "$($ProjectName.ToLower())-api:latest" .
#docker container create --name "$($ProjectName.ToLower())-api" -p 8080:8080 "$($ProjectName.ToLower())-api:latest"

"@ | Set-Content "src/Api/Dockerfile"

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
            chmod +x src/Api/deploy.sh
            ./src/Api/deploy.sh
        failOnStdErr: false
'@ | Set-Content "src/Api/azure-pipelines.yml"

$projectDirName = "api-$($ProjectName.ToLower())"
$projectSlug = $ProjectName.ToLower().Replace('.', '-').Replace('_', '-')
$azurePipelinesContent = Get-Content -Raw "src/Api/azure-pipelines.yml"
$azurePipelinesContent = $azurePipelinesContent.Replace("__PROJECT_DIR__", $projectDirName).Replace("__PROJECT_NAME__", $ProjectName)
$azurePipelinesContent | Set-Content "src/Api/azure-pipelines.yml"

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
docker run -d -e TZ=$TZ -p 8010:80 --name webapi-__PROJECT_SLUG__1 $IMAGE_NAME
docker run -d -e TZ=$TZ -p 8011:80 --name webapi-__PROJECT_SLUG__2 $IMAGE_NAME
docker run -d -e TZ=$TZ -p 8012:80 --name webapi-__PROJECT_SLUG__3 $IMAGE_NAME
docker run -d -e TZ=$TZ -p 8013:80 --name webapi-__PROJECT_SLUG__4 $IMAGE_NAME

echo "====================================="
echo "Deploy finalizado correctamente"
echo "====================================="
'@ | Set-Content "src/Api/deploy.sh"

$deployScriptContent = Get-Content -Raw "src/Api/deploy.sh"
$deployScriptContent = $deployScriptContent.Replace("__PROJECT_DIR__", $projectDirName).Replace("__PROJECT_NAME__", $ProjectName).Replace("__PROJECT_SLUG__", $projectSlug)
$deployScriptContent | Set-Content "src/Api/deploy.sh"

# Git ignore
dotnet new gitignore

Write-Host "Clean Architecture solution created successfully!"