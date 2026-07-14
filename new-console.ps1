# =========================================================================
#  new-console.ps1
#  Powered by David Vázquez Palestino
# =========================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName
)

Write-Host "Creating Console project: $ProjectName"

# Root
New-Item -ItemType Directory -Path $ProjectName | Out-Null
Set-Location $ProjectName

# Solution
dotnet new sln -n "$ProjectName"

# Console project
dotnet new console -n $ProjectName -o "src/$ProjectName"

# Add to solution
dotnet sln add "src/$ProjectName"

# =========================
# ADD PACKAGES
# =========================
dotnet add "src/$ProjectName" package Microsoft.Extensions.Hosting
dotnet add "src/$ProjectName" package Microsoft.Extensions.Configuration
dotnet add "src/$ProjectName" package Microsoft.Extensions.Configuration.Json
dotnet add "src/$ProjectName" package Microsoft.Extensions.Configuration.EnvironmentVariables
dotnet add "src/$ProjectName" package Microsoft.Extensions.Configuration.Binder
dotnet add "src/$ProjectName" package Microsoft.Extensions.DependencyInjection
dotnet add "src/$ProjectName" package Microsoft.Extensions.Options.ConfigurationExtensions
dotnet add "src/$ProjectName" package Microsoft.Extensions.Logging
dotnet add "src/$ProjectName" package Microsoft.Extensions.Logging.Console

# =========================
# CREATE BASE FOLDERS
# =========================
New-Item -ItemType Directory -Path "src/$ProjectName/Options" -Force | Out-Null

# =========================
# CONFIGURE CSPROJ (copy appsettings on build)
# =========================
$csprojPath = "src/$ProjectName/$ProjectName.csproj"
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

# =========================
# CREATE BASIC FILES
# =========================

# appsettings.json
@"
{
    "EnvironmentOptions": {
        "EnvironmentName": "Production"
    },
    "Logging": {
        "LogLevel": {
            "Default": "Information",
            "Microsoft": "Warning"
        }
    }
}
"@ | Set-Content "src/$ProjectName/appsettings.json"

# appsettings.Development.json
@"
{
    "Logging": {
        "LogLevel": {
            "Default": "Debug"
        }
    }
}
"@ | Set-Content "src/$ProjectName/appsettings.Development.json"

# GlobalUsings
@"
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Hosting;
global using Microsoft.Extensions.Logging;
global using Microsoft.Extensions.Options;
global using $ProjectName.Options;
"@ | Set-Content "src/$ProjectName/GlobalUsings.cs"

# EnvironmentOptions
@"
namespace $ProjectName.Options
{
    public class EnvironmentOptions
    {
        public const string SectionKey = nameof(EnvironmentOptions);
        public string EnvironmentName { get; set; } = "Production";
    }
}
"@ | Set-Content "src/$ProjectName/Options/EnvironmentOptions.cs"

# Program.cs (Generic Host + DI + appsettings)
@"
using $ProjectName.Options;

IHostBuilder builder = Host.CreateDefaultBuilder(args)
    .ConfigureAppConfiguration((context, config) =>
    {
        EnvironmentOptions envOptions = config.Build()
            .GetSection(EnvironmentOptions.SectionKey)
            .Get<EnvironmentOptions>() ?? new EnvironmentOptions();

        config.AddJsonFile(`$"appsettings.{envOptions.EnvironmentName}.json", optional: true, reloadOnChange: true);
        config.AddEnvironmentVariables();
    })
    .ConfigureServices((context, services) =>
    {
        services.Configure<EnvironmentOptions>(context.Configuration.GetSection(EnvironmentOptions.SectionKey));
    });

using IHost host = builder.Build();

await host.RunAsync();
"@ | Set-Content "src/$ProjectName/Program.cs"

# Git ignore
dotnet new gitignore

Write-Host "Console project created successfully!"
Write-Host "Powered by David Vázquez Palestino" -ForegroundColor DarkGray
