[cmdletbinding(PositionalBinding = $false)]
param(
    [string]$Config='Release'
)

$ErrorActionPreference='Stop'

$repos = Get-Content $PSScriptRoot/repos.txt
$branch='master'
$buildDir = Join-Path $PSScriptRoot bin
$artifacts = Join-Path $PSScriptRoot artifacts
# remove-item $buildDir -Recurse

remove-item $artifacts -Recurse -ErrorAction Ignore

mkdir $buildDir -ErrorAction Ignore | Out-Null
mkdir $buildDir/zip -ErrorAction Ignore | Out-Null
mkdir $buildDir/$branch -ErrorAction Ignore | Out-Null

$repos | % { 
    $unzip = Join-Path $buildDir "src/$_"
    $zip = Join-Path $buildDir "zip/$_-$branch.zip"
    if (!(Test-Path $zip)) {
        iwr https://github.com/aspnet/$_/archive/$branch.zip -OutFile $zip -Verbose
    }
    if (!(Test-Path $unzip)) {
        Write-Verbose "Unzipping $zip"
        $dest=Split-Path -Parent $unzip
        Expand-Archive -Path $zip -DestinationPath $dest
        Move-Item $dest/$_-$branch $unzip
    }

    Get-ChildItem $unzip/src/* -Directory |
        # filter projects
        ? { !($_ -like '*.Testing' -or $_ -like '*.Tests' -or $_ -like 'PageGenerator') } |
        ? { 
            if (!(Test-Path $_/project.json)) {
                return $True
            }

            $p = Get-Content -Raw $_/project.json | ConvertFrom-Json
            # filter projects who are only netcoreapps, like dotnet-razor-tooling
            $isNetCoreApp=($p.frameworks | Get-Member -MemberType NoteProperty -Name "netcoreapp1.0") -and ($p.frameworks | Get-Member -MemberType NoteProperty | Measure-Object).Count -eq 1
            return !$isNetCoreApp
        } |
        % {
            $dest="$buildDir/$branch/$(Split-Path -Leaf $_)"
            if (Test-Path $dest) {
                Write-Host "Skipping '$_'. Already exists."
                return
            }
            Write-Verbose "Copying $_"
            Copy-Item $_ -Recurse $buildDir/$branch
        }
}

'{}' | Out-File $buildDir/$branch/global.json

Write-Host "Restoring packages" -ForegroundColor Blue
dotnet restore $buildDir/$branch

if ($LASTEXITCODE -ne 0) {
    Write-Error "Restore failed"
}

& 'C:\Program Files (x86)\msbuild\14.0\Bin\MSBuild.exe' $PSScriptRoot/SourceBrowser.sln /p:Configuration=$Config
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed"
}

& "$PSScriptRoot\bin\$Config\HtmlGenerator\HtmlGenerator.exe" $buildDir/$branch/global.json /out:$artifacts/website/
if ($LASTEXITCODE -ne 0) {
    Write-Error "Generation failed"
}