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

# Pregunta si se usara Azure Key Vault
Write-Host ""
$keyVaultInput = (Read-Host "Se usara Azure Key Vault? (S/N) [S]").Trim().ToUpper()
if ([string]::IsNullOrWhiteSpace($keyVaultInput)) {
    $keyVaultInput = "S"
}
$USE_KEYVAULT = $keyVaultInput -eq 'S'

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
# y la carpeta-capa (UseCases, Adapters, Frameworks, etc.) pueda alojar proyectos hermanos.

# API host (Frameworks & Drivers)
dotnet new web -n "$ProjectName.WebApi" -o "src/Frameworks/WebApi"

# UseCases sub-projects (reglas de aplicación, separate projects)
dotnet new classlib -n "$ProjectName.Abstractions" -o "src/UseCases/Abstractions"
dotnet new classlib -n "$ProjectName.Commands" -o "src/UseCases/Commands"
dotnet new classlib -n "$ProjectName.Models" -o "src/UseCases/Models"
dotnet new classlib -n "$ProjectName.Queries" -o "src/UseCases/Queries"
dotnet new classlib -n "$ProjectName.Validators" -o "src/UseCases/Validators"

# Interface Adapters (controllers y gateways)
dotnet new classlib -n "$ProjectName.Controllers" -o "src/Adapters/Controllers"

# IoC Project (composición raíz, Frameworks & Drivers)
dotnet new classlib -n "$ProjectName.IoC" -o "src/Frameworks/IoC"

# Entities (capa central: reglas de negocio de empresa)
dotnet new classlib -n "$ProjectName.Entities" -o "src/Entities"

# Frameworks & Drivers: bases de datos
if ($USE_SQLSERVER -or $USE_MYSQL -or $USE_POSTGRES -or $USE_ORACLE -or $USE_MONGO) {
    New-Item -ItemType Directory -Path "src/Frameworks/DataBases" -Force
}

# Create specific DB projects based on selection
if ($USE_SQLSERVER) {
    dotnet new classlib -n "$ProjectName.SqlServer" -o "src/Frameworks/DataBases/SQLServer"
}
if ($USE_MYSQL) {
    dotnet new classlib -n "$ProjectName.MySql" -o "src/Frameworks/DataBases/MySQL"
}
if ($USE_POSTGRES) {
    dotnet new classlib -n "$ProjectName.PostgreSql" -o "src/Frameworks/DataBases/PostgreSQL"
}
if ($USE_ORACLE) {
    dotnet new classlib -n "$ProjectName.Oracle" -o "src/Frameworks/DataBases/Oracle"
}
if ($USE_MONGO) {
    dotnet new classlib -n "$ProjectName.MongoDb" -o "src/Frameworks/DataBases/MongoDB"
}

# RabbitMQ (opcional)
if ($USE_RABBITMQ) {
    New-Item -ItemType Directory -Path "src/Frameworks/Messaging" -Force -ErrorAction SilentlyContinue
    dotnet new classlib -n "$ProjectName.RabbitMQ" -o "src/Frameworks/Messaging/RabbitMQ"
}

# External APIs / Web Services (opcional, gateways en Interface Adapters)
if ($USE_EXTERNAL_APIS) {
    dotnet new classlib -n "$ProjectName.WebApis" -o "src/Adapters/WebApis"
}

if ($USE_REDIS) {
    dotnet new classlib -n "$ProjectName.Redis" -o "src/Frameworks/Redis"
}

# Azure Key Vault (opcional)
if ($USE_KEYVAULT) {
    dotnet new classlib -n "$ProjectName.AzureKeyVault" -o "src/Frameworks/AzureKeyVault"
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
Remove-Item "src/UseCases/Abstractions/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/UseCases/Commands/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/UseCases/Models/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/UseCases/Queries/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Adapters/Controllers/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Frameworks/IoC/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/Entities/Class1.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "src/UseCases/Validators/Class1.cs" -Force -ErrorAction SilentlyContinue
if ($USE_SQLSERVER) { Remove-Item "src/Frameworks/DataBases/SQLServer/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_MYSQL) { Remove-Item "src/Frameworks/DataBases/MySQL/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_POSTGRES) { Remove-Item "src/Frameworks/DataBases/PostgreSQL/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_ORACLE) { Remove-Item "src/Frameworks/DataBases/Oracle/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_MONGO) { Remove-Item "src/Frameworks/DataBases/MongoDB/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_RABBITMQ) { Remove-Item "src/Frameworks/Messaging/RabbitMQ/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_EXTERNAL_APIS) { Remove-Item "src/Adapters/WebApis/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_REDIS) { Remove-Item "src/Frameworks/Redis/Class1.cs" -Force -ErrorAction SilentlyContinue }
if ($USE_KEYVAULT) { Remove-Item "src/Frameworks/AzureKeyVault/Class1.cs" -Force -ErrorAction SilentlyContinue }
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

dotnet sln add src/Frameworks/WebApi
dotnet sln add src/UseCases/Abstractions
dotnet sln add src/UseCases/Commands
dotnet sln add src/UseCases/Models
dotnet sln add src/UseCases/Queries
dotnet sln add src/UseCases/Validators
dotnet sln add src/Adapters/Controllers
dotnet sln add src/Frameworks/IoC
dotnet sln add src/Entities
if ($USE_SQLSERVER) { dotnet sln add src/Frameworks/DataBases/SQLServer }
if ($USE_MYSQL) { dotnet sln add src/Frameworks/DataBases/MySQL }
if ($USE_POSTGRES) { dotnet sln add src/Frameworks/DataBases/PostgreSQL }
if ($USE_ORACLE) { dotnet sln add src/Frameworks/DataBases/Oracle }
if ($USE_MONGO) { dotnet sln add src/Frameworks/DataBases/MongoDB }
if ($USE_RABBITMQ) { dotnet sln add src/Frameworks/Messaging/RabbitMQ }
if ($USE_EXTERNAL_APIS) { dotnet sln add src/Adapters/WebApis }
if ($USE_REDIS) { dotnet sln add src/Frameworks/Redis }
if ($USE_KEYVAULT) { dotnet sln add src/Frameworks/AzureKeyVault }
dotnet sln add tests/UnitTests

# =========================
# PROJECT REFERENCES
# =========================

# UseCases sub-projects depend on Entities
dotnet add src/UseCases/Commands reference src/Entities
dotnet add src/UseCases/Models reference src/Entities
dotnet add src/UseCases/Queries reference src/Entities
dotnet add src/UseCases/Validators reference src/Entities

dotnet add src/UseCases/Abstractions reference src/Entities
dotnet add src/UseCases/Abstractions reference src/UseCases/Models
dotnet add src/UseCases/Commands reference src/UseCases/Abstractions
dotnet add src/UseCases/Commands reference src/UseCases/Models
dotnet add src/UseCases/Queries reference src/UseCases/Abstractions
dotnet add src/UseCases/Queries reference src/UseCases/Models
dotnet add src/UseCases/Validators reference src/UseCases/Commands
dotnet add src/UseCases/Validators reference src/UseCases/Models

# Controllers (Adapters) depend only on UseCases layer projects
dotnet add src/Adapters/Controllers reference src/UseCases/Commands
dotnet add src/Adapters/Controllers reference src/UseCases/Queries
dotnet add src/Adapters/Controllers reference src/UseCases/Models
dotnet add src/Adapters/Controllers reference src/UseCases/Abstractions
# IoC depends on all UseCases projects + Adapters + Frameworks + Entities
dotnet add src/Frameworks/IoC reference src/UseCases/Abstractions
dotnet add src/Frameworks/IoC reference src/UseCases/Commands
dotnet add src/Frameworks/IoC reference src/UseCases/Models
dotnet add src/Frameworks/IoC reference src/UseCases/Queries
dotnet add src/Frameworks/IoC reference src/UseCases/Validators
dotnet add src/Frameworks/IoC reference src/Adapters/Controllers
if ($USE_SQLSERVER) { dotnet add src/Frameworks/IoC reference src/Frameworks/DataBases/SQLServer }
if ($USE_MYSQL) { dotnet add src/Frameworks/IoC reference src/Frameworks/DataBases/MySQL }
if ($USE_POSTGRES) { dotnet add src/Frameworks/IoC reference src/Frameworks/DataBases/PostgreSQL }
if ($USE_ORACLE) { dotnet add src/Frameworks/IoC reference src/Frameworks/DataBases/Oracle }
if ($USE_MONGO) { dotnet add src/Frameworks/IoC reference src/Frameworks/DataBases/MongoDB }
if ($USE_EXTERNAL_APIS) { dotnet add src/Frameworks/IoC reference src/Adapters/WebApis }
if ($USE_REDIS) { dotnet add src/Frameworks/IoC reference src/Frameworks/Redis }
if ($USE_KEYVAULT) { dotnet add src/Frameworks/IoC reference src/Frameworks/AzureKeyVault }
dotnet add src/Frameworks/IoC reference src/Entities

if ($USE_SQLSERVER) { dotnet add src/Frameworks/DataBases/SQLServer reference src/Entities }
if ($USE_MYSQL) { dotnet add src/Frameworks/DataBases/MySQL reference src/Entities }
if ($USE_POSTGRES) { dotnet add src/Frameworks/DataBases/PostgreSQL reference src/Entities }
if ($USE_ORACLE) { dotnet add src/Frameworks/DataBases/Oracle reference src/Entities }
if ($USE_MONGO) { dotnet add src/Frameworks/DataBases/MongoDB reference src/Entities }
if ($USE_RABBITMQ) {
    dotnet add src/Frameworks/Messaging/RabbitMQ reference src/Entities
    dotnet add src/Frameworks/IoC reference src/Frameworks/Messaging/RabbitMQ
}
if ($USE_EXTERNAL_APIS) {
    dotnet add src/Adapters/WebApis reference src/Entities
}
if ($USE_KEYVAULT) {
    dotnet add src/Frameworks/AzureKeyVault reference src/Entities
}
if ($USE_SQLSERVER -and $USE_KEYVAULT) {
    dotnet add src/Frameworks/DataBases/SQLServer reference src/Frameworks/AzureKeyVault
}

$applicationPortAdapters = @()
if ($USE_SQLSERVER) { $applicationPortAdapters += "src/Frameworks/DataBases/SQLServer" }
if ($USE_MYSQL) { $applicationPortAdapters += "src/Frameworks/DataBases/MySQL" }
if ($USE_POSTGRES) { $applicationPortAdapters += "src/Frameworks/DataBases/PostgreSQL" }
if ($USE_ORACLE) { $applicationPortAdapters += "src/Frameworks/DataBases/Oracle" }
if ($USE_MONGO) { $applicationPortAdapters += "src/Frameworks/DataBases/MongoDB" }
if ($USE_RABBITMQ) { $applicationPortAdapters += "src/Frameworks/Messaging/RabbitMQ" }
if ($USE_EXTERNAL_APIS) { $applicationPortAdapters += "src/Adapters/WebApis" }
if ($USE_REDIS) { $applicationPortAdapters += "src/Frameworks/Redis" }
if ($USE_KEYVAULT) { $applicationPortAdapters += "src/Frameworks/AzureKeyVault" }
foreach ($adapter in $applicationPortAdapters) {
    dotnet add $adapter reference src/UseCases/Abstractions
}

# API host depends on IoC
dotnet add src/Frameworks/WebApi reference src/Frameworks/IoC

# Tests
dotnet add tests/UnitTests reference src/UseCases/Abstractions
dotnet add tests/UnitTests reference src/Entities
dotnet add tests/UnitTests reference src/UseCases/Commands
dotnet add tests/UnitTests reference src/UseCases/Queries
dotnet add tests/UnitTests reference src/UseCases/Models
dotnet add tests/UnitTests reference src/UseCases/Validators

# =========================
# ADD PACKAGES
# =========================

# UseCases sub-projects
dotnet add src/UseCases/Commands package FluentValidation
dotnet add src/UseCases/Commands package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/UseCases/Commands package DependencyInjection.ReflectionExtensions

dotnet add src/UseCases/Models package FluentValidation
dotnet add src/UseCases/Models package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/UseCases/Models package DependencyInjection.ReflectionExtensions

dotnet add src/UseCases/Abstractions package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/UseCases/Abstractions package DependencyInjection.ReflectionExtensions

dotnet add src/UseCases/Queries package FluentValidation
dotnet add src/UseCases/Queries package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/UseCases/Queries package DependencyInjection.ReflectionExtensions

dotnet add src/UseCases/Validators package FluentValidation
dotnet add src/UseCases/Validators package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add src/UseCases/Validators package DependencyInjection.ReflectionExtensions

# Controllers needs ASP.NET Core framework reference (ControllerBase, [ApiController], etc.)
$controllersCsproj = "src/Adapters/Controllers/$ProjectName.Controllers.csproj"
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
dotnet add src/Frameworks/IoC package Microsoft.Extensions.DependencyInjection
dotnet add src/Frameworks/IoC package FluentValidation
dotnet add src/Frameworks/IoC package DependencyInjection.ReflectionExtensions
dotnet add src/Frameworks/IoC package CoreJsonWebToken
if ($USE_REDIS) {
    dotnet add src/Frameworks/Redis package StackExchange.Redis
    dotnet add src/Frameworks/Redis package Microsoft.Extensions.Options
    dotnet add src/Frameworks/Redis package Microsoft.Extensions.DependencyInjection.Abstractions
}

# Frameworks: persistencia
if ($USE_SQLSERVER) {
    dotnet add src/Frameworks/DataBases/SQLServer package Microsoft.EntityFrameworkCore
    dotnet add src/Frameworks/DataBases/SQLServer package Microsoft.EntityFrameworkCore.SqlServer
    dotnet add src/Frameworks/DataBases/SQLServer package Dapper
    dotnet add src/Frameworks/DataBases/SQLServer package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Frameworks/DataBases/SQLServer package Microsoft.Extensions.Options.ConfigurationExtensions
    dotnet add src/Frameworks/DataBases/SQLServer package DependencyInjection.ReflectionExtensions
    dotnet add src/Frameworks/DataBases/SQLServer package Serilog.AspNetCore
    dotnet add src/Frameworks/DataBases/SQLServer package Serilog.Sinks.MSSqlServer
}
if ($USE_MYSQL) {
    dotnet add src/Frameworks/DataBases/MySQL package Microsoft.EntityFrameworkCore
    dotnet add src/Frameworks/DataBases/MySQL package Pomelo.EntityFrameworkCore.MySql
    dotnet add src/Frameworks/DataBases/MySQL package Dapper
    dotnet add src/Frameworks/DataBases/MySQL package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Frameworks/DataBases/MySQL package Microsoft.Extensions.Options.ConfigurationExtensions
    dotnet add src/Frameworks/DataBases/MySQL package DependencyInjection.ReflectionExtensions
}
if ($USE_POSTGRES) {
    dotnet add src/Frameworks/DataBases/PostgreSQL package Microsoft.EntityFrameworkCore
    dotnet add src/Frameworks/DataBases/PostgreSQL package Npgsql.EntityFrameworkCore.PostgreSQL
    dotnet add src/Frameworks/DataBases/PostgreSQL package Dapper
    dotnet add src/Frameworks/DataBases/PostgreSQL package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Frameworks/DataBases/PostgreSQL package Microsoft.Extensions.Options.ConfigurationExtensions
    dotnet add src/Frameworks/DataBases/PostgreSQL package DependencyInjection.ReflectionExtensions
}
if ($USE_ORACLE) {
    dotnet add src/Frameworks/DataBases/Oracle package Microsoft.EntityFrameworkCore
    dotnet add src/Frameworks/DataBases/Oracle package Oracle.EntityFrameworkCore
    dotnet add src/Frameworks/DataBases/Oracle package Dapper
    dotnet add src/Frameworks/DataBases/Oracle package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Frameworks/DataBases/Oracle package Microsoft.Extensions.Options.ConfigurationExtensions
    dotnet add src/Frameworks/DataBases/Oracle package DependencyInjection.ReflectionExtensions
}
if ($USE_MONGO) {
    dotnet add src/Frameworks/DataBases/MongoDB package MongoDB.Driver
    dotnet add src/Frameworks/DataBases/MongoDB package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Frameworks/DataBases/MongoDB package Microsoft.Extensions.Options.ConfigurationExtensions
    dotnet add src/Frameworks/DataBases/MongoDB package DependencyInjection.ReflectionExtensions
}

# RabbitMQ
if ($USE_RABBITMQ) {
    dotnet add src/Frameworks/Messaging/RabbitMQ package RabbitMQ.Client
    dotnet add src/Frameworks/Messaging/RabbitMQ package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Frameworks/Messaging/RabbitMQ package DependencyInjection.ReflectionExtensions
}

# External Services (gateways)
if ($USE_EXTERNAL_APIS) {
    dotnet add src/Adapters/WebApis package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Adapters/WebApis package DependencyInjection.ReflectionExtensions
}

# Azure Key Vault
if ($USE_KEYVAULT) {
    dotnet add src/Frameworks/AzureKeyVault package Azure.Identity
    dotnet add src/Frameworks/AzureKeyVault package Azure.Security.KeyVault.Secrets
    dotnet add src/Frameworks/AzureKeyVault package Microsoft.Extensions.Options
    dotnet add src/Frameworks/AzureKeyVault package Microsoft.Extensions.DependencyInjection.Abstractions
    dotnet add src/Frameworks/AzureKeyVault package DependencyInjection.ReflectionExtensions
}

# API host
dotnet add src/Frameworks/WebApi package Scalar.AspNetCore
dotnet add src/Frameworks/WebApi package Swashbuckle.AspNetCore

# Tests
dotnet add tests/UnitTests package FluentAssertions

# =========================
# CREATE BASE FOLDERS
# =========================

# Entities structure
New-Item -ItemType Directory -Path "src/Entities/Entities"
New-Item -ItemType Directory -Path "src/Entities/ValueObjects"
New-Item -ItemType Directory -Path "src/Entities/Enums"
New-Item -ItemType Directory -Path "src/Entities/Interfaces"
New-Item -ItemType Directory -Path "src/Frameworks/DataBases/Options" -Force

# Keep entity folders visible in Visual Studio Solution Explorer
"" | Set-Content "src/Entities/Entities/.gitkeep"
"" | Set-Content "src/Entities/ValueObjects/.gitkeep"
"" | Set-Content "src/Entities/Enums/.gitkeep"
"" | Set-Content "src/Entities/Interfaces/.gitkeep"

# API host structure

New-Item -ItemType Directory -Path "src/Frameworks/WebApi/Middleware" -Force
New-Item -ItemType Directory -Path "src/Frameworks/WebApi/Configurations" -Force
New-Item -ItemType Directory -Path "src/Frameworks/WebApi/Properties" -Force

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
"@ | Set-Content "src/Frameworks/WebApi/Properties/launchSettings.json"

# appsettings.json
@"
{
    "EnvironmentOptions": {
        "EnvironmentName": "Production" /*Development, Staging, Production*/
    }
}
"@ | Set-Content "src/Frameworks/WebApi/appsettings.json"

# appsettings.Development.json
$dataBaseOptionsDevList = @()
if ($USE_SQLSERVER) { $dataBaseOptionsDevList += '        "SQLServer": { "Server": null, "Database": null, "User": null, "Password": null, "Port": 1433 }' }
if ($USE_MYSQL) { $dataBaseOptionsDevList += '        "MySql": { "Server": null, "Database": null, "User": null, "Password": null, "Port": 3306 }' }
if ($USE_POSTGRES) { $dataBaseOptionsDevList += '        "PostgreSql": { "Server": null, "Database": null, "User": null, "Password": null, "Port": 5432 }' }
if ($USE_ORACLE) { $dataBaseOptionsDevList += '        "Oracle": { "Server": null, "Database": null, "User": null, "Password": null, "Port": 1521 }' }
if ($USE_MONGO) { $dataBaseOptionsDevList += '        "MongoDb": { "Server": null, "Database": null, "User": null, "Password": null, "Port": 27017 }' }
$dataBaseOptionsDev = $dataBaseOptionsDevList -join ",`r`n"

$devAppSettings = @"
{
    "DatabaseConnection": {
$dataBaseOptionsDev
    },
    "JwtOptions": {
        "SecurityKey": "1234567890ABCDEFGHIJKLMN�OPQRSTU",
        "ValidIssuer": "empresa",
        "ValidAudience": "empresa",
        "ExpireInMinutes": 1440
    }$(if($USE_REDIS){",`n    `"RedisOptions`": {`n        `"ConnectionRedis`": `"[Server],password=[Password]`",`n        `"Environment`": `"Development`",`n        `"DiasCache`": 1`n    }"})$(if($USE_KEYVAULT){",`n    `"KeyVaultOptions`": {`n        `"ClientID`": `"`",`n        `"KeyVaultName`": `"`",`n        `"SecretName`": `"`"`n    }"}),
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
$devAppSettings | Set-Content "src/Frameworks/WebApi/appsettings.Development.json"

# appsettings.Production.json
$dataBaseOptionsProdList = @()
if ($USE_SQLSERVER) { $dataBaseOptionsProdList += '        "SQLServer": { "Server": null, "Database": null, "User": null, "Password": null, "Port": 1433 }' }
if ($USE_MYSQL) { $dataBaseOptionsProdList += '        "MySql": { "Server": null, "Database": null, "User": null, "Password": null, "Port": 3306 }' }
if ($USE_POSTGRES) { $dataBaseOptionsProdList += '        "PostgreSql": { "Server": null, "Database": null, "User": null, "Password": null, "Port": 5432 }' }
if ($USE_ORACLE) { $dataBaseOptionsProdList += '        "Oracle": { "Server": null, "Database": null, "User": null, "Password": null, "Port": 1521 }' }
if ($USE_MONGO) { $dataBaseOptionsProdList += '        "MongoDb": { "Server": null, "Database": null, "User": null, "Password": null, "Port": 27017 }' }
$dataBaseOptionsProd = $dataBaseOptionsProdList -join ",`r`n"

$prodAppSettings = @"
{
    "DatabaseConnection": {
$dataBaseOptionsProd
    },
    "JwtOptions": {
        "SecurityKey": "1234567890ABCDEFGHIJKLMN�OPQRSTU",
        "ValidIssuer": "empresa",
        "ValidAudience": "empresa",
        "ExpireInMinutes": 1440
    }$(if($USE_REDIS){",`n    `"RedisOptions`": {`n        `"ConnectionRedis`": `"[Server],password=[Password]`",`n        `"Environment`": `"Production`",`n        `"DiasCache`": 1`n    }"})$(if($USE_KEYVAULT){",`n    `"KeyVaultOptions`": {`n        `"ClientID`": `"`",`n        `"KeyVaultName`": `"`",`n        `"SecretName`": `"`"`n    }"}),
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
$prodAppSettings | Set-Content "src/Frameworks/WebApi/appsettings.Production.json"

# CREATE BASIC FILES
# =========================

# RegisterServices class in Abstractions Project
New-Item -ItemType Directory -Path "src/UseCases/Abstractions/Shared" -Force | Out-Null
@"
using System;
using System.Collections.Generic;
using System.Reflection;
using Microsoft.Extensions.DependencyInjection;

namespace $ProjectName.Abstractions.Shared
{
    public static class RegisterServices
    {
        /// <summary>
        /// Registra automáticamente las clases de un ensamblado en el contenedor de servicios.
        /// </summary>
        /// <param name="services">La colección de servicios de <see cref="IServiceCollection"/>.</param>
        /// <param name="assembly">El ensamblado de donde se cargarán los tipos.</param>
        /// <param name="filter">Filtro opcional para los tipos.</param>
        /// <param name="logTo">Acción opcional para registrar el proceso.</param>
        /// <param name="onlyClass">Si es verdadero, registra la clase directamente. Si es falso (por defecto), registra por sus interfaces.</param>
        /// <param name="lifetime">El tiempo de vida del servicio (Scoped por defecto).</param>
        /// <returns>La misma colección de servicios para encadenar llamadas.</returns>
        public static IServiceCollection AddServicesFromAssembly(this IServiceCollection services,
            Assembly assembly,
            Func<Type, bool> filter = null,
            Action<string> logTo = null,
            bool onlyClass = false,
            ServiceLifetime lifetime = ServiceLifetime.Scoped)
        {
            if (services == null)
            {
                throw new ArgumentNullException(nameof(services));
            }
            if (assembly == null)
            {
                throw new ArgumentNullException(nameof(assembly));
            }

            string assemblyName = assembly.GetName().Name ?? assembly.ManifestModule.Name;

            bool IsCandidate(Type type)
            {
                if (type == null)
                {
                    return false;
                }
                if (type.IsClass == false || type.IsAbstract)
                {
                    return false;
                }
                // Excluir records (clases con método de instancia <Clone>$ generado por el compilador).
                if (type.GetMethod("<Clone>$", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic) is not null)
                {
                    return false;
                }
                string fullName = type.FullName;
                if (string.IsNullOrWhiteSpace(fullName))
                {
                    return false;
                }
                if (fullName.Contains("+<") || fullName.Contains("+>") || fullName.Contains("<") || fullName.Contains(">") || fullName.Contains("<>"))
                {
                    return false;
                }
                if (fullName.Contains("Microsoft") || fullName.Contains("System.Runtime"))
                {
                    return false;
                }

                if (filter is not null && filter(type) == false)
                {
                    return false;
                }
                return true;
            }

            List<Type> types = assembly.GetTypes()
                .Where(IsCandidate)
                .ToList();

            foreach (Type type in types)
            {
                if (onlyClass)
                {
                    services.TryAdd(new ServiceDescriptor(type, type, lifetime));
                    logTo?.Invoke($"Registrado => {type.Name}");
                }
                else
                {
                    Type[] interfaces = type.GetInterfaces().Where(p => p.FullName.Contains("IEnumerable") == false).ToArray();
                    foreach (Type service in interfaces)
                    {
                        services.TryAdd(new ServiceDescriptor(service, type, lifetime));
                        logTo?.Invoke($"Registrado => {type.Name}:{service.Name}");
                    }
                }
            }

            logTo?.Invoke(types.Count == 0
                ? $"No se encontraron tipos en el ensamblado {assemblyName} que coincidan con los criterios."
                : $"Se encontraron {types.Count} tipos en el ensamblado {assemblyName}.");

            return services;
        }

        /// <summary>
        /// Registra servicios desde múltiples ensamblados.
        /// </summary>
        /// <param name="services">La colección de servicios de <see cref="IServiceCollection"/>.</param>
        /// <param name="assemblies">Lista de ensamblados.</param>
        /// <param name="filter">Filtro opcional.</param>
        /// <param name="logTo">Acción de registro opcional.</param>
        /// <param name="lifetime">Tiempo de vida del servicio.</param>
        /// <returns>La misma colección de servicios.</returns>
        public static IServiceCollection AddServicesFromAssemblies(this IServiceCollection services,
            IEnumerable<Assembly> assemblies,
            Func<Type, bool> filter = null,
            Action<string> logTo = null,
            ServiceLifetime lifetime = ServiceLifetime.Scoped)
        {
            if (services == null)
            {
                throw new ArgumentNullException(nameof(services));
            }

            foreach (Assembly assembly in assemblies)
            {
                services.AddServicesFromAssembly(assembly, filter, logTo, false, lifetime);
            }
            return services;
        }

        /// <summary>
        /// Registra servicios del ensamblado actual automáticamente.
        /// </summary>
        /// <param name="services">La colección de servicios de <see cref="IServiceCollection"/>.</param>
        /// <param name="filter"></param>
        /// <param name="logTo">Acción de registro opcional.</param>
        /// <param name="onlyClass"></param>
        /// <param name="lifetime"></param>
        /// <returns>La misma colección de servicios.</returns>
        public static IServiceCollection AddServicesCurrentAssembly(this IServiceCollection services,
            Func<Type, bool> filter = null,
            Action<string> logTo = null,
            bool onlyClass = false,
            ServiceLifetime lifetime = ServiceLifetime.Scoped)
        {
            if (services == null)
            {
                throw new ArgumentNullException(nameof(services));
            }

            Assembly callingAssembly = Assembly.GetCallingAssembly();
            return services.AddServicesFromAssembly(callingAssembly, filter, logTo, onlyClass, lifetime);
        }

        /// <summary>
        /// Registra los servicios del proyecto Abstractions.
        /// </summary>
        public static IServiceCollection AddAbstractions(this IServiceCollection services)
        {
            return services.AddServicesFromAssembly(typeof(RegisterServices).Assembly);
        }

    }
}
"@ | Set-Content "src/UseCases/Abstractions/Shared/RegisterServices.cs"

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
"@ | Set-Content "src/UseCases/Commands/DependencyContainer.cs"

# GlobalUsings Commands
@"
global using System.Reflection;
global using $ProjectName.Abstractions.Shared;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/UseCases/Commands/GlobalUsings.cs"

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
"@ | Set-Content "src/UseCases/Queries/DependencyContainer.cs"

# GlobalUsings Queries
@"
global using System.Reflection;
global using $ProjectName.Abstractions.Shared;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/UseCases/Queries/GlobalUsings.cs"

# DependencyContainers

# DependencyContainer class in Validators Project
@"
namespace $ProjectName.Validators
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddValidators(this IServiceCollection services)
        {  
             services.AddServicesCurrentAssembly(onlyClass: true);
             return services;
        }
    }
}
"@ | Set-Content "src/UseCases/Validators/DependencyContainer.cs"

# DependencyContainer class in Infrastructure Projects
$sqlServerDependencyContainer = @"
namespace $ProjectName.SqlServer
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddSqlServer(this IServiceCollection services, IConfiguration configuration)
        { 
            services.Configure<DatabaseConnection>(configuration.GetSection(DatabaseConnection.SectionKey));
            services.AddServicesCurrentAssembly();
            services.ConfigureSerilog();
            return services;
        }
    }
}
"@

$sqlServerSerilogConfiguration = @"
namespace $ProjectName.SqlServer
{
    public static class SerilogConfiguration
    {
        public static IServiceCollection ConfigureSerilog(this IServiceCollection services)
        {
            services.AddSerilog((serviceProvider, configuration) =>
            {             
                configuration.ReadFrom.Configuration(serviceProvider.GetRequiredService<IConfiguration>())
                             .Enrich.FromLogContext()
                             .Enrich.WithProperty("Application", "$ProjectName")                   
                             .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {SourceContext} {Message:lj}{NewLine}{Exception}");
            });

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
        public static IServiceCollection AddMySql(this IServiceCollection services, IConfiguration configuration)
        {
            services.Configure<DatabaseConnection>(configuration.GetSection(DatabaseConnection.SectionKey));
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
        public static IServiceCollection AddPostgreSql(this IServiceCollection services, IConfiguration configuration)
        {
            services.Configure<DatabaseConnection>(configuration.GetSection(DatabaseConnection.SectionKey));
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
        public static IServiceCollection AddOracle(this IServiceCollection services, IConfiguration configuration)
        {
            services.Configure<DatabaseConnection>(configuration.GetSection(DatabaseConnection.SectionKey));
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
        public static IServiceCollection AddMongoDb(this IServiceCollection services, IConfiguration configuration)
        {
            services.Configure<DatabaseConnection>(configuration.GetSection(DatabaseConnection.SectionKey));
            services.AddServicesCurrentAssembly();
            return services;
        }
    }
}
"@

$mongoDbGlobalUsings = @"
global using System.Reflection;
global using $ProjectName.Abstractions.Shared;
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using $ProjectName.MongoDb.Models;

"@

if ($USE_SQLSERVER) {
    $sqlServerDependencyContainer | Set-Content "src/Frameworks/DataBases/SQLServer/DependencyContainer.cs"
    $sqlServerSerilogConfiguration | Set-Content "src/Frameworks/DataBases/SQLServer/SerilogConfiguration.cs"
    New-Item -ItemType Directory -Path "src/Frameworks/DataBases/SQLServer/Models" -Force | Out-Null
    @"
namespace $ProjectName.SqlServer.Models
{
    public sealed class DatabaseConnection
    {   
        public const string SectionKey = "DatabaseConnection:SQLServer";
        public string User { get; set; }
        public string Password { get; set; }
        public int Port { get; set; } = 1433;
        public string Server { get; set; }
        public string Database { get; set; }

        public string ConnectionString => `$"Server={Server},{Port};Database={Database};User Id={User};Password={Password};MultipleActiveResultSets=true;encrypt=false;";
    }
}
"@ | Set-Content "src/Frameworks/DataBases/SQLServer/Models/DatabaseConnection.cs"
}
if ($USE_MYSQL) {
    $mySqlDependencyContainer | Set-Content "src/Frameworks/DataBases/MySQL/DependencyContainer.cs"
    New-Item -ItemType Directory -Path "src/Frameworks/DataBases/MySQL/Models" -Force | Out-Null
    @"
namespace $ProjectName.MySql.Models
{
    public sealed class DatabaseConnection
    {
        public const string SectionKey = "DatabaseConnection:MySql";
        public string User { get; set; }
        public string Password { get; set; }
        public int Port { get; set; } = 3306;
        public string Server { get; set; }
        public string Database { get; set; }

        public string ConnectionString => `$"Server={Server};Port={Port};Database={Database};User Id={User};Password={Password};";
    }
}
"@ | Set-Content "src/Frameworks/DataBases/MySQL/Models/DatabaseConnection.cs"
}
if ($USE_POSTGRES) {
    $postgreSqlDependencyContainer | Set-Content "src/Frameworks/DataBases/PostgreSQL/DependencyContainer.cs"
    New-Item -ItemType Directory -Path "src/Frameworks/DataBases/PostgreSQL/Models" -Force | Out-Null
    @"
namespace $ProjectName.PostgreSql.Models
{
    public sealed class DatabaseConnection
    {
        public const string SectionKey = "DatabaseConnection:PostgreSql";
        public string User { get; set; }
        public string Password { get; set; }
        public int Port { get; set; } = 5432;
        public string Server { get; set; }
        public string Database { get; set; }

        public string ConnectionString => `$"Host={Server};Port={Port};Database={Database};Username={User};Password={Password};";
    }
}
"@ | Set-Content "src/Frameworks/DataBases/PostgreSQL/Models/DatabaseConnection.cs"
}
if ($USE_ORACLE) {
    $oracleDependencyContainer | Set-Content "src/Frameworks/DataBases/Oracle/DependencyContainer.cs"
    New-Item -ItemType Directory -Path "src/Frameworks/DataBases/Oracle/Models" -Force | Out-Null
    @"
namespace $ProjectName.Oracle.Models
{
    public sealed class DatabaseConnection
    {
        public const string SectionKey = "DatabaseConnection:Oracle";
        public string User { get; set; }
        public string Password { get; set; }
        public int Port { get; set; } = 1521;
        public string Server { get; set; }
        public string Database { get; set; }

        public string ConnectionString => `$"Data Source=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST={Server})(PORT={Port}))(CONNECT_DATA=(SERVICE_NAME={Database})));User Id={User};Password={Password};";
    }
}
"@ | Set-Content "src/Frameworks/DataBases/Oracle/Models/DatabaseConnection.cs"
}
if ($USE_MONGO) {
    $mongoDbDependencyContainer | Set-Content "src/Frameworks/DataBases/MongoDB/DependencyContainer.cs"
    $mongoDbGlobalUsings | Set-Content "src/Frameworks/DataBases/MongoDB/GlobalUsings.cs"
    New-Item -ItemType Directory -Path "src/Frameworks/DataBases/MongoDB/Models" -Force | Out-Null
    @"
namespace $ProjectName.MongoDb.Models
{
    public sealed class DatabaseConnection
    {
        public const string SectionKey = "DatabaseConnection:MongoDb";
        public string User { get; set; }
        public string Password { get; set; }
        public int Port { get; set; } = 27017;
        public string Server { get; set; }
        public string Database { get; set; }

        public string ConnectionString => `$"mongodb://{User}:{Password}@{Server}:{Port}/{Database}";
    }
}
"@ | Set-Content "src/Frameworks/DataBases/MongoDB/Models/DatabaseConnection.cs"
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
global using $ProjectName.Abstractions.Shared;
global using Microsoft.Extensions.DependencyInjection;

"@

if ($USE_RABBITMQ) {
    $rabbitMqDependencyContainer | Set-Content "src/Frameworks/Messaging/RabbitMQ/DependencyContainer.cs"
    $rabbitMqGlobalUsings | Set-Content "src/Frameworks/Messaging/RabbitMQ/GlobalUsings.cs"
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
global using $ProjectName.Abstractions.Shared;
global using Microsoft.Extensions.DependencyInjection;

"@

if ($USE_EXTERNAL_APIS) {
    $webApisDependencyContainer | Set-Content "src/Adapters/WebApis/DependencyContainer.cs"
    $webApisGlobalUsings | Set-Content "src/Adapters/WebApis/GlobalUsings.cs"
}

if ($USE_REDIS) {
    New-Item -ItemType Directory -Path "src/Frameworks/Redis/Options", "src/UseCases/Abstractions/Caching" -Force | Out-Null

    @"
global using System.Linq.Expressions;
global using System.Reflection;
global using System.Text.Json;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Options;
global using StackExchange.Redis;
global using $ProjectName.Abstractions.Caching;
global using $ProjectName.Redis.Options;
"@ | Set-Content "src/Frameworks/Redis/GlobalUsings.cs"

    @"
namespace $ProjectName.Redis;

public static class DependencyContainer
{
    public static IServiceCollection AddRedisCache(this IServiceCollection services)
    {
        services.AddSingleton<IConnectionMultiplexer>(provider =>
        {
            RedisOptions options = provider.GetRequiredService<IOptions<RedisOptions>>().Value;
            ConfigurationOptions configuration = ConfigurationOptions.Parse(options.ConnectionRedis);
            configuration.ConnectRetry = 3;
            configuration.SyncTimeout = 10000;
            configuration.AbortOnConnectFail = true;
            configuration.KeepAlive = 180;
            return ConnectionMultiplexer.Connect(configuration);
        });
        services.AddSingleton<ICacheGateway, CacheGateway>();
        return services;
    }
}
"@ | Set-Content "src/Frameworks/Redis/DependencyContainer.cs"

    @"
namespace $ProjectName.Redis.Options;

public class RedisOptions
{
    public const string SectionKey = nameof(RedisOptions);
    public string ConnectionRedis { get; set; }
    public string Environment { get; set; }
    public int DiasCache { get; set; }
}
"@ | Set-Content "src/Frameworks/Redis/Options/RedisOptions.cs"

    @"
using System.Linq.Expressions;

namespace $ProjectName.Abstractions.Caching;

public interface ICacheGateway
{
    Task<T> GetOrSetAsync<T>(Expression<Func<Task<T>>> expression);
    Task InvalidateAsync(params Expression[] expressions);
}
"@ | Set-Content "src/UseCases/Abstractions/Caching/ICacheGateway.cs"

    $redisCacheGateway = @'
namespace __PROJECT_NAME__.Redis;

internal class CacheGateway : ICacheGateway
{
    private readonly IOptions<RedisOptions> RedisOptions;
    private readonly IDatabase DataBase;

    public CacheGateway(IOptions<RedisOptions> redisOptions, IConnectionMultiplexer connection)
    {
        RedisOptions = redisOptions;
        DataBase = connection.GetDatabase();
    }

    public async Task<T> GetOrSetAsync<T>(Expression<Func<Task<T>>> expression)
    {
        string fullKey = BuildKey(ExpressionConditionExtractor.BuildRedisKey(expression));
        RedisValue cached = await DataBase.StringGetAsync(fullKey);
        if (cached.HasValue)
        {
            return JsonSerializer.Deserialize<T>((string)cached);
        }

        T value = await expression.Compile()();
        if (IsNullOrEmpty(value))
        {
            return value;
        }

        TimeSpan effectiveTtl = TimeSpan.FromDays(Math.Max(0, RedisOptions.Value.DiasCache));
        if (effectiveTtl > TimeSpan.Zero)
        {
            await DataBase.StringSetAsync(fullKey, JsonSerializer.Serialize(value), effectiveTtl);
        }
        return value;
    }

    public async Task InvalidateAsync(params Expression[] expressions)
    {
        if (expressions == null || expressions.Length == 0)
        {
            return;
        }

        IEnumerable<Task<bool>> tasks = expressions.OfType<LambdaExpression>()
            .Select(lambda => DataBase.KeyDeleteAsync(BuildKey(ExpressionConditionExtractor.BuildRedisKey(lambda))));
        await Task.WhenAll(tasks);
    }

    private static bool IsNullOrEmpty<T>(T value) => value switch
    {
        null => true,
        string text => string.IsNullOrWhiteSpace(text),
        System.Collections.IEnumerable enumerable => !enumerable.Cast<object>().Any(),
        _ => false
    };

    private string BuildKey(string key) => $"{RedisOptions.Value.Environment}|{key}";
}
'@
    $redisCacheGateway.Replace('__PROJECT_NAME__', $ProjectName) | Set-Content "src/Frameworks/Redis/CacheGateway.cs"

    $redisExpressionConditionExtractor = @'
namespace __PROJECT_NAME__.Redis;

public class ExpressionConditionExtractor : ExpressionVisitor
{
    public List<(string Property, string Operator, object Value)> Conditions { get; } = new();

    public static string BuildRedisKey(LambdaExpression expression, int pageNumber = 0)
    {
        List<string> keyParts = expression.ReturnType == typeof(bool)
            ? GetPredicateParts(expression)
            : GetMethodCallParts(expression);
        if (pageNumber > 0)
        {
            keyParts.Add($"Page:{pageNumber}");
        }
        return string.Join(":", keyParts);
    }

    protected override Expression VisitBinary(BinaryExpression binaryExpression)
    {
        if (binaryExpression.Left is MemberExpression memberExpression)
        {
            Conditions.Add((memberExpression.Member.Name, binaryExpression.NodeType.ToString(), GetValue(binaryExpression.Right)));
        }
        return base.VisitBinary(binaryExpression);
    }

    protected override Expression VisitMethodCall(MethodCallExpression methodCallExpression)
    {
        if (methodCallExpression.Object is MemberExpression memberExpression)
        {
            object argumentValue = methodCallExpression.Arguments.Count > 0
                ? GetValue(methodCallExpression.Arguments[0]) : null;
            Conditions.Add((memberExpression.Member.Name, methodCallExpression.Method.Name, argumentValue));
        }
        return base.VisitMethodCall(methodCallExpression);
    }

    private static List<string> GetPredicateParts(LambdaExpression expression)
    {
        ExpressionConditionExtractor extractor = new();
        extractor.Visit(expression.Body);
        List<string> parts = extractor.Conditions.OrderBy(condition => condition.Property)
            .ThenBy(condition => condition.Operator)
            .Select(condition => $"{condition.Property}{NormalizeOperator(condition.Operator)}{FormatValue(condition.Value)}")
            .ToList();
        return parts.Count > 0 ? parts : new List<string> { "ALL" };
    }

    private static List<string> GetMethodCallParts(LambdaExpression expression)
    {
        MethodCallExpression methodCall = expression.Body switch
        {
            MethodCallExpression call => call,
            UnaryExpression { Operand: MethodCallExpression call } => call,
            _ => throw new ArgumentException("La expresion debe ser una llamada a un metodo o un predicado.")
        };
        List<string> parts = new()
        {
            methodCall.Method.DeclaringType == null ? "Unknown" : GetCleanTypeName(methodCall.Method.DeclaringType),
            methodCall.Method.Name,
            GetCleanTypeName(methodCall.Method.ReturnType)
        };
        parts.AddRange(methodCall.Arguments.Where(argument => argument.Type != typeof(CancellationToken))
            .Select(argument => FormatValue(GetValue(argument))));
        return parts;
    }

    private static string NormalizeOperator(string operatorName) => operatorName switch
    {
        "Equal" => "=",
        "NotEqual" => "!=",
        "GreaterThan" => ">",
        "GreaterThanOrEqual" => ">=",
        "LessThan" => "<",
        "LessThanOrEqual" => "<=",
        "StartsWith" => "^=",
        "EndsWith" => "=$",
        "Contains" => "*=",
        "In" => "IN",
        "NotIn" => "NOT IN",
        "IsNull" => "IS NULL",
        "IsNotNull" => "IS NOT NULL",
        "Between" => "BETWEEN",
        _ => operatorName
    };

    private static string GetCleanTypeName(Type type)
    {
        if (type == typeof(Task))
        {
            return "Void";
        }
        if (type.IsGenericType && type.GetGenericTypeDefinition() == typeof(Task<>))
        {
            return GetCleanTypeName(type.GetGenericArguments()[0]);
        }
        if (type.IsGenericType)
        {
            string typeName = type.Name.Split('`')[0];
            return $"{typeName}|{string.Join("|", type.GetGenericArguments().Select(GetCleanTypeName))}|";
        }
        return type.Name;
    }

    private static string FormatValue(object value) => value switch
    {
        null => "NULL",
        DateTime dateTime => dateTime.ToString("yyyy-MM-ddTHH:mm:ss"),
        bool boolean => boolean ? "1" : "0",
        string text => text,
        LambdaExpression lambda => BuildRedisKey(lambda),
        Dictionary<string, object> dictionary => string.Join(",", dictionary.Select(pair => $"{pair.Key}|{FormatValue(pair.Value)}")),
        System.Collections.IEnumerable enumerable => $"[{string.Join(",", enumerable.Cast<object>().Select(item => item?.ToString() ?? "NULL"))}]",
        _ => value.ToString()?.Trim()
    };

    private static object GetValue(Expression expression) => expression switch
    {
        ConstantExpression constant => constant.Value,
        MemberExpression member => EvaluateMemberExpression(member),
        UnaryExpression unary => EvaluateUnaryExpression(unary),
        MethodCallExpression methodCall => EvaluateExpression(methodCall),
        ParameterExpression parameter => parameter.Name,
        BinaryExpression binary => EvaluateExpression(binary),
        _ => null
    };

    private static object EvaluateMemberExpression(MemberExpression expression)
    {
        object result = Expression.Lambda(expression).Compile().DynamicInvoke();
        if (result is LambdaExpression)
        {
            return result;
        }
        return result != null && IsComplexType(result.GetType()) ? ExtractProperties(result) : result;
    }

    private static object EvaluateUnaryExpression(UnaryExpression expression)
    {
        try
        {
            return Expression.Lambda(expression).Compile().DynamicInvoke();
        }
        catch
        {
            return GetValue(expression.Operand);
        }
    }

    private static object EvaluateExpression(Expression expression)
    {
        try
        {
            return Expression.Lambda(expression).Compile().DynamicInvoke();
        }
        catch
        {
            return null;
        }
    }

    private static bool IsComplexType(Type type)
    {
        bool isSimple = type.IsPrimitive || type.IsEnum || type == typeof(string) || type == typeof(decimal)
            || type == typeof(DateTime) || type == typeof(DateTimeOffset) || type == typeof(TimeSpan) || type == typeof(Guid);
        return !isSimple && !typeof(System.Collections.IEnumerable).IsAssignableFrom(type);
    }

    private static Dictionary<string, object> ExtractProperties(object source)
    {
        Dictionary<string, object> properties = new();
        foreach (PropertyInfo property in source.GetType().GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            if (property.PropertyType == typeof(CancellationToken))
            {
                continue;
            }
            try
            {
                properties[property.Name] = property.GetValue(source);
            }
            catch
            {
                properties[property.Name] = null;
            }
        }
        return properties;
    }
}
'@
    $redisExpressionConditionExtractor.Replace('__PROJECT_NAME__', $ProjectName) | Set-Content "src/Frameworks/Redis/ExpressionConditionExtractor.cs"
}

# Azure Key Vault project (opcional)
$azureKeyVaultDependencyContainer = @"
namespace $ProjectName.AzureKeyVault
{
    public static class DependencyContainer
    {
        public static IServiceCollection AddAzureKeyVault(this IServiceCollection services)
        {
            services.AddSingleton<IKeyVaultSecretProvider, KeyVaultSecretProvider>();
            return services;
        }
    }
}
"@

$azureKeyVaultGlobalUsings = @"
global using System;
global using System.Collections.Concurrent;
global using System.Reflection;
global using System.Text.Json;
global using System.Threading;
global using System.Threading.Tasks;
global using Azure.Core;
global using Azure.Identity;
global using Azure.Security.KeyVault.Secrets;
global using $ProjectName.Abstractions.Shared;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Options;
global using $ProjectName.AzureKeyVault.Options;
global using $ProjectName.AzureKeyVault.Providers;

"@

$azureKeyVaultOptions = @"
namespace $ProjectName.AzureKeyVault.Options
{
    public class KeyVaultOptions
    {
        public const string SectionKey = nameof(KeyVaultOptions);
        public string ClientID { get; set; }
        public string KeyVaultName { get; set; }
        public string SecretName { get; set; }
    }
}
"@

$azureKeyVaultSecretProviderInterface = @"
namespace $ProjectName.AzureKeyVault.Providers
{
    /// <summary>
    /// Define el contrato para obtener secretos de Azure Key Vault.
    /// Permite sustituir la implementación y facilita las pruebas unitarias.
    /// </summary>
    public interface IKeyVaultSecretProvider
    {
        /// <summary>
        /// Obtiene el valor en texto del secreto configurado en KeyVaultOptions.
        /// </summary>
        /// <param name="cancellationToken">Token de cancelación.</param>
        /// <returns>Valor del secreto.</returns>
        Task<string> GetSecretAsync(CancellationToken cancellationToken = default);

        /// <summary>
        /// Obtiene el valor en texto del secreto indicado.
        /// </summary>
        /// <param name="keyVaultName">Nombre del Key Vault (sin .vault.azure.net).</param>
        /// <param name="secretName">Nombre del secreto.</param>
        /// <param name="cancellationToken">Token de cancelación.</param>
        /// <returns>Valor del secreto.</returns>
        Task<string> GetSecretAsync(string keyVaultName, string secretName, CancellationToken cancellationToken = default);

        /// <summary>
        /// Obtiene un secreto del Key Vault indicado y lo deserializa.
        /// </summary>
        /// <typeparam name="T">Tipo esperado del JSON del secreto.</typeparam>
        /// <param name="keyVaultName">Nombre del Key Vault (sin .vault.azure.net).</param>
        /// <param name="secretName">Nombre del secreto.</param>
        /// <param name="cancellationToken">Token de cancelación.</param>
        /// <returns>Instancia deserializada o null si no se pudo obtener.</returns>
        Task<T> GetSecretAsync<T>(string keyVaultName, string secretName, CancellationToken cancellationToken = default) where T : class;
    }
}
"@

$azureKeyVaultSecretProvider = @"
namespace $ProjectName.AzureKeyVault.Providers
{
    /// <summary>
    /// Proveedor de secretos de Azure Key Vault para uso interno de la capa Frameworks
    /// (connection strings, credenciales de herramientas de infraestructura o
    /// servicios externos). Es un detalle técnico, no un puerto del núcleo;
    /// la interfaz facilita las pruebas y la sustitución de la implementación.
    /// </summary>
    public sealed class KeyVaultSecretProvider : IKeyVaultSecretProvider
    {
        private static readonly JsonSerializerOptions SerializerOptions = new()
        {
            PropertyNameCaseInsensitive = true
        };

        private readonly ConcurrentDictionary<string, SecretClient> Clients = new();
        private readonly TokenCredential Credential;
        private readonly KeyVaultOptions Options;

        /// <summary>
        /// Inicializa el proveedor con la configuración de Key Vault especificada.
        /// </summary>
        public KeyVaultSecretProvider(IOptions<KeyVaultOptions> options)
        {
            ArgumentNullException.ThrowIfNull(options);
            ArgumentNullException.ThrowIfNull(options.Value);
            Options = options.Value;
            Credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
            {
                ManagedIdentityClientId = Options.ClientID
            });
        }

        /// <summary>
        /// Obtiene el valor en texto del secreto configurado en KeyVaultOptions.
        /// </summary>
        /// <param name="cancellationToken">Token de cancelación.</param>
        /// <returns>Valor del secreto.</returns>
        public Task<string> GetSecretAsync(CancellationToken cancellationToken = default)
        {
            return GetSecretAsync(Options.KeyVaultName, Options.SecretName, cancellationToken);
        }

        /// <summary>
        /// Obtiene el valor en texto del secreto indicado.
        /// </summary>
        /// <param name="keyVaultName">Nombre del Key Vault (sin .vault.azure.net).</param>
        /// <param name="secretName">Nombre del secreto.</param>
        /// <param name="cancellationToken">Token de cancelación.</param>
        /// <returns>Valor del secreto.</returns>
        public async Task<string> GetSecretAsync(string keyVaultName, string secretName, CancellationToken cancellationToken = default)
        {
            ArgumentException.ThrowIfNullOrWhiteSpace(keyVaultName);
            ArgumentException.ThrowIfNullOrWhiteSpace(secretName);

            SecretClient client = Clients.GetOrAdd(keyVaultName, name => new SecretClient(new Uri(`$"https://{name}.vault.azure.net/"), Credential));

            Azure.Response<KeyVaultSecret> response = await client.GetSecretAsync(secretName, cancellationToken: cancellationToken).ConfigureAwait(false);
            return response.Value.Value;
        }

        /// <summary>
        /// Obtiene un secreto del Key Vault indicado y lo deserializa.
        /// </summary>
        /// <typeparam name="T">Tipo esperado del JSON del secreto.</typeparam>
        /// <param name="keyVaultName">Nombre del Key Vault (sin .vault.azure.net).</param>
        /// <param name="secretName">Nombre del secreto.</param>
        /// <param name="cancellationToken">Token de cancelación.</param>
        /// <returns>Instancia deserializada o null si no se pudo obtener.</returns>
        public async Task<T> GetSecretAsync<T>(string keyVaultName, string secretName, CancellationToken cancellationToken = default) where T : class
        {
            string json = await GetSecretAsync(keyVaultName, secretName, cancellationToken).ConfigureAwait(false);
            return JsonSerializer.Deserialize<T>(json, SerializerOptions);
        }
    }
}
"@

if ($USE_KEYVAULT) {
    New-Item -ItemType Directory -Path "src/Frameworks/AzureKeyVault/Models" -Force | Out-Null
    New-Item -ItemType Directory -Path "src/Frameworks/AzureKeyVault/Options" -Force | Out-Null
    New-Item -ItemType Directory -Path "src/Frameworks/AzureKeyVault/Providers" -Force | Out-Null
    "" | Set-Content "src/Frameworks/AzureKeyVault/Models/.gitkeep"
    $azureKeyVaultDependencyContainer | Set-Content "src/Frameworks/AzureKeyVault/DependencyContainer.cs"
    $azureKeyVaultGlobalUsings | Set-Content "src/Frameworks/AzureKeyVault/GlobalUsings.cs"
    $azureKeyVaultOptions | Set-Content "src/Frameworks/AzureKeyVault/Options/KeyVaultOptions.cs"
    $azureKeyVaultSecretProviderInterface | Set-Content "src/Frameworks/AzureKeyVault/Providers/IKeyVaultSecretProvider.cs"
    $azureKeyVaultSecretProvider | Set-Content "src/Frameworks/AzureKeyVault/Providers/KeyVaultSecretProvider.cs"
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
            $(if($USE_REDIS){"services.Configure<RedisOptions>(configuration.GetSection(RedisOptions.SectionKey));"})
            $(if($USE_KEYVAULT){"services.Configure<KeyVaultOptions>(configuration.GetSection(KeyVaultOptions.SectionKey));"})
            services.AddJwtServices(options => configuration.GetSection(JwtOptions.SectionKey).Bind(options));
            $(if($USE_REDIS){"services.AddRedisCache();"})

            services.AddCommands()
                    .AddQueries()
                    .AddValidators()$(if($USE_SQLSERVER){"`n                    .AddSqlServer(configuration)"})$(if($USE_MYSQL){"`n                    .AddMySql(configuration)"})$(if($USE_POSTGRES){"`n                    .AddPostgreSql(configuration)"})$(if($USE_ORACLE){"`n                    .AddOracle(configuration)"})$(if($USE_MONGO){"`n                    .AddMongoDb(configuration)"})$(if($USE_RABBITMQ){"`n                    .AddRabbitMq()"})$(if($USE_EXTERNAL_APIS){"`n                    .AddWebApis()"})$(if($USE_KEYVAULT){"`n                    .AddAzureKeyVault()"});
            return services;
        }
    }
}
"@ | Set-Content "src/Frameworks/IoC/DependencyContainer.cs"

# GlobalUsings

# GlobalUsings Validators
$validatorsGlobalUsings = @"
global using System.Reflection;
global using $ProjectName.Abstractions.Shared;
global using Microsoft.Extensions.DependencyInjection;
global using System;

"@

$validatorsGlobalUsings | Set-Content "src/UseCases/Validators/GlobalUsings.cs"

# GlobalUsings Infrastructure
$dbGlobalUsings = @"
global using System.Reflection;
global using $ProjectName.Abstractions.Shared;
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using System;
global using __MODELS_NAMESPACE__;

"@

if ($USE_SQLSERVER) {
    $sqlServerGlobalUsings = @"
global using System.Reflection;
global using $ProjectName.Abstractions.Shared;
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using Serilog;
global using Serilog.Sinks.MSSqlServer;
global using System;
global using System.Data;
global using $ProjectName.SqlServer.Models;
$(if($USE_KEYVAULT){"global using $ProjectName.AzureKeyVault.Providers;"})

"@
    $sqlServerGlobalUsings | Set-Content "src/Frameworks/DataBases/SQLServer/GlobalUsings.cs"
}
if ($USE_MYSQL) {
    $dbGlobalUsings.Replace('__MODELS_NAMESPACE__', "$ProjectName.MySql.Models") | Set-Content "src/Frameworks/DataBases/MySQL/GlobalUsings.cs"
}
if ($USE_POSTGRES) {
    $dbGlobalUsings.Replace('__MODELS_NAMESPACE__', "$ProjectName.PostgreSql.Models") | Set-Content "src/Frameworks/DataBases/PostgreSQL/GlobalUsings.cs"
}
if ($USE_ORACLE) {
    $dbGlobalUsings.Replace('__MODELS_NAMESPACE__', "$ProjectName.Oracle.Models") | Set-Content "src/Frameworks/DataBases/Oracle/GlobalUsings.cs"
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
$(if($USE_KEYVAULT){"global using $ProjectName.AzureKeyVault;"})
$(if($USE_KEYVAULT){"global using $ProjectName.AzureKeyVault.Options;"})
global using $ProjectName.IoC.Options;
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using DevKit.JWT.Extensions;
global using DevKit.JWT.Options;
$(if($USE_REDIS){"global using $ProjectName.Redis;"})
$(if($USE_REDIS){"global using $ProjectName.Redis.Options;"})

"@
$iocGlobalUsings | Set-Content "src/Frameworks/IoC/GlobalUsings.cs"

# GlobalUsings Abstractions
@"
global using System;
global using System.Collections.Generic;
global using System.Linq;
global using System.Reflection;
global using Microsoft.Extensions.DependencyInjection;

"@ | Set-Content "src/UseCases/Abstractions/GlobalUsings.cs"

# GlobalUsings Controllers
$controllersGlobalUsings = @"
global using Microsoft.AspNetCore.Mvc;
global using Microsoft.AspNetCore.Http;
"@
$controllersGlobalUsings | Set-Content "src/Adapters/Controllers/GlobalUsings.cs"

# GlobalUsings Entities
$domainGlobalUsings = @"
"@
$domainGlobalUsings | Set-Content "src/Entities/GlobalUsings.cs"

# Options classes in IoC
New-Item -ItemType Directory -Path "src/Frameworks/IoC/Options" -Force | Out-Null

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
$environmentOptions | Set-Content "src/Frameworks/IoC/Options/EnvironmentOptions.cs"

# GlobalUsings Api
$apiGlobalUsings = @"
global using Microsoft.AspNetCore.Builder;
global using Microsoft.AspNetCore.Http;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Logging;
global using System.Text.Json.Serialization;
global using $ProjectName.IoC;
global using Microsoft.OpenApi;
global using Microsoft.AspNetCore.Mvc;
global using $ProjectName.WebApi.Configurations;
global using $ProjectName.WebApi.Middleware;
global using $ProjectName.IoC.Options;
global using System;

"@
$apiGlobalUsings | Set-Content "src/Frameworks/WebApi/GlobalUsings.cs"

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
"@ | Set-Content "src/Frameworks/WebApi/Configurations/MiddlewaresConfiguration.cs"
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
"@ | Set-Content "src/Frameworks/WebApi/Configurations/ServicesConfiguration.cs"

@"
namespace $ProjectName.WebApi.Middleware
{
    public class ErrorHandlerMiddleware(RequestDelegate next, ILogger<ErrorHandlerMiddleware> logger)
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
                    logger.LogError(exception, "La respuesta ya comenz�. El error no se devuelve al cliente. {TraceId}", context.TraceIdentifier);
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
                logger.LogError(exception, "Error occurred with details {@ProblemDetails}", problemDetails);

                response.StatusCode = statusCode;
                await context.Response.WriteAsJsonAsync(problemDetails, CancellationToken.None);
            }
        }
    }
}
"@ | Set-Content "src/Frameworks/WebApi/Middleware/ErrorHandlerMiddleware.cs"

# Minimal API starter
@"
WebApplication.CreateBuilder(args)
    .ConfigureWebApiServices()
    .ConfigureWebApiMiddlewares()
    .Run();
"@ | Set-Content "src/Frameworks/WebApi/Program.cs"

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
COPY src/Frameworks/WebApi/$ProjectName.WebApi.csproj src/Frameworks/WebApi/
COPY src/UseCases/Abstractions/$ProjectName.Abstractions.csproj src/UseCases/Abstractions/
COPY src/UseCases/Commands/$ProjectName.Commands.csproj src/UseCases/Commands/
COPY src/Adapters/Controllers/$ProjectName.Controllers.csproj src/Adapters/Controllers/
COPY src/Entities/$ProjectName.Entities.csproj src/Entities/
$(if($USE_SQLSERVER){"COPY src/Frameworks/DataBases/SQLServer/$ProjectName.SqlServer.csproj src/Frameworks/DataBases/SQLServer/"})
$(if($USE_MYSQL){"COPY src/Frameworks/DataBases/MySQL/$ProjectName.MySql.csproj src/Frameworks/DataBases/MySQL/"})
$(if($USE_POSTGRES){"COPY src/Frameworks/DataBases/PostgreSQL/$ProjectName.PostgreSql.csproj src/Frameworks/DataBases/PostgreSQL/"})
$(if($USE_ORACLE){"COPY src/Frameworks/DataBases/Oracle/$ProjectName.Oracle.csproj src/Frameworks/DataBases/Oracle/"})
$(if($USE_MONGO){"COPY src/Frameworks/DataBases/MongoDB/$ProjectName.MongoDb.csproj src/Frameworks/DataBases/MongoDB/"})
COPY src/Frameworks/IoC/$ProjectName.IoC.csproj src/Frameworks/IoC/
COPY src/UseCases/Models/$ProjectName.Models.csproj src/UseCases/Models/
COPY src/UseCases/Queries/$ProjectName.Queries.csproj src/UseCases/Queries/
COPY src/UseCases/Validators/$ProjectName.Validators.csproj src/UseCases/Validators/
$(if($USE_RABBITMQ){"COPY src/Frameworks/Messaging/RabbitMQ/$ProjectName.RabbitMQ.csproj src/Frameworks/Messaging/RabbitMQ/"})
$(if($USE_EXTERNAL_APIS){"COPY src/Adapters/WebApis/$ProjectName.WebApis.csproj src/Adapters/WebApis/"})
$(if($USE_REDIS){"COPY src/Frameworks/Redis/$ProjectName.Redis.csproj src/Frameworks/Redis/"})
$(if($USE_KEYVAULT){"COPY src/Frameworks/AzureKeyVault/$ProjectName.AzureKeyVault.csproj src/Frameworks/AzureKeyVault/"})

# Restore dependencies
RUN dotnet restore src/Frameworks/WebApi/$ProjectName.WebApi.csproj

# Copy all source code
COPY . .

# Build project
WORKDIR /src/src/Frameworks/WebApi
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
# docker build -f src/Frameworks/WebApi/Dockerfile -t "$($ProjectName.ToLower())-api:latest" .
# docker container rm -f "$($ProjectName.ToLower())-api"
# docker run -d --name "$($ProjectName.ToLower())-api" -p $($DockerPort1):8080 "$($ProjectName.ToLower())-api:latest"

"@ | Set-Content "src/Frameworks/WebApi/Dockerfile"

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
            chmod +x src/Frameworks/WebApi/deploy.sh
            ./src/Frameworks/WebApi/deploy.sh
        failOnStdErr: false
'@ | Set-Content "src/Frameworks/WebApi/azure-pipelines.yml"

$projectDirName = "api-$($ProjectName.ToLower())"
$projectSlug = $ProjectName.ToLower().Replace('.', '-').Replace('_', '-')
$azurePipelinesContent = Get-Content -Raw "src/Frameworks/WebApi/azure-pipelines.yml"
$azurePipelinesContent = $azurePipelinesContent.Replace("__PROJECT_DIR__", $projectDirName).Replace("__PROJECT_NAME__", $ProjectName)
$azurePipelinesContent | Set-Content "src/Frameworks/WebApi/azure-pipelines.yml"

# deploy.sh
$deployScript = @'
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
'@

$deployDir = Split-Path "src/Frameworks/WebApi/deploy.sh" -Parent
if (-not (Test-Path $deployDir)) {
    New-Item -ItemType Directory -Path $deployDir -Force | Out-Null
}
$deployScript | Set-Content "src/Frameworks/WebApi/deploy.sh"

if (Test-Path "src/Frameworks/WebApi/deploy.sh") {
    $deployScriptContent = Get-Content -Raw "src/Frameworks/WebApi/deploy.sh"
    if ($deployScriptContent) {
        $deployScriptContent = $deployScriptContent.Replace("__PROJECT_DIR__", $projectDirName).Replace("__PROJECT_NAME__", $ProjectName).Replace("__PROJECT_SLUG__", $projectSlug).Replace("__DOCKER_PORT_1__", "$DockerPort1").Replace("__DOCKER_PORT_2__", "$DockerPort2").Replace("__DOCKER_PORT_3__", "$DockerPort3").Replace("__DOCKER_PORT_4__", "$DockerPort4")
        $deployScriptContent | Set-Content "src/Frameworks/WebApi/deploy.sh"
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
│  Frameworks & Drivers (detalles técnicos)               │
│  ASP.NET Core host, EF Core, Redis, RabbitMQ, IoC...    │  ← capa externa
├─────────────────────────────────────────────────────────┤
│  Interface Adapters (adaptadores)                       │
│  Controllers, gateways de APIs externas...              │
├─────────────────────────────────────────────────────────┤
│  Use Cases (reglas de aplicación)                       │
│  Commands, queries, use cases, validaciones, DTOs...    │
├─────────────────────────────────────────────────────────┤
│  Entities (reglas de negocio de empresa)                │
│  Entidades, value objects, interfaces de puertos...     │  ← centro
└─────────────────────────────────────────────────────────┘
```

> **Regla:** las flechas de dependencia apuntan hacia abajo. La capa de
> arriba puede conocer a la de abajo, pero nunca al revés.

### 2.1 Entities — el centro

Contiene las reglas de negocio puras (enterprise business rules). No
conoce ASP.NET Core, EF Core, HTTP, JSON, etc.

- `Entities/`: objetos con identidad (`Order`, `User`).
- `ValueObjects/`: objetos inmutables (`Email`, `Money`).
- `Enums/`: enumeraciones de negocio.
- `Interfaces/`: **puertos** que expresan lo que el negocio necesita,
  p. ej. `IOrderRepository`, `IEmailSender`.

**Regla:** si tienes que importar `Microsoft.EntityFrameworkCore` aquí,
algo está mal.

### 2.2 Use Cases — las reglas de aplicación

Orquesta las entidades para resolver una necesidad concreta del usuario.

- `Commands/`: comandos que mutan estado (`CreateOrderCommand`).
- `Queries/`: consultas que leen estado (`GetOrderByIdQuery`).
- `Models/`: DTOs y modelos de transporte entre capas.
- `Validators/`: reglas de validación de entrada con FluentValidation.
- `Abstractions/`: proyecto de puertos de entrada y salida de la aplicación,
  como contratos de casos de uso, `IUnitOfWork` e `ICacheGateway`.
  Referencia Entities y Models, nunca adaptadores ni frameworks.

Commands y Queries referencian Abstractions y Models. Los adaptadores
referencian Abstractions para implementar estos puertos y acceder a sus DTOs.
Los puertos propios del negocio permanecen en Entities/Interfaces.

Un caso de uso no sabe que existe `DbContext`; solo conoce interfaces.

### 2.3 Interface Adapters — los adaptadores

Convierten los datos entre el formato de los casos de uso y el formato
de los agentes externos (web, servicios).

- `Controllers/`: controladores ASP.NET Core que exponen endpoints HTTP.
- `WebApis/`: gateways que implementan puertos consumiendo APIs externas
  o servicios web.

Los adaptadores implementan puertos de Entities y UseCases, pero no
conocen detalles de frameworks: un controller no sabe qué ORM se usa y
un gateway no sabe cómo se configura el `HttpClient`.

### 2.3.1 Consumo de APIs externas con `IHttpClientFactory`

Cuando la aplicación consuma APIs externas o servicios web, usa
`IHttpClientFactory` en lugar de crear instancias de `HttpClient` a mano.
Registra el factory en la composición raíz con `services.AddHttpClient()`
y utilízalo únicamente dentro de los gateways de Adapters
(`src/Adapters/WebApis`).

Ventajas:

- Evita el agotamiento de sockets por reutilización inadecuada de
  conexiones.
- Centraliza la configuración de clientes mediante clientes nombrados o
  tipados (`AddHttpClient<TClient, TImplementation>`).
- Facilita el registro, resiliencia y tests de los adaptadores HTTP.

> **Regla:** los Controllers y Use Cases no deben inyectar
> `IHttpClientFactory` directamente. Solicitan un puerto definido en
> Entities/UseCases y lo implementa un gateway HTTP en Adapters.

> **Estrategia de persistencia:** por convención, los **Commands**
> (escritura) usan **Entity Framework Core** para aprovechar el
> seguimiento de cambios, validaciones y migraciones. Los **Queries**
> (lectura) usan **Dapper** para leer de forma ligera y eficiente,
> especialmente cuando se proyectan DTOs planos.

### 2.4 Frameworks & Drivers — los detalles

La capa más externa: frameworks, drivers y la composición raíz.

- `WebApi/`: host ASP.NET Core, middlewares, configuraciones, Program.cs.
- `DataBases/`: EF Core, Dapper, repositorios, migraciones, opciones.
  - `SQLServer/`: Implementación específica para SQL Server.
  - `MySQL/`: Implementación específica para MySQL.
  - `PostgreSQL/`: Implementación específica para PostgreSQL.
  - `Oracle/`: Implementación específica para Oracle.
  - `MongoDB/`: Implementación específica para MongoDB.
- `Messaging/`: colas de mensajes (RabbitMQ).
- `Redis/`: caché distribuida.
- `AzureKeyVault/`: gestión de secretos.
- `IoC/`: composición raíz donde se registran implementaciones concretas.

Es la única capa que conoce connection strings, ORM y configuración de
frameworks. Por pragmatismo, las implementaciones de repositorios viven
junto a su tecnología de persistencia (p. ej. `DataBases/SQLServer`);
conceptualmente actúan como gateways hacia la base de datos.

---

## 3. Regla de la dependencia

> Las dependencias del código fuente solo pueden apuntar hacia adentro.

```
Frameworks ──►  Adapters  ──►  UseCases  ──►  Entities
Frameworks ──►  UseCases  ──►  Entities
Frameworks ──►  Entities
```

Nunca al revés:

- ❌ `Entities` no referencia `UseCases`, `Adapters` ni `Frameworks`.
- ❌ `UseCases` no referencia `Adapters` ni `Frameworks`.
- ❌ `Adapters` no referencia `Frameworks`.
- ✅ `Frameworks` sí referencia capas internas.

### 3.1 ¿Cómo se invierte la dependencia?

Ejemplo: crear un pedido necesita persistirlo en base de datos.

1. `Entities/Interfaces/Orders/IOrderRepository.cs` define el puerto.
2. `Frameworks/DataBases/SQLServer/Orders/OrderRepository.cs` implementa el puerto.
3. `UseCases/Commands/Orders/CreateOrder/CreateOrderUseCase.cs` depende
   de `IOrderRepository`.
4. `Frameworks/IoC/DependencyContainer.cs` registra la implementación.
5. `Adapters/Controllers/Orders/OrdersController.cs` expone el endpoint.

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

### 3.2 Constructores e inyección de dependencias

> **Regla de dependencia:** los Controllers y Use Cases solicitan puertos
> del núcleo para acceder a servicios externos; no reciben tipos de
> infraestructura, ORM o clientes HTTP.

✅ Correcto:

```csharp
public class OrdersController : ControllerBase
{
    private readonly ICreateOrderUseCase _createOrder;
    private readonly IGetOrderByIdUseCase _getOrder;

    public OrdersController(
        ICreateOrderUseCase createOrder,
        IGetOrderByIdUseCase getOrder)
    {
        _createOrder = createOrder;
        _getOrder = getOrder;
    }
}
```

❌ Incorrecto:

```csharp
public class OrdersController : ControllerBase
{
    private readonly AppDbContext _dbContext;      // Clase concreta de infraestructura
    private readonly IHttpClientFactory _httpFactory;

    public OrdersController(AppDbContext dbContext, IHttpClientFactory httpFactory)
    {
        _dbContext = dbContext;
        _httpFactory = httpFactory;
    }
}
```

Los adaptadores sí pueden recibir tipos concretos de su tecnología,
como DbContext, HttpClient o clientes de Redis. Estos detalles no deben
aparecer en los contratos del núcleo. Los tipos de valor, DTOs y opciones
no necesitan interfaces por el solo hecho de usarse en un constructor.
Evita IHttpContextAccessor en el núcleo: transmite los datos necesarios
del usuario o de la petición mediante parámetros o puertos de aplicación.

---

## 4. Organización por features (Vertical Slice)

Además de las capas, el código se organiza por **features**. Cada feature
es un caso de uso completo que agrupa todos sus archivos.

No hay una carpeta `Features` a nivel raíz. En su lugar, cada feature usa
subcarpetas con el mismo nombre dentro de cada capa.

### Ejemplo: CreateOrder

```text
src
├── Entities
│   ├── Entities/Orders/
│   │   └── Order.cs
│   └── Interfaces/Orders/
│       └── IOrderRepository.cs
├── UseCases
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
├── Adapters
│   └── Controllers/Orders/
│       └── OrdersController.cs
└── Frameworks
    └── DataBases/SQLServer/Orders/
        └── OrderRepository.cs

tests/UnitTests/Orders/CreateOrder
├── CreateOrderUseCaseTests.cs
└── CreateOrderValidatorTests.cs
```

**Regla de oro:** si necesitas buscar por toda la solución para encontrar
los archivos de una feature, la organización está mal.

## 🔑 Cómo encaja en Hexagonal

- **Entities** → el núcleo: entidades y contratos (puertos).
- **UseCases** → casos de uso (commands, queries, use cases, DTOs, validadores).
- **Adapters** → adaptadores de interfaz (controllers, gateways de APIs externas).
- **Frameworks** → detalles técnicos (persistencia, mensajería, host web, IoC).
- **Tests** → organizados también por feature, validando use cases y reglas.

## ✅ Buenas prácticas

- **Mantener independencia por feature**: cada carpeta de `Orders`, `Customers`, etc. debe contener todo lo necesario para esa funcionalidad.
- **Puertos en el núcleo**: contratos de negocio en Entities/Interfaces;
    contratos de aplicación en UseCases/Abstractions, nunca en Adapters ni Frameworks.
- **Casos de uso en UseCases**: orquestan lógica de negocio usando puertos.
- **Adaptadores en Adapters**: implementan los puertos hacia el exterior
  (`OrdersController`, `OrderGateway`).
- **Persistencia en Frameworks**: los repositorios (`OrderRepository`)
  viven junto a su tecnología (EF Core, Dapper) en `Frameworks/DataBases`.
- **APIs externas con `IHttpClientFactory`**: los gateways HTTP deben
  usar `IHttpClientFactory` registrado mediante `AddHttpClient()`; nunca
  crees instancias de `HttpClient` manualmente.
- **Controllers en Adapters**: exponen los casos de uso hacia el exterior.
- **Tests alineados**: cada feature tiene sus pruebas en la misma estructura.

---

## 5. Estructura de carpetas de esta plantilla

```
/scripts-ps
  new-clean-arch-api.ps1             ← punto de entrada

/{ProjectName}
  /src
    /Entities                          Reglas de negocio de empresa (capa central)
      /Entities
      /ValueObjects
      /Enums
      /Interfaces
    /UseCases                          Reglas de aplicación
      /Abstractions                    Puertos de entrada y salida
        /Caching                       ICacheGateway (si se selecciona Redis)
      /Commands                        Comandos (write side)
      /Queries                         Consultas (read side)
      /Models                          DTOs
      /Validators                      Reglas de validación
    /Adapters                          Interface Adapters
      /Controllers                     Controladores HTTP
      /WebApis                         Gateways hacia APIs externas (opcional)
    /Frameworks                        Frameworks & Drivers
      /WebApi                          ASP.NET Core Web API host
        /Configurations
        /Middleware
        /Properties
      /IoC                             Composición de dependencias
      /DataBases                       Persistencia (EF Core, repositorios)
        /SQLServer                     Implementación SQL Server
        /MySQL                         Implementación MySQL
        /PostgreSQL                    Implementación PostgreSQL
        /Oracle                        Implementación Oracle
        /MongoDB                       Implementación MongoDB
        /Options
      /Messaging/RabbitMQ              Mensajería (opcional)
      /Redis                           Caché distribuida (opcional)
      /AzureKeyVault                   Secretos (opcional)
  /tests
    /UnitTests
  /documentation
    architecture-guide.md
```

Referencias entre proyectos:

| Proyecto        | Referencia a                       |
|-----------------|------------------------------------|
| Entities        | *(ninguna)*                        |
| Models          | Entities                           |
| Abstractions    | Entities, Models                   |
| Commands/Queries | Entities, Abstractions, Models    |
| Validators      | Entities, Commands, Models         |
| Controllers     | UseCases (Commands, Queries, Models, Abstractions) |
| WebApis, DataBases, Messaging, Redis, KeyVault | Entities, Abstractions |
| IoC             | UseCases, Adapters, Frameworks     |
| WebApi (host)   | IoC (Controllers transitivo)       |
| UnitTests       | Entities, UseCases, Validators     |

---

## 6. Flujo de una petición HTTP

```
Cliente HTTP
   │
   ▼
Frameworks/WebApi               (routing, middlewares, swagger)
   │
   ▼
Adapters/Controllers            (endpoint que expone el caso de uso)
   │
   ▼
UseCases/Commands o Queries     (caso de uso)
   │
   ▼
UseCases/Validators             (valida entrada)
   │
   ▼
Entities/Interfaces o UseCases/Abstractions (puerto)
   │
   ▼
Frameworks/DataBases            (EF Core, repositorios)
   │
   ▼
Entities                        (reglas de negocio)
```

Reglas prácticas:

- Los **Controllers** no llaman directamente a `DataBases`; invocan un
  **Use Case** (representado por un `Command` o `Query`).
- Los constructores de los **Controllers** y **Use Cases** solo reciben
  **interfaces**; nunca clases concretas de frameworks.
- Los **Commands** mutan estado (`Create`, `Update`, `Delete`) y
  devuelven el resultado mínimo necesario.
- Los **Queries** solo leen; nunca mutan estado.
- Los **Validators** no acceden a la base de datos.
- **Adapters** y **Frameworks** son las únicas capas que hablan con la BD,
  APIs externas, colas o caché.
- El flujo de retorno mapea entidades a DTOs (`UseCases/Models`) antes
  de salir por el Controller.

---

## 7. ¿Cómo añadir una nueva feature?

Sigue estos pasos para mantener el orden de capas y Vertical Slice:

1. **Entities:** define entidades, value objects e interfaces de puertos.
   - `Entities/Interfaces/{Feature}/I{Feature}Repository.cs`
   - `Entities/Entities/{Feature}/{Entity}.cs`

2. **UseCases:** crea el comando/consulta, caso de uso, validator y DTOs.
   - `UseCases/Abstractions/{Feature}/I{UseCase}.cs` para puertos de entrada.
   - `UseCases/Abstractions/{Feature}/I{Feature}Gateway.cs` para puertos de salida (gateways).
   - `UseCases/Commands/{Feature}/{Action}/{Action}Command.cs` (solo si tiene 2+ parámetros)
   - `UseCases/Commands/{Feature}/{Action}/{Action}UseCase.cs`
   - `UseCases/Commands/{Feature}/{Action}/{Action}Result.cs`
   - `UseCases/Queries/{Feature}/{Action}/{Action}Query.cs` (solo si tiene 2+ parámetros)
   - `UseCases/Queries/{Feature}/{Action}/{Action}UseCase.cs`
   - `UseCases/Validators/{Feature}/{Action}Validator.cs`
   - `UseCases/Models/{Feature}/{Entity}Dto.cs`

3. **Adapters:** crea el endpoint o gateway.
   - `Adapters/Controllers/{Feature}/{Feature}sController.cs`
   - `Adapters/WebApis/{Feature}/{Feature}WebApi.cs` (si consume una API externa)

4. **Frameworks:** implementa el puerto de persistencia.
   - `Frameworks/DataBases/{Provider}/{Feature}/{Entity}Repository.cs`

5. **IoC:** registra la implementación si la inyección automática no la
   encuentra (`Frameworks/IoC/DependencyContainer.cs`).

6. **Tests:** prueba el use case y el validator sin levantar la API ni la
   base de datos real.

> **Tip:** si una feature es muy pequeña, puedes agruparla en una sola
> carpeta por capa (`Auth/`) en lugar de crear una carpeta por acción.

---

## 8. Antipatrones a evitar

- ❌ Lógica de negocio en controladores o endpoints.
- ❌ Usar `DbContext`, `SqlConnection` o instanciar `HttpClient`
  directamente dentro de use cases; usa `IHttpClientFactory` desde
  gateways de Adapters o implementaciones en Frameworks.
- ❌ Definir interfaces de repositorios en Adapters o Frameworks.
- ❌ Exponer entidades de dominio directamente como respuesta HTTP.
- ❌ Crear carpetas genéricas grandes como `Services/`, `Models/`,
  `Helpers/` fuera de una feature.
- ❌ Repositorios genéricos (`IRepository<T>`): cada agregado expone su
  propio puerto (`IOrderRepository`) e implementación (`OrderRepository`).
- ❌ Controllers o use cases que reciban tipos de infraestructura,
    ORM o clientes HTTP en lugar de puertos del núcleo.
- ❌ Contratos de aplicación definidos dentro de adaptadores concretos.
    Los detalles internos de un adaptador no necesitan una interfaz propia.

---

## 9. Beneficios de esta combinación

- **Cambios localizados:** una feature vive junta; tocarla no rompe otras.
- **Testabilidad:** Entities y UseCases se prueban sin frameworks.
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
    foreach ($docPath in @('documentation/README.md', 'documentation/architecture-guide.md', 'documentation/CONTRIBUTING.md')) {
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
├── Entities/                  # Reglas de negocio de empresa (capa central)
├── UseCases/                  # Reglas de aplicación (Commands, Queries, Validators, Models, Abstractions)
├── Adapters/                  # Controllers y gateways de APIs externas
└── Frameworks/                # WebApi host, DataBases, Messaging, Redis, KeyVault, IoC
```

## Configuración

Edita los archivos `appsettings.json` para configurar:
- Connection strings de base de datos
- Configuración de JWT
- Configuración de Redis
- Configuración de RabbitMQ (si aplica)

## Ejecutar

```bash
dotnet run --project src/Frameworks/WebApi
```

## Tests

```bash
dotnet test
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

$endTime = Get-Date
$duration = $endTime - $startTime
$hours = [int]$duration.TotalHours
$minutes = $duration.Minutes
$seconds = $duration.Seconds

Write-Host "Clean Architecture solution created successfully!"
Write-Host "Powered by David Vazquez Palestino" -ForegroundColor DarkGray
Write-Host "Time elapsed: $($hours)h $($minutes)m $($seconds)s" -ForegroundColor Green
