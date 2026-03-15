# 1. Project Information
$projectName = Read-Host "Enter project name"
$versionInput = Read-Host "Enter Umbraco version (e.g., 17.0.0) or press Enter for latest stable"

$UsrName = Read-Host "Please enter admin Username for Umbraco (default: Admin)"
if ([string]::IsNullOrWhiteSpace($UsrName)) {
    $UsrName = "Admin"
}

$UsrEmail = Read-Host "Please enter admin Email for Umbraco (default: a@b.c)"
if ([string]::IsNullOrWhiteSpace($UsrEmail)) {
    $UsrEmail = "a@b.c"
}

$UsrPassword = Read-Host "Please enter admin Password for Umbraco (default: Password1234!)"
if ([string]::IsNullOrWhiteSpace($UsrPassword)) {
    $UsrPassword = "Password1234!"
}

if ([string]::IsNullOrWhiteSpace($versionInput)) {
    Write-Host "Fetching version list from NuGet..." -ForegroundColor Gray
    try {
        $apiUrl = "https://api.nuget.org/v3-flatcontainer/umbraco.templates/index.json"
        $data = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
        $versionInput = $data.versions | Where-Object { $_ -notlike "*-*" } | Select-Object -Last 1
    } catch {
        Write-Host "Could not reach NuGet API. Falling back to version 17.0.0" -ForegroundColor Yellow
        $versionInput = "17.0.0"
    }
}

Write-Host "Using version: $versionInput" -ForegroundColor Cyan

# 2. Install Templates and Create Project
Write-Host "Updating templates..." -ForegroundColor Gray
dotnet new install "Umbraco.Templates@$versionInput" --force

New-Item -ItemType Directory -Path $projectName -Force | Out-Null
Set-Location $projectName

Write-Host "Creating Solution and Project..." -ForegroundColor Gray
dotnet new sln --name $projectName
dotnet new umbraco --name $projectName --output ./www
dotnet sln add "./www/$projectName.csproj" --in-root

# 3. Configure Unattended Install
$config = @{
  ConnectionStrings = @{
    umbracoDbDSN = "Data Source=|DataDirectory|/Umbraco.sqlite.db;Cache=Shared;Foreign Keys=True;Pooling=True"
    umbracoDbDSN_ProviderName = "Microsoft.Data.Sqlite"
  }
  Umbraco = @{
    CMS = @{
      Global = @{ InstallMissingDatabase = $true }
      Unattended = @{
        InstallUnattended = $true
        UnattendedUserName = $UsrName
        UnattendedUserEmail = $UsrEmail
        UnattendedUserPassword = $UsrPassword
      }
    }
  }
}
$config | ConvertTo-Json -Depth 10 | Out-File -FilePath "./www/appsettings.Development.json" -Encoding utf8
Write-Host "appsettings.Development.json created with Unattended Install configuration."

# 4. Initial Database Setup (Clean Boot)
Write-Host "`nStarting Umbraco for initial database setup..." -ForegroundColor Yellow
Set-Location "./www"
$process = Start-Process "dotnet" -ArgumentList "run" -PassThru

Write-Host "Waiting for Umbraco.sqlite.db to be fully initialized..." -ForegroundColor Gray
$dbPath = "umbraco/Data/Umbraco.sqlite.db"
$timeout = 90
$elapsed = 0
while (-not (Test-Path $dbPath) -and $elapsed -lt $timeout) {
    Start-Sleep -Seconds 2
    $elapsed += 2
}

# Allow extra time for OpenIddict tables to commit
Write-Host "Finalizing migrations..." -ForegroundColor Gray
Start-Sleep -Seconds 8
Stop-Process -Id $process.Id -Force
Write-Host "Initial setup complete. Database and tables created." -ForegroundColor Green

# 5. Package Installation
$installExtras = Read-Host "`nDo you want to install uSync, Contentment, and BlockPreview now? (yes/no)"

if ($installExtras -match '^(y|yes)$') {
    $major = [int]$versionInput.Split('.')[0]
    
    switch ($major) {
        17 {
            $contentmentVersion = "6.1.1" 
            $usyncVersion = "17.0.4"
            $blockPreviewVersion = "5.3.2"
        }
        13 {
            $contentmentVersion = "5.2.0"
            $usyncVersion = "13.5.2"
            $blockPreviewVersion = "1.13.7"
        }
        default {
            $contentmentVersion = $null 
            $usyncVersion = $null
            $blockPreviewVersion = $null
        }
    }

    $projectPath = "./$projectName.csproj"
    function Add-Pkg($name, $ver) {
        if ($ver) { 
            Write-Host "Installing $name version $ver..." -ForegroundColor Gray
            dotnet add $projectPath package $name --version $ver 
        } else { 
            Write-Host "Installing latest stable $name..." -ForegroundColor Gray
            dotnet add $projectPath package $name 
        }
    }

    Add-Pkg "uSync" $usyncVersion
    Add-Pkg "Umbraco.Community.Contentment" $contentmentVersion
    Add-Pkg "Umbraco.Community.BlockPreview" $blockPreviewVersion
    
    Write-Host "Building project with new packages..." -ForegroundColor Gray
    dotnet build
}

# 6. Completion
Write-Host "`nUmbraco project '$projectName' is ready!" -ForegroundColor Cyan
Write-Host "Credentials: Email: $UsrEmail | Password: $UsrPassword"
Write-Host "Tip: If the database error persists, delete the .db file and run 'dotnet run' manually."

$answer = Read-Host "`nWould you like to open the solution in Visual Studio now? (yes/no)"
if ($answer -match '^(y|yes)$') {
    $slnPath = "../$projectName.sln"
    if (Test-Path $slnPath) {
        Write-Host "Launching Visual Studio..."
        Start-Process $slnPath
    }
} else {
    Write-Host "Setup finished. You can open the solution manually when ready."
}
