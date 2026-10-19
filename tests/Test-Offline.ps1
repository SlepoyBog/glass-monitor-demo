$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceRoot=Split-Path -Parent $root
$mainCandidates=@(Get-ChildItem -LiteralPath $sourceRoot -Directory|ForEach-Object{Join-Path $_.FullName 'GlassMonitor.ps1'}|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf})
if($mainCandidates.Count-ne1){throw "Expected exactly one source GlassMonitor.ps1, found $($mainCandidates.Count)."}
$main=$mainCandidates[0]
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('glass-monitor-fixtures-'+[guid]::NewGuid().ToString('N'))

function New-LaserFixture([string]$Path,[bool]$LaserOn){
    $bitmap=New-Object Drawing.Bitmap(1000,700,[Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{
        $graphics.Clear([Drawing.Color]::FromArgb(170,170,170))
        if($LaserOn){$brush=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(245,110,35));try{$graphics.FillRectangle($brush,860,38,130,77)}finally{$brush.Dispose()}}
        $bitmap.Save($Path,[Drawing.Imaging.ImageFormat]::Png)
    }finally{$graphics.Dispose();$bitmap.Dispose()}
}

function New-EmptyCounterFixture([string]$Path){
    $bitmap=New-Object Drawing.Bitmap(1920,1080,[Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{$graphics.Clear([Drawing.Color]::White);$bitmap.Save($Path,[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}
}

[void][IO.Directory]::CreateDirectory($fixtureRoot)
try{
    $laserOn=Join-Path $fixtureRoot 'laser-on.png';$laserOff=Join-Path $fixtureRoot 'laser-off.png';$counterEmpty=Join-Path $fixtureRoot 'counter-empty.png'
    New-LaserFixture $laserOn $true;New-LaserFixture $laserOff $false;New-EmptyCounterFixture $counterEmpty
    $required=@($laserOn,$laserOff,$counterEmpty)
    foreach($path in $required){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Required offline fixture was not created: $path"}}

    $detectorResults=@()
    foreach($case in @(@{Path=$laserOn;Expected=$true},@{Path=$laserOff;Expected=$false})){
        $raw=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $main -Headless -TestImage $case.Path
        if($LASTEXITCODE-ne0){throw "Detector process failed for $($case.Path)"}
        $result=$raw|ConvertFrom-Json;$ok=([bool]$result.LaserOn-eq[bool]$case.Expected)
        $detectorResults+=[pscustomobject]@{Fixture=(Split-Path -Leaf $case.Path);Detected=$result.LaserOn;Expected=$case.Expected;OK=$ok}
        if(-not$ok){throw "Laser detector fixture failed: $($case.Path)"}
    }

    $counterRaw=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $main -Headless -TestCounterImage $counterEmpty
    if($LASTEXITCODE-ne0){throw 'Counter OCR process failed.'}
    $counterResult=$counterRaw|ConvertFrom-Json;$counterOk=($null-eq$counterResult.Counter)
    if(-not$counterOk){throw "Empty counter fixture was incorrectly recognized as $($counterResult.Counter)."}

    $applicationTests=@()
    foreach($station in @('A01','B02')){
        $self=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $main -SelfTest -FixedStation $station|ConvertFrom-Json
        $falseChecks=@($self.PSObject.Properties|Where-Object{$_.Value-is[bool]-and-not[bool]$_.Value}|ForEach-Object Name)
        if($LASTEXITCODE-ne0-or$self.CsvRows-ne6-or$falseChecks.Count){throw "Application self-test failed for station $station. False checks: $($falseChecks-join', ')"}
        $applicationTests+=[pscustomobject]@{Station=$station;Passed=$true}
    }
    [pscustomobject]@{RequiredFixtures=$required.Count;FixturesExecuted=$detectorResults.Count+1;LaserDetector=$detectorResults;CounterEmptyRejected=$counterOk;ApplicationSelfTests=$applicationTests;Passed=$true}|ConvertTo-Json -Depth 5
}finally{if(Test-Path -LiteralPath $fixtureRoot){[IO.Directory]::Delete($fixtureRoot,$true)}}
