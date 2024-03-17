function GetBootstrap {
	$bootstrapUrl = "https://static.runelite.net/bootstrap.json"
    $USER_AGENT = "RuneLite/2.6.14-SNAPSHOT"
	$bootstrapResp = Invoke-WebRequest -Uri $bootstrapUrl -UserAgent $USER_AGENT

	if ($bootstrapResp.StatusCode -ne 200) {
		throw "Unable to download bootstrap (status code $($bootstrapResp.StatusCode)): $($bootstrapResp.Content)"
	}

	$bytes = $bootstrapResp.Content

	$bootstrap = ConvertFrom-Json -InputObject $bytes
	return $bootstrap
}
function InsertTextAtLine {
    param (
        [string]$filePath,
        [string]$textToInsert,
        [int]$positionToInsert
    )

    $currentline = 0

    $newContent = switch -File $filePath {
        default {
            $currentline++
            if ($currentline -eq $positionToInsert) { $textToInsert }
            $_
        }
    }

    Set-Content -Path $filePath -Value $newContent
}

function DeleteLines {
    param (
        [string]$filePath,
        [string]$matchPattern,
        [int]$linesToDelete
    )

    $deleteMode = $false
    $currentLinesDeleted = 0

    $newContent = Get-Content -Path $filePath | ForEach-Object {
        if ($_ -match $matchPattern) {
            $deleteMode = $true
        }
        if ($deleteMode -eq $false) {
            $_
        }
        if ($deleteMode -eq $true -and $currentLinesDeleted -lt $linesToDelete) {
            $currentLinesDeleted++
        }
        if ($currentLinesDeleted -eq $linesToDelete) {
            $deleteMode = $false
        }
    }

    Set-Content -Path $filePath -Value $newContent
}

$mavenUrl = "https://dlcdn.apache.org/maven/maven-3/3.9.6/binaries/apache-maven-3.9.6-bin.zip"
$mvnPath = "./apache-maven-3.9.6/bin/"
$mavenZipPath = "./apache-maven-3.9.6-bin.zip"

if (-not (Test-Path $mvnPath)) {
    if (-not (Test-Path $mavenZipPath)) {
        Write-Host "Downloading Maven..."
        Invoke-WebRequest -Uri $mavenUrl -OutFile $mavenZipPath
    }
    Expand-Archive -Path $mavenZipPath -DestinationPath "./" -Force
}

$mvnBin = Resolve-Path $mvnPath/mvn.cmd
$runelite = "https://github.com/runelite/runelite.git"
$launcher = "https://github.com/runelite/launcher.git"

$bootstrap = GetBootstrap
$version = $bootstrap.version

$appdatarunelite = "$env:LOCALAPPDATA\RuneLite"
$runeliteroot= "runelite"
$launcherroot = "launcher"
$rootpom = "$runeliteroot/pom.xml"
$apipom = "$runeliteroot/runelite-api/pom.xml"
$clientpom = "$runeliteroot/runelite-client/pom.xml"
$jshellpom = "$runeliteroot/runelite-jshell/pom.xml"
$mavenpom = "$runeliteroot/runelite-maven-plugin/pom.xml"
$cachepom = "$runeliteroot/cache/pom.xml"
$repositoryPath = "~/.runelite/repository1"
$launcherJavaPath = "./launcher/src/main/java/net/runelite/launcher/Launcher.java"
$jvmLauncherJavaPath = "./launcher/src/main/java/net/runelite/launcher/JvmLauncher.java"

$runelitejava = "$runeliteroot/runelite-client/src/main/java/net/runelite/client/RuneLite.java"

$clientjar = "$runeliteroot/runelite-client/target/client-$version.jar"
$apijar = "$runeliteroot/runelite-api/target/runelite-api-$version.jar"
$jshelljar = "$runeliteroot/runelite-jshell/target/jshell-$version.jar"
$mavenjar = "$runeliteroot/runelite-maven-plugin/target/runelite-maven-plugin-$version.jar"
$pomFiles = @($rootpom, $apipom, $clientpom, $jshellpom, $mavenpom, $cachepom)
$runelitelauncherjar = "$launcherroot/target/RuneLite.jar"

$runeliteDefaultJar = "$appdatarunelite/Runelite-Default.jar"
$runelitePatchedJar = "$appdatarunelite/Runelite-Patched.jar"
$runeliteJar = "$appdatarunelite/Runelite.jar"

if ((Test-Path $runeliteDefaultJar) -or (Test-Path $runelitePatchedJar)) {
    $userChoice = ""
    while ($userChoice -ne "r" -And $userChoice -ne "s") {
        $userChoice = Read-Host "Do you want to rerun the script or switch files? (r/s)"
        if ($userChoice -eq "r") {
            # Continue with the script
        } elseif ($userChoice -eq "s") {
            if (Test-Path $runeliteDefaultJar) {
                Rename-Item -Path $runeliteJar -NewName "Runelite-Patched.jar"
                Rename-Item -Path $runeliteDefaultJar -NewName "Runelite.jar"
            } elseif (Test-Path $runelitePatchedJar) {
                Rename-Item -Path $runeliteJar -NewName "Runelite-Default.jar"
                Rename-Item -Path $runelitePatchedJar -NewName "Runelite.jar"
            }
            exit
        } else {
            Write-Host "Invalid choice. Please choose either 'rerun' or 'switch'."
        }
    }
}

if (Test-Path -Path "./runelite") {
    Remove-Item -Path "./runelite" -Recurse -Force
}
Write-Host "Cloning runelite..."
git clone $runelite

if (Test-Path -Path "./launcher") {
    Remove-Item -Path "./launcher" -Recurse -Force
}
Write-Host "Cloning launcher..."
git clone $launcher

Write-Host "Editing pom.xml files..."
foreach ($pomFile in $pomFiles) {
    (Get-Content -Path $pomFile) -replace '<version>.*SNAPSHOT</version>', "<version>$version</version>" | Set-Content -Path $pomFile
}

Write-Host "Editing RuneLite.java..."
(Get-Content -Path $runelitejava) -replace 'final boolean developerMode.*', 'final boolean developerMode = true;' | Set-Content -Path $runelitejava
(Get-Content -Path $runelitejava) -replace 'boolean assertions = false;', 'boolean assertions = true;' | Set-Content -Path $runelitejava

Write-Host "Editing Launcher.java..."
$textToInsert = '	private static final File REPO1_DIR = new File(RUNELITE_DIR, "repository1");'
InsertTextAtLine -filePath $launcherJavaPath -textToInsert $textToInsert -positionToInsert 94

$textToInsert = "if \(JagexLauncherCompatibility.check\(\)\)"
DeleteLines -filePath $launcherJavaPath -matchPattern $textToInsert -linesToDelete 5

$textToInsert = "if \(settings.launchMode == LaunchMode.REFLECT\)"
DeleteLines -filePath $launcherJavaPath -matchPattern $textToInsert -linesToDelete 22

$textToInsert = "			JvmLauncher.launch(bootstrap, REPO1_DIR.getAbsolutePath(), REPO_DIR.getAbsolutePath(), clientArgs, jvmProps, jvmParams);"
InsertTextAtLine -filePath $launcherJavaPath -textToInsert $textToInsert -positionToInsert 407

Write-Host "Editing JvmLauncher.java..."
(Get-Content -Path $jvmLauncherJavaPath) -replace 'List<File> classpath,', "String repo1,`n`t`tString repo2," | Set-Content -Path $jvmLauncherJavaPath

DeleteLines -filePath $jvmLauncherJavaPath -matchPattern "StringBuilder classPath = new StringBuilder\(\);" -linesToDelete 10

InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		}' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '			classPath.append(f.getAbsolutePath());' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '			}' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '				classPath.append(File.pathSeparatorChar);' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '			{' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '			if (classPath.length() > 0)' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		{' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		for (var f : files)' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		}' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '			files.addAll(Arrays.asList(files2));' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		{' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		if (files2 != null)' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		}' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '			files.addAll(Arrays.asList(files1));' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		{' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		if (files1 != null)' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		List<File> files = new ArrayList<>();' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		File[] files2 = dir2.listFiles((d, name) -> name.endsWith(".jar") && !name.startsWith("client-1.10") && !name.startsWith("jshell-1.10") && !name.startsWith("runelite-api-1.10") && !name.startsWith("runelite-maven-plugin-1.10"));' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		File[] files1 = dir1.listFiles((d, name) -> name.endsWith(".jar"));' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		File dir2 = new File(repo2);' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		File dir1 = new File(repo1);' -positionToInsert 80
InsertTextAtLine -filePath $jvmLauncherJavaPath -textToInsert '		StringBuilder classPath = new StringBuilder();' -positionToInsert 80

Write-Host "Running Maven from RuneLite root with -DskipTests..."
Set-Location -Path $runeliteroot
Start-Process -FilePath $mvnBin -ArgumentList 'install', '-DskipTests' -NoNewWindow -Wait
Set-Location -Path ".."

Write-Host "Running Maven from Launcher root with -DskipTests..."
Set-Location -Path $launcherroot
Start-Process -FilePath $mvnBin -ArgumentList 'install', '-DskipTests' -NoNewWindow -Wait
Set-Location -Path ".."

if (-not (Test-Path $repositoryPath)) {
    New-Item -ItemType Directory -Force -Path $repositoryPath
}

Get-ChildItem -Path $repositoryPath | Remove-Item -Force -Recurse

$jarFiles = @($clientjar, $apijar, $jshelljar, $mavenjar)
foreach ($jarFile in $jarFiles) {
    Move-Item -Path $jarFile -Destination $repositoryPath
}

if (-not (Test-Path "$appdatarunelite\RuneLite-Default.jar")) {
    Rename-Item -Path "$appdatarunelite\RuneLite.jar" -NewName "RuneLite-Default.jar"
}

if (Test-Path "$appdatarunelite\RuneLite-Patched.jar") {
    Remove-Item -Path "$appdatarunelite\RuneLite-Patched.jar" -Force
}

Move-Item -Path $runelitelauncherjar -Destination $appdatarunelite -Force

Write-Host "Done."
