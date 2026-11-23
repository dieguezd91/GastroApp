param([string]$ScratchPath)
# Replicates the Dockerfile restore order (project file only, then sources, then publish --no-restore)
# and fails when the published output lacks the Blazor Server script.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-publish-' + [guid]::NewGuid().ToString('N')) }
$ScratchPath = [IO.Path]::GetFullPath($ScratchPath)
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
if (!$ScratchPath.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'ScratchPath must be under the OS temporary directory.' }
if (Test-Path $ScratchPath) { throw 'ScratchPath must be a new directory.' }
New-Item -ItemType Directory -Path $ScratchPath | Out-Null
Write-Host "Verification scratch: $ScratchPath (retained for inspection)"

$src = Join-Path $ScratchPath 'src'
$packages = Join-Path $ScratchPath 'packages'
$out = Join-Path $ScratchPath 'publish'
New-Item -ItemType Directory -Path $src | Out-Null

# Dockerfile step: restore with only the project file present.
Copy-Item (Join-Path $repo 'GastroApp.csproj') $src
& dotnet restore (Join-Path $src 'GastroApp.csproj') --packages $packages | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'dotnet restore failed.' }

# Dockerfile step: copy the remaining sources (tracked and untracked non-ignored files, no build output).
$files = & git -C $repo ls-files -co --exclude-standard
if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
foreach ($file in $files) {
    if ($file -match '(^|/)(bin|obj)/' -or $file -eq 'GastroApp.csproj') { continue }
    $source = Join-Path $repo $file
    if (!(Test-Path $source -PathType Leaf)) { continue }
    $target = Join-Path $src $file
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item $source $target
}

# Dockerfile step: publish without restoring again.
& dotnet publish (Join-Path $src 'GastroApp.csproj') -c Release -o $out --no-restore --packages $packages | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed.' }

$script = Join-Path $out 'wwwroot/_framework/blazor.server.js'
if (Test-Path $script -PathType Leaf) {
    Write-Host 'PASS publish output contains wwwroot/_framework/blazor.server.js'
    exit 0
}
Write-Host 'FAIL publish output is missing wwwroot/_framework/blazor.server.js'
exit 1
