﻿param(
    [string]$RootPath = "$env:USERPROFILE\Projects\Nano",
    [string]$GithubRepo = "https://github.com/clemahieu/raiblocks.git",
    [string]$GithubBranch = "master", # default to master, empty to bypass git clone 
    [string]$VsVersion = "2017",
    [string]$Bitness = "64",
    [string]$BoostVersion = "1.66.0",
    [string]$QtRelease = "5.10",
    [string]$QtPath = "C:\Qt",
    [string]$CMakePath = $null,
    [string]$ProgramFiles = $env:ProgramFiles,
    [string]$Python2Path = $env:PYTHONPATH,
    [boolean]$InstallDevTools = $true,
    [boolean]$UseVsCmake = $true,
    [boolean]$UseBoostFromSource = $false
)

If (($InstallDevTools -eq $true) -AND (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))) {
    Write-Error "** RUN SCRIPT AS ADMINISTRATOR IF INSTALLING DEVTOOLS **"
    Return
}

if (-NOT (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio")) {
    Write-Error "** Visual Studio 2012 or newer is required. **"
    Return
}

clear

$ProgramFiles32 = $(Get-Item "env:programfiles(x86)").Value
$bitArch1 = $(if ($Bitness -eq "64") {"x64"} else {"x86"})

function Set-VsCmd {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Enter VS version as 2012, 2013, 2015, 2017")]
        [ValidateSet(2012, 2013, 2015, 2017)]
        [int]$version
    )
    $VS_VERSION = @{ 2012 = "11.0"; 2013 = "12.0"; 2015 = "14.0"; 2017 = "14.1" }
    $VS_VERSION2 = @{ 2012 = "11"; 2013 = "12"; 2015 = "14"; 2017 = "15" }

    write-host "* Searching for Visual Studio"

    $env:VsVersion = $VS_VERSION[$version]
    $VS_VERSION3 = $env:VsVersion.Replace(".", "")
    if ($version -ge 2015) {
        $env:msvcver = "msvc-$env:VsVersion"
        Push-Location
        $targetDir = $(if ($version -eq 2015) { "$ProgramFiles32\Microsoft Visual Studio $env:VsVersion" } else { "$ProgramFiles32\Microsoft Visual Studio\$version" })
        Set-Location $targetDir
        $vcvars = Get-ChildItem -Recurse vcvarsall.bat | Resolve-Path -Relative 
        $env:CMAKE_BIN = "$CMakePath\bin"
        if ([string]::IsNullOrEmpty($CMakePath)) {
            $env:CMAKE_BIN = "$(Get-ChildItem CMake -Recurse | where {$_.Parent -match 'CMake'})\bin"
        }
        $env:FINDBOOST_PATH = "$(Get-ChildItem -Recurse FindBoost.cmake | Resolve-Path)" | Convert-Path 
        $env:VS_ARCH = "Visual Studio $($VS_VERSION2[$version]) $version"
        Pop-Location
    }
    else {
        $env:msvcver = "msvc-$($VS_VERSION[$version])"
        $env:VS_ARCH = "Visual Studio $($VS_VERSION2[$version]) $version"
        Push-Location
        $targetDir = "$ProgramFiles32\Microsoft Visual Studio $($VS_VERSION[$version])\VC"
        Set-Location $targetDir
        $vcvars = "vcvarsall.bat"
        $env:CMAKE_BIN = "$(Get-ChildItem CMake -Recurse | where {$_.Parent -match 'CMake'} | Resolve-Path -Relative)\bin"
        Pop-Location
    }

    $env:CMAKE_TOOLSET = "v$VS_VERSION3,host=$bitArch1"
  
    if (!(Test-Path (Join-Path $targetDir $vcvars))) {
        "* Error: Visual Studio $version not installed"
        return
    }
    $is64 = $(Test-Path "env:ProgramFiles(x86)")
    if ($Bitness -eq "64") { 
        Write-Host "*   Setting 64-bit mode"
        if ($is64) {
            $vcvars = $($vcvars -replace "all", "64");
        }
        else {
            $vcvars = $($vcvars -replace "all", "x86_amd64");
        }
        $env:VS_ARCH += " Win64"
    }
    else {
        if ($is64) {
            $vcvars = $($vcvars -replace "all", "amd64_x86");
        }
        else {
            $vcvars = $($vcvars -replace "all", "x86");
        }
    }
    Write-host "* Running $targetDir $vcvars"
    Push-Location $targetDir
    $vcvars += "&set"
    cmd /c $vcvars |
        ForEach-Object {
        if ($_ -match "(.*?)=(.*)") {
            Set-Item -force -path "ENV:\$($matches[1])" -value "$($matches[2])"
        }
    }
    Pop-Location
    write-host "*   Visual Studio $version environment variables set."
}

## setup Visual Studio path
Set-VsCmd -version $VsVersion

$env:BOOST_DEBUG = "ON"
$env:BOOST_CUSTOM = "ON"
$env:RAIBLOCKS_GUI = "ON"
$env:ENABLE_AVX2 = "ON"
$env:CRYPTOPP_CUSTOM = "ON"
$env:BOOST_THEADING = "multi"  # (multi|single)
$env:BOOST_RUNTIME_LINK = "static"    # (static|shared)
$env:BOOST_LINK = "static"
$env:BOOST_ARCH = "x86"
$env:BOOST_VARIANT = "release"

$bitArch2 = $(if ($Bitness -eq "64") {"win64"} else {"win32"})
$bitArch3 = $(if ($Bitness -eq "64") {"amd64"} else {""})
$bitArch4 = $(if ($Bitness -eq "64") {"-x64"} else {""})
$bitArch5 = $(if ($Bitness -eq "64") {"X64"} else {"x86"})
$bitArch6 = $(if ($Bitness -eq "64") {"64"} else {""})
$bitArch7 = $(if ($Bitness -eq "64") {"-x64"} else {"-x32"})

$repoPath = "$RootPath\github"
$buildPath = "$RootPath\github-build"

$boostSrcPath = "$buildPath\boost-src"
$boostPrefixPath = "$buildPath\boost"
$boostBuildPath = "$buildPath\boost-build"
$boostBaseName = "boost_" + $BoostVersion.Replace(".", "_")
$boostBaseNameShort = "boost-" + $BoostVersion.Replace(".0", "").Replace(".", "_")
$QtReleaseFull = "$QtRelease.0"
$downloadPath = "$RootPath\downloads"
$ProgramFiles32 = $(Get-Item "env:programfiles(x86)").Value

if ([string]::IsNullOrEmpty($Python2Path)) { 
    $Python2Path = $env:PYTHONHOME
}
if ([string]::IsNullOrEmpty($Python2Path)) { 
    $Python2Path = 'C:\Python27'
}

$downloads = $(
    @{
        name              = "7zip";
        url               = "http://www.7-zip.org/a/7z1800$bitArch4.exe"; 
        filename          = "7z1800$bitArch4.exe";
        installPath       = "$ProgramFiles\7-Zip";
        addPath           = "$ProgramFiles\7-Zip";
        enabled           = $true;
    },
    @{
        name              = "wget";
        url               = "https://eternallybored.org/misc/wget/releases/wget-1.19.4-win$Bitness.zip"; 
        filename          = "wget-1.19.4-win$Bitness.zip";
        extractPath       = "$env:TEMP\wget";
        enabled           = $true;
    },
    @{
        name              = "Python2";
        url               = "https://www.python.org/ftp/python/2.7.14/python-2.7.14.$bitArch3.msi";
        filename          = "python-2.7.14.$bitArch3.msi";
        extractPath       = "$env:TEMP\python2";
        installPath       = "$Python2Path";
        addPath           = "$Python2Path";
        enabled           = $true;
    },
    @{
        name              = "NSIS";
        url               = "https://downloads.sourceforge.net/project/nsis/NSIS%203/3.02.1/nsis-3.02.1-setup.exe";
        filename          = "nsis-3.02.1-setup.exe";
        installPath       = "$ProgramFiles32\NSIS\";
        addPath           = "$ProgramFiles32\NSIS\bin";
        enabled           = $true;
    },
    @{
        name              = "MS MPI";
        url               = "https://download.microsoft.com/download/2/E/C/2EC96D7F-687B-4613-80F6-E10F670A2D97/msmpisdk.msi";
        filename          = "MSMpiSetup.exe";
        installPath       = "$ProgramFiles\Microsoft MPI";
        addPath           = "$ProgramFiles\Microsoft MPI\Bin";
        enabled           = $true;
    },
    @{
        name              = "MS MPI SDK";
        url               = "https://download.microsoft.com/download/2/E/C/2EC96D7F-687B-4613-80F6-E10F670A2D97/msmpisdk.msi";
        filename          = "msmpisdk.msi";
        installPath       = "$ProgramFiles32\Microsoft SDKs\MPI";
        addPath           = "$ProgramFiles32\Microsoft SDKs\MPI\Bin";
        enabled           = $true; 
    },
    @{
        name              = "git";
        url               = "https://github.com/git-for-windows/git/releases/download/v2.16.1.windows.2/Git-2.16.1.2-64-bit.exe";
        filename          = "Git-2.16.1.2-64-bit.exe";
        installPath       = "$ProgramFiles\git";
        enabled           = $true;
    },
    @{
        name              = "CMake";
        url               = "https://cmake.org/files/v3.10/cmake-3.10.2-$bitArch2-$bitArch1.zip";
        filename          = "cmake-3.10.2-$bitArch2-$bitArch1.zip";
        collapseDir       = $true;
        extractpath       = "$RootPath\cmake";
        linkedInstallName = "cmake";
        linkedInstallPath = "$RootPath\cmake";
        enabled           = !$UseVsCmake;
    },
    @{
        name              = "Boost Source";
        url               = "https://dl.bintray.com/boostorg/release/$BoostVersion/source/$boostBaseName.zip";
        filename          = "$boostBaseName.zip";
        collapseDir       = $true;
        extractPath       = $boostSrcPath;
        boostIncludePath  = "$boostPrefixPath\include\$boostBaseNameShort\boost";
        boostLibPath      = "$boostPrefixPath\lib";
        enabled           = $UseBoostFromSource;
    },
    @{
        name              = "Boost Binary";
        url               = "https://dl.bintray.com/boostorg/release/$BoostVersion/binaries/$boostBaseName-$env:msvcver-$Bitness.exe";
        filename          = "$boostBaseName-$env:msvcver-$Bitness.exe";
        installPath       = "$RootPath\boost";
        installParams     = "/DIR=`"$RootPath\boost`"";
        removeArch        = $true;
        removePath        = "lib$Bitness-$env:msvcver"
        removeSearchFor   = $bitArch7
        linkedInstallName = "boost";
        linkedInstallPath = "$RootPath\boost";
        boostIncludePath  = "$boostPrefixPath\boost";
        boostLibPath      = "$boostPrefixPath\lib$bitArch6-$env:msvcver";
        enabled           = !$UseBoostFromSource;
    },
    @{
        name              = "Qt";
        url               = "http://download.qt.io/official_releases/qt/$QtRelease/$QtReleaseFull/qt-opensource-windows-x86-$QtReleaseFull.exe";
        filename          = "qt-opensource-windows-x86-$QtReleaseFull.exe";
        installPath       = "$QtPath\Qt$QtReleaseFull";
        addPath           = "$QtPath\Qt$QtReleaseFull\$QtReleaseFull\msvc$VsVersion`_$Bitness\bin;$QtPath\Qt$QtReleaseFull\Tools\QtCreator\bin";
        installComment    = "Please check msvc$VsVersion $Bitness-bit Prebuilt Components";
        linkedInstallName = "qt";
        linkedInstallPath = "$QtReleaseFull\msvc$VsVersion`_$Bitness";
        enabled           = $true;
    },
    @{
        name              = "Qt-src";
        url               = "http://download.qt.io/official_releases/qt/$QtRelease/$QtReleaseFull/single/qt-everywhere-src-$QtReleaseFull.zip";
        filename          = "qt-everywhere-src-$QtReleaseFull.zip";
        extractPath       = "$buildPath\qt-src";
        enabled           = $false;
    }

)

$buildQtPath = "$buildPath\qt"
$buildQtSrcPath = "$buildPath\qt-src"
$env:Qt5_DIR = $buildQtPath
$env:FINDBOOST_PATH = ""
$env:BOOST_INCLUDEDIR = "";
$env:BOOST_LIBRARYDIR = "";
$boostProjectConfig = "$boostSrcPath\project-config.jam"
$boostUserConfig = "$boostSrcPath\user-config$bitArch6.jam"
$boostUserHpp = "$boostSrcPath\boost\config\user.hpp"
$boostProc = "j$processors"
$boostLink = "link=$env:BOOST_LINK"
$boostRuntimeLink = @("runtime-link=$env:BOOST_RUNTIME_LINK", "")[[bool][string]::IsNullOrEmpty($env:BOOST_RUNTIME_LINK)]
$boostThreading = @("threading=$env:BOOST_THEADING", "")[[bool][string]::IsNullOrEmpty($env:BOOST_THEADING)]
$boostArch = "architecture=$env:BOOST_ARCH"
$boostVariant = @("variant=$env:BOOST_VARIANT", "")[[bool][string]::IsNullOrEmpty($env:BOOST_VARIANT)]
$boostProjectConfigBitness = @("", "<address-model>64 ; ")[[bool]$Bitness -eq 64]
if ($CMakePath -eq $null) { $CMakePath = "$buildPath\cmake" }


##############################################################################

function Unzip {
    param([string]$zipfile, [string]$outpath)
    $backupErrorActionPreference = $script:ErrorActionPreference
    $script:ErrorActionPreference = "Stop"
    if (Test-Path $outpath) {
        rmdir -recursive -force $outpath | out-null
    }
    if (!(Test-Path $outpath)) {
        mkdir -force $outpath | out-null
    }
    7z x $zipfile -o"$outpath" -r | out-null
    $script:ErrorActionPreference = $backupErrorActionPreference
}


function Resolve-Anypath {
    param ($file, $find)
    $paths = (".;" + $env:PATH).Split(";")
    foreach ($path in $paths) {
        $testPath = Join-Path $path $file
        if ((Test-Path $testPath) -and ($testPath -match $find)) {
            return ($testPath)
        }
    }
    return $false
}

function Invoke-SearchReplace {
    [CmdletBinding()]    
    param(
        [string] $file,
        [string] $searchFor,
        [string] $replaceWith
    )
    $DebugPreference = "Continue"
    if ((Get-Item $file).length -eq 0) {
        Write-Host "*   Failed to find $file"
        return
    } 
    $content = Get-Content $file -Raw
    $saveContent = $content
    $searchFor = "(?smi)$searchFor"
    $regex = [Regex]::new($searchFor)
    $match = $regex.Matches($content)
    if ($match.Success -eq $TRUE) {
        $content = $content -replace $searchFor, $replaceWith
        $content | Out-File $file -Encoding ascii
    }
}

function exec {
    # fixes bad applications that output to STDERR instead of STDOUT
    param
    (
        [ScriptBlock] $ScriptBlock,
        [string] $StderrPrefix = "",
        [int[]] $AllowedExitCodes = @(0)
    ) 

    $sb = [ScriptBlock]::Create($ScriptBlock)

    Write-Host "*   Calling $sb"

    $backupErrorActionPreference = $script:ErrorActionPreference

    $script:ErrorActionPreference = "Continue"
    try {
        & $ScriptBlock 2>&1 | ForEach-Object -Process `
        {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { "$StderrPrefix$_" } else { "$_" }
        }
        if ($AllowedExitCodes -notcontains $LASTEXITCODE) {
            Write-Error "* Execution failed with exit code $LASTEXITCODE"
            return $LASTEXITCODE
        }
    }
    finally {
        $script:ErrorActionPreference = $backupErrorActionPreference
    }
}

function Pack-EnvPath {
    return
    $latestTs = dir "$ProgramFiles32\Microsoft SDKs\TypeScript\" | Sort | Select -last 1 $_.Name
    $fso = New-Object -ComObject "Scripting.FileSystemObject"
    $shortpaths = @();
    $originalPaths = [environment]::GetEnvironmentVariable("path", "Machine").Split(";")
    foreach ($path in $originalPaths) {
        $fpath = [System.IO.Path]::GetFullPath("$path");
        if ($fpath.StartsWith("$ProgramFiles32\Microsoft SDKs\TypeScript\")) {
            $fpath = "$ProgramFiles\Microsoft SDKs\TypeScript\$latestTs\";
        }
        $fspath = $fso.GetFolder("$fpath").ShortPath;
        $foundIdx = $shortpaths.IndexOf($fspath);
        if ($foundIdx -gt -1) {	continue; }
        write-host $fpath  -->  $fspath;
        $shortpaths += $fspath;
    }
    $env:Path = $shortpaths -join ";"
}

function Add-EnvPath {
    param
    (
        [string] $Item = "",
        [bool] $Append = $true
    )
    Write-Host "*   Adding to PATH $Item"
    Pack-EnvPath
    if ($Append -eq $true) {
        $env:PATH = "$env:PATH;$Item"
    }
    else {
        $env:PATH = "$Item;$env:PATH"
    }
    Pack-EnvPath    
}

function Process-Downloads {
    cd $buildPath

    foreach ($file in $downloads) {
        $name = "$($file.name)"
        $filePath = "$downloadPath\$($file.filename)"
        $enabled = $($file.enabled)
        $url = "$($file.url)"
        $extractPath = "$($file.extractPath)"
        $installPath = "$($file.installPath)"
        $installParams = "$($file.installParams)"
        $linkedInstallName = "$($file.linkedInstallName)"
        $linkedInstallPath = "$($file.linkedInstallPath)"
        $installComment = "$($file.installComment)"
        $addPath = "$($file.addPath)"
        $collapseDir = $(if ($file.collapseDir) {$true} else {$false})
        $wget = "$env:TEMP\wget\wget.exe"
        $targetDir = $(if (!([string]::IsNullOrEmpty($installPath))) {$installPath} else {$extractPath})
        $shouldInstall = (!([string]::IsNullOrEmpty($installPath)))
        $alreadyInstalled =  $shouldInstall -and (Test-Path $installPath)
        $removeArch = $($file.removeArch)
        $removePath = "$($file.removePath)"
        $removeSearchFor = "$($file.removeSearchFor)"
        $realLinkedInstallPath = "$installPath\$linkedInstallPath"
        if ($installPath -eq $linkedInstallPath) { $realLinkedInstallPath = $installPath }

        if (!($enabled)) {
            Write-Host "* $name disabled, skipping."
            continue
        }

        Write-Host "* Checking $name is installed in $targetDir"

        if (!(Test-Path $downloadPath)) {
            Write-Host "* Creating $downloadPath"
            mkdir $downloadPath
        }

        if ($file.deleteBeforeDownload -eq $true -and (Test-Path $filePath)) {
            Write-Host "*   Deleting old download $filePath"
            del -Force -Recurse $filePath
        }
        if ($file.deleteBeforeExtract -eq $true -and (Test-Path $extractPath)) {
            Write-Host "*   Deleting old extraction $extractPath"
            del -Force -Recurse $extractPath
        }

        $boostIncludePath = $($file.boostIncludePath)
        if ($boostIncludePath) { 
            Write-Host "*   Setting BOOST_INCLUDEDIR=$boostIncludePath"
            $env:BOOST_INCLUDEDIR = $boostIncludePath 
        }
        $boostLibPath = $($file.boostLibPath)
        if ($boostLibPath) { 
            Write-Host "*   Setting BOOST_LIBRARYDIR=$boostLibPath"
            $env:BOOST_LIBRARYDIR = $boostLibPath 
        }

        if (!(Test-Path $filePath)) {
            Write-Host "*   Missing $filePath, downloading $url"
            if (Test-Path $wget) {
                Push-Location
                cd $filePath\..
                exec { & $wget --tries=50 --retry-connrefused --no-verbose --continue $url }
                Pop-Location
            }
            else {
                Invoke-WebRequest -Uri $url -OutFile $filePath
            }
        }
        if ((($filePath -match ".msi") -or ($filePath -match ".exe")) -and ($shouldInstall -and !($alreadyInstalled))) {
            Write-Host "*   Installing $filepath."
            if (!([string]::IsNullOrEmpty($installComment))) {
                Write-Host "*** $installComment ***" -ForegroundColor Yellow 
                pause
            }
            if ([string]::IsNullOrEmpty($installParams)) {
                Start-Process -FilePath "$filePath" -Wait
            } else {
                Start-Process -FilePath "$filePath" -ArgumentList $installParams -Wait
            }
            if (($removeArch) -and (Test-Path "$installPath\$removePath\*$removeSearchFor*")) {
                Write-Host "*   Removing $removeSearchFor in filenames inside $installPath\$removePath."
                dir "$installPath\$removePath" | Rename-Item -NewName { $_.Name -replace $removeSearchFor,"" } | Out-Null
            }
        }
        if (($filePath -match ".zip") -and (!(Test-Path $extractPath))) {
            Write-Host "*   U
            nzipping $filePath into $extractPath..."
            Push-Location
            Unzip $filePath $extractPath
            cd $extractPath
            if (($collapseDir) -and ((Get-ChildItem | ? { $_.PSIsContainer }).Length -eq 1)) {
                $dirName = $(Get-ChildItem | ? { $_.PSIsContainer } | Select-Object -First 1).Name
                move -force $dirName\* .
                rmdir -recurse $dirName
            }
            Pop-Location
        }

        if ((!([string]::IsNullOrEmpty($linkedInstallName))) -and (!([string]::IsNullOrEmpty($extractPath))) -and (Test-Path $extractPath) -and (!(Test-Path "$buildPath\$linkedInstallName"))) {
            Write-Host "*   Creating symbolic link from $buildPath\$linkedInstallName to $extractPath"
            Push-Location
            cd $buildPath
            New-Item -ItemType SymbolicLink -Name $linkedInstallName -Target $extractPath | out-null
            Pop-Location
        } 

        if ((!([string]::IsNullOrEmpty($linkedInstallName))) -and (Test-Path $realLinkedInstallPath) -and (!(Test-Path "$buildPath\$linkedInstallName"))) {
            Write-Host "*   Creating symbolic link from $buildPath\$linkedInstallName to $realLinkedInstallPath"
            Push-Location
            cd $buildPath
            New-Item -ItemType SymbolicLink -Name $linkedInstallName -Target $realLinkedInstallPath | out-null
            Pop-Location
        }
        if ((!([string]::IsNullOrEmpty($addPath))) -and (!($env:PATH.Contains($addPath)))) {
            Add-EnvPath -Item $addPath
        }
    }
}

##############################################################################
##############################################################################
##############################################################################

Write-Host "* Preparing build tools..."

if (!([string]::IsNullOrEmpty($env:PATH_BACKUP))) {
    Write-Host "* Restoring previous path backup."
    $env:PATH = $env:PATH_BACKUP
}
$env:PATH_BACKUP = $env:PATH

if (!(Test-Path $repoPath)) {
    mkdir $repoPath | out-null
}

if (!([string]::IsNullOrEmpty($GithubBranch))) {
    if (Test-Path $repoPath) {
        Write-Host "* Clearing $repoPath"
        rm -Force -Recurse $repoPath | Out-Null
    }

    Write-Host "* Cloning $GithubRepo into $repoPath from $GithubBranch branch"
    $backupErrorActionPreference = $script:ErrorActionPreference
    $script:ErrorActionPreference = "Stop"
    exec { & git clone --branch $GithubBranch $GithubRepo $repoPath }
    $script:ErrorActionPreference = $backupErrorActionPreference

    if (Test-Path $buildPath\qt) {
        (Get-Item $buildPath\qt).Delete() | out-null
    }

    if ((Test-Path $buildPath\cmake) -and (!$UseVsCmake)) {
        (Get-Item $buildPath\cmake).Delete() | out-null
    }

    if ((Test-Path $buildPath\boost) -and (!$UseBoostFromSource)) {
        (Get-Item $buildPath\boost).Delete() | out-null
    }
}
Write-Host "* Mirroring $repoPath into $buildPath"
robocopy $repoPath $buildPath /mir | out-null 
 
Write-Host "* Preparing build tools..."
Process-Downloads

Write-Host "* Building Nano..."

# add python to path
if ([string]::IsNullOrEmpty($env:PYTHONPATH)) {
    Write-Host "*   Set PYTHONPATH=$Python2Path"
    $env:PYTHONPATH = $Python2Path
}

# check for custom cmake
if (Test-Path "$buildPath\cmake") {
    $env:CMAKE_BIN = "$buildPath\cmake\bin"
}

# add cmake to path
if (!($env:PATH.Contains($env:CMAKE_BIN))) {
    Add-EnvPath -Item $env:CMAKE_BIN
}

# patch FindBoost.cmake with repo version
If ((!([string]::IsNullOrEmpty($env:FINDBOOST_PATH))) -and !(Get-Content $env:FINDBOOST_PATH | Select-String -Pattern "_boost_AAM_TAG")) {
    Set-ItemProperty -Path $env:FINDBOOST_PATH -Name IsReadOnly -Value $false
    Write-Host "*   Copying $buildPath\FindBoost.cmake to $env:FINDBOOST_PATH"
    copy "$buildPath\FindBoost.cmake" "$env:FINDBOOST_PATH"
}

# make BOOST
if (Test-Path $boostSrcPath) {
    cd $boostSrcPath
    if (!(Test-Path "project-config.jam")) {
        Write-Host "* Defining BOOST_CONFIG_SUPPRESS_OUTDATED_MESSAGE in $boostUserHpp"
        Invoke-SearchReplace "$boostUserHpp" "// define this to locate a compiler config file:" "#define BOOST_CONFIG_SUPPRESS_OUTDATED_MESSAGE`n// define this to locate a compiler config file:"
        & .\bootstrap.bat --with-libraries=date_time,filesystem,system,log,thread,program_options,regex,chrono,atomic,python
    }
    #If (!(Get-Content $boostProjectConfig | Select-String -Pattern "cl.exe")) {
    #    Write-Host "* Fixing $boostProjectConfig"
    #    $clPath = (Resolve-Anypath -file  "cl.exe" -find "Host$bitArch5.$bitArch1").Replace("\", "/")
    #    Write-Host "* Patching $boostProjectConfig with $rpl"
    #    Invoke-SearchReplace $boostProjectConfig "using msvc ;" "using msvc : $env:VsVersion : `"$clPath`" ; "
    #    Write-output `n | Out-File boostProjectConfig -Append 
    #    Add-Content $boostProjectConfig "using python : 2.7 : $Python2Path : $Python2Path\include : $Python2Path\libs : $boostProjectConfigBitness".Replace("\", "\\")
    #    if (!(Test-Path $boostUserConfig)) {
    #        Add-Content $boostUserConfig "using mpi ; "
    #    }
    #}
    if (!(Test-Path "$boostBuildPath\boost")) {
        .\b2 --prefix="$boostPrefixPath" --build-dir="$boostBuildPath" --layout=versioned $boostLink $boostThreading install
        #.\b2 install --prefix="$boostPrefixPath" --build-dir="$boostBuildPath" --layout=versioned --abbreviate-paths toolset=$env:msvcver $boostArch $boostLink $boostRuntimeLink $boostThreading $boostVariant runtime-debugging=off
        dir $env:BOOST_LIBRARYDIR -Recurse | Rename-Item -NewName { $_.Name -replace "$bitArch7-$boostBaseNameShort","" }
        # notes: http://www.boost.org/doc/libs/1_66_0/more/getting_started/windows.html
        #    https://gitlab.kitware.com/cmake/cmake/issues/17575
    }
}

## Build Qt source when available
if (Test-Path $buildQtSrcPath) {
    cd $buildQtSrcPath 
    if (!(Test-Path $buildQtPath)) {
        & ./configure -shared -opensource -nomake examples -nomake tests -confirm-license -prefix $env:Qt5_DIR
    }
    & nmake 
    & nmake install
}

cd $buildPath

if (!(Get-Content "CMakeLists.txt" | Select-String -Pattern "find_package .Boost $BoostVersion")) {
    Write-Host "* Fixing CMakeLists.txt with Boost $BoostVersion"
    Invoke-SearchReplace "CMakeLists.txt" "find_package \(Boost \d+\.\d+\.\d+" "find_package (Boost $BoostVersion"
}

exec { & git submodule update --init --recursive }

if (Test-Path CMakeCache.txt) {
    del CMakeCache.txt | out-null
}
if (Test-Path CMakeFiles) {
    rm -Force -Recurse CMakeFiles | out-null
}

cmake `
-G $env:VS_ARCH `
-T $env:CMAKE_TOOLSET `
-DQt5_DIR="$($env:Qt5_DIR)" `
-DBOOST_ROOT="$($boostPrefixPath)" `
-DBOOST_INCLUDEDIR="$($env:BOOST_INCLUDEDIR)" `
-DBOOST_LIBRARYDIR="$($env:BOOST_LIBRARYDIR)" `
-DBoost_DEBUG="$($env:BOOST_DEBUG)" `
-DRAIBLOCKS_GUI="$($env:RAIBLOCKS_GUI)" `
-BOOST_CUSTOM="$($env:BOOST_CUSTOM)" `
-DCRYPTOPP_CUSTOM="$($env:CRYPTOPP_CUSTOM)" `
-DRAIBLOCKS_SIMD_OPTIMIZATIONS=ON `
CMakeLists.txt

if (Test-Path ALL_BUILD.vcxproj) {
    devenv /Rebuild Debug ALL_BUILD.vcxproj
    #devenv nano_wallet
}
#$env:PATH = $env:PATH_BACKUP