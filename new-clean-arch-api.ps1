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

# Infrastructure structure
New-Item -ItemType Directory -Path "src/Infrastructure/Data"
New-Item -ItemType Directory -Path "src/Infrastructure/Services"
New-Item -ItemType Directory -Path "src/Infrastructure/Files"

# API structure
New-Item -ItemType Directory -Path "src/Api/Endpoints" -Force
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
            services.AddFromAssembly(Assembly.GetExecutingAssembly());
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
            services.AddFromAssembly(Assembly.GetExecutingAssembly());
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
            services.AddFromAssembly(Assembly.GetExecutingAssembly());
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
            services.AddFromAssembly(Assembly.GetExecutingAssembly());
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

# DependencyContainer class in Validators Project
@"

namespace $ProjectName.Validators
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddValidators(this IServiceCollection services)
        {  
            services.AddFromAssembly(Assembly.GetExecutingAssembly());
            return services;
        }
    }
}
"@ | Set-Content "src/Validators/DependencyContainer.cs"

# GlobalUsings Validators
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Validators/GlobalUsings.cs"


# GlobalUsings Controllers
@"
"@ | Set-Content "src/Controllers/GlobalUsings.cs"

# DependencyContainer class in Infrastructure Project
@"
using System.Reflection;

namespace $ProjectName.Infrastructure
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddInfrastructure(this IServiceCollection services)
        {
            services.AddFromAssembly(Assembly.GetExecutingAssembly());
            return services;
        }
    }
}
"@ | Set-Content "src/Infrastructure/DependencyContainer.cs"

# GlobalUsings Infrastructure
@"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/Infrastructure/GlobalUsings.cs"

# GlobalUsings Domain
@"

"@ | Set-Content "src/Domain/GlobalUsings.cs"

# DependencyContainer class in IoC Project
@"

namespace $ProjectName.IoC
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddIoC(this IServiceCollection services)
        {
            services.AddApplication()
                    .AddCommands()
                    .AddModels()
                    .AddQueries()
                    .AddValidators()
                    .AddInfrastructure()
                    .AddSerilog();            
            return services;
        }

         public static IServiceCollection AddSerilog(this IServiceCollection services)
        {
            services.AddSingleton<ILogger>(new LoggerConfiguration()
                .MinimumLevel.Debug()
                .CreateLogger());
            return services;
        }
    }
}
"@ | Set-Content "src/IoC/DependencyContainer.cs"

# GlobalUsings class in IoC Project
@"
global using $ProjectName.Application;
global using $ProjectName.Commands;
global using $ProjectName.Infrastructure;
global using $ProjectName.Models;
global using $ProjectName.Queries;
global using $ProjectName.Validators;
global using Serilog;
global using Microsoft.Extensions.DependencyInjection;
"@ | Set-Content "src/IoC/GlobalUsings.cs"

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
                c.SwaggerEndpoint("/swagger/v1/swagger.json", "API v1");
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
                        app.Services.AddIoC();
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

# Git ignore
dotnet new gitignore

Write-Host "Clean Architecture solution created successfully!"