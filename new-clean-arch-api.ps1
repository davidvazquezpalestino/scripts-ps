# =========================================================================
#  new-clean-arch-api.ps1
#  Powered by David Vazquez Palestino
# =========================================================================

$ProjectName = Read-Host "Nombre del proyecto"
$startTime = Get-Date

# ============================================
# SELECCION DE BASE DE DATOS
# ============================================
$USE_SQLSERVER = $false
$USE_MYSQL = $false
$USE_POSTGRES = $false
$USE_ORACLE = $false

Write-Host ""
$dbInput = (Read-Host "¿Se usaran bases de datos relacionales? (S/N) [S]").Trim().ToUpper()
if ([string]::IsNullOrWhiteSpace($dbInput)) {
    $dbInput = "S"
}

if ($dbInput -eq 'S') {
    Write-Host ""
    Write-Host "Selecciona la bases de datos a usar "
    Write-Host "1) SQL Server"
    Write-Host "2) MySQL"
    Write-Host "3) PostgreSQL"
    Write-Host "4) Oracle"
    $DB_SELECTION = Read-Host "Ejemplo: 1,3 para SQL Server y PostgreSQL"

    # Parsear seleccion de DBs
    $DB_ARRAY = $DB_SELECTION -split ','
    foreach ($db in $DB_ARRAY) {
        switch ($db.Trim()) {
            '1' { $USE_SQLSERVER = $true }
            '2' { $USE_MYSQL = $true }
            '3' { $USE_POSTGRES = $true}
            '4' { $USE_ORACLE = $true }
        }
    }
}

# Pregunta si se usara RabbitMQ
Write-Host ""
$rabbitMQInput = (Read-Host "Se usara RabbitMQ? (S/N) [S]").Trim().ToUpper()
if ([string]::IsNullOrWhiteSpace($rabbitMQInput)) {
    $rabbitMQInput = "S"
}
$USE_RABBITMQ = $rabbitMQInput -eq 'S'

# Pregunta si se usara MongoDB
Write-Host ""
$mongoInput = (Read-Host "Se usara MongoDB? (S/N) [S]").Trim().ToUpper()
if ([string]::IsNullOrWhiteSpace($mongoInput)) {
    $mongoInput = "S"
}
$USE_MONGO = $mongoInput -eq 'S'

# Pregunta si se usara Redis
Write-Host ""
$redisInput = (Read-Host "Se usara Redis? (S/N) [S]").Trim().ToUpper()
if ([string]::IsNullOrWhiteSpace($redisInput)) {
    $redisInput = "S"
}
$USE_REDIS = $redisInput -eq 'S'

# Pregunta si se consumiran APIs externas
Write-Host ""
$externalApisInput = (Read-Host "¿Se consumiran APIs externas o Servicios Web? (S/N) [S]").Trim().ToUpper()
if ([string]::IsNullOrWhiteSpace($externalApisInput)) {
    $externalApisInput = "S"
}
$USE_EXTERNAL_APIS = $externalApisInput -eq 'S'

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
if ($USE_SQLSERVER -or $USE_MYSQL -or $USE_POSTGRES -or $USE_ORACLE -or $USE_MONGO) {
    New-Item -ItemType Directory -Path "src/Infrastructure/DataBases" -Force
}

# Create specific DB projects based on selection
if ($USE_SQLSERVER) {
    dotnet new classlib -n "$ProjectName.SqlServer" -o "src/Infrastructure/DataBases/SQLServer"
}
if ($USE_MYSQL) {
    dotnet new classlib -n "$ProjectName.MySql" -o "src/Infrastructure/DataBases/MySQL"
}
if ($USE_POSTGRES) {
    dotnet new classlib -n "$ProjectName.PostgreSql" -o "src/Infrastructure/DataBases/PostgreSQL"
}
if ($USE_ORACLE) {
    dotnet new classlib -n "$ProjectName.Oracle" -o "src/Infrastructure/DataBases/Oracle"
}
if ($USE_MONGO) {
    dotnet new classlib -n "$ProjectName.MongoDb" -o "src/Infrastructure/DataBases/MongoDB"
}

# RabbitMQ (opcional)
if ($USE_RABBITMQ) {
    New-Item -ItemType Directory -Path "src/Infrastructure/Messaging" -Force -ErrorAction SilentlyContinue
    dotnet new classlib -n "$ProjectName.RabbitMQ" -o "src/Infrastructure/Messaging/RabbitMQ"
}

# External APIs / Web Services (opcional)
if ($USE_EXTERNAL_APIS) {
    dotnet new classlib -n "$ProjectName.WebApis" -o "src/Infrastructure/WebApis"
}

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
if ($USE_SQLSERVER) { Remove-Item "src/Infrastructure/DataBases/SQLServer/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_MYSQL) { Remove-Item "src/Infrastructure/DataBases/MySQL/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_POSTGRES) { Remove-Item "src/Infrastructure/DataBases/PostgreSQL/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_ORACLE) { Remove-Item "src/Infrastructure/DataBases/Oracle/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_MONGO) { Remove-Item "src/Infrastructure/DataBases/MongoDB/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_RABBITMQ) { Remove-Item "src/Infrastructure/Messaging/RabbitMQ/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_EXTERNAL_APIS) { Remove-Item "src/Infrastructure/WebApis/Class1.cs" -Force -ErrorAction SilentlyContinue }
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
if ($USE_SQLSERVER) { dotnet sln add src/Infrastructure/DataBases/SQLServer }
if ($USE_MYSQL) { dotnet sln add src/Infrastructure/DataBases/MySQL }
if ($USE_POSTGRES) { dotnet sln add src/Infrastructure/DataBases/PostgreSQL }
if ($USE_ORACLE) { dotnet sln add src/Infrastructure/DataBases/Oracle }
if ($USE_MONGO) { dotnet sln add src/Infrastructure/DataBases/MongoDB }
if ($USE_RABBITMQ) { dotnet sln add src/Infrastructure/Messaging/RabbitMQ }
if ($USE_EXTERNAL_APIS) { dotnet sln add src/Infrastructure/WebApis }
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
if ($USE_SQLSERVER) { dotnet add src/Presentation/IoC reference src/Infrastructure/DataBases/SQLServer }
if ($USE_MYSQL) { dotnet add src/Presentation/IoC reference src/Infrastructure/DataBases/MySQL }
if ($USE_POSTGRES) { dotnet add src/Presentation/IoC reference src/Infrastructure/DataBases/PostgreSQL }
if ($USE_ORACLE) { dotnet add src/Presentation/IoC reference src/Infrastructure/DataBases/Oracle }
if ($USE_MONGO) { dotnet add src/Presentation/IoC reference src/Infrastructure/DataBases/MongoDB }
if ($USE_EXTERNAL_APIS) { dotnet add src/Presentation/IoC reference src/Infrastructure/WebApis }
dotnet add src/Presentation/IoC reference src/Domain

# Infrastructure depends only on Domain (implements interfaces defined there)
if ($USE_SQLSERVER) { dotnet add src/Infrastructure/DataBases/SQLServer reference src/Domain }
if ($USE_MYSQL) { dotnet add src/Infrastructure/DataBases/MySQL reference src/Domain }
if ($USE_POSTGRES) { dotnet add src/Infrastructure/DataBases/PostgreSQL reference src/Domain }
if ($USE_ORACLE) { dotnet add src/Infrastructure/DataBases/Oracle reference src/Domain }
if ($USE_MONGO) { dotnet add src/Infrastructure/DataBases/MongoDB reference src/Domain }
if ($USE_RABBITMQ) {
    dotnet add src/Infrastructure/Messaging/RabbitMQ reference src/Domain
    dotnet add src/Presentation/IoC reference src/Infrastructure/Messaging/RabbitMQ
}
if ($USE_EXTERNAL_APIS) {
    dotnet add src/Infrastructure/WebApis reference src/Domain
}

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
dotnet add src/Presentation/IoC package FluentValidation
dotnet add src/Presentation/IoC package DependencyInjection.ReflectionExtensions
dotnet add src/Presentation/IoC package CoreJsonWebToken
if ($USE_REDIS) {
    dotnet add src/Presentation/IoC package DevKit.ExecutionEngine.Redis
}

# Infrastructure
if ($USE_SQLSERVER) {
    dotnet add src/Infrastructure/DataBases/SQLServer package Microsoft.EntityFrameworkCore
    dotnet add src/Infrastructure/DataBases/SQLServer package Microsoft.EntityFrameworkCore.SqlServer
    dotnet add src/Infrastructure/DataBases/SQLServer package Dapper
    dotnet add src/Infrastructure/DataBases/SQLServer package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Infrastructure/DataBases/SQLServer package DependencyInjection.ReflectionExtensions
}
if ($USE_MYSQL) {
    dotnet add src/Infrastructure/DataBases/MySQL package Microsoft.EntityFrameworkCore
    dotnet add src/Infrastructure/DataBases/MySQL package Pomelo.EntityFrameworkCore.MySql
    dotnet add src/Infrastructure/DataBases/MySQL package Dapper
    dotnet add src/Infrastructure/DataBases/MySQL package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Infrastructure/DataBases/MySQL package DependencyInjection.ReflectionExtensions
}
if ($USE_POSTGRES) {
    dotnet add src/Infrastructure/DataBases/PostgreSQL package Microsoft.EntityFrameworkCore
    dotnet add src/Infrastructure/DataBases/PostgreSQL package Npgsql.EntityFrameworkCore.PostgreSQL
    dotnet add src/Infrastructure/DataBases/PostgreSQL package Dapper
    dotnet add src/Infrastructure/DataBases/PostgreSQL package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Infrastructure/DataBases/PostgreSQL package DependencyInjection.ReflectionExtensions
}
if ($USE_ORACLE) {
    dotnet add src/Infrastructure/DataBases/Oracle package Microsoft.EntityFrameworkCore
    dotnet add src/Infrastructure/DataBases/Oracle package Oracle.EntityFrameworkCore
    dotnet add src/Infrastructure/DataBases/Oracle package Dapper
    dotnet add src/Infrastructure/DataBases/Oracle package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Infrastructure/DataBases/Oracle package DependencyInjection.ReflectionExtensions
}
if ($USE_MONGO) {
    dotnet add src/Infrastructure/DataBases/MongoDB package MongoDB.Driver
    dotnet add src/Infrastructure/DataBases/MongoDB package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Infrastructure/DataBases/MongoDB package DependencyInjection.ReflectionExtensions
}

# RabbitMQ
if ($USE_RABBITMQ) {
    dotnet add src/Infrastructure/Messaging/RabbitMQ package RabbitMQ.Client
    dotnet add src/Infrastructure/Messaging/RabbitMQ package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Infrastructure/Messaging/RabbitMQ package DependencyInjection.ReflectionExtensions
}

# External Services
if ($USE_EXTERNAL_APIS) {
    dotnet add src/Infrastructure/WebApis package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Infrastructure/WebApis package DependencyInjection.ReflectionExtensions
}

# API
dotnet add src/Presentation/Api package Scalar.AspNetCore
dotnet add src/Presentation/Api package Serilog.AspNetCore
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
New-Item -ItemType Directory -Path "src/Infrastructure/DataBases/Options" -Force

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
$dataBaseOptionsDevList = @()
if ($USE_SQLSERVER) { $dataBaseOptionsDevList += '        "SQLServer": "Server=[Server];Database=[Database];User Id=sa;Password=[Password];MultipleActiveResultSets=true;encrypt=false;"' }
if ($USE_MYSQL) { $dataBaseOptionsDevList += '        "MySql": "Server=[Server];Database=[Database];User Id=[User];Password=[Password];"' }
if ($USE_POSTGRES) { $dataBaseOptionsDevList += '        "PostgreSql": "Host=[Server];Database=[Database];Username=[User];Password=[Password];"' }
if ($USE_ORACLE) { $dataBaseOptionsDevList += '        "Oracle": "Data Source=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=[Server])(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=[Service])));User Id=[User];Password=[Password];"' }
$dataBaseOptionsDev = $dataBaseOptionsDevList -join ",`r`n"

$devAppSettings = @"
{
    "DataBaseOptions": {
$dataBaseOptionsDev
    },
    "JwtOptions": {
        "SecurityKey": "1234567890ABCDEFGHIJKLMN�OPQRSTU",
        "ValidIssuer": "empresa",
        "ValidAudience": "empresa",
        "ExpireInMinutes": 1440
    }$(if($USE_REDIS){",`n    `"RedisOptions`": {`n        `"ConnectionRedis`": `"[Server],password=[Password]`",`n        `"Environment`": `"Development`",`n        `"DiasCache`": 1`n    }"}),
    "AllowedHosts": "*",
    "Serilog": {
        "MinimumLevel": {
            "Default": "Warning",
            "Override": {
                "Microsoft": "Warning",
                "System": "Warning",
                "$ProjectName": "Information"
            }
        }
    }
}
"@
$devAppSettings | Set-Content "src/Presentation/Api/appsettings.Development.json"

# appsettings.Production.json
$dataBaseOptionsProdList = @()
if ($USE_SQLSERVER) { $dataBaseOptionsProdList += '        "SQLServer": "Server=[Server];Database=[Database];User Id=sa;Password=[Password];MultipleActiveResultSets=true;encrypt=false;"' }
if ($USE_MYSQL) { $dataBaseOptionsProdList += '        "MySql": "Server=[Server];Database=[Database];User Id=[User];Password=[Password];"' }
if ($USE_POSTGRES) { $dataBaseOptionsProdList += '        "PostgreSql": "Host=[Server];Database=[Database];Username=[User];Password=[Password];"' }
if ($USE_ORACLE) { $dataBaseOptionsProdList += '        "Oracle": "Data Source=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=[Server])(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=[Service])));User Id=[User];Password=[Password];"' }
$dataBaseOptionsProd = $dataBaseOptionsProdList -join ",`r`n"

$prodAppSettings = @"
{
    "DataBaseOptions": {
$dataBaseOptionsProd
    },
    "JwtOptions": {
        "SecurityKey": "1234567890ABCDEFGHIJKLMN�OPQRSTU",
        "ValidIssuer": "empresa",
        "ValidAudience": "empresa",
        "ExpireInMinutes": 1440
    }$(if($USE_REDIS){",`n    `"RedisOptions`": {`n        `"ConnectionRedis`": `"[Server],password=[Password]`",`n        `"Environment`": `"Production`",`n        `"DiasCache`": 1`n    }"}),
    "AllowedHosts": "*",
    "Serilog": {
        "MinimumLevel": {
            "Default": "Warning",
            "Override": {
                "Microsoft": "Warning",
                "System": "Warning",
                "$ProjectName": "Information"
            }
        }
    }
}
"@
$prodAppSettings | Set-Content "src/Presentation/Api/appsettings.Production.json"

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
            services.AddServicesCurrentAssembly();
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
            services.AddServicesCurrentAssembly();
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
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@ | Set-Content "src/Application/Validators/DependencyContainer.cs"

# DependencyContainer class in Infrastructure Projects
$sqlServerDependencyContainer = @"
namespace $ProjectName.SqlServer
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddRepositorySqlServer(this IServiceCollection services)
        {
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@

$mySqlDependencyContainer = @"
namespace $ProjectName.MySql
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddRepositoryMySql(this IServiceCollection services)
        {
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@

$postgreSqlDependencyContainer = @"
namespace $ProjectName.PostgreSql
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddRepositoryPostgreSql(this IServiceCollection services)
        {
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@

$oracleDependencyContainer = @"
namespace $ProjectName.Oracle
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddRepositoryOracle(this IServiceCollection services)
        {
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@

$mongoDbDependencyContainer = @"
namespace $ProjectName.MongoDb
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddRepositoryMongo(this IServiceCollection services)
        {
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@

$mongoDbGlobalUsings = @"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@

if ($USE_SQLSERVER) {
    $sqlServerDependencyContainer | Set-Content "src/Infrastructure/DataBases/SQLServer/DependencyContainer.cs"
}
if ($USE_MYSQL) {
    $mySqlDependencyContainer | Set-Content "src/Infrastructure/DataBases/MySQL/DependencyContainer.cs"
}
if ($USE_POSTGRES) {
    $postgreSqlDependencyContainer | Set-Content "src/Infrastructure/DataBases/PostgreSQL/DependencyContainer.cs"
}
if ($USE_ORACLE) {
    $oracleDependencyContainer | Set-Content "src/Infrastructure/DataBases/Oracle/DependencyContainer.cs"
}
if ($USE_MONGO) {
    $mongoDbDependencyContainer | Set-Content "src/Infrastructure/DataBases/MongoDB/DependencyContainer.cs"
    $mongoDbGlobalUsings | Set-Content "src/Infrastructure/DataBases/MongoDB/GlobalUsings.cs"
}

# DependencyContainer class in RabbitMQ Project (opcional)
$rabbitMqDependencyContainer = @"
namespace $ProjectName.RabbitMQ
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddRabbitMq(this IServiceCollection services)
        {  
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@

$rabbitMqGlobalUsings = @"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@

if ($USE_RABBITMQ) {
    $rabbitMqDependencyContainer | Set-Content "src/Infrastructure/Messaging/RabbitMQ/DependencyContainer.cs"
    $rabbitMqGlobalUsings | Set-Content "src/Infrastructure/Messaging/RabbitMQ/GlobalUsings.cs"
}

# DependencyContainer class in WebApis Project (opcional)
$webApisDependencyContainer = @"
namespace $ProjectName.WebApis
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddWebApis(this IServiceCollection services)
        {  
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@

$webApisGlobalUsings = @"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;

"@

if ($USE_EXTERNAL_APIS) {
    $webApisDependencyContainer | Set-Content "src/Infrastructure/WebApis/DependencyContainer.cs"
    $webApisGlobalUsings | Set-Content "src/Infrastructure/WebApis/GlobalUsings.cs"
}

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
            $(if($USE_REDIS){"services.Configure<RedisOptions>(configuration.GetSection(RedisOptions.SectionKey));"})
            services.AddJwtServices(options => configuration.GetSection(JwtOptions.SectionKey).Bind(options));
            $(if($USE_REDIS){"services.AddRedisCache();"})

            services.AddCommands()
                        .AddQueries()
                        .AddValidators()$(if($USE_SQLSERVER){".AddRepositorySqlServer()"})$(if($USE_MYSQL){".AddRepositoryMySql()"})$(if($USE_POSTGRES){".AddRepositoryPostgreSql()"})$(if($USE_ORACLE){".AddRepositoryOracle()"})$(if($USE_MONGO){".AddRepositoryMongo()"})$(if($USE_RABBITMQ){".AddRabbitMq()"})$(if($USE_EXTERNAL_APIS){".AddWebApis()"});
            return services;
        }
    }
}
"@ | Set-Content "src/Presentation/IoC/DependencyContainer.cs"

# GlobalUsings

# GlobalUsings Validators
$validatorsGlobalUsings = @"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
global using System;

"@

$validatorsGlobalUsings | Set-Content "src/Application/Validators/GlobalUsings.cs"

# GlobalUsings Infrastructure
$dbGlobalUsings = @"
global using System.Reflection;
global using DevKit.Injection.Extensions;
global using Microsoft.Extensions.DependencyInjection;
global using System;

"@

if ($USE_SQLSERVER) {
    $dbGlobalUsings | Set-Content "src/Infrastructure/DataBases/SQLServer/GlobalUsings.cs"
}
if ($USE_MYSQL) {
    $dbGlobalUsings | Set-Content "src/Infrastructure/DataBases/MySQL/GlobalUsings.cs"
}
if ($USE_POSTGRES) {
    $dbGlobalUsings | Set-Content "src/Infrastructure/DataBases/PostgreSQL/GlobalUsings.cs"
}
if ($USE_ORACLE) {
    $dbGlobalUsings | Set-Content "src/Infrastructure/DataBases/Oracle/GlobalUsings.cs"
}

# GlobalUsings class in IoC Project
$iocGlobalUsings = @"
global using $ProjectName.Commands;
$(if($USE_SQLSERVER){"global using $ProjectName.SqlServer;"})
$(if($USE_MYSQL){"global using $ProjectName.MySql;"})
$(if($USE_POSTGRES){"global using $ProjectName.PostgreSql;"})
$(if($USE_ORACLE){"global using $ProjectName.Oracle;"})
$(if($USE_MONGO){"global using $ProjectName.MongoDb;"})
global using $ProjectName.Queries;
global using $ProjectName.Validators;
$(if($USE_RABBITMQ){"global using $ProjectName.RabbitMQ;"})
$(if($USE_EXTERNAL_APIS){"global using $ProjectName.WebApis;"})
global using $ProjectName.IoC.Options;
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using DevKit.JWT.Extensions;
global using DevKit.JWT.Options;
$(if($USE_REDIS){"global using DevKit.ExecutionEngine.Redis;"})
$(if($USE_REDIS){"global using DevKit.ExecutionEngine.Redis.Options;"})

"@
$iocGlobalUsings | Set-Content "src/Presentation/IoC/GlobalUsings.cs"

# GlobalUsings Controllers
$controllersGlobalUsings = @"
global using Microsoft.AspNetCore.Mvc;
global using Microsoft.AspNetCore.Http;
"@
$controllersGlobalUsings | Set-Content "src/Presentation/Controllers/GlobalUsings.cs"

# GlobalUsings Domain
$domainGlobalUsings = @"
"@
$domainGlobalUsings | Set-Content "src/Domain/GlobalUsings.cs"

# DataBaseOptions class in IoC
New-Item -ItemType Directory -Path "src/Presentation/IoC/Options" -Force | Out-Null
$dataBaseOptions = @"
namespace $ProjectName.IoC.Options
{
    public class DataBaseOptions
    {
        public const string SectionKey = nameof(DataBaseOptions);
$(if($USE_SQLSERVER){"        public string SQLServer { get; set; }"})
$(if($USE_MYSQL){"        public string MySql { get; set; }"})
$(if($USE_POSTGRES){"        public string PostgreSql { get; set; }"})
$(if($USE_ORACLE){"        public string Oracle { get; set; }"})
    }
}
"@
$dataBaseOptions | Set-Content "src/Presentation/IoC/Options/DataBaseOptions.cs"

# EnvironmentOptions class in IoC
$environmentOptions = @"
namespace $ProjectName.IoC.Options
{
    public class EnvironmentOptions
    {
        public const string SectionKey = nameof(EnvironmentOptions);
        public string EnvironmentName { get; set; }
    }
}
"@
$environmentOptions | Set-Content "src/Presentation/IoC/Options/EnvironmentOptions.cs"

# GlobalUsings Api
$apiGlobalUsings = @"
global using Microsoft.AspNetCore.Builder;
global using Microsoft.AspNetCore.Http;
global using Microsoft.Extensions.DependencyInjection;
global using System.Text.Json.Serialization;
global using Serilog;
global using $ProjectName.IoC;
global using Microsoft.OpenApi;
global using Microsoft.AspNetCore.Mvc;
global using $ProjectName.WebApi.Configurations;
global using $ProjectName.WebApi.Middleware;
global using $ProjectName.IoC.Options;
global using System;

"@
$apiGlobalUsings | Set-Content "src/Presentation/Api/GlobalUsings.cs"

# GlobalUsings Tests
@"
global using FluentAssertions;
global using Xunit;
global using System;

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
            
            app.Host.UseSerilog((context, configuration) => configuration
                .ReadFrom.Configuration(context.Configuration)
                .Enrich.FromLogContext()
                .Enrich.WithProperty("Application", "$ProjectName")
                .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {SourceContext} {Message:lj}{NewLine}{Exception}")
            );

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
# Base image for $ProjectName (DB: $(if($USE_SQLSERVER){"SQL Server"} elseif($USE_MYSQL){"MySQL"} elseif($USE_POSTGRES){"PostgreSQL"} elseif($USE_ORACLE){"Oracle"} else{"Not selected"}))
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
EXPOSE 8080

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG Configuration=Release
WORKDIR /src

# Copy project files
COPY src/Presentation/Api/$ProjectName.WebApi.csproj src/Presentation/Api/
COPY src/Application/Commands/$ProjectName.Commands.csproj src/Application/Commands/
COPY src/Presentation/Controllers/$ProjectName.Controllers.csproj src/Presentation/Controllers/
COPY src/Domain/$ProjectName.Domain.csproj src/Domain/
$(if($USE_SQLSERVER){"COPY src/Infrastructure/DataBases/SQLServer/$ProjectName.SqlServer.csproj src/Infrastructure/DataBases/SQLServer/"})
$(if($USE_MYSQL){"COPY src/Infrastructure/DataBases/MySQL/$ProjectName.MySql.csproj src/Infrastructure/DataBases/MySQL/"})
$(if($USE_POSTGRES){"COPY src/Infrastructure/DataBases/PostgreSQL/$ProjectName.PostgreSql.csproj src/Infrastructure/DataBases/PostgreSQL/"})
$(if($USE_ORACLE){"COPY src/Infrastructure/DataBases/Oracle/$ProjectName.Oracle.csproj src/Infrastructure/DataBases/Oracle/"})
$(if($USE_MONGO){"COPY src/Infrastructure/DataBases/MongoDB/$ProjectName.MongoDb.csproj src/Infrastructure/DataBases/MongoDB/"})
COPY src/Presentation/IoC/$ProjectName.IoC.csproj src/Presentation/IoC/
COPY src/Application/Models/$ProjectName.Models.csproj src/Application/Models/
COPY src/Application/Queries/$ProjectName.Queries.csproj src/Application/Queries/
COPY src/Application/Validators/$ProjectName.Validators.csproj src/Application/Validators/
$(if($USE_RABBITMQ){"COPY src/Infrastructure/Messaging/RabbitMQ/$ProjectName.RabbitMQ.csproj src/Infrastructure/Messaging/RabbitMQ/"})
$(if($USE_EXTERNAL_APIS){"COPY src/Infrastructure/WebApis/$ProjectName.WebApis.csproj src/Infrastructure/WebApis/"})

# Restore dependencies
RUN dotnet restore src/Presentation/Api/$ProjectName.WebApi.csproj

# Copy all source code
COPY . .

# Build project
WORKDIR /src/src/Presentation/Api
RUN dotnet build $ProjectName.WebApi.csproj -c `${Configuration} -o /app/build

# Publish stage
FROM build AS publish
ARG Configuration=Release
RUN dotnet publish $ProjectName.WebApi.csproj -c `${Configuration} -o /app/publish /p:UseAppHost=false

# Final stage
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "$ProjectName.WebApi.dll"]

# Helper commands:
# docker build -f src/Presentation/Api/Dockerfile -t "$($ProjectName.ToLower())-api:latest" .
# docker container rm -f "$($ProjectName.ToLower())-api"
# docker run -d --name "$($ProjectName.ToLower())-api" -p $($DockerPort1):8080 "$($ProjectName.ToLower())-api:latest"

"@ | Set-Content "src/Presentation/Api/Dockerfile"

# azure-pipelines.yml
@"
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
$deployScript = @"
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
"@

$deployScript | Set-Content "src/Presentation/Api/deploy.sh"

$deployDir = Split-Path "src/Presentation/Api/deploy.sh" -Parent
if (-not (Test-Path $deployDir)) {
    New-Item -ItemType Directory -Path $deployDir -Force | Out-Null
}
$deployScript | Set-Content "src/Presentation/Api/deploy.sh"

if (Test-Path "src/Presentation/Api/deploy.sh") {
    $deployScriptContent = Get-Content -Raw "src/Presentation/Api/deploy.sh"
    if ($deployScriptContent) {
        $deployScriptContent = $deployScriptContent.Replace("__PROJECT_DIR__", $projectDirName).Replace("__PROJECT_NAME__", $ProjectName).Replace("__PROJECT_SLUG__", $projectSlug).Replace("__DOCKER_PORT_1__", "$DockerPort1").Replace("__DOCKER_PORT_2__", "$DockerPort2").Replace("__DOCKER_PORT_3__", "$DockerPort3").Replace("__DOCKER_PORT_4__", "$DockerPort4")
        $deployScriptContent | Set-Content "src/Presentation/Api/deploy.sh"
    }
}


# =========================
# CLEAN ARCHITECTURE DOC
# =========================
Write-Host "Writing documentation/architecture-guide.md..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "documentation" -Force | Out-Null
$architectureGuide = @'

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

Un caso de uso no sabe que existe `DbContext`; solo conoce interfaces.

### 2.3 Infrastructure — los adaptadores

Implementa los puertos de Domain y Application.

- `DataBases/`: EF Core, Dapper, repositorios, migraciones, opciones.
  - `SQLServer/`: Implementación específica para SQL Server.
  - `MySQL/`: Implementación específica para MySQL.
  - `PostgreSQL/`: Implementación específica para PostgreSQL.
  - `Oracle/`: Implementación específica para Oracle.
- `Adapters/`: APIs externas, colas de mensajes, servicios de correo, etc.

Es la única capa que conoce conexiones de base de datos, ORM y APIs
externas.

> **Estrategia de persistencia:** por convención, los **Commands**
> (escritura) usan **Entity Framework Core** para aprovechar el
> seguimiento de cambios, validaciones y migraciones. Los **Queries**
> (lectura) usan **Dapper** para leer de forma ligera y eficiente,
> especialmente cuando se proyectan DTOs planos.

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
3. `Application/Commands/Orders/CreateOrder/CreateOrderUseCase.cs` depende
   de `IOrderRepository`.
4. `Presentation/IoC/DependencyContainer.cs` registra la implementación.
5. `Presentation/Controllers/Orders/OrdersController.cs` expone el endpoint.

### Cuándo usar `Query`/`Command` vs tipos primitivos

- Si la consulta o comando requiere **2 o más parámetros**, encapsúlalos
  en un objeto `Query` o `Command`.
- Si requiere **1 solo parámetro**, pásalo directamente como tipo
  primitivo o `Guid`.

Ejemplo:

```csharp
// Un solo parámetro: tipo primitivo
public async Task<OrderDto?> ExecuteAsync(Guid orderId, CancellationToken ct = default)

// Dos o más parámetros: objeto Query
public record GetOrdersQuery(DateTime From, DateTime To, string Status);
public async Task<IEnumerable<OrderDto>> ExecuteAsync(GetOrdersQuery query, CancellationToken ct = default)
```

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

```text
src
├── Domain
│   ├── Entities/Orders/
│   │   └── Order.cs
│   └── Interfaces/Orders/
│       └── IOrderRepository.cs
├── Application
│   ├── Commands/Orders/CreateOrder/
│   │   ├── CreateOrderCommand.cs
│   │   ├── CreateOrderUseCase.cs
│   │   └── CreateOrderResult.cs
│   ├── Queries/Orders/GetOrderById/
│   │   └── GetOrderByIdUseCase.cs
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
├── CreateOrderUseCaseTests.cs
└── CreateOrderValidatorTests.cs
```

**Regla de oro:** si necesitas buscar por toda la solución para encontrar
los archivos de una feature, la organización está mal.

## 🔑 Cómo encaja en Hexagonal

- **Domain** → el núcleo: entidades y contratos (puertos).
- **Application** → casos de uso (commands, queries, handlers, DTOs, validadores).
- **Infrastructure** → adaptadores concretos (repositorios, persistencia, mensajería).
- **Presentation** → capa externa (controllers, endpoints).
- **Tests** → organizados también por feature, validando handlers y reglas.

## ✅ Buenas prácticas

- **Mantener independencia por feature**: cada carpeta de `Orders`, `Customers`, etc. debe contener todo lo necesario para esa funcionalidad.
- **Interfaces en Domain**: siempre definen los puertos (`IOrderRepository`).
- **UseCases en Application**: orquestan lógica de negocio usando puertos.
- **Adaptadores en Infrastructure**: implementan los puertos (`OrderRepository`).
- **Controllers en Presentation**: exponen los casos de uso hacia el exterior.
- **Tests alineados**: cada feature tiene sus pruebas en la misma estructura.

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
      /DataBases                        Persistencia (EF Core, repositorios)
        /SQLServer                      Implementación SQL Server
        /MySQL                          Implementación MySQL
        /PostgreSQL                     Implementación PostgreSQL
        /Oracle                         Implementación Oracle
        /Options
  /tests
    /UnitTests
  /documentation
    architecture-guide.md
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
Application/Commands o Queries  (caso de uso)
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

2. **Application:** crea el comando/consulta, caso de uso, validator y DTOs.
   - `Application/Commands/{Feature}/{Action}/{Action}Command.cs` (solo si tiene 2+ parámetros)
   - `Application/Commands/{Feature}/{Action}/{Action}UseCase.cs`
   - `Application/Commands/{Feature}/{Action}/{Action}Result.cs`
   - `Application/Queries/{Feature}/{Action}/{Action}Query.cs` (solo si tiene 2+ parámetros)
   - `Application/Queries/{Feature}/{Action}/{Action}UseCase.cs`
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
- **Sustituibilidad:** cambiar EF Core por Dapper (o viceversa), SQL Server por Postgres,
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
- Martin Fowler — *Patterns of Enterprise Application Architecture*.
'@
$architectureGuide | Set-Content "documentation/architecture-guide.md"

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
    foreach ($docPath in @('documentation/README.md', 'documentation/architecture-guide.md')) {
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

# README.md
Write-Host "Writing documentation/README.md..." -ForegroundColor Yellow
$readme = @'
# $ProjectName

ASP.NET Core Web API con Clean Architecture y Vertical Slice Architecture.

## Arquitectura

Este proyecto combina:
- **Clean Architecture**: Capas concéntricas donde el dominio es el centro
- **Vertical Slice Architecture**: Código organizado por features (casos de uso)

Para más detalles, consulta [architecture-guide.md](architecture-guide.md).

## Estructura del Proyecto

```text
src/
├── Domain/                    # Dominio y reglas de negocio
├── Application/              # Casos de uso (Commands, Queries, Validators)
├── Infrastructure/           # Implementaciones (DataBases, Messaging)
├── Presentation/             # API, Controllers, IoC
└── IoC/                      # Inyección de dependencias
```

## Configuración

Edita los archivos `appsettings.json` para configurar:
- Connection strings de base de datos
- Configuración de JWT
- Configuración de Redis
- Configuración de RabbitMQ (si aplica)

## Ejecutar

```bash
dotnet run --project src/Presentation/Api
```

## Tests

```bash
dotnet test
```

## Git - Subir al repositorio

```bash
# Inicializar repositorio (si no existe)
git init

# Agregar todos los archivos
git add .

# Hacer commit inicial
git commit -m "Initial commit - Clean Architecture setup"

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

$endTime = Get-Date
$duration = $endTime - $startTime
$hours = [int]$duration.TotalHours
$minutes = $duration.Minutes
$seconds = $duration.Seconds

Write-Host "Clean Architecture solution created successfully!"
Write-Host "Powered by David Vazquez Palestino" -ForegroundColor DarkGray
Write-Host "Time elapsed: $($hours)h $($minutes)m $($seconds)s" -ForegroundColor Green
