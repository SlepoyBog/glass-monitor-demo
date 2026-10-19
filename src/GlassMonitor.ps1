param(
    [switch]$Headless,
    [switch]$SelfTest,
    [switch]$CenteringSelfTest,
    [switch]$UiLayoutTest,
    [string]$UiLayoutArtifact = '',
    [ValidateSet('','A01','B02')][string]$FixedStation = '',
    [string]$TestImage,
    [string]$TestCounterImage
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]|Out-Null
[Windows.Graphics.Imaging.BitmapDecoder,Windows.Foundation,ContentType=WindowsRuntime]|Out-Null

Add-Type -ReferencedAssemblies 'System.Drawing','System.Windows.Forms' -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

public sealed class CenteredTextButton : Button {
    public CenteredTextButton() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
    }
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.Clear(BackColor);
        TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, ForeColor, BackColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis);
    }
    public void PaintForTest(Graphics graphics, Rectangle clip) { OnPaint(new PaintEventArgs(graphics, clip)); }
}

public sealed class CenteredTextLabel : Label {
    public CenteredTextLabel() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
    }
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.Clear(BackColor);
        TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, ForeColor, BackColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
    }
}

public static class TubeProWindow {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, ref POINT lParam);
    [DllImport("shell32.dll")] static extern int SHGetStockIconInfo(uint id, uint flags, ref SHSTOCKICONINFO info);
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr hIcon);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct SHSTOCKICONINFO { public uint cbSize; public IntPtr hIcon; public int iSysImageIndex; public int iIcon; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string szPath; }

    public static IntPtr Find(out string title) {
        IntPtr found = IntPtr.Zero;
        string foundTitle = null;
        EnumWindows(delegate(IntPtr h, IntPtr p) {
            if (!IsWindowVisible(h)) return true;
            StringBuilder s = new StringBuilder(1024);
            GetWindowText(h, s, s.Capacity);
            string t = s.ToString();
            if (t.StartsWith("TubePro", StringComparison.OrdinalIgnoreCase)) {
                found = h; foundTitle = t; return false;
            }
            return true;
        }, IntPtr.Zero);
        title = foundTitle;
        return found;
    }
    public static Icon GetSettingsIcon() {
        SHSTOCKICONINFO info=new SHSTOCKICONINFO(); info.cbSize=(uint)Marshal.SizeOf(info);
        if(SHGetStockIconInfo(106,0x100,ref info)==0 && info.hIcon!=IntPtr.Zero){try{return (Icon)Icon.FromHandle(info.hIcon).Clone();}finally{DestroyIcon(info.hIcon);}}
        return (Icon)SystemIcons.Application.Clone();
    }
    public static void SetApplicationId(string appId) { SetCurrentProcessExplicitAppUserModelID(appId); }
    public static int GetFirstVisibleLine(IntPtr hWnd) { return SendMessage(hWnd, 0x00CE, IntPtr.Zero, IntPtr.Zero).ToInt32(); }
    public static void RestoreFirstVisibleLine(IntPtr hWnd, int line) {
        int current=GetFirstVisibleLine(hWnd); int delta=line-current;
        if(delta!=0) SendMessage(hWnd, 0x00B6, IntPtr.Zero, new IntPtr(delta));
    }
    public static POINT GetScrollPosition(IntPtr hWnd) { POINT p=new POINT(); SendMessage(hWnd,0x04DD,IntPtr.Zero,ref p); return p; }
    public static void RestoreScrollPosition(IntPtr hWnd, POINT p) { SendMessage(hWnd,0x04DE,IntPtr.Zero,ref p); }
}
'@

if($CenteringSelfTest){
    function Measure-CenteredControl($control,[Drawing.Color]$background){
        $bitmap=New-Object Drawing.Bitmap($control.Width,$control.Height)
        try{
            $control.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)))
            $minY=$bitmap.Height;$maxY=-1
            for($y=0;$y-lt$bitmap.Height;$y++){for($x=0;$x-lt$bitmap.Width;$x++){if($bitmap.GetPixel($x,$y).ToArgb()-ne$background.ToArgb()){$minY=[math]::Min($minY,$y);$maxY=[math]::Max($maxY,$y)}}}
            if($maxY-lt0){throw "Текст не отрисован: $($control.GetType().Name)"}
            $inkCenter=($minY+$maxY)/2.0;$controlCenter=($control.Height-1)/2.0
            [pscustomobject]@{control=$control.GetType().Name;top=$minY;bottom=$maxY;inkCenterY=$inkCenter;controlCenterY=$controlCenter;offsetY=[math]::Round($inkCenter-$controlCenter,2);centered=([math]::Abs($inkCenter-$controlCenter)-le2)}
        }finally{$bitmap.Dispose();$control.Dispose()}
    }
    $yellow=[Drawing.Color]::FromArgb(255,236,0)
    $testButton=New-Object CenteredTextButton;$testButton.Size=New-Object Drawing.Size(236,53);$testButton.BackColor=$yellow;$testButton.ForeColor=[Drawing.Color]::Black;$testButton.Font=New-Object Drawing.Font('Segoe UI Semibold',10);$testButton.Text='Начать наблюдение'
    $testLabel=New-Object CenteredTextLabel;$testLabel.Size=New-Object Drawing.Size(50,46);$testLabel.BackColor=$yellow;$testLabel.ForeColor=[Drawing.Color]::Black;$testLabel.Font=New-Object Drawing.Font('Segoe UI Black',11);$testLabel.Text='LD'
    $results=@(Measure-CenteredControl $testButton $yellow;Measure-CenteredControl $testLabel $yellow)
    $reference=New-Object Drawing.Bitmap(236,53);$partial=New-Object Drawing.Bitmap(236,53);$probe=New-Object CenteredTextButton
    try{
        $probe.Size=New-Object Drawing.Size(236,53);$probe.BackColor=$yellow;$probe.ForeColor=[Drawing.Color]::Black;$probe.Font=New-Object Drawing.Font('Segoe UI Semibold',10);$probe.Text='Выгрузить отчёт'
        $g=[Drawing.Graphics]::FromImage($reference);try{$probe.PaintForTest($g,(New-Object Drawing.Rectangle(0,0,236,53)))}finally{$g.Dispose()}
        $g=[Drawing.Graphics]::FromImage($partial);try{$g.SetClip((New-Object Drawing.Rectangle(0,0,236,26)));$probe.PaintForTest($g,(New-Object Drawing.Rectangle(0,0,236,26)));$g.ResetClip();$g.SetClip((New-Object Drawing.Rectangle(0,26,236,27)));$probe.PaintForTest($g,(New-Object Drawing.Rectangle(0,26,236,27)))}finally{$g.Dispose()}
        $partialPaintStable=$true;for($y=0;$y-lt53-and$partialPaintStable;$y++){for($x=0;$x-lt236;$x++){if($reference.GetPixel($x,$y).ToArgb()-ne$partial.GetPixel($x,$y).ToArgb()){$partialPaintStable=$false;break}}}
    }finally{$probe.Dispose();$reference.Dispose();$partial.Dispose()}
    [pscustomobject]@{Centering=$results;PartialPaintStable=$partialPaintStable}|ConvertTo-Json -Depth 4
    if(@($results|Where-Object{-not$_.centered}).Count-or-not$partialPaintStable){exit 1};exit 0
}

$script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:AppParent = Split-Path -Parent $script:AppRoot
$script:IsPackaged = ((Split-Path -Leaf $script:AppRoot) -eq 'Программа' -and (Split-Path -Leaf $script:AppParent) -like 'Комплект для станка *')
$script:PackageRoot = if($script:IsPackaged){Split-Path -Parent $script:AppRoot}else{$script:AppRoot}
$script:ProjectRoot = if($script:IsPackaged){$null}else{$script:AppParent}
$script:SourceRoot = if($script:IsPackaged){$null}else{$script:ProjectRoot}
$script:DataRoot = if($script:IsPackaged){Join-Path $script:PackageRoot 'Данные станка'}else{Join-Path $script:ProjectRoot 'data'}
$script:ReferenceRoot = if($script:IsPackaged){Join-Path $script:PackageRoot 'Справочники'}else{Join-Path $script:ProjectRoot 'demo\reference'}
$script:ExportsRoot = if($script:IsPackaged){Join-Path $script:PackageRoot 'Выгрузки'}else{Join-Path $script:ProjectRoot 'exports'}
$script:EventsPath = Join-Path $script:DataRoot 'События.csv'
$script:GlassesPath = Join-Path $script:DataRoot 'Ресурс_стекол.csv'
$script:CatalogPath = Join-Path $script:ReferenceRoot 'Справочник_номенклатуры.csv'
$script:TypeBasePath = Join-Path $script:ReferenceRoot 'База_типоразмеров.csv'
$script:DatabaseCheck = $null
$script:CounterPath = Join-Path $script:DataRoot 'Наблюдения_счетчика.csv'
$script:CounterAuditPath = Join-Path $script:DataRoot 'Журнал_распознавания_счетчика.csv'
$script:CounterDiagnosticsRoot = Join-Path $script:DataRoot 'Диагностика счетчика'
$script:CyclesPath = Join-Path $script:DataRoot 'Циклы_метража.csv'
$script:StatePath = Join-Path $script:DataRoot 'state.json'
$script:GlassChangePath = Join-Path $script:DataRoot 'pending-glass-change.json'
$script:ExcelReportScript = Join-Path $script:AppRoot 'ExcelReport.ps1'
if(-not(Test-Path -LiteralPath $script:ExcelReportScript)){throw 'ExcelReport.ps1 не найден рядом с монитором.'}
. $script:ExcelReportScript
$script:MonitorStarted = $false
$script:LaserCandidate = $false
$script:LaserCandidateCount = 0
$script:LaserCandidateUtc = $null
$script:LaserOn = $false
$script:LaserOnUtc = $null
$script:LaserOnJob = ''
$script:LastTitle = ''
$script:LastJob = ''
$script:ActiveGlass = $null
$script:ActiveGlasses = @{}
$script:GlassCounters = @{'A01'=0;'B02'=0}
$script:ExportCounters = @{'A01'=0;'B02'=0}
$script:Session = [ordered]@{active=$false;station='';operator='';startedUtc='';laserOn=$false;laserOnUtc='';job=''}
$script:RecoveryInfo = $null
$script:ClockWarning = ''
$script:StateWarning = ''
$script:SignalAvailable = $null
$script:TotalsByGlass = @{}
$script:ProductionTotalsByGlass = @{}
$script:LastStatusWriteUtc = [datetime]::MinValue
$script:RecentEvents = New-Object System.Collections.ArrayList
$script:SignalLossUtc = $null
$script:UnavailableSeconds = 0.0
$script:AppVersion = '2026.09.23.20'
$script:BuildDate = '2026-09-23'
$script:MinimumFreeBytes = 100MB
$script:LastCounterPollUtc=[datetime]::MinValue
$script:CounterValue=$null
$script:CounterCandidate=$null
$script:CounterCandidateCount=0
$script:CounterStatus='нет данных'
$script:LastCounterOcrText=''
$script:LastCounterCropPng=$null
$script:CounterFailureCount=0
$script:LastCounterDiagnosticUtc=[datetime]::MinValue
$script:DatabaseVersion=''
$script:Production=[ordered]@{active=$false;runId='';job='';startCount=0;lastCount=0;quantity=0;lengthMm=$null;meters=$null;startedLocal='';uncertain=$false}
$script:CounterNeedsRebase=$false
$script:OcrAsTask=([System.WindowsRuntimeSystemExtensions].GetMethods()|Where-Object{$_.Name-eq'AsTask'-and$_.IsGenericMethod-and$_.GetParameters().Count-eq1})[0]

function Ensure-DataRoot {
    if (-not (Test-Path -LiteralPath $script:DataRoot)) {
        [void](New-Item -ItemType Directory -Path $script:DataRoot)
    }
}

function Ensure-ReferenceRoot {if(-not(Test-Path -LiteralPath $script:ReferenceRoot)){[void](New-Item -ItemType Directory -Path $script:ReferenceRoot)}}
function Get-DatabaseVersion { $parts=@($script:CatalogPath,$script:TypeBasePath)|ForEach-Object{if(Test-Path -LiteralPath $_){(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}else{'MISSING'}};$h=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes(($parts-join'|'))))).Replace('-','')}finally{$h.Dispose()} }

function Migrate-LegacyLayout {
    if(-not$script:IsPackaged){return}
    Ensure-DataRoot;Ensure-ReferenceRoot
    foreach($legacyName in @('Monitor_Data','Данные')){
        $legacy=Join-Path $script:PackageRoot $legacyName;if(-not(Test-Path -LiteralPath $legacy)){continue}
        foreach($file in [IO.Directory]::GetFiles($legacy)){
            $leaf=Split-Path -Leaf $file;$destinationRoot=if($leaf-in@('Справочник_номенклатуры.csv','База_типоразмеров.csv')){$script:ReferenceRoot}else{$script:DataRoot};$destination=Join-Path $destinationRoot $leaf
            if(-not(Test-Path -LiteralPath $destination)){[IO.File]::Move($file,$destination);continue}
            $oldHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash;$newHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
            if($oldHash-eq$newHash){[IO.File]::Delete($file)}else{$preserved=Join-Path $destinationRoot (([IO.Path]::GetFileNameWithoutExtension($leaf))+' - перенесено '+(Get-Date -Format 'yyyyMMddHHmmssfff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+[IO.Path]::GetExtension($leaf));[IO.File]::Move($file,$preserved)}
        }
        if([IO.Directory]::GetFileSystemEntries($legacy).Count-eq0){[IO.Directory]::Delete($legacy)}
    }
    $oldBook=Join-Path $script:PackageRoot 'Документация\База типоразмеров.xlsx';if(Test-Path -LiteralPath $oldBook){$newBook=Join-Path $script:ReferenceRoot 'База типоразмеров.xlsx';if(-not(Test-Path -LiteralPath $newBook)){[IO.File]::Move($oldBook,$newBook)}}
}

function Csv-Escape([object]$Value) {
    if ($null -eq $Value) { return '""' }
    return '"' + ([string]$Value).Replace('"','""') + '"'
}

function Append-CsvRow([string]$Path, [string[]]$Headers, [object[]]$Values) {
    Ensure-DataRoot
    $newFile = -not (Test-Path -LiteralPath $Path)
    $utf8 = New-Object System.Text.UTF8Encoding($true)
    $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
        $writer = New-Object System.IO.StreamWriter($stream, $utf8)
        try {
            if ($newFile) { $writer.WriteLine((($Headers | ForEach-Object { Csv-Escape $_ }) -join ';')) }
            $writer.WriteLine((($Values | ForEach-Object { Csv-Escape $_ }) -join ';'))
        } finally { $writer.Dispose() }
    } finally { $stream.Dispose() }
}

function Write-Event([string]$Type, [string]$Details, [Nullable[double]]$DurationSeconds,[string]$JobOverride='') {
    $seconds = if ($null -eq $DurationSeconds) { $null } else { [double]$DurationSeconds }
    $roundedSeconds = if ($null -eq $seconds) { $null } else { [math]::Round($seconds,3) }
    $duration = if ($null -eq $roundedSeconds) { '' } else { $roundedSeconds.ToString([Globalization.CultureInfo]::InvariantCulture) }
    $class = ''
    if ($null -ne $roundedSeconds) {
        if ($roundedSeconds -lt 1.0) { $class = 'короткий импульс' }
        elseif ($roundedSeconds -le 3.0) { $class = 'пробивка/настройка' }
        else { $class = 'рабочая резка' }
    }
    Append-CsvRow $script:EventsPath @('Дата_время','UTC','Станок','Оператор','ID_стекла','Номенклатура','Событие','Длительность_с','Класс','Подробности') @(
        (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'), [datetime]::UtcNow.ToString('o'), $stationBox.Text, $operatorBox.Text,
        $(if($script:ActiveGlass){$script:ActiveGlass.id}else{''}), $(if($JobOverride){$JobOverride}else{$script:LastJob}), $Type, $duration, $class, $Details
    )
    if($script:ActiveGlass -and $null-ne$roundedSeconds){
        $id=[string]$script:ActiveGlass.id
        if(-not$script:TotalsByGlass.ContainsKey($id)){$script:TotalsByGlass[$id]=[ordered]@{seconds=0.0;short=0;setup=0;work=0}}
        $total=$script:TotalsByGlass[$id];$total.seconds=[double]$total.seconds+$roundedSeconds
        if($class-eq'короткий импульс'){$total.short++}elseif($class-eq'пробивка/настройка'){$total.setup++}elseif($class-eq'рабочая резка'){$total.work++}
    }
    [void]$script:RecentEvents.Add(('{0} — {1}{2}' -f (Get-Date -Format 'HH:mm:ss'),$Type,$(if($duration){" ($duration с)"}else{''})))
    while($script:RecentEvents.Count-gt5){$script:RecentEvents.RemoveAt(0)}
}

function Test-DataStorage {
    try {
        Ensure-DataRoot
        $probe=Join-Path $script:DataRoot ('.write-test-'+[guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($probe,'ok',[Text.Encoding]::ASCII);[IO.File]::Delete($probe)
        $root=[IO.Path]::GetPathRoot($script:DataRoot);$drive=New-Object IO.DriveInfo($root)
        if($drive.AvailableFreeSpace-lt$script:MinimumFreeBytes){return "На диске осталось менее 100 МБ."}
        return ''
    } catch {return 'Нет записи в папку данных: '+$_.Exception.Message}
}

function Save-State {
    Ensure-DataRoot
    $state = [ordered]@{schemaVersion=3;activeGlasses=@($script:ActiveGlasses.Values);glassCounters=$script:GlassCounters;exportCounters=$script:ExportCounters;session=$script:Session;production=$script:Production;station=$stationBox.Text;operator=$operatorBox.Text;savedLocal=(Get-Date).ToString('o');savedUtc=[datetime]::UtcNow.ToString('o');utcOffset=(Get-Date).ToString('zzz')}
    $tmp = $script:StatePath + '.tmp'
    [System.IO.File]::WriteAllText($tmp, ($state | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($true)))
    if (Test-Path -LiteralPath $script:StatePath) {
        [System.IO.File]::Copy($script:StatePath,$script:StatePath+'.bak',$true)
        [System.IO.File]::Copy($tmp, $script:StatePath, $true)
        [System.IO.File]::Delete($tmp)
    } else {
        [System.IO.File]::Move($tmp, $script:StatePath)
    }
}

function Reset-LaserDetectionState {
    $script:LaserOn=$false;$script:LaserOnUtc=$null;$script:LaserOnJob='';$script:LaserCandidate=$false;$script:LaserCandidateCount=0;$script:LaserCandidateUtc=$null
}

function Load-State {
    $candidate=$script:StatePath
    if(-not(Test-Path -LiteralPath $candidate)){if(Test-Path -LiteralPath ($script:StatePath+'.bak')){$candidate=$script:StatePath+'.bak'}else{return}}
    try {
        try{$state=Get-Content -Raw -LiteralPath $candidate|ConvertFrom-Json}catch{if($candidate-ne($script:StatePath+'.bak')-and(Test-Path -LiteralPath ($script:StatePath+'.bak'))){$candidate=$script:StatePath+'.bak';$state=Get-Content -Raw -LiteralPath $candidate|ConvertFrom-Json;[IO.File]::Copy($candidate,$script:StatePath,$true);$script:StateWarning='Основное состояние было повреждено и восстановлено из резервной копии.'}else{throw}}
        if ($state.station) { $stationBox.Text = [string]$state.station }
        if ($state.operator) { $operatorBox.Text = [string]$state.operator }
        $stateProps=@($state.psobject.Properties.Name)
        if ($stateProps -contains 'activeGlasses' -and $state.activeGlasses) {
            foreach($glass in @($state.activeGlasses)) { if($glass.station){$script:ActiveGlasses[[string]$glass.station]=$glass} }
        } elseif ($stateProps -contains 'activeGlass' -and $state.activeGlass -and $state.activeGlass.station) {
            # Migration of the first prototype state format.
            $script:ActiveGlasses[[string]$state.activeGlass.station]=$state.activeGlass
        }
        foreach($pair in @(@('glassCounters',$script:GlassCounters),@('exportCounters',$script:ExportCounters))){if($stateProps-contains$pair[0]-and$state.($pair[0])){foreach($prop in $state.($pair[0]).psobject.Properties){$pair[1][[string]$prop.Name]=[int]$prop.Value}}}
        if($stateProps-contains'session'-and$state.session){$script:Session=[ordered]@{active=[bool]$state.session.active;station=[string]$state.session.station;operator=[string]$state.session.operator;startedUtc=[string]$state.session.startedUtc;laserOn=[bool]$state.session.laserOn;laserOnUtc=[string]$state.session.laserOnUtc;job=[string]$state.session.job};if($script:Session.active){$script:RecoveryInfo=$script:Session}}
        if($stateProps-contains'production'-and$state.production){$p=$state.production;$script:Production=[ordered]@{active=[bool]$p.active;runId=[string]$p.runId;job=[string]$p.job;startCount=[int]$p.startCount;lastCount=[int]$p.lastCount;quantity=[int]$p.quantity;lengthMm=$(if($null-ne$p.lengthMm){[double]$p.lengthMm}else{$null});meters=$(if($null-ne$p.meters){[double]$p.meters}else{$null});startedLocal=[string]$p.startedLocal;uncertain=[bool]$p.uncertain};if($script:Production.active){$script:CounterNeedsRebase=$true}}
        if($stateProps-contains'savedUtc'-and$state.savedUtc){$saved=[datetime]::Parse([string]$state.savedUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind);if([datetime]::UtcNow-lt$saved.AddMinutes(-5)){$script:ClockWarning='Системные часы переведены назад.'}}
        if((Get-Date).ToString('zzz')-ne'+05:00'){$script:ClockWarning='Часовой пояс не UTC+05:00; проверьте часы.'}
    } catch {
        [System.Windows.Forms.MessageBox]::Show('Файл состояния не прочитан. Исходные CSV не изменены.','Предупреждение') | Out-Null
    }
}

function Select-ActiveGlassForStation {
    $key=[string]$stationBox.Text
    if($script:ActiveGlasses.ContainsKey($key)){$script:ActiveGlass=$script:ActiveGlasses[$key]}else{$script:ActiveGlass=$null}
}

function New-FriendlyGlassId([string]$Station) {
    if(-not$script:GlassCounters.ContainsKey($Station)){$script:GlassCounters[$Station]=0}
    $script:GlassCounters[$Station]=[int]$script:GlassCounters[$Station]+1
    return ('Стекло {0}-{1:0000}' -f $Station,$script:GlassCounters[$Station])
}

function Rebuild-GlassTotals {
    $script:TotalsByGlass=@{}
    if(-not(Test-Path -LiteralPath $script:EventsPath)){return}
    foreach($row in @(Import-Csv -LiteralPath $script:EventsPath -Delimiter ';')){
        if([string]::IsNullOrWhiteSpace($row.'ID_стекла')-or[string]::IsNullOrWhiteSpace($row.'Длительность_с')){continue}
        $id=[string]$row.'ID_стекла';if(-not$script:TotalsByGlass.ContainsKey($id)){$script:TotalsByGlass[$id]=[ordered]@{seconds=0.0;short=0;setup=0;work=0}}
        $total=$script:TotalsByGlass[$id];$total.seconds=[double]$total.seconds+[double]::Parse($row.'Длительность_с',[Globalization.CultureInfo]::InvariantCulture)
        if($row.'Класс'-eq'короткий импульс'){$total.short++}elseif($row.'Класс'-eq'пробивка/настройка'){$total.setup++}elseif($row.'Класс'-eq'рабочая резка'){$total.work++}
    }
}

function Rebuild-ProductionTotals {
    $script:ProductionTotalsByGlass=@{}
    if(-not(Test-Path -LiteralPath $script:CyclesPath)){return}
    foreach($row in @(Import-Csv -LiteralPath $script:CyclesPath -Delimiter ';')){
        $id=[string]$row.'ID_стекла';if([string]::IsNullOrWhiteSpace($id)){continue}
        if(-not$script:ProductionTotalsByGlass.ContainsKey($id)){$script:ProductionTotalsByGlass[$id]=[ordered]@{quantity=0;meters=0.0;hasMeters=$false}}
        $total=$script:ProductionTotalsByGlass[$id]
        $parsedQuantity=0;if([int]::TryParse([string]$row.'Количество',[ref]$parsedQuantity)){$total.quantity=[int]$total.quantity+$parsedQuantity}
        $parsedMeters=0.0;if([double]::TryParse(([string]$row.'Метраж').Replace(',','.'),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsedMeters)){$total.meters=[double]$total.meters+$parsedMeters;$total.hasMeters=$true}
    }
}

function Get-DisplayedProductionTotals {
    $quantity=0;$meters=0.0;$hasMeters=$false
    if($script:ActiveGlass){$id=[string]$script:ActiveGlass.id;if($script:ProductionTotalsByGlass.ContainsKey($id)){$closed=$script:ProductionTotalsByGlass[$id];$quantity=[int]$closed.quantity;$meters=[double]$closed.meters;$hasMeters=[bool]$closed.hasMeters}}
    if($script:Production.active){$quantity+=[int]$script:Production.quantity;if($null-ne$script:Production.meters){$meters+=[double]$script:Production.meters;$hasMeters=$true}}
    [pscustomobject]@{quantity=$quantity;meters=[math]::Round($meters,3);hasMeters=$hasMeters}
}

function Format-Duration([double]$Seconds) {
    $span=[timespan]::FromSeconds([math]::Max(0,$Seconds))
    if($span.TotalDays-ge1){return ('{0} дн. {1:00}:{2:00}:{3:00}' -f [math]::Floor($span.TotalDays),$span.Hours,$span.Minutes,$span.Seconds)}
    return ('{0:00}:{1:00}:{2:00}' -f [math]::Floor($span.TotalHours),$span.Minutes,$span.Seconds)
}

function Await-Ocr($Operation,[Type]$ResultType){$task=$script:OcrAsTask.MakeGenericMethod($ResultType).Invoke($null,@($Operation));return $task.GetAwaiter().GetResult()}

function Invoke-DigitOcr([Drawing.Bitmap]$Source){$large=$null;$ms=$null;$ras=$null;$software=$null;try{$large=New-Object Drawing.Bitmap($Source,[Drawing.Size]::new($Source.Width*8,$Source.Height*8));$ms=New-Object IO.MemoryStream;$large.Save($ms,[Drawing.Imaging.ImageFormat]::Png);$ms.Position=0;$ras=[IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($ms);$decoder=Await-Ocr ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder]);$software=Await-Ocr ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap]);$engine=[Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages();if($null-eq$engine){return $null};$result=Await-Ocr ($engine.RecognizeAsync($software)) ([Windows.Media.Ocr.OcrResult]);$text=[string]$result.Text;$numbers=@([regex]::Matches($text,'(?<!\d)\d{1,7}(?!\d)')|ForEach-Object{[int]$_.Value});if($numbers.Count-eq1){return [pscustomobject]@{Value=$numbers[0];Text=$text}};return $null}catch{return $null}finally{if($software){$software.Dispose()};if($ras){$ras.Dispose()};if($ms){$ms.Dispose()};if($large){$large.Dispose()}}}

function Read-CounterCrop([Drawing.Bitmap]$Crop){$plain=Invoke-DigitOcr $Crop;if($plain){$script:LastCounterOcrText=$plain.Text;return $plain.Value};$binary=$Crop.Clone();try{for($py=0;$py-lt$binary.Height;$py++){for($px=0;$px-lt$binary.Width;$px++){$c=$binary.GetPixel($px,$py);$gray=([int]$c.R+[int]$c.G+[int]$c.B)/3;$binary.SetPixel($px,$py,$(if($gray-lt170){[Drawing.Color]::Black}else{[Drawing.Color]::White}))}};$result=Invoke-DigitOcr $binary;if($result){$script:LastCounterOcrText=$result.Text;return $result.Value};return $null}finally{$binary.Dispose()}}

function Read-CounterFromBitmap([Drawing.Bitmap]$Bitmap,[int]$WindowHeight=0) {
    if($WindowHeight-le0){$WindowHeight=$Bitmap.Height;if($Bitmap.Height-ge1000){$WindowHeight=$Bitmap.Height-40}}
    $x=[int]($Bitmap.Width*.758);$y=[int]($WindowHeight*.906);$w=[int]($Bitmap.Width*.07);$h=[int]($WindowHeight*.022)
    if($x-lt0-or$y-lt0-or$x+$w-gt$Bitmap.Width-or$y+$h-gt$Bitmap.Height){return $null}
    $crop=New-Object Drawing.Bitmap($w,$h,[Drawing.Imaging.PixelFormat]::Format24bppRgb);$g=[Drawing.Graphics]::FromImage($crop)
    try{
        $g.DrawImage($Bitmap,(New-Object Drawing.Rectangle(0,0,$w,$h)),(New-Object Drawing.Rectangle($x,$y,$w,$h)),[Drawing.GraphicsUnit]::Pixel)
        return Read-CounterCrop $crop
    }catch{return $null}finally{$g.Dispose();$crop.Dispose()}
}

function Get-CounterSnapshot {
    $title=$null;$handle=[TubeProWindow]::Find([ref]$title);if($handle-eq[IntPtr]::Zero-or[TubeProWindow]::IsIconic($handle)){return $null}
    $rect=New-Object TubeProWindow+RECT;if(-not[TubeProWindow]::GetWindowRect($handle,[ref]$rect)){return $null};$w=$rect.Right-$rect.Left;$h=$rect.Bottom-$rect.Top
    $x=[int]($w*.758);$y=[int]($h*.906);$cw=[int]($w*.07);$ch=[int]($h*.022);$bmp=New-Object Drawing.Bitmap($cw,$ch,[Drawing.Imaging.PixelFormat]::Format24bppRgb);$g=[Drawing.Graphics]::FromImage($bmp)
    try{$g.CopyFromScreen($rect.Left+$x,$rect.Top+$y,0,0,$bmp.Size,[Drawing.CopyPixelOperation]::SourceCopy);$ms=New-Object IO.MemoryStream;try{$bmp.Save($ms,[Drawing.Imaging.ImageFormat]::Png);$script:LastCounterCropPng=$ms.ToArray()}finally{$ms.Dispose()};return Read-CounterCrop $bmp}finally{$g.Dispose();$bmp.Dispose()}
}

function Ensure-Catalog {
    Ensure-ReferenceRoot
    if(-not(Test-Path -LiteralPath $script:CatalogPath)){Append-CsvRow $script:CatalogPath @('Номенклатура','Длина_детали_мм','Примечание') @('','','');$lines=Get-Content -LiteralPath $script:CatalogPath;if($lines.Count-gt1){[IO.File]::WriteAllLines($script:CatalogPath,@($lines[0]),(New-Object Text.UTF8Encoding($true)))}}
}

function Get-JobLengthMm([string]$Job){
    Ensure-Catalog
    foreach($row in @(Import-Csv -LiteralPath $script:CatalogPath -Delimiter ';')){if($row.'Номенклатура'-eq$Job-and-not[string]::IsNullOrWhiteSpace($row.'Длина_детали_мм')){try{return [double]::Parse(([string]$row.'Длина_детали_мм').Replace(',','.'),[Globalization.CultureInfo]::InvariantCulture)}catch{return $null}}}
    if(-not(Test-Path -LiteralPath $script:TypeBasePath)){return $null}
    if($script:DatabaseCheck-and-not$script:DatabaseCheck.TypeBaseValid){return $null}
    $name=[IO.Path]::GetFileNameWithoutExtension($Job).ToLowerInvariant();$type='';$subtype=''
    $specialPattern='(?:^|[_\s.\-])(рп|сдз)(?:[_\s.\-]|$)'
    if($name-match'корпус'){$type=if($name-match'муфтов'){'Корпус муфтовый'}elseif($name-match'под\s*врез'){'Корпус под врезку'}elseif($name-match$specialPattern){'Корпус РП/СДЗ'}else{'Корпус'}}
    elseif($name-match'патруб'){
        if($name-match'regula'){$type='Патрубок фланцевый REGULA'}elseif($name-match'energy'){$type='Патрубок фланцевый Energy Gas'}elseif($name-match$specialPattern){$type='Патрубок фланцевый РП/СДЗ'}elseif($name-match'привар'){$type='Патрубок приварной';if($name-match'нсд'){$subtype='НСД'}elseif($name-match'ссд'){$subtype='ССД'}}elseif($name-match'фланц'){$type='Патрубок фланцевый ГАЗ/ВОДА'}
    }
    $dnMatch=[regex]::Match($name,'ду\s*(\d+)\s*[_/]\s*(\d+)','IgnoreCase');if(-not$dnMatch.Success-or-not$type){return $null};$dn=$dnMatch.Groups[1].Value+'/'+$dnMatch.Groups[2].Value
    $matches=@(Import-Csv -LiteralPath $script:TypeBasePath -Delimiter ';'|Where-Object{$baseDn=(([string]$_.'DN')-replace'(?i)^ду\s*','')-replace'_','/';$_.'Тип_детали'-eq$type-and$baseDn-eq$dn-and$_.'Статус'-eq'однозначно'-and([string]::IsNullOrWhiteSpace($subtype)-or$_.'Подтип'-eq$subtype)})
    $lengths=@($matches|ForEach-Object{$_.'Длина_номинал_мм'}|Where-Object{$_}|Sort-Object -Unique);if($lengths.Count-ne1){return $null}
    try{return [double]::Parse(([string]$lengths[0]).Replace(',','.'),[Globalization.CultureInfo]::InvariantCulture)}catch{return $null}
}

function Close-ProductionCycle([string]$Reason) {
    if(-not$script:Production.active){return}
    $meters=if($null-ne$script:Production.lengthMm){[math]::Round(([double]$script:Production.quantity*[double]$script:Production.lengthMm/1000),3)}else{''}
    Append-CsvRow $script:CyclesPath @('Начало','Окончание','Станок','Оператор','ID_стекла','Номенклатура','ID_цикла','Начальный_счетчик','Конечный_счетчик','Количество','Длина_детали_мм','Метраж','Статус','Причина_закрытия') @($script:Production.startedLocal,(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'),$stationBox.Text,$operatorBox.Text,$(if($script:ActiveGlass){$script:ActiveGlass.id}else{''}),$script:Production.job,$script:Production.runId,$script:Production.startCount,$script:Production.lastCount,$script:Production.quantity,$(if($null-ne$script:Production.lengthMm){$script:Production.lengthMm}else{''}),$meters,$(if($script:Production.uncertain){'теневой: требует проверки'}elseif($null-eq$script:Production.lengthMm){'теневой: нет длины'}else{'теневой'}),$Reason)
    if($script:ActiveGlass){$id=[string]$script:ActiveGlass.id;if(-not$script:ProductionTotalsByGlass.ContainsKey($id)){$script:ProductionTotalsByGlass[$id]=[ordered]@{quantity=0;meters=0.0;hasMeters=$false}};$closed=$script:ProductionTotalsByGlass[$id];$closed.quantity=[int]$closed.quantity+[int]$script:Production.quantity;if($meters-ne''){$closed.meters=[double]$closed.meters+[double]$meters;$closed.hasMeters=$true}}
    $script:Production=[ordered]@{active=$false;runId='';job='';startCount=0;lastCount=0;quantity=0;lengthMm=$null;meters=$null;startedLocal='';uncertain=$false}
    Save-State
}

function Write-PendingGlassChange($Transaction){
    Ensure-DataRoot;$tmp=$script:GlassChangePath+'.tmp';[IO.File]::WriteAllText($tmp,($Transaction|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($true)));if(Test-Path -LiteralPath $script:GlassChangePath){[IO.File]::Delete($script:GlassChangePath)};[IO.File]::Move($tmp,$script:GlassChangePath)
}

function Complete-PendingGlassChange {
    if(-not(Test-Path -LiteralPath $script:GlassChangePath)){return}
    $tx=Get-Content -Raw -LiteralPath $script:GlassChangePath -Encoding UTF8|ConvertFrom-Json
    if(-not$tx.id-or-not$tx.newGlass-or-not$tx.station){throw 'Файл незавершённой замены стекла повреждён.'}
    if($tx.oldGlass){
        $alreadyRemoved=$false
        if(Test-Path -LiteralPath $script:GlassesPath){$alreadyRemoved=@(Import-Csv -LiteralPath $script:GlassesPath -Delimiter ';'|Where-Object{[string]$_.ID_стекла-eq[string]$tx.oldGlass.id-and[string]$_.Снято-eq[string]$tx.removedLocal}).Count-gt0}
        if(-not$alreadyRemoved){Append-CsvRow $script:GlassesPath @('ID_стекла','Станок','Оператор_установки','Установлено','Снято','Оператор_снятия','Причина') @($tx.oldGlass.id,$tx.oldGlass.station,$tx.oldGlass.operator,$tx.oldGlass.installedLocal,$tx.removedLocal,$tx.operator,$tx.reason)}
    }
    $script:ActiveGlass=$tx.newGlass;$script:ActiveGlasses[[string]$tx.station]=$script:ActiveGlass
    $suffix=[regex]::Match([string]$tx.newGlass.id,'(\d+)$');if($suffix.Success){$n=[int]$suffix.Groups[1].Value;if($n-gt[int]$script:GlassCounters[[string]$tx.station]){$script:GlassCounters[[string]$tx.station]=$n}}
    Save-State
    $eventDetails="Операция: $($tx.id)";$existingEvents=if(Test-Path -LiteralPath $script:EventsPath){@(Import-Csv -LiteralPath $script:EventsPath -Delimiter ';')}else{@()}
    if($tx.oldGlass-and-not@($existingEvents|Where-Object{$_.Событие-eq'стекло снято'-and$_.Подробности-like"Операция: $($tx.id)*"}).Count){$removedUtc=if($tx.PSObject.Properties.Name-contains'removedUtc'){$tx.removedUtc}else{[datetime]::UtcNow.ToString('o')};Append-CsvRow $script:EventsPath @('Дата_время','UTC','Станок','Оператор','ID_стекла','Номенклатура','Событие','Длительность_с','Класс','Подробности') @($tx.removedLocal,$removedUtc,$tx.station,$tx.operator,$tx.oldGlass.id,$script:LastJob,'стекло снято','','',("$eventDetails; причина: $($tx.reason)"+$(if($tx.note){"; примечание: $($tx.note)"}else{''})))}
    if(-not@($existingEvents|Where-Object{$_.Событие-eq'стекло установлено'-and$_.Подробности-eq$eventDetails}).Count){Append-CsvRow $script:EventsPath @('Дата_время','UTC','Станок','Оператор','ID_стекла','Номенклатура','Событие','Длительность_с','Класс','Подробности') @($tx.newGlass.installedLocal,$tx.newGlass.installedUtc,$tx.station,$tx.operator,$tx.newGlass.id,$script:LastJob,'стекло установлено','','',$eventDetails)}
    [IO.File]::Delete($script:GlassChangePath)
}

function Accept-CounterValue([int]$Value) {
    if([string]::IsNullOrWhiteSpace($script:LastJob)){$script:CounterStatus='нет номенклатуры';return}
    if($script:CounterNeedsRebase-and$script:Production.active){Close-ProductionCycle 'перерыв наблюдения — прирост не начислялся';$script:Production=[ordered]@{active=$true;runId=[guid]::NewGuid().ToString('N');job=$script:LastJob;startCount=$Value;lastCount=$Value;quantity=0;lengthMm=(Get-JobLengthMm $script:LastJob);meters=$null;startedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');uncertain=$false};$script:CounterNeedsRebase=$false;$script:CounterStatus='новая база после перерыва';Save-State;return}
    if(-not$script:Production.active-or$script:Production.job-ne$script:LastJob){Close-ProductionCycle 'смена номенклатуры';$script:Production=[ordered]@{active=$true;runId=[guid]::NewGuid().ToString('N');job=$script:LastJob;startCount=$Value;lastCount=$Value;quantity=0;lengthMm=(Get-JobLengthMm $script:LastJob);meters=$null;startedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');uncertain=$false};$script:CounterStatus='база установлена';Save-State;return}
    if($Value-lt[int]$script:Production.lastCount){Close-ProductionCycle 'счётчик уменьшился/сброшен';$script:Production=[ordered]@{active=$true;runId=[guid]::NewGuid().ToString('N');job=$script:LastJob;startCount=$Value;lastCount=$Value;quantity=0;lengthMm=(Get-JobLengthMm $script:LastJob);meters=$null;startedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');uncertain=$false};$script:CounterStatus='новый цикл после сброса';Save-State;return}
    if($Value-eq[int]$script:Production.lastCount){$script:CounterStatus='подтверждён';return}
    $delta=$Value-[int]$script:Production.lastCount
    if($delta-gt200){
        Close-ProductionCycle 'скачок счётчика более 200 — прирост не начислен'
        $script:Production=[ordered]@{active=$true;runId=[guid]::NewGuid().ToString('N');job=$script:LastJob;startCount=$Value;lastCount=$Value;quantity=0;lengthMm=(Get-JobLengthMm $script:LastJob);meters=$null;startedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');uncertain=$true}
        Append-CsvRow $script:CounterPath @('Дата_время','Станок','Оператор','ID_стекла','Номенклатура','ID_цикла','Счетчик','Прирост','Количество_цикла','Длина_детали_мм','Метраж','Режим','Примечание') @((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'),$stationBox.Text,$operatorBox.Text,$(if($script:ActiveGlass){$script:ActiveGlass.id}else{''}),$script:Production.job,$script:Production.runId,$Value,0,0,$(if($null-ne$script:Production.lengthMm){$script:Production.lengthMm}else{''}),'','теневой','скачок более 200 заблокирован; установлена новая база')
        $script:CounterStatus='скачок заблокирован, установлена новая база';Save-State;return
    }
    $script:Production.lastCount=$Value;$script:Production.quantity=[int]$script:Production.quantity+$delta
    if($null-ne$script:Production.lengthMm){$script:Production.meters=[math]::Round(([double]$script:Production.quantity*[double]$script:Production.lengthMm/1000),3)}
    Append-CsvRow $script:CounterPath @('Дата_время','Станок','Оператор','ID_стекла','Номенклатура','ID_цикла','Счетчик','Прирост','Количество_цикла','Длина_детали_мм','Метраж','Режим','Примечание') @((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'),$stationBox.Text,$operatorBox.Text,$(if($script:ActiveGlass){$script:ActiveGlass.id}else{''}),$script:Production.job,$script:Production.runId,$Value,$delta,$script:Production.quantity,$(if($null-ne$script:Production.lengthMm){$script:Production.lengthMm}else{''}),$(if($null-ne$script:Production.meters){$script:Production.meters}else{''}),'теневой',$(if($delta-gt200){'скачок более 200 — требует проверки'}else{''}))
    $script:CounterStatus=$(if($delta-gt200){'скачок требует проверки'}elseif($null-eq$script:Production.lengthMm){'счёт идёт, длина не задана'}else{'теневой расчёт'});Save-State
}

function Save-CounterDiagnostic([string]$Reason){if(-not$script:LastCounterCropPng-or([datetime]::UtcNow-$script:LastCounterDiagnosticUtc).TotalSeconds-lt30){return ''};[void][IO.Directory]::CreateDirectory($script:CounterDiagnosticsRoot);$safe=($Reason-replace'[^\p{L}\p{Nd}_-]','_');$path=Join-Path $script:CounterDiagnosticsRoot ((Get-Date -Format 'yyyyMMdd_HHmmss_fff')+'_'+$safe+'.png');[IO.File]::WriteAllBytes($path,$script:LastCounterCropPng);$script:LastCounterDiagnosticUtc=[datetime]::UtcNow;Split-Path -Leaf $path}
function Write-CounterAudit($Value,[int]$Repeats,[string]$Decision,[string]$Reason,[string]$Image=''){Append-CsvRow $script:CounterAuditPath @('Дата_время','UTC','Станок','Оператор','ID_стекла','Номенклатура','Текст_OCR','Распознанное_число','Кандидат','Повторов','Решение','Причина','Снимок') @((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'),[datetime]::UtcNow.ToString('o'),$stationBox.Text,$operatorBox.Text,$(if($script:ActiveGlass){$script:ActiveGlass.id}else{''}),$script:LastJob,$script:LastCounterOcrText,$(if($null-ne$Value){$Value}else{''}),$(if($null-ne$script:CounterCandidate){$script:CounterCandidate}else{''}),$Repeats,$Decision,$Reason,$Image)}
function Process-CounterCandidate($Value){
    if($null-eq$Value){$script:CounterFailureCount++;$script:CounterCandidate=$null;$script:CounterCandidateCount=0;$script:CounterStatus='не распознан';if($script:CounterFailureCount-eq1-or$script:CounterFailureCount%10-eq0){$image=if($script:CounterFailureCount-ge5){Save-CounterDiagnostic 'не_распознано'}else{''};Write-CounterAudit $null 0 'отклонено' ("не распознано подряд: $($script:CounterFailureCount)") $image};return}
    $script:CounterFailureCount=0;if($script:CounterCandidate-eq$Value){$script:CounterCandidateCount++}else{$script:CounterCandidate=$Value;$script:CounterCandidateCount=1;Write-CounterAudit $Value 1 'ожидание' 'новый кандидат'}
    if($script:CounterCandidateCount-eq2){Write-CounterAudit $Value 2 'ожидание' 'нужно третье совпадение'}
    if($script:CounterCandidateCount-ge3-and$script:CounterValue-ne$Value){$script:CounterValue=[int]$Value;Accept-CounterValue ([int]$Value);$image=if($script:CounterStatus-match'скачок|сброс'){Save-CounterDiagnostic $script:CounterStatus}else{''};Write-CounterAudit $Value $script:CounterCandidateCount 'принято' $script:CounterStatus $image}
}

function Recover-InterruptedSession {
    if(-not$script:RecoveryInfo){return}
    $oldStation=[string]$stationBox.Text;$oldOperator=[string]$operatorBox.Text;$oldJob=$script:LastJob
    try {
        if($script:RecoveryInfo.station){$stationBox.Text=[string]$script:RecoveryInfo.station;Select-ActiveGlassForStation}
        if($script:RecoveryInfo.operator){$operatorBox.Text=[string]$script:RecoveryInfo.operator}
        $script:LastJob=[string]$script:RecoveryInfo.job
        if([bool]$script:RecoveryInfo.laserOn){Write-Event 'интервал лазера прерван' 'Окончание и длительность неизвестны: предыдущий запуск завершился без штатной остановки.' $null}
        Write-Event 'предыдущий сеанс прерван' 'Монитор восстановил состояние после нештатного завершения; длительность не вычислялась.' $null
    } finally {
        $script:Session=[ordered]@{active=$false;station='';operator='';startedUtc='';laserOn=$false;laserOnUtc='';job=''}
        $script:LastJob=$oldJob
        if(-not[string]::IsNullOrWhiteSpace($FixedStation)){$stationBox.Text=$FixedStation}else{$stationBox.Text=$oldStation}
        $operatorBox.Text=$oldOperator;Select-ActiveGlassForStation;Save-State
    }
}

function Export-DataToFolder([string]$BaseFolder,[string]$Station,[switch]$SkipExcel) {
    Save-State
    $emptyFiles=@(
        @($script:EventsPath,@('Дата_время','UTC','Станок','Оператор','ID_стекла','Номенклатура','Событие','Длительность_с','Класс','Подробности')),
        @($script:GlassesPath,@('ID_стекла','Станок','Оператор_установки','Установлено','Снято','Оператор_снятия','Причина')),
        @($script:CounterPath,@('Дата_время','Станок','Оператор','ID_стекла','Номенклатура','ID_цикла','Счетчик','Прирост','Количество_цикла','Длина_детали_мм','Метраж','Режим','Примечание')),
        @($script:CounterAuditPath,@('Дата_время','UTC','Станок','Оператор','ID_стекла','Номенклатура','Текст_OCR','Распознанное_число','Кандидат','Повторов','Решение','Причина','Снимок')),
        @($script:CyclesPath,@('Начало','Окончание','Станок','Оператор','ID_стекла','Номенклатура','ID_цикла','Начальный_счетчик','Конечный_счетчик','Количество','Длина_детали_мм','Метраж','Статус','Причина_закрытия'))
    )
    foreach($spec in $emptyFiles){if(-not(Test-Path -LiteralPath $spec[0])){$line=(@($spec[1])|ForEach-Object{Csv-Escape $_})-join';';[IO.File]::WriteAllText([string]$spec[0],$line+[Environment]::NewLine,(New-Object Text.UTF8Encoding($true)))}}
    $sourceFiles=@($script:EventsPath,$script:GlassesPath,$script:CatalogPath,$script:TypeBasePath,$script:CounterPath,$script:CounterAuditPath,$script:CyclesPath,$script:StatePath)|Where-Object{Test-Path -LiteralPath $_}
    if($sourceFiles.Count-eq0){throw 'Данных для выгрузки пока нет.'}
    $next=if($script:ExportCounters.ContainsKey($Station)){[int]$script:ExportCounters[$Station]+1}else{1}
    $name='Отчет_{0}_{1:0000}_{2}' -f $Station,$next,(Get-Date -Format 'yyyyMMdd_HHmmss')
    $target=Join-Path $BaseFolder $name
    $finalTarget=$target
    if(Test-Path -LiteralPath $finalTarget){throw "Export folder already exists: $finalTarget"}
    $target=$finalTarget+'.building-'+[guid]::NewGuid().ToString('N')
    [void][System.IO.Directory]::CreateDirectory($target)
    $technical=Join-Path $target 'Технические данные'
    [void][System.IO.Directory]::CreateDirectory($technical)
    foreach($source in $sourceFiles){
        $dest=Join-Path $technical (Split-Path -Leaf $source)
        [System.IO.File]::Copy($source,$dest,$false)
    }
    if(Test-Path -LiteralPath $script:CounterDiagnosticsRoot){Copy-Item -LiteralPath $script:CounterDiagnosticsRoot -Destination (Join-Path $technical 'Диагностика счетчика') -Recurse}
    if(-not$SkipExcel){$xlsx=Join-Path $target ("Учет ресурса стекол станок $Station.xlsx");$null=New-GlassExcelReport -EventsPath (Join-Path $technical 'События.csv') -GlassesPath (Join-Path $technical 'Ресурс_стекол.csv') -CatalogPath (Join-Path $technical 'Справочник_номенклатуры.csv') -TypeBasePath (Join-Path $technical 'База_типоразмеров.csv') -CounterPath (Join-Path $technical 'Наблюдения_счетчика.csv') -CounterAuditPath (Join-Path $technical 'Журнал_распознавания_счетчика.csv') -CyclesPath (Join-Path $technical 'Циклы_метража.csv') -Station $Station -OutputPath $xlsx -AppVersion $script:AppVersion -DatabaseVersion $script:DatabaseVersion}
    $manifest=@()
    foreach($dest in [IO.Directory]::GetFiles($target,'*',[IO.SearchOption]::AllDirectories)){
        $hash=[Security.Cryptography.SHA256]::Create()
        try{$stream=[IO.File]::OpenRead($dest);try{$hex=([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','')}finally{$stream.Dispose()}}finally{$hash.Dispose()}
        $item=Get-Item -LiteralPath $dest
        $relative=$dest.Substring($target.Length).TrimStart('\')
        $manifest+=[pscustomobject]@{file=$relative;bytes=$item.Length;sha256=$hex}
    }
    $meta=[ordered]@{station=$Station;appVersion=$script:AppVersion;databaseVersion=$script:DatabaseVersion;exportedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');exportedUtc=[datetime]::UtcNow.ToString('o');files=$manifest}
    [IO.File]::WriteAllText((Join-Path $target 'manifest.json'),($meta|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($true)))
    [IO.Directory]::Move($target,$finalTarget)
    $target=$finalTarget
    $script:ExportCounters[$Station]=$next;Save-State
    return $target
}

function Export-Report {
    if($script:MonitorStarted){[Windows.Forms.MessageBox]::Show('Сначала остановите наблюдение.')|Out-Null;return}
    $dialog=New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description='Выберите флешку или папку, куда создать копию отчёта.'
    $dialog.ShowNewFolderButton=$true
    if(Test-Path -LiteralPath $script:ExportsRoot){$dialog.SelectedPath=$script:ExportsRoot}
    try {
        if($dialog.ShowDialog()-ne[Windows.Forms.DialogResult]::OK){return}
        $operationLabel.Text='Формируется выгрузка и проверяются файлы...'
        $operationProgress.Style=[Windows.Forms.ProgressBarStyle]::Marquee
        $operationProgress.MarqueeAnimationSpeed=28
        $operationProgress.Visible=$true
        [Windows.Forms.Application]::DoEvents()
        $target=Export-DataToFolder $dialog.SelectedPath $stationBox.Text
        [Windows.Forms.MessageBox]::Show("Отчёт создан:`r`n$target",'Выгрузка завершена')|Out-Null
    } catch {
        [Windows.Forms.MessageBox]::Show("Выгрузка не выполнена. Журналы наблюдения не изменены.`r`n$($_.Exception.Message)",'Ошибка выгрузки')|Out-Null
    } finally {
        $operationProgress.Visible=$false
        $operationProgress.MarqueeAnimationSpeed=0
        $operationLabel.Text=''
        $dialog.Dispose()
    }
}

function Parse-JobFromTitle([string]$Title) {
    if ([string]::IsNullOrWhiteSpace($Title)) { return '' }
    $m = [regex]::Match($Title, '^TubePro\s+(.+?\.(?:zx|zzx))\s*(?:\[|$)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Get-TubeProSnapshot {
    $title = $null
    $handle = [TubeProWindow]::Find([ref]$title)
    if ($handle -eq [IntPtr]::Zero) { return [pscustomobject]@{Found=$false;Available=$false;Minimized=$false;Title='';Job='';LaserBrightPixels=0;LaserOn=$false} }
    if([TubeProWindow]::IsIconic($handle)){return [pscustomobject]@{Found=$true;Available=$false;Minimized=$true;Title=$title;Job=(Parse-JobFromTitle $title);LaserBrightPixels=0;LaserOn=$false}}
    $rect = New-Object TubeProWindow+RECT
    if (-not [TubeProWindow]::GetWindowRect($handle,[ref]$rect)) { return [pscustomobject]@{Found=$false;Available=$false;Minimized=$false;Title='';Job='';LaserBrightPixels=0;LaserOn=$false} }
    $w=$rect.Right-$rect.Left; $h=$rect.Bottom-$rect.Top
    if ($w -lt 600 -or $h -lt 500) { return [pscustomobject]@{Found=$true;Available=$false;Minimized=$false;Title=$title;Job=(Parse-JobFromTitle $title);LaserBrightPixels=0;LaserOn=$false} }

    # Only the upper-right TubePro control strip is copied. No image is saved.
    $x=[int]($w*0.86); $y=[int]($h*0.055); $cw=[int]($w*0.13); $ch=[int]($h*0.11)
    $bmp=New-Object System.Drawing.Bitmap($cw,$ch,[Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g=[Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CopyFromScreen($rect.Left+$x,$rect.Top+$y,0,0,$bmp.Size,[Drawing.CopyPixelOperation]::SourceCopy)
        $bright=0;$surface=0
        for($py=0;$py -lt $ch;$py+=2){
            for($px=0;$px -lt $cw;$px+=2){
                $c=$bmp.GetPixel($px,$py)
                if($c.R -ge 225 -and $c.G -ge 65 -and $c.G -le 165 -and $c.B -le 120){$bright++}
                if(([math]::Abs($c.R-$c.G)-le25-and[math]::Abs($c.G-$c.B)-le25-and$c.R-ge100-and$c.R-le245)-or($c.R-ge180-and$c.G-ge50-and$c.G-le190-and$c.B-le140)){$surface++}
            }
        }
        $available=($surface-ge100)
        return [pscustomobject]@{Found=$true;Available=$available;Minimized=$false;Title=$title;Job=(Parse-JobFromTitle $title);LaserBrightPixels=$bright;LaserOn=($available-and$bright -ge 25)}
    } finally { $g.Dispose(); $bmp.Dispose() }
}

function Analyze-TestImage([string]$Path) {
    $bmp=[Drawing.Bitmap]::FromFile($Path)
    try {
        $x=[int]($bmp.Width*0.86); $y=[int]($bmp.Height*0.055); $cw=[int]($bmp.Width*0.13); $ch=[int]($bmp.Height*0.11); $bright=0
        for($py=$y;$py -lt [math]::Min($bmp.Height,$y+$ch);$py+=2){for($px=$x;$px -lt [math]::Min($bmp.Width,$x+$cw);$px+=2){$c=$bmp.GetPixel($px,$py);if($c.R-ge225-and$c.G-ge65-and$c.G-le165-and$c.B-le120){$bright++}}}
        return [pscustomobject]@{Path=$Path;Width=$bmp.Width;Height=$bmp.Height;BrightOrangeSamples=$bright;LaserOn=($bright-ge25)}
    } finally {$bmp.Dispose()}
}

if ($Headless) {
    if(-not[string]::IsNullOrWhiteSpace($TestCounterImage)){$bmp=[Drawing.Bitmap]::FromFile($TestCounterImage);try{$value=Read-CounterFromBitmap $bmp;[pscustomobject]@{Path=$TestCounterImage;Counter=$value;OcrText=$script:LastCounterOcrText}|ConvertTo-Json}finally{$bmp.Dispose()};exit 0}
    if ([string]::IsNullOrWhiteSpace($TestImage)) { throw 'Headless mode requires -TestImage or -TestCounterImage.' }
    Analyze-TestImage $TestImage | ConvertTo-Json
    exit 0
}

if ($SelfTest) {
    $sourceTypeBaseForTest=$script:TypeBasePath
    $testBase = Join-Path ([IO.Path]::GetTempPath()) 'glass-monitor-demo'
    if (-not (Test-Path -LiteralPath $testBase)) { [void](New-Item -ItemType Directory -Path $testBase) }
    $testRoot = Join-Path $testBase ('glass-monitor-selftest-' + [guid]::NewGuid().ToString('N'))
    $script:DataRoot = $testRoot
    $script:EventsPath = Join-Path $testRoot 'События.csv'
    $script:GlassesPath = Join-Path $testRoot 'Ресурс_стекол.csv'
    $script:CatalogPath = Join-Path $testRoot 'Справочник_номенклатуры.csv'
    $script:TypeBasePath = Join-Path $testRoot 'База_типоразмеров.csv'
    $script:CounterPath = Join-Path $testRoot 'Наблюдения_счетчика.csv'
    $script:CounterAuditPath = Join-Path $testRoot 'Журнал_распознавания_счетчика.csv'
    $script:CounterDiagnosticsRoot = Join-Path $testRoot 'Диагностика счетчика'
    $script:CyclesPath = Join-Path $testRoot 'Циклы_метража.csv'
    $script:StatePath = Join-Path $testRoot 'state.json'
    $script:GlassChangePath = Join-Path $testRoot 'pending-glass-change.json'
    [void][IO.Directory]::CreateDirectory($testRoot)
    if(Test-Path -LiteralPath $sourceTypeBaseForTest){[IO.File]::Copy($sourceTypeBaseForTest,$script:TypeBasePath,$true)}
    $stationBox = [pscustomobject]@{Text='B02'}
    $operatorBox = [pscustomobject]@{Text='Тест; "Оператор"'}
    $script:LastJob = 'Корпус Ду32_24_X1.zx'
    $script:ActiveGlass = [pscustomobject]@{id='B02-TEST';station='B02';operator=$operatorBox.Text;installedLocal='2026-08-19 08:00:00';installedUtc='2026-08-19T03:00:00Z'}
    $script:ActiveGlasses['B02']=$script:ActiveGlass
    $script:ActiveGlasses['A01']=[pscustomobject]@{id='A01-TEST';station='A01';operator='Другой';installedLocal='2026-08-19 07:00:00';installedUtc='2026-08-19T02:00:00Z'}
    try {
        $baseMatchOk=((Get-JobLengthMm 'Корпус Ду32_24_X1.zx')-eq80)
        $muftBaseMatchOk=((Get-JobLengthMm 'Корпус муфтовый Ду40_30_X1.zx')-eq70)
        Save-State
        Save-State
        Write-Event 'лазер выключён' 'короткий' ([Nullable[double]]0.5)
        Write-Event 'лазер выключён' 'пробивка' ([Nullable[double]]2.0)
        Write-Event 'лазер выключён' 'граница' ([Nullable[double]]3.0)
        Write-Event 'лазер выключён' 'выше границы' ([Nullable[double]]3.001)
        Write-Event 'лазер выключён' 'резка' ([Nullable[double]]4.0)
        $script:LastJob='Тестовая позиция без длины.zx';Write-Event 'смена задания' 'self-test missing length' $null;$script:LastJob='Корпус Ду32_24_X1.zx'
        Append-CsvRow $script:CatalogPath @('Номенклатура','Длина_детали_мм','Примечание') @($script:LastJob,'1250','тест')
        Accept-CounterValue 700;Accept-CounterValue 744;Accept-CounterValue 800;Close-ProductionCycle 'self-test'
        $cycleRow=@(Import-Csv -LiteralPath $script:CyclesPath -Delimiter ';')[-1];$counterRows=@(Import-Csv -LiteralPath $script:CounterPath -Delimiter ';')
        $meterOk=($cycleRow.'Количество'-eq'100'-and$cycleRow.'Метраж'-eq'125'-and$counterRows.Count-eq2)
        Accept-CounterValue 1;Accept-CounterValue 191;$beforeReset=Get-DisplayedProductionTotals;Accept-CounterValue 1;$afterReset=Get-DisplayedProductionTotals;$resetPersistenceOk=($beforeReset.quantity-eq290-and$afterReset.quantity-eq290-and$beforeReset.meters-eq362.5-and$afterReset.meters-eq362.5)
        $script:LastCounterOcrText='801';$script:CounterCandidate=$null;$script:CounterCandidateCount=0;Process-CounterCandidate 801;Process-CounterCandidate 801;Process-CounterCandidate 801;$auditRows=@(Import-Csv -LiteralPath $script:CounterAuditPath -Delimiter ';');$auditOk=($auditRows.Count-eq3-and$auditRows[-1].Решение-eq'принято'-and$auditRows[-1].Распознанное_число-eq'801')
        $rows = @(Import-Csv -LiteralPath $script:EventsPath -Delimiter ';')
        $classesOk = (($rows[0].'Класс' -eq 'короткий импульс') -and ($rows[1].'Класс' -eq 'пробивка/настройка') -and ($rows[2].'Класс' -eq 'пробивка/настройка') -and ($rows[3].'Класс' -eq 'рабочая резка') -and ($rows[4].'Класс' -eq 'рабочая резка'))
        $titleOk = ((Parse-JobFromTitle 'TubePro Корпус Ду32_24_X1.zx [10.2502.4.0]') -eq 'Корпус Ду32_24_X1.zx')
        $script:ActiveGlasses=@{};$script:ActiveGlass=$null
        Load-State
        $stateOk = ($script:ActiveGlasses.Count -eq 2 -and $script:ActiveGlasses['A01'].id -eq 'A01-TEST' -and $script:ActiveGlasses['B02'].id -eq 'B02-TEST')
        $friendlyId=New-FriendlyGlassId 'B02';$friendlyOk=($friendlyId-eq'Стекло B02-0001')
        $backupOk=Test-Path -LiteralPath ($script:StatePath+'.bak')
        [IO.File]::WriteAllText($script:StatePath,'{повреждено',[Text.Encoding]::UTF8);$script:StateWarning='';Load-State;$backupRecoveryOk=(-not[string]::IsNullOrWhiteSpace($script:StateWarning)-and(Get-Content -Raw -LiteralPath $script:StatePath|ConvertFrom-Json))
        $script:LaserOn=$true;$script:LaserOnUtc=[datetime]::UtcNow;$script:LaserCandidate=$true;$script:LaserCandidateCount=2;$script:LaserCandidateUtc=[datetime]::UtcNow.AddHours(-1);Reset-LaserDetectionState;$laserResetOk=(-not$script:LaserOn-and$null-eq$script:LaserOnUtc-and-not$script:LaserCandidate-and$script:LaserCandidateCount-eq0-and$null-eq$script:LaserCandidateUtc)
        $txOld=$script:ActiveGlasses['B02'];$txNew=[pscustomobject]@{id='Стекло B02-0002';station='B02';operator='Тест';installedLocal='2026-09-08 10:00:00';installedUtc='2026-09-08T05:00:00Z'};$tx=[ordered]@{id='selftest-tx';station='B02';operator='Тест';reason='Тест';note='';removedLocal='2026-09-08 10:00:00';oldGlass=$txOld;newGlass=$txNew};Write-PendingGlassChange $tx;Complete-PendingGlassChange;Complete-PendingGlassChange;$removedRows=@(Import-Csv -LiteralPath $script:GlassesPath -Delimiter ';'|Where-Object{[string]$_.ID_стекла-eq[string]$txOld.id-and$_.Снято-eq$tx.removedLocal});$glassTransactionOk=($removedRows.Count-eq1-and$script:ActiveGlasses['B02'].id-eq$txNew.id-and-not(Test-Path -LiteralPath $script:GlassChangePath))
        $bytes = [System.IO.File]::ReadAllBytes($script:EventsPath)
        $bomOk = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $exportPath=Export-DataToFolder $testRoot 'B02'
        $manifest=Get-Content -Raw -LiteralPath (Join-Path $exportPath 'manifest.json')|ConvertFrom-Json
        $exportOk=($manifest.station-eq'B02'-and$manifest.appVersion-eq$script:AppVersion-and@($manifest.files).Count-eq9-and(Test-Path -LiteralPath (Join-Path $exportPath 'Учет ресурса стекол станок B02.xlsx')))
        foreach($entry in @($manifest.files)){$actual=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $exportPath $entry.file)).Hash;if($actual-ne$entry.sha256){$exportOk=$false}}
        $missingLengthOk=$false;$xlsxPath=Join-Path $exportPath 'Учет ресурса стекол станок B02.xlsx';$xlsxStream=[IO.File]::OpenRead($xlsxPath);try{$xlsxZip=New-Object IO.Compression.ZipArchive($xlsxStream,[IO.Compression.ZipArchiveMode]::Read,$true);try{$sheet=$xlsxZip.GetEntry('xl/worksheets/sheet4.xml');if($sheet){$reader=New-Object IO.StreamReader($sheet.Open(),[Text.Encoding]::UTF8);try{$sheetText=$reader.ReadToEnd();$missingLengthOk=($sheetText.Contains('Тестовая позиция без длины.zx')-and$sheetText.Contains('Длина для добавления, мм'))}finally{$reader.Dispose()}}}finally{$xlsxZip.Dispose()}}finally{$xlsxStream.Dispose()}
        $finiteNumbersOk=($null-eq(Convert-DbNumber 'NaN')-and$null-eq(Convert-DbNumber 'Infinity')-and$null-eq(Convert-DbNumber '1e309'))
        $result = [pscustomobject]@{CsvRows=$rows.Count;CsvEscaping=($rows[0].'Оператор' -eq $operatorBox.Text);Classes=$classesOk;TitleParsing=$titleOk;TypeBaseMatch=$baseMatchOk;MuftBodyMatch=$muftBaseMatchOk;ShadowMetering=$meterOk;CounterResetKeepsGlassTotals=$resetPersistenceOk;OcrAudit=$auditOk;MissingLengthReport=$missingLengthOk;StateFirstAndReplace=$stateOk;FriendlyId=$friendlyOk;StateBackup=$backupOk;BackupRecovery=$backupRecoveryOk;LaserStateReset=$laserResetOk;GlassChangeTransaction=$glassTransactionOk;FiniteNumbers=$finiteNumbersOk;Utf8Bom=$bomOk;AutonomousXlsx=$exportOk;ExportManifest=$exportOk;ExportSequence=($script:ExportCounters['B02']-eq1)}
        if (-not ($result.CsvRows -eq 6 -and $result.CsvEscaping -and $result.Classes -and $result.TitleParsing -and $result.TypeBaseMatch -and $result.MuftBodyMatch -and $result.ShadowMetering -and $result.CounterResetKeepsGlassTotals -and $result.OcrAudit -and $result.MissingLengthReport -and $result.StateFirstAndReplace -and $result.FriendlyId -and $result.StateBackup -and $result.BackupRecovery -and $result.LaserStateReset -and $result.GlassChangeTransaction -and $result.FiniteNumbers -and $result.Utf8Bom -and $result.AutonomousXlsx -and $result.ExportManifest -and $result.ExportSequence)) { throw ('Self-test failed: ' + ($result | ConvertTo-Json -Compress)) }
        $result | ConvertTo-Json
    } finally {
        if ($testRoot.StartsWith($testBase + '\glass-monitor-selftest-', [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $testRoot)) {
            [System.IO.Directory]::Delete($testRoot, $true)
        }
    }
    exit 0
}

function Repair-PackageShortcut {
    if(-not$script:IsPackaged-or[string]::IsNullOrWhiteSpace($FixedStation)){return}
    $launcher=Join-Path $script:PackageRoot ("Запустить монитор станка $FixedStation.cmd")
    $icon=Join-Path $script:PackageRoot 'Ресурсы\Иконка монитора v2.ico'
    $link=Join-Path $script:PackageRoot ("Монитор стекол — станок $FixedStation.lnk")
    if(-not(Test-Path -LiteralPath $launcher)-or-not(Test-Path -LiteralPath $icon)){return}
    try{
        $shell=New-Object -ComObject WScript.Shell
        $shortcut=$shell.CreateShortcut($link)
        $shortcut.TargetPath=$launcher;$shortcut.Arguments='';$shortcut.WorkingDirectory=$script:PackageRoot;$shortcut.WindowStyle=7
        $shortcut.Description="Монитор ресурса защитных стёкол — станок $FixedStation";$shortcut.IconLocation="$icon,0";$shortcut.Save()
    }catch{}
}

$script:InstanceMutex=$null
if(-not$UiLayoutTest){
    $instanceScope=if([string]::IsNullOrWhiteSpace($FixedStation)){'Common'}else{$FixedStation}
    $mutexName='Local\Friendess.GlassMonitor.'+$instanceScope
    $createdNew=$false
    $script:InstanceMutex=[Threading.Mutex]::new($true,$mutexName,[ref]$createdNew)
    if(-not$createdNew){
        $script:InstanceMutex.Dispose();$script:InstanceMutex=$null
        [Windows.Forms.MessageBox]::Show("Монитор станка $instanceScope уже запущен.",'Повторный запуск',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null
        exit 3
    }
}

Repair-PackageShortcut
[TubeProWindow]::SetApplicationId(('Friendess.GlassMonitor.'+$(if($FixedStation){$FixedStation}else{'Common'})))
$form = New-Object Windows.Forms.Form
$form.Text = 'Монитор ресурса защитных стёкол TubePro'
$iconPath=if($script:IsPackaged){Join-Path $script:PackageRoot 'Ресурсы\Иконка монитора.ico'}else{Join-Path $script:SourceRoot 'Ресурсы\Иконка монитора.ico'}
if(Test-Path -LiteralPath $iconPath){$iconStream=[IO.File]::OpenRead($iconPath);try{$loadedIcon=New-Object Drawing.Icon($iconStream);try{$form.Icon=$loadedIcon.Clone()}finally{$loadedIcon.Dispose()}}finally{$iconStream.Dispose()}}else{$form.Icon=[TubeProWindow]::GetSettingsIcon()}
$form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi
$form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $true
$form.ClientSize = New-Object Drawing.Size(980,650)
$form.StartPosition = 'Manual'
$form.MinimumSize = New-Object Drawing.Size(820,600)
$form.BackColor=[Drawing.Color]::FromArgb(242,242,242)
$form.Font=New-Object Drawing.Font('Segoe UI',10)
$work=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea;$form.Location=New-Object Drawing.Point($work.Left,[math]::Max($work.Top,$work.Bottom-$form.Height))

function New-Label([string]$Text){$c=New-Object Windows.Forms.Label;$c.Text=$Text;$c.Dock='Fill';$c.TextAlign='MiddleLeft';$c.Margin=New-Object Windows.Forms.Padding(4);$c.AutoEllipsis=$true;$c}
function New-Combo($items){$c=New-Object Windows.Forms.ComboBox;$c.DropDownStyle='DropDownList';$c.DrawMode='OwnerDrawFixed';$c.ItemHeight=22;$c.Dock='Fill';$c.Margin=New-Object Windows.Forms.Padding(5);[void]$c.Items.AddRange([object[]]$items);$c.Add_DrawItem({param($sender,$e);if($e.Index-lt0){return};$selected=(($e.State-band[Windows.Forms.DrawItemState]::Selected)-ne0)-and$sender.Enabled;$back=if($selected){[Drawing.SystemColors]::Highlight}else{[Drawing.Color]::White};$fore=if($selected){[Drawing.SystemColors]::HighlightText}else{[Drawing.Color]::FromArgb(20,20,20)};$brush=New-Object Drawing.SolidBrush($back);try{$e.Graphics.FillRectangle($brush,$e.Bounds)}finally{$brush.Dispose()};[Windows.Forms.TextRenderer]::DrawText($e.Graphics,[string]$sender.Items[$e.Index],$sender.Font,$e.Bounds,$fore,$back,[Windows.Forms.TextFormatFlags]::VerticalCenter-bor[Windows.Forms.TextFormatFlags]::Left-bor[Windows.Forms.TextFormatFlags]::NoPadding)});$c}
function Set-ActionButtonColors($button){
    if(-not$button.Enabled){$button.BackColor=[Drawing.Color]::FromArgb(224,224,224);$button.ForeColor=[Drawing.Color]::FromArgb(90,90,90);return}
    if([string]$button.Tag-eq'primary'){$button.BackColor=[Drawing.Color]::FromArgb(255,236,0);$button.ForeColor=[Drawing.Color]::FromArgb(20,20,20)}
    else{$button.BackColor=[Drawing.Color]::FromArgb(36,36,36);$button.ForeColor=[Drawing.Color]::White}
}
function Style-ActionButton($button,[bool]$primary=$false){$button.Dock='Fill';$button.Margin=New-Object Windows.Forms.Padding(5);$button.Padding=New-Object Windows.Forms.Padding(0);$button.AutoSize=$false;$button.FlatStyle='Flat';$button.FlatAppearance.BorderSize=0;$button.UseVisualStyleBackColor=$false;$button.UseCompatibleTextRendering=$false;$button.UseMnemonic=$false;$button.TextAlign=[Drawing.ContentAlignment]::MiddleCenter;$button.Cursor='Hand';$button.Font=New-Object Drawing.Font('Segoe UI Semibold',10);$button.Tag=if($primary){'primary'}else{'secondary'};$button.Add_EnabledChanged({Set-ActionButtonColors $this;$this.Cursor=$(if($this.Enabled){'Hand'}else{'Default'})});$button.Add_MouseEnter({if($this.Enabled){$this.BackColor=$(if([string]$this.Tag-eq'primary'){[Drawing.Color]::FromArgb(255,243,66)}else{[Drawing.Color]::FromArgb(52,52,52)})}});$button.Add_MouseLeave({Set-ActionButtonColors $this});$button.Add_MouseDown({if($this.Enabled){$this.BackColor=$(if([string]$this.Tag-eq'primary'){[Drawing.Color]::FromArgb(230,212,0)}else{[Drawing.Color]::FromArgb(21,21,21)})}});$button.Add_MouseUp({Set-ActionButtonColors $this});Set-ActionButtonColors $button}
function New-ActionHost($button){$hostPanel=New-Object Windows.Forms.Panel;$hostPanel.Dock='Fill';$hostPanel.Margin=New-Object Windows.Forms.Padding(0);$button.Dock='None';$button.Margin=New-Object Windows.Forms.Padding(0);$hostPanel.Controls.Add($button);$resize={param($sender,$eventArgs);$w=[math]::Max(1,$sender.ClientSize.Width-10);$h=[math]::Max(1,$sender.ClientSize.Height-10);foreach($child in $sender.Controls){$child.SetBounds(5,5,$w,$h)}};$hostPanel.Add_Resize($resize);$hostPanel.Add_Layout($resize);$hostPanel}
function New-SectionPanel([string]$Title){$p=New-Object Windows.Forms.Panel;$p.Dock='Fill';$p.BackColor=[Drawing.Color]::White;$p.Margin=New-Object Windows.Forms.Padding(0,0,12,0);$p.Padding=New-Object Windows.Forms.Padding(16,42,16,14);$heading=New-Object Windows.Forms.Label;$heading.Text=$Title;$heading.Font=New-Object Drawing.Font('Segoe UI Semibold',13);$heading.ForeColor=[Drawing.Color]::FromArgb(36,36,36);$heading.Location=New-Object Drawing.Point(16,12);$heading.AutoSize=$true;$p.Controls.Add($heading);$p}
function New-KpiCard([string]$Caption){$p=New-Object Windows.Forms.Panel;$p.Dock='Fill';$p.BackColor=[Drawing.Color]::White;$p.Margin=New-Object Windows.Forms.Padding(0,0,10,0);$captionLabel=New-Object Windows.Forms.Label;$captionLabel.Text=$Caption.ToUpperInvariant();$captionLabel.ForeColor=[Drawing.Color]::FromArgb(104,104,104);$captionLabel.Font=New-Object Drawing.Font('Segoe UI Semibold',8);$captionLabel.Location=New-Object Drawing.Point(12,9);$captionLabel.Size=New-Object Drawing.Size(160,20);$captionLabel.Anchor='Top,Left,Right';$captionLabel.AutoEllipsis=$true;$p.Controls.Add($captionLabel);$value=New-Object Windows.Forms.Label;$value.Text='—';$value.ForeColor=[Drawing.Color]::FromArgb(36,36,36);$value.Font=New-Object Drawing.Font('Segoe UI Semibold',14);$value.Location=New-Object Drawing.Point(12,35);$value.Size=New-Object Drawing.Size(160,31);$value.Anchor='Top,Left,Right';$value.AutoEllipsis=$true;$p.Controls.Add($value);$p.Add_Resize({$newWidth=[math]::Max(20,$this.ClientSize.Width-24);foreach($child in $this.Controls){if($child-is[Windows.Forms.Label]){$child.Width=$newWidth}}});[pscustomobject]@{Panel=$p;Value=$value}}

$layout=New-Object Windows.Forms.TableLayoutPanel;$layout.Dock='Fill';$layout.Padding=New-Object Windows.Forms.Padding(18);$layout.ColumnCount=1;$layout.RowCount=6;$layout.BackColor=$form.BackColor
foreach($h in @(64,58,92,0,58,24)){$style=if($h-eq 0){New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)}else{New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,$h)};[void]$layout.RowStyles.Add($style)}
$form.Controls.Add($layout)

$header=New-Object Windows.Forms.TableLayoutPanel;$header.Dock='Fill';$header.BackColor=[Drawing.Color]::FromArgb(36,36,36);$header.Margin=New-Object Windows.Forms.Padding(0,0,0,10);$header.ColumnCount=3;$header.RowCount=1;[void]$header.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$header.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,64)));[void]$header.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)));[void]$header.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,200)))
$brandHost=New-Object Windows.Forms.Panel;$brandHost.Dock='Fill';$brandHost.Margin=New-Object Windows.Forms.Padding(9,4,5,4);$brandHost.BackColor=[Drawing.Color]::FromArgb(255,236,0)
$brand=New-Object CenteredTextLabel;$brand.Text='LD';$brand.BackColor=$brandHost.BackColor;$brand.ForeColor=[Drawing.Color]::Black;$brand.Font=New-Object Drawing.Font('Segoe UI Black',11);$brand.Dock='None';$brand.Margin=New-Object Windows.Forms.Padding(0);$brandHost.Controls.Add($brand)
$brandResize={param($sender,$eventArgs);$brand.SetBounds(0,0,$sender.ClientSize.Width,$sender.ClientSize.Height)};$brandHost.Add_Resize($brandResize);$brandHost.Add_Layout($brandResize);$header.Controls.Add($brandHost,0,0)
$titlePanel=New-Object Windows.Forms.Panel;$titlePanel.Dock='Fill';$titlePanel.Margin=New-Object Windows.Forms.Padding(6,4,4,4)
$title=New-Object Windows.Forms.Label;$title.Text='Монитор ресурса защитных стёкол';$title.ForeColor=[Drawing.Color]::White;$title.Font=New-Object Drawing.Font('Segoe UI Semibold',13);$title.Location=New-Object Drawing.Point(0,2);$title.Size=New-Object Drawing.Size(520,27);$title.Anchor='Top,Left,Right';$title.AutoEllipsis=$true;$titlePanel.Controls.Add($title);$titlePanel.Add_Resize({$title.Width=$titlePanel.ClientSize.Width})
$headerSubTitle=New-Object Windows.Forms.Label;$headerSubTitle.Text='Промышленный контроль TubePro';$headerSubTitle.ForeColor=[Drawing.Color]::FromArgb(184,184,184);$headerSubTitle.Location=New-Object Drawing.Point(1,29);$headerSubTitle.AutoSize=$true;$titlePanel.Controls.Add($headerSubTitle);$header.Controls.Add($titlePanel,1,0)
$metaPanel=New-Object Windows.Forms.Panel;$metaPanel.Dock='Fill';$metaPanel.Margin=New-Object Windows.Forms.Padding(6);$metaPanel.BackColor=[Drawing.Color]::FromArgb(255,236,0)
$versionLabel=New-Object Windows.Forms.Label;$versionLabel.Text="СТАНОК $(if($FixedStation){$FixedStation}else{'—'})";$versionLabel.ForeColor=[Drawing.Color]::FromArgb(20,20,20);$versionLabel.Font=New-Object Drawing.Font('Segoe UI Semibold',12);$versionLabel.TextAlign='MiddleCenter';$versionLabel.Location=New-Object Drawing.Point(0,1);$versionLabel.Size=New-Object Drawing.Size(188,25);$versionLabel.Anchor='Top,Left,Right';$metaPanel.Controls.Add($versionLabel)
$versionSmall=New-Object Windows.Forms.Label;$versionSmall.Text="v $script:AppVersion";$versionSmall.ForeColor=[Drawing.Color]::FromArgb(70,70,70);$versionSmall.Font=New-Object Drawing.Font('Segoe UI',8);$versionSmall.TextAlign='MiddleCenter';$versionSmall.Location=New-Object Drawing.Point(0,25);$versionSmall.Size=New-Object Drawing.Size(188,18);$versionSmall.Anchor='Top,Left,Right';$metaPanel.Controls.Add($versionSmall);$metaPanel.Add_Resize({$versionLabel.Width=$metaPanel.ClientSize.Width;$versionSmall.Width=$metaPanel.ClientSize.Width});$header.Controls.Add($metaPanel,2,0)
$layout.Controls.Add($header,0,0)

$statePanel=New-Object Windows.Forms.Panel;$statePanel.Dock='Fill';$statePanel.Margin=New-Object Windows.Forms.Padding(0,0,0,10);$statePanel.Padding=New-Object Windows.Forms.Padding(16,4,16,4)
$stateDot=New-Object Windows.Forms.Label;$stateDot.Text='●';$stateDot.Font=New-Object Drawing.Font('Segoe UI',15);$stateDot.Location=New-Object Drawing.Point(14,10);$stateDot.Size=New-Object Drawing.Size(28,30);$statePanel.Controls.Add($stateDot)
$banner=New-Object Windows.Forms.Label;$banner.Font=New-Object Drawing.Font('Segoe UI Semibold',12);$banner.Location=New-Object Drawing.Point(46,5);$banner.Size=New-Object Drawing.Size(360,25);$banner.AutoEllipsis=$true;$statePanel.Controls.Add($banner)
$stateDetail=New-Object Windows.Forms.Label;$stateDetail.Location=New-Object Drawing.Point(47,28);$stateDetail.Size=New-Object Drawing.Size(850,22);$stateDetail.Anchor='Top,Left,Right';$stateDetail.AutoEllipsis=$true;$statePanel.Controls.Add($stateDetail);$layout.Controls.Add($statePanel,0,1)

$kpis=New-Object Windows.Forms.TableLayoutPanel;$kpis.Dock='Fill';$kpis.ColumnCount=5;$kpis.RowCount=1;$kpis.Margin=New-Object Windows.Forms.Padding(0,0,0,10);[void]$kpis.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));1..5|ForEach-Object{[void]$kpis.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,20)))}
$kg=New-KpiCard 'Активное стекло';$kl=New-KpiCard 'Время лазера';$kp=New-KpiCard 'Детали';$km=New-KpiCard 'Метраж';$ku=New-KpiCard 'Недоступность';$kpiGlassValue=$kg.Value;$kpiLaserValue=$kl.Value;$kpiPartsValue=$kp.Value;$kpiMetersValue=$km.Value;$kpiUnavailableValue=$ku.Value;@($kg.Panel,$kl.Panel,$kp.Panel,$km.Panel,$ku.Panel)|ForEach-Object{$kpis.Controls.Add($_)};$layout.Controls.Add($kpis,0,2)

$workspace=New-Object Windows.Forms.TableLayoutPanel;$workspace.Dock='Fill';$workspace.ColumnCount=2;$workspace.RowCount=1;$workspace.Margin=New-Object Windows.Forms.Padding(0,0,0,10);[void]$workspace.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,64)));[void]$workspace.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,36)))
$left=New-Object Windows.Forms.TableLayoutPanel;$left.Dock='Fill';$left.ColumnCount=1;$left.RowCount=1;$left.Margin=New-Object Windows.Forms.Padding(0,0,12,0);[void]$left.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
$statusPanel=New-SectionPanel 'Подробности и последние события';$statusPanel.Margin=New-Object Windows.Forms.Padding(0)
$diagnosticsButton=New-Object Windows.Forms.Button;$diagnosticsButton.Text='Диагностика';$diagnosticsButton.FlatStyle='Flat';$diagnosticsButton.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(210,210,210);$diagnosticsButton.BackColor=[Drawing.Color]::White;$diagnosticsButton.ForeColor=[Drawing.Color]::FromArgb(60,60,60);$diagnosticsButton.Size=New-Object Drawing.Size(112,27);$diagnosticsButton.Location=New-Object Drawing.Point(450,9);$diagnosticsButton.Anchor='Top,Right';$statusPanel.Controls.Add($diagnosticsButton);$statusPanel.Add_Resize({$diagnosticsButton.Left=$statusPanel.ClientSize.Width-$diagnosticsButton.Width-14})
$status=New-Object Windows.Forms.RichTextBox;$status.Dock='Fill';$status.BorderStyle='None';$status.Font=New-Object Drawing.Font('Segoe UI',9);$status.ReadOnly=$true;$status.DetectUrls=$false;$status.ScrollBars='Vertical';$status.WordWrap=$true;$status.BackColor=[Drawing.Color]::White;$status.TabStop=$false;$statusPanel.Controls.Add($status);$left.Controls.Add($statusPanel,0,0);$workspace.Controls.Add($left,0,0)
$script:StatusScrollPauseUntilUtc=[datetime]::MinValue;$script:LastVisualUpdateUtc=[datetime]::MinValue;$script:DiagnosticText='';$status.Add_MouseWheel({$script:StatusScrollPauseUntilUtc=[datetime]::UtcNow.AddSeconds(3)})

$setupPanel=New-SectionPanel 'Смена и стекло';$setupPanel.Margin=New-Object Windows.Forms.Padding(0)
$setup=New-Object Windows.Forms.TableLayoutPanel;$setup.Dock='Fill';$setup.ColumnCount=1;$setup.RowCount=7;$setup.Margin=New-Object Windows.Forms.Padding(0);foreach($h in @(22,36,18,25,25,25,44)){[void]$setup.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,$h)))}
$stationBox=New-Combo @('A01','B02');$stationBox.Text='A01';$stationBox.TabStop=$false
$operatorCaption=New-Label 'ОПЕРАТОР';$operatorCaption.ForeColor=[Drawing.Color]::FromArgb(104,104,104);$operatorCaption.Font=New-Object Drawing.Font('Segoe UI Semibold',8)
$operatorBox=New-Combo @('Оператор 1','Оператор 2','Оператор 3');$operatorBox.Text='Оператор 1'
$activeCaption=New-Label 'АКТИВНОЕ СТЕКЛО';$activeCaption.ForeColor=[Drawing.Color]::FromArgb(104,104,104);$activeCaption.Font=New-Object Drawing.Font('Segoe UI Semibold',8)
$activeGlassValue=New-Label 'Не установлено';$activeGlassValue.Font=New-Object Drawing.Font('Segoe UI Semibold',11)
$activeGlassInstalled=New-Label 'Установлено: —';$activeGlassInstalled.ForeColor=[Drawing.Color]::FromArgb(90,90,90)
$activeGlassService=New-Label 'Срок службы: —';$activeGlassService.ForeColor=[Drawing.Color]::FromArgb(90,90,90)
$glassButtonHost=New-Object Windows.Forms.Panel;$glassButtonHost.Dock='Fill';$glassButtonHost.Margin=New-Object Windows.Forms.Padding(0)
$glassButton=New-Object CenteredTextButton;$glassButton.Text='Установить / заменить стекло';Style-ActionButton $glassButton $false;$glassButton.Dock='None';$glassButton.Margin=New-Object Windows.Forms.Padding(0);$glassButton.Size=New-Object Drawing.Size(230,36);$glassButtonHost.Controls.Add($glassButton)
$glassButtonHost.Add_Resize({$glassButton.Left=[math]::Max(0,[math]::Floor(($glassButtonHost.ClientSize.Width-$glassButton.Width)/2));$glassButton.Top=[math]::Max(0,[math]::Floor(($glassButtonHost.ClientSize.Height-$glassButton.Height)/2))})
@($operatorCaption,$operatorBox,$activeCaption,$activeGlassValue,$activeGlassInstalled,$activeGlassService,$glassButtonHost)|ForEach-Object{$setup.Controls.Add($_)};$setupPanel.Controls.Add($setup);$workspace.Controls.Add($setupPanel,1,0);$layout.Controls.Add($workspace,0,3)
$reasonBox=New-Object Windows.Forms.ComboBox;$reasonBox.DropDownStyle='DropDown';[void]$reasonBox.Items.AddRange([object[]]@('Сгорело','Загрязнение','Брак','Настройка'));$reasonBox.Text=''
$noteBox=New-Object Windows.Forms.TextBox;$noteBox.MaxLength=250

$actions=New-Object Windows.Forms.TableLayoutPanel;$actions.Dock='Fill';$actions.ColumnCount=4;$actions.RowCount=1;$actions.Margin=New-Object Windows.Forms.Padding(0);[void]$actions.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));1..4|ForEach-Object{[void]$actions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,25)))}
$startButton=New-Object CenteredTextButton;$startButton.Text='Начать наблюдение';Style-ActionButton $startButton $true
$stopButton=New-Object CenteredTextButton;$stopButton.Text='Остановить наблюдение';$stopButton.Enabled=$false;$stopButton.Visible=$false;Style-ActionButton $stopButton
$monitorActionHost=New-ActionHost $startButton;$stopButton.Dock='None';$stopButton.Margin=New-Object Windows.Forms.Padding(0);$monitorActionHost.Controls.Add($stopButton);$monitorResize={param($sender,$eventArgs);$w=[math]::Max(1,$sender.ClientSize.Width-10);$h=[math]::Max(1,$sender.ClientSize.Height-10);foreach($child in $sender.Controls){$child.SetBounds(5,5,$w,$h)}};$monitorActionHost.Add_Resize($monitorResize);$monitorActionHost.Add_Layout($monitorResize)
$shiftButton=New-Object CenteredTextButton;$shiftButton.Text='Завершить смену';$shiftButton.Enabled=$false;Style-ActionButton $shiftButton
$exportButton=New-Object CenteredTextButton;$exportButton.Text='Выгрузить отчёт';Style-ActionButton $exportButton
$helpButton=New-Object CenteredTextButton;$helpButton.Text='Инструкция';Style-ActionButton $helpButton
$shiftHost=New-ActionHost $shiftButton;$exportHost=New-ActionHost $exportButton;$helpHost=New-ActionHost $helpButton
$actions.Controls.Add($monitorActionHost,0,0);$actions.Controls.Add($shiftHost,1,0);$actions.Controls.Add($exportHost,2,0);$actions.Controls.Add($helpHost,3,0);$layout.Controls.Add($actions,0,4)

$operationPanel=New-Object Windows.Forms.Panel;$operationPanel.Dock='Fill';$operationPanel.Margin=New-Object Windows.Forms.Padding(5,0,5,2)
$operationLabel=New-Object Windows.Forms.Label;$operationLabel.Dock='Left';$operationLabel.Width=330;$operationLabel.TextAlign='MiddleLeft';$operationLabel.ForeColor=[Drawing.Color]::FromArgb(70,80,92);$operationPanel.Controls.Add($operationLabel)
$operationProgress=New-Object Windows.Forms.ProgressBar;$operationProgress.Dock='Fill';$operationProgress.Visible=$false;$operationPanel.Controls.Add($operationProgress);$operationProgress.BringToFront();$layout.Controls.Add($operationPanel,0,5)
$toolTip=New-Object Windows.Forms.ToolTip;$toolTip.SetToolTip($stopButton,'Доступно после запуска наблюдения.');$toolTip.SetToolTip($shiftButton,'Доступно во время наблюдения.');$toolTip.SetToolTip($exportButton,'Во время наблюдения сначала остановите учёт.');$toolTip.SetToolTip($glassButton,'Откроет отдельное окно установки или замены стекла.')
$stationBox.TabIndex=0;$stationBox.TabStop=$false;$operatorBox.TabIndex=1;$glassButton.TabIndex=2;$startButton.TabIndex=3;$stopButton.TabIndex=3;$shiftButton.TabIndex=4;$exportButton.TabIndex=5;$helpButton.TabIndex=6
$stationBox.AccessibleName='Номер станка';$operatorBox.AccessibleName='Оператор смены';$glassButton.AccessibleName='Установить или заменить защитное стекло';$startButton.AccessibleName='Начать наблюдение TubePro';$stopButton.AccessibleName='Остановить наблюдение TubePro'
$form.AcceptButton=$startButton

if($UiLayoutTest){
    $form.ShowInTaskbar=$false;$form.Opacity=0;$form.StartPosition='Manual';$form.Location=New-Object Drawing.Point(-10000,-10000)
    $form.Show();[Windows.Forms.Application]::DoEvents();$form.PerformLayout();[Windows.Forms.Application]::DoEvents()
    $bitmap=New-Object Drawing.Bitmap($form.ClientSize.Width,$form.ClientSize.Height)
    try{
        $form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)))
        if($UiLayoutArtifact){$bitmap.Save($UiLayoutArtifact,[Drawing.Imaging.ImageFormat]::Png)}
        $rowHeights=$layout.GetRowHeights();$headerVisibleHeight=$rowHeights[0]-$header.Margin.Vertical;$actionVisibleHeight=$rowHeights[4]-$actions.Margin.Vertical
        $geometry=[pscustomobject]@{headerVisibleHeight=$headerVisibleHeight;brandHeight=$brand.Height;actionVisibleHeight=$actionVisibleHeight;startButtonHeight=$startButton.Height;fits=($brand.Height-le$headerVisibleHeight-and$startButton.Height-le$actionVisibleHeight)}
        $geometry|ConvertTo-Json
        if(-not$geometry.fits){exit 1};exit 0
    }finally{$bitmap.Dispose();$form.Close();$form.Dispose()}
}

Migrate-LegacyLayout
Ensure-DataRoot
Ensure-Catalog
$script:DatabaseCheck=Test-GlassReferenceDatabase -CatalogPath $script:CatalogPath -TypeBasePath $script:TypeBasePath
$script:DatabaseVersion=Get-DatabaseVersion
Load-State
Complete-PendingGlassChange
if(-not[string]::IsNullOrWhiteSpace($FixedStation)){$stationBox.Text=$FixedStation;$stationBox.Enabled=$false}
Select-ActiveGlassForStation
Rebuild-GlassTotals
Rebuild-ProductionTotals
$stationBox.Add_TextChanged({$versionLabel.Text="СТАНОК $($stationBox.Text)";if(-not$script:MonitorStarted){Select-ActiveGlassForStation;Update-Status (Get-TubeProSnapshot)}})

function Update-Status($snap) {
    $glassText=if($script:ActiveGlass){$script:ActiveGlass.id}else{'НЕ УСТАНОВЛЕНО'}
    $signalText=if(-not$snap.Found){'НЕ НАЙДЕН — наблюдение сигнала невозможно'}elseif($snap.Minimized){'ОКНО СВЁРНУТО — разверните TubePro'}elseif(-not$snap.Available){'ИНДИКАТОР НЕ ВИДЕН — проверьте, не перекрыто ли окно'}else{'сигнал доступен'}
    $confidence=if($snap.Available){'индикатор распознаётся'}else{'нет данных'}
    $total=[ordered]@{seconds=0.0;short=0;setup=0;work=0}
    if($script:ActiveGlass-and$script:TotalsByGlass.ContainsKey([string]$script:ActiveGlass.id)){$total=$script:TotalsByGlass[[string]$script:ActiveGlass.id]}
    $service=if($script:ActiveGlass){try{Format-Duration ((Get-Date)-[datetime]::Parse([string]$script:ActiveGlass.installedLocal)).TotalSeconds}catch{'—'}}else{'—'}
    $warning=@($script:ClockWarning,$script:StateWarning,$(if($script:RecoveryInfo){'Обнаружен незавершённый предыдущий сеанс; запись восстановления добавлена.'}else{''}))|Where-Object{$_}
    $unavailable=$script:UnavailableSeconds;if($script:SignalLossUtc){$unavailable+=([datetime]::UtcNow-$script:SignalLossUtc).TotalSeconds}
    if(-not$script:MonitorStarted){$banner.Text='Наблюдение остановлено';$stateDetail.Text='Новые события лазера и счётчика сейчас не записываются.';$statePanel.BackColor=[Drawing.Color]::FromArgb(238,238,238);$banner.ForeColor=[Drawing.Color]::FromArgb(70,70,70);$stateDetail.ForeColor=[Drawing.Color]::FromArgb(90,90,90);$stateDot.ForeColor=[Drawing.Color]::FromArgb(110,110,110)}
    elseif(-not$snap.Available){$banner.Text='TubePro не виден';$stateDetail.Text='Лазер и детали временно не учитываются. Разверните TubePro и освободите область индикатора.';$statePanel.BackColor=[Drawing.Color]::FromArgb(255,244,204);$banner.ForeColor=[Drawing.Color]::FromArgb(122,78,0);$stateDetail.ForeColor=$banner.ForeColor;$stateDot.ForeColor=[Drawing.Color]::FromArgb(154,101,0)}
    elseif($script:LaserOn){$banner.Text='Лазер включён';$stateDetail.Text='Рабочий импульс и счётчик записываются. Окно монитора можно свернуть.';$statePanel.BackColor=[Drawing.Color]::FromArgb(232,244,250);$banner.ForeColor=[Drawing.Color]::FromArgb(20,108,148);$stateDetail.ForeColor=$banner.ForeColor;$stateDot.ForeColor=[Drawing.Color]::FromArgb(20,108,148)}
    else{$banner.Text='Наблюдение ведётся';$stateDetail.Text='События лазера и счётчик записываются. Окно монитора можно свернуть.';$statePanel.BackColor=[Drawing.Color]::FromArgb(232,245,237);$banner.ForeColor=[Drawing.Color]::FromArgb(22,131,74);$stateDetail.ForeColor=$banner.ForeColor;$stateDot.ForeColor=[Drawing.Color]::FromArgb(22,131,74)}
    $recent=if($script:RecentEvents.Count){$script:RecentEvents.ToArray() -join"`r`n"}else{'Событий пока нет'}
    $counterText=if($null-ne$script:CounterValue){[string]$script:CounterValue}else{'—'}
    $productionTotal=Get-DisplayedProductionTotals;$qty=$productionTotal.quantity;$meters=if($productionTotal.hasMeters){"$($productionTotal.meters) м"}else{'—'}
    $kpiGlassValue.Text=$glassText
    $kpiLaserValue.Text=Format-Duration ([double]$total.seconds)
    $kpiPartsValue.Text=[string]$qty
    $kpiMetersValue.Text=$meters
    $kpiUnavailableValue.Text=Format-Duration $unavailable
    $activeGlassValue.Text=$glassText
    $activeGlassInstalled.Text='Установлено: '+$(if($script:ActiveGlass){[string]$script:ActiveGlass.installedLocal}else{'—'})
    $activeGlassService.Text="Срок службы: $service"
    $scrollPosition=[TubeProWindow]::GetScrollPosition($status.Handle)
    $newStatusText = "TubePro: $signalText`r`n" +
        "Задание: " + $(if($snap.Job){$snap.Job}else{'—'}) + "`r`n" +
        "Лазер: " + $(if($script:LaserOn){'ВКЛЮЧЁН'}else{'выключен'}) + "`r`n" +
        "Распознавание: $confidence`r`n"+
        "Недоступность TubePro за сеанс: $(Format-Duration $unavailable)`r`n`r`n" +
        "Активное стекло: $glassText`r`n" +
        "Установлено: " + $(if($script:ActiveGlass){$script:ActiveGlass.installedLocal}else{'—'}) + "`r`n" +
        "Календарный срок службы: $service`r`n" +
        "Накопленное время лазера: $(Format-Duration ([double]$total.seconds)) ($([math]::Round([double]$total.seconds,3)) с)`r`n" +
        "Импульсы: <1 с — $($total.short); 1–3 с — $($total.setup); >3 с — $($total.work)`r`n`r`n" +
        "Счётчик деталей: $counterText — $($script:CounterStatus)`r`n"+
        "Накоплено по стеклу: $qty деталей; метраж: $meters`r`n"+
        "Версия программы: $($script:AppVersion) ($($script:BuildDate))`r`n"+
        "Версия базы: $($script:DatabaseVersion.Substring(0,[math]::Min(12,$script:DatabaseVersion.Length)))`r`n"+
        "База: $($script:DatabaseCheck.Status); ошибок: $($script:DatabaseCheck.Errors); предупреждений: $($script:DatabaseCheck.Warnings)`r`n"+
        "Наблюдение: " + $(if($script:MonitorStarted){'ИДЁТ'}else{'остановлено'}) +"`r`n`r`nПоследние события:`r`n$recent"+
        $(if($warning){"`r`n`r`nВНИМАНИЕ: "+($warning-join' ') }else{''})
    $script:DiagnosticText=$newStatusText
    $mainStatusText="Текущее задание: "+$(if($snap.Job){$snap.Job}else{'—'})+"`r`n"+
        "Счётчик: $counterText — $($script:CounterStatus)`r`n"+
        "Накоплено по стеклу: $qty деталей; метраж: $meters`r`n`r`n"+
        "Последние события:`r`n$recent"+
        $(if($warning){"`r`n`r`nВНИМАНИЕ: "+($warning-join' ')}else{''})
    if($status.Text-ne$mainStatusText -and [datetime]::UtcNow-ge$script:StatusScrollPauseUntilUtc){$status.Text=$mainStatusText;[TubeProWindow]::RestoreScrollPosition($status.Handle,$scrollPosition)}
    $glassButton.Text=if($script:ActiveGlass){'Заменить стекло'}else{'Установить первое стекло'}
}

$timer=New-Object Windows.Forms.Timer;$timer.Interval=200
$timer.Add_Tick({
    try {
        $snap=Get-TubeProSnapshot
        if($snap.Found -and $snap.Title-ne$script:LastTitle){
            $old=$script:LastJob;$script:LastTitle=$snap.Title;$script:LastJob=$snap.Job
            if($script:MonitorStarted -and $old-ne$script:LastJob){Close-ProductionCycle 'смена номенклатуры';$script:CounterValue=$null;$script:CounterCandidate=$null;$script:CounterCandidateCount=0;Write-Event 'смена задания' "Было: $old; стало: $($script:LastJob)" $null}
        }
        if($script:MonitorStarted -and $snap.Available){
            if($script:SignalAvailable-ne$true){if($script:SignalLossUtc){$script:UnavailableSeconds+=([datetime]::UtcNow-$script:SignalLossUtc).TotalSeconds;$script:SignalLossUtc=$null};Write-Event 'сигнал TubePro доступен' '' $null}
            $script:SignalAvailable=$true
            if($snap.LaserOn -eq $script:LaserCandidate){$script:LaserCandidateCount++}else{$script:LaserCandidate=$snap.LaserOn;$script:LaserCandidateCount=1;$script:LaserCandidateUtc=[datetime]::UtcNow}
            if($script:LaserCandidateCount-ge2 -and $script:LaserCandidate-ne$script:LaserOn){
                $script:LaserOn=$script:LaserCandidate
                $transitionUtc=if($null-ne$script:LaserCandidateUtc){$script:LaserCandidateUtc}else{[datetime]::UtcNow}
                if($script:LaserOn){$script:LaserOnUtc=$transitionUtc;$script:LaserOnJob=$script:LastJob;$script:Session.laserOn=$true;$script:Session.laserOnUtc=$transitionUtc.ToString('o');$script:Session.job=$script:LastJob;Save-State;Write-Event 'лазер включён' '' $null}
                else {
                    if($null-ne$script:LaserOnUtc){$d=($transitionUtc-$script:LaserOnUtc).TotalSeconds;Write-Event 'лазер выключён' '' ([Nullable[double]]$d) $script:LaserOnJob}
                    $script:LaserOnUtc=$null;$script:LaserOnJob='';$script:Session.laserOn=$false;$script:Session.laserOnUtc='';$script:Session.job=$script:LastJob;Save-State
                }
            }
            if(([datetime]::UtcNow-$script:LastCounterPollUtc).TotalMilliseconds-ge1000){$script:LastCounterPollUtc=[datetime]::UtcNow;Process-CounterCandidate (Get-CounterSnapshot)}
        } elseif($script:MonitorStarted -and -not$snap.Available) {
            if($script:SignalAvailable-ne$false){
                $script:SignalLossUtc=[datetime]::UtcNow
                if($script:LaserOn){Write-Event 'интервал лазера прерван' 'Сигнал потерян; окончание и длительность не вычислялись.' $null}
                Write-Event 'сигнал TubePro потерян' $(if(-not$snap.Found){'Окно TubePro не найдено.'}elseif($snap.Minimized){'Окно TubePro свёрнуто.'}else{'Область индикатора не видна или перекрыта.'}) $null
                $script:CounterNeedsRebase=$true;$script:CounterValue=$null;$script:CounterCandidate=$null;$script:CounterCandidateCount=0
                $script:Session.laserOn=$false;$script:Session.laserOnUtc='';Save-State
            }
            $script:SignalAvailable=$false;$script:LaserOn=$false;$script:LaserOnUtc=$null;$script:LaserOnJob='';$script:LaserCandidate=$false;$script:LaserCandidateCount=0
        }
        if(([datetime]::UtcNow-$script:LastVisualUpdateUtc).TotalMilliseconds-ge750){$script:LastVisualUpdateUtc=[datetime]::UtcNow;Update-Status $snap}
    } catch { $status.Text='Ошибка наблюдения: '+$_.Exception.Message }
})

function Show-GlassDialog {
    $dialog=New-Object Windows.Forms.Form;$dialog.Text=if($script:ActiveGlass){'Замена защитного стекла'}else{'Установка первого стекла'};$dialog.ClientSize=New-Object Drawing.Size(520,330);$dialog.FormBorderStyle='FixedDialog';$dialog.MaximizeBox=$false;$dialog.MinimizeBox=$false;$dialog.StartPosition='CenterParent';$dialog.BackColor=[Drawing.Color]::FromArgb(244,244,242);$dialog.Font=New-Object Drawing.Font('Segoe UI',10);$dialog.ShowInTaskbar=$false
    $head=New-Object Windows.Forms.Panel;$head.Dock='Top';$head.Height=58;$head.BackColor=[Drawing.Color]::FromArgb(36,36,36);$dialog.Controls.Add($head)
    $mark=New-Object Windows.Forms.Label;$mark.Text='LD';$mark.BackColor=[Drawing.Color]::FromArgb(255,236,0);$mark.ForeColor=[Drawing.Color]::Black;$mark.Font=New-Object Drawing.Font('Segoe UI Black',13);$mark.TextAlign='MiddleCenter';$mark.Location=New-Object Drawing.Point(14,10);$mark.Size=New-Object Drawing.Size(48,36);$head.Controls.Add($mark)
    $headTitle=New-Object Windows.Forms.Label;$headTitle.Text=if($script:ActiveGlass){'Замена стекла'}else{'Установка стекла'};$headTitle.ForeColor=[Drawing.Color]::White;$headTitle.Font=New-Object Drawing.Font('Segoe UI Semibold',13);$headTitle.Location=New-Object Drawing.Point(78,15);$headTitle.Size=New-Object Drawing.Size(415,30);$headTitle.AutoEllipsis=$true;$head.Controls.Add($headTitle)
    $reasonLabel=New-Object Windows.Forms.Label;$reasonLabel.Text='Причина замены';$reasonLabel.Location=New-Object Drawing.Point(24,82);$reasonLabel.Size=New-Object Drawing.Size(470,22);$dialog.Controls.Add($reasonLabel)
    $dialogReason=New-Object Windows.Forms.ComboBox;$dialogReason.DropDownStyle='DropDown';$dialogReason.Location=New-Object Drawing.Point(24,106);$dialogReason.Size=New-Object Drawing.Size(470,30);[void]$dialogReason.Items.AddRange([object[]]@('Сгорело','Загрязнение','Брак','Настройка'));$dialogReason.Text=$reasonBox.Text;$dialog.Controls.Add($dialogReason)
    if(-not$script:ActiveGlass){$reasonLabel.Text='Причина замены не требуется для первого стекла';$dialogReason.Enabled=$false}
    $noteLabel=New-Object Windows.Forms.Label;$noteLabel.Text='Примечание (необязательно)';$noteLabel.Location=New-Object Drawing.Point(24,153);$noteLabel.Size=New-Object Drawing.Size(470,22);$dialog.Controls.Add($noteLabel)
    $dialogNote=New-Object Windows.Forms.TextBox;$dialogNote.Location=New-Object Drawing.Point(24,177);$dialogNote.Size=New-Object Drawing.Size(470,58);$dialogNote.Multiline=$true;$dialogNote.MaxLength=250;$dialogNote.Text=$noteBox.Text;$dialog.Controls.Add($dialogNote)
    $cancel=New-Object CenteredTextButton;$cancel.Text='Отмена';$cancel.Location=New-Object Drawing.Point(204,263);$cancel.Size=New-Object Drawing.Size(100,42);$cancel.DialogResult=[Windows.Forms.DialogResult]::Cancel;Style-ActionButton $cancel $false;$cancel.Dock='None';$cancel.Margin=New-Object Windows.Forms.Padding(0);$dialog.Controls.Add($cancel)
    $confirm=New-Object CenteredTextButton;$confirm.Text=if($script:ActiveGlass){'Подтвердить замену'}else{'Установить стекло'};$confirm.Location=New-Object Drawing.Point(314,263);$confirm.Size=New-Object Drawing.Size(180,42);Style-ActionButton $confirm $true;$confirm.Dock='None';$confirm.Margin=New-Object Windows.Forms.Padding(0);$dialog.Controls.Add($confirm)
    $confirm.Add_Click({if($script:ActiveGlass-and[string]::IsNullOrWhiteSpace($dialogReason.Text)){[Windows.Forms.MessageBox]::Show($dialog,'Укажите причину снятия старого стекла.','Не заполнено')|Out-Null;return};$dialog.DialogResult=[Windows.Forms.DialogResult]::OK;$dialog.Close()})
    $dialog.AcceptButton=$confirm;$dialog.CancelButton=$cancel
    try{$result=$dialog.ShowDialog($form);if($result-ne[Windows.Forms.DialogResult]::OK){return $false};$reasonBox.Text=$dialogReason.Text;$noteBox.Text=$dialogNote.Text;return $true}finally{$dialog.Dispose()}
}

$glassButton.Add_Click({
    if([string]::IsNullOrWhiteSpace($stationBox.Text)-or[string]::IsNullOrWhiteSpace($operatorBox.Text)){[Windows.Forms.MessageBox]::Show('Укажите станок и оператора.')|Out-Null;return}
    if($script:LaserOn){[Windows.Forms.MessageBox]::Show('Нельзя фиксировать замену, пока индикатор лазера включён.')|Out-Null;return}
    if(-not(Show-GlassDialog)){return}
    if($script:LaserOn){[Windows.Forms.MessageBox]::Show('Замена отменена: пока было открыто окно, лазер включился.')|Out-Null;return}
    $now=[datetime]::UtcNow;$removedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    if($script:ActiveGlass){
        Close-ProductionCycle 'замена стекла'
        $script:CounterValue=$null;$script:CounterCandidate=$null;$script:CounterCandidateCount=0;$script:CounterNeedsRebase=$true
    }
    $oldGlass=$script:ActiveGlass;$id=New-FriendlyGlassId $stationBox.Text;$newGlass=[pscustomobject]@{id=$id;station=$stationBox.Text;operator=$operatorBox.Text;installedLocal=$removedLocal;installedUtc=$now.ToString('o')}
    $tx=[ordered]@{id=[guid]::NewGuid().ToString('N');station=$stationBox.Text;operator=$operatorBox.Text;reason=$reasonBox.Text;note=$noteBox.Text;removedLocal=$removedLocal;removedUtc=$now.ToString('o');oldGlass=$oldGlass;newGlass=$newGlass}
    Write-PendingGlassChange $tx;Complete-PendingGlassChange
    $reasonBox.Text='';$noteBox.Text='';[void]$script:RecentEvents.Add(('{0} — стекло установлено ({1})'-f(Get-Date -Format 'HH:mm:ss'),$id));while($script:RecentEvents.Count-gt5){$script:RecentEvents.RemoveAt(0)};Update-Status (Get-TubeProSnapshot)
})

$startButton.Add_Click({
    if(-not$script:ActiveGlass){[Windows.Forms.MessageBox]::Show('Сначала установите активное стекло.')|Out-Null;return}
    if([string]$script:ActiveGlass.station-ne$stationBox.Text){[Windows.Forms.MessageBox]::Show('Активное стекло относится к другому станку. Сначала зафиксируйте установку стекла на выбранном станке.')|Out-Null;return}
    if([string]::IsNullOrWhiteSpace($operatorBox.Text)){[Windows.Forms.MessageBox]::Show('Укажите оператора.')|Out-Null;return}
    $storageError=Test-DataStorage;if($storageError){[Windows.Forms.MessageBox]::Show($storageError,'Наблюдение не запущено')|Out-Null;return}
    if($script:ClockWarning){[Windows.Forms.MessageBox]::Show($script:ClockWarning,'Проверьте системное время')|Out-Null;return}
    Reset-LaserDetectionState;$ready=Get-TubeProSnapshot
    if(-not$ready.Found){[Windows.Forms.MessageBox]::Show('TubePro не найден. Откройте TubePro и повторите запуск.')|Out-Null;return}
    if(-not$ready.Available){[Windows.Forms.MessageBox]::Show('Индикатор лазера не виден. Разверните TubePro и уберите перекрывающие окна.')|Out-Null;return}
    $script:MonitorStarted=$true;$script:SignalAvailable=$true;$script:SignalLossUtc=$null;$script:UnavailableSeconds=0.0;$script:Session=[ordered]@{active=$true;station=$stationBox.Text;operator=$operatorBox.Text;startedUtc=[datetime]::UtcNow.ToString('o');laserOn=$false;laserOnUtc='';job=$script:LastJob};Save-State;$startButton.Enabled=$false;$startButton.Visible=$false;$stopButton.Enabled=$true;$stopButton.Visible=$true;$stopButton.BringToFront();$form.AcceptButton=$null;$shiftButton.Enabled=$true;$exportButton.Enabled=$false;$stationBox.Enabled=$false;$operatorBox.Enabled=$false;Write-Event 'наблюдение начато' '' $null;Update-Status $ready
})
$stopButton.Add_Click({
    if($script:LaserOn -and $null-ne$script:LaserOnUtc){$d=([datetime]::UtcNow-$script:LaserOnUtc).TotalSeconds;Write-Event 'лазер выключён при остановке монитора' '' ([Nullable[double]]$d) $script:LaserOnJob};Reset-LaserDetectionState
    if($script:SignalLossUtc){$script:UnavailableSeconds+=([datetime]::UtcNow-$script:SignalLossUtc).TotalSeconds;$script:SignalLossUtc=$null}
    Close-ProductionCycle 'наблюдение остановлено';Write-Event 'наблюдение остановлено' '' $null;$script:MonitorStarted=$false;$script:Session=[ordered]@{active=$false;station='';operator='';startedUtc='';laserOn=$false;laserOnUtc='';job=''};Save-State;$stopButton.Enabled=$false;$stopButton.Visible=$false;$startButton.Enabled=$true;$startButton.Visible=$true;$startButton.BringToFront();$form.AcceptButton=$startButton;$shiftButton.Enabled=$false;$exportButton.Enabled=$true;$stationBox.Enabled=[string]::IsNullOrWhiteSpace($FixedStation);$operatorBox.Enabled=$true;Update-Status (Get-TubeProSnapshot)
})
$shiftButton.Add_Click({if([Windows.Forms.MessageBox]::Show('Завершить смену? Стекло останется установленным, отчёт выгружаться не будет.','Конец смены',[Windows.Forms.MessageBoxButtons]::YesNo)-eq[Windows.Forms.DialogResult]::Yes){$stopButton.PerformClick();Write-Event 'конец смены' 'Стекло оставлено установленным; выгрузка не выполнялась.' $null;Save-State;Update-Status (Get-TubeProSnapshot)}})
$diagnosticsButton.Add_Click({
    $d=New-Object Windows.Forms.Form;$d.Text='Диагностика монитора';$d.ClientSize=New-Object Drawing.Size(720,520);$d.MinimumSize=New-Object Drawing.Size(620,420);$d.StartPosition='CenterParent';$d.BackColor=[Drawing.Color]::FromArgb(244,244,242);$d.Font=New-Object Drawing.Font('Segoe UI',10);$d.ShowInTaskbar=$false
    $diagLayout=New-Object Windows.Forms.TableLayoutPanel;$diagLayout.Dock='Fill';$diagLayout.ColumnCount=1;$diagLayout.RowCount=2;[void]$diagLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,52)));[void]$diagLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));$d.Controls.Add($diagLayout)
    $head=New-Object Windows.Forms.Panel;$head.Dock='Fill';$head.BackColor=[Drawing.Color]::FromArgb(36,36,36);$head.Margin=New-Object Windows.Forms.Padding(0);$diagLayout.Controls.Add($head,0,0)
    $caption=New-Object Windows.Forms.Label;$caption.Text='Диагностика';$caption.ForeColor=[Drawing.Color]::White;$caption.Font=New-Object Drawing.Font('Segoe UI Semibold',13);$caption.Location=New-Object Drawing.Point(16,13);$caption.AutoSize=$true;$head.Controls.Add($caption)
    $box=New-Object Windows.Forms.RichTextBox;$box.Dock='Fill';$box.ReadOnly=$true;$box.BorderStyle='None';$box.BackColor=[Drawing.Color]::White;$box.Font=New-Object Drawing.Font('Consolas',10);$box.Text=$script:DiagnosticText;$box.Margin=New-Object Windows.Forms.Padding(14);$diagLayout.Controls.Add($box,0,1)
    try{[void]$d.ShowDialog($form)}finally{$d.Dispose()}
})
$helpButton.Add_Click({
    $station=if($FixedStation){$FixedStation}else{$stationBox.Text}
    $text="КРАТКАЯ ИНСТРУКЦИЯ`r`n`r`n1. Откройте и разверните TubePro.`r`n2. Не перекрывайте верхнюю правую область с индикатором «Лазер».`r`n3. Выберите оператора и проверьте активное стекло.`r`n4. Нажмите «Начать наблюдение».`r`n5. Сам монитор можно свернуть — учёт продолжится в фоне.`r`n6. TubePro сворачивать нельзя: лазер и детали временно перестанут учитываться.`r`n7. При замене стекла используйте отдельное окно «Заменить стекло».`r`n8. В конце работы нажмите «Завершить смену». Стекло останется активным.`r`n9. Отчёт выгружайте отдельной кнопкой по необходимости.`r`n`r`nВерсия: $($script:AppVersion)`r`nСтанок: $station`r`nДата сборки: $($script:BuildDate)"
    [Windows.Forms.MessageBox]::Show($text,'Инструкция — монитор ресурса стёкол',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null
})
$exportButton.Add_Click({Export-Report})
$form.Add_FormClosing({if($script:MonitorStarted){$stopButton.PerformClick()};Save-State})
Recover-InterruptedSession
$timer.Start();Update-Status (Get-TubeProSnapshot)
try{[void]$form.ShowDialog()}finally{if($null-ne$script:InstanceMutex){try{$script:InstanceMutex.ReleaseMutex()}catch{};$script:InstanceMutex.Dispose();$script:InstanceMutex=$null}}
