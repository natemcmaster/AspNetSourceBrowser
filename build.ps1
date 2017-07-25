[cmdletbinding(PositionalBinding = $false)]
param(
    [string]$Config='Release'
)

$ErrorActionPreference='Stop'

function __exec($_cmd) {
    $ErrorActionPreference = 'Continue'
    Write-Host -ForegroundColor Cyan ">>> $_cmd $args"
    & $_cmd @args
    $exit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($exit -ne 0) {
        Write-Error "<<<< [$exit] $_cmd $args"
    }
}


$repos = Get-Content $PSScriptRoot/repos.txt
$branch='1.0.0'
$buildDir = Join-Path $PSScriptRoot bin
$artifacts = Join-Path $PSScriptRoot artifacts
# remove-item $buildDir -Recurse

remove-item $artifacts -Recurse -ErrorAction Ignore

mkdir $buildDir -ErrorAction Ignore | Out-Null
mkdir $buildDir/zip -ErrorAction Ignore | Out-Null
mkdir $buildDir/$branch -ErrorAction Ignore | Out-Null

$repos | ForEach-Object {
    $unzip = Join-Path $buildDir "src/$_"
    $zip = Join-Path $buildDir "zip/$_-$branch.zip"
    if (!(Test-Path $zip)) {
        Invoke-WebRequest https://github.com/aspnet/$_/archive/$branch.zip -OutFile $zip -Verbose
    }
    if (!(Test-Path $unzip)) {
        Write-Verbose "Unzipping $zip"
        $dest=Split-Path -Parent $unzip
        Expand-Archive -Path $zip -DestinationPath $dest
        Move-Item $dest/$_-$branch $unzip
    }

    Get-ChildItem $unzip/src/* -Directory `
        | Where-Object { !($_ -like '*.Testing' -or $_ -like '*.Tests' -or $_ -like 'PageGenerator') } `
        | Where-Object {
            if (!(Test-Path $_/project.json)) {
                return $True
            }

            $p = Get-Content -Raw $_/project.json | ConvertFrom-Json
            # filter projects who are only netcoreapps, like dotnet-razor-tooling
            $isNetCoreApp=($p.frameworks | Get-Member -MemberType NoteProperty -Name "netcoreapp1.0") -and ($p.frameworks | Get-Member -MemberType NoteProperty | Measure-Object).Count -eq 1
            return !$isNetCoreApp
        } `
        | ForEach-Object {
            $dest="$buildDir/$branch/$(Split-Path -Leaf $_)"
            if (Test-Path $dest) {
                Write-Host "Skipping '$_'. Already exists."
                return
            }
            Write-Verbose "Copying $_"
            Copy-Item $_ -Recurse $buildDir/$branch
        }
}

iwr https://raw.githubusercontent.com/dotnet/cli/rel/1.0.0/scripts/obtain/dotnet-install.ps1 -outfile bin/dotnet-install.ps1
__exec ./bin/dotnet-install.ps1 -Version 1.0.0-preview2-003121 -InstallDir "$PSScriptRoot/.dotnet"
__exec ./bin/dotnet-install.ps1 -Version 1.0.4 -InstallDir "$PSScriptRoot/.dotnet"

'{ "sdk": { "version": "1.0.0-preview2-003121" } }' | Set-Content -Path $buildDir/$branch/global.json -Encoding Ascii


Write-Host "Restoring packages" -ForegroundColor Cyan
Push-Location $buildDir/$branch -Verbose
try {
    $dotnet = "$PSScriptRoot/.dotnet/dotnet.exe"
    $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
    __exec $dotnet --version
    __exec $dotnet restore
} finally {
    Pop-Location -Verbose
}

__exec dotnet --version
__exec dotnet restore $PSScriptRoot/SourceBrowser.sln
__exec dotnet publish "$PSScriptRoot/src/HtmlGenerator/HtmlGenerator.csproj" --configuration $Config --output "$PSScriptRoot/bin/HtmlGenerator/publish/"

Write-Host "Generating the website"
__exec "$PSScriptRoot/bin/HtmlGenerator/publish/HtmlGenerator.exe" $buildDir/$branch/global.json /out:$artifacts/website/
