#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Windows Health Check - Gelismis Sistem Tani Araci v2.0
.DESCRIPTION
    SMART disk analizi, SSD TRIM, Defender, Windows Update,
    tarayici onbellekleri, yuklu programlar ve guc plani dahil
    kapsamli sistem saglik raporu uretir.
.NOTES
    Yonetici (Administrator) olarak calistirilmalidir.
    Calistirmak icin: Set-ExecutionPolicy -Scope Process Bypass
#>

# ------------------------------------
# RAPOR NESNESI
# ------------------------------------

$Report = [ordered]@{
    ComputerName = $env:COMPUTERNAME
    Date         = Get-Date
    Findings     = New-Object System.Collections.ArrayList
    Score        = 100
}

function Add-Finding {
    param(
        [ValidateSet("CRITICAL","HIGH","MEDIUM","LOW","INFO")]
        [string]$Severity,
        [string]$Message,
        [int]$Penalty = 0
    )

    $null = $Report.Findings.Add([PSCustomObject]@{
        Severity = $Severity
        Message  = $Message
    })

    $script:Report.Score -= $Penalty
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("-" * 45) -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("-" * 45) -ForegroundColor DarkGray
}

function Write-KV {
    param([string]$Key, [string]$Value, [string]$Color = "White")
    $padded = $Key.PadRight(22)
    Write-Host "  $padded : " -NoNewline
    Write-Host $Value -ForegroundColor $Color
}

# ------------------------------------
# BASLIK
# ------------------------------------

Clear-Host
Write-Host ""
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "       WINDOWS HEALTH CHECK  v2.0             " -ForegroundColor Cyan
Write-Host "       Gelismis Sistem Tani Araci              " -ForegroundColor Cyan
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "  Bilgisayar : $($env:COMPUTERNAME)" -ForegroundColor Gray
Write-Host "  Tarih      : $(Get-Date -Format 'dd.MM.yyyy HH:mm')" -ForegroundColor Gray

# ------------------------------------
# 1. SISTEM BILGISI
# ------------------------------------

Write-Section "1. SISTEM BILGISI"

$os  = Get-CimInstance Win32_OperatingSystem
$cs  = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor

Write-KV "Bilgisayar"  $cs.Name
Write-KV "Islemci"     $cpu.Name
Write-KV "Windows"     $os.Caption
Write-KV "Surum"       $os.Version
Write-KV "Mimari"      $os.OSArchitecture

# ------------------------------------
# 2. RAM
# ------------------------------------

Write-Section "2. BELLEK (RAM)"

$totalRamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$freeRamGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$usedPct    = [math]::Round((($totalRamGB - $freeRamGB) / $totalRamGB) * 100)

Write-KV "Toplam RAM"  "$totalRamGB GB"
Write-KV "Bos RAM"     "$freeRamGB GB"
Write-KV "Kullanim"    "%$usedPct"

if ($totalRamGB -lt 8) {
    Add-Finding "HIGH" "RAM 8 GB altinda ($totalRamGB GB). Performans etkilenebilir." 20
}
if ($usedPct -gt 85) {
    Add-Finding "MEDIUM" "RAM kullanimi cok yuksek (%$usedPct)." 10
}

# ------------------------------------
# 3. DISK - FIZIKSEL + SMART
# ------------------------------------

Write-Section "3. DISK ANALIZI"

$physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue

foreach ($disk in $physicalDisks) {

    $type   = $disk.MediaType
    $health = $disk.HealthStatus
    $sizeGB = [math]::Round($disk.Size / 1GB, 0)

    Write-Host ""
    Write-Host "  >> $($disk.FriendlyName)" -ForegroundColor Yellow

    $typeColor   = if ($type -eq "SSD") { "Green" } else { "Red" }
    $healthColor = if ($health -eq "Healthy") { "Green" } else { "Red" }

    Write-KV "  Tip"    $type   $typeColor
    Write-KV "  Boyut"  "$sizeGB GB"
    Write-KV "  Saglik" $health $healthColor

    # SMART - StorageReliabilityCounter
    try {
        $diskNum = $disk.DeviceId
        $smartData = Get-Disk -Number $diskNum -ErrorAction SilentlyContinue

        if ($smartData) {
            $opStatus = $smartData.OperationalStatus
            Write-KV "  Op.Durum" $opStatus
            if ($opStatus -notin @("OK","Online")) {
                Add-Finding "CRITICAL" "$($disk.FriendlyName) - Disk operasyonel durumu kritik: $opStatus" 40
            }
        }

        $reliability = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue

        if ($reliability) {
            $tempC = if ($reliability.Temperature)     { "$($reliability.Temperature) C" }  else { "N/A" }
            $wear  = if ($reliability.Wear)            { "%$($reliability.Wear)" }           else { "N/A" }
            $reads = if ($reliability.ReadErrorsTotal) { $reliability.ReadErrorsTotal }      else { 0 }
            $writes= if ($reliability.WriteErrorsTotal){ $reliability.WriteErrorsTotal }     else { 0 }

            Write-KV "  SMART Sicaklik" $tempC
            Write-KV "  SMART Asinma"   $wear
            Write-KV "  Okuma Hatasi"   "$reads"
            Write-KV "  Yazma Hatasi"   "$writes"

            if ($reliability.Temperature -and $reliability.Temperature -gt 55) {
                Add-Finding "HIGH" "$($disk.FriendlyName) - Disk sicakligi yuksek: $($reliability.Temperature)C" 15
            }
            if ($reliability.Wear -and $reliability.Wear -gt 80) {
                Add-Finding "HIGH" "$($disk.FriendlyName) - SSD asinma degeri kritik: %$($reliability.Wear)" 20
            }
            if (($reads -gt 0) -or ($writes -gt 0)) {
                Add-Finding "MEDIUM" "$($disk.FriendlyName) - Disk I/O hatalari mevcut (Okuma: $reads, Yazma: $writes)" 10
            }
        }
    }
    catch {
        Write-KV "  SMART" "Okunamadi" "DarkGray"
    }

    if ($type -ne "SSD") {
        Add-Finding "HIGH" "$($disk.FriendlyName) - SSD degil ($type). Performans dusuk olabilir." 25
    }
    if ($health -ne "Healthy") {
        Add-Finding "CRITICAL" "$($disk.FriendlyName) - Disk sagligi kritik: $health" 40
    }
}

# SSD TRIM
Write-Host ""
Write-Host "  >> SSD TRIM Kontrolu" -ForegroundColor Yellow

try {
    $trimQuery = & fsutil behavior query DisableDeleteNotify 2>$null
    if ($trimQuery -match "0") {
        Write-KV "  TRIM" "Aktif" "Green"
    }
    else {
        Write-KV "  TRIM" "DEVRE DISI" "Red"
        Add-Finding "HIGH" "SSD TRIM devre disi. SSD performansi dusuyor olabilir." 15
    }
}
catch {
    Write-KV "  TRIM" "Sorgulanamadi" "DarkGray"
}

# Mantiksal disk dolulugu
Write-Host ""
Write-Host "  >> Surucu Dolulugu" -ForegroundColor Yellow

Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $freeGB  = [math]::Round($_.FreeSpace / 1GB, 1)
    $totalGB = [math]::Round($_.Size / 1GB, 0)
    $freePct = [math]::Round(($_.FreeSpace / $_.Size) * 100)
    $color   = if ($freePct -lt 10) { "Red" } elseif ($freePct -lt 20) { "Yellow" } else { "Green" }

    Write-KV "  $($_.DeviceID) Bos" "$freeGB GB / $totalGB GB  (%$freePct)" $color

    if ($freePct -lt 10) {
        Add-Finding "HIGH"   "$($_.DeviceID) surucusu kritik dolu (%$freePct bos)." 20
    }
    elseif ($freePct -lt 20) {
        Add-Finding "MEDIUM" "$($_.DeviceID) surucusu dolmaya yaklasiyor (%$freePct bos)." 10
    }
}

# ------------------------------------
# 4. WINDOWS DEFENDER
# ------------------------------------

Write-Section "4. WINDOWS DEFENDER"

try {
    $defender      = Get-MpComputerStatus -ErrorAction Stop
    $avEnabled     = $defender.AntivirusEnabled
    $rtEnabled     = $defender.RealTimeProtectionEnabled
    $lastScanDays  = ([datetime]::Now - $defender.QuickScanEndTime).Days
    $defAge        = ([datetime]::Now - $defender.AntivirusSignatureLastUpdated).Days
    $defVer        = $defender.AntivirusSignatureVersion

    $avColor   = if ($avEnabled)          { "Green"  } else { "Red" }
    $rtColor   = if ($rtEnabled)          { "Green"  } else { "Red" }
    $scanColor = if ($lastScanDays -le 7) { "Green"  } elseif ($lastScanDays -le 14) { "Yellow" } else { "Red" }
    $defColor  = if ($defAge -le 3)       { "Green"  } elseif ($defAge -le 7)        { "Yellow" } else { "Red" }

    Write-KV "Antivirus"       $(if ($avEnabled) {"Aktif"} else {"DEVRE DISI"}) $avColor
    Write-KV "Gercek Zamanli"  $(if ($rtEnabled) {"Aktif"} else {"DEVRE DISI"}) $rtColor
    Write-KV "Son Tarama"      "$lastScanDays gun once"                          $scanColor
    Write-KV "Tanim Guncellik" "$defAge gun once guncellendi"                    $defColor
    Write-KV "Tanim Surumu"    $defVer

    if (-not $avEnabled)          { Add-Finding "CRITICAL" "Windows Defender Antivirus devre disi!" 30 }
    if (-not $rtEnabled)          { Add-Finding "CRITICAL" "Gercek zamanli koruma kapali!" 25 }
    if ($lastScanDays -gt 14)     { Add-Finding "MEDIUM"   "Son Defender taramasi $lastScanDays gun once yapildi." 10 }
    if ($defAge -gt 7)            { Add-Finding "HIGH"     "Defender tanim dosyalari $defAge gundur guncellenmemis." 15 }
}
catch {
    Write-KV "Durum" "Sorgulanamadi" "DarkGray"
    Add-Finding "INFO" "Defender durumu sorgulanamadi." 0
}

# ------------------------------------
# 5. WINDOWS UPDATE
# ------------------------------------

Write-Section "5. WINDOWS UPDATE"

try {
    $updateSession  = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()

    Write-Host "  Bekleyen guncellestirmeler araniyor..." -ForegroundColor Gray

    $pendingUpdates = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
    $pendingCount   = $pendingUpdates.Updates.Count
    $criticalCount  = ($pendingUpdates.Updates | Where-Object { $_.MsrcSeverity -eq "Critical" }).Count
    $securityCount  = ($pendingUpdates.Updates | Where-Object { $_.MsrcSeverity -eq "Important" }).Count

    $pColor = if ($pendingCount -eq 0) { "Green" } elseif ($pendingCount -lt 5) { "Yellow" } else { "Red" }

    Write-KV "Bekleyen"  "$pendingCount guncellestirme"   $pColor
    Write-KV "Kritik"    "$criticalCount adet"            $(if ($criticalCount -gt 0) {"Red"}    else {"Green"})
    Write-KV "Onemli"    "$securityCount adet"            $(if ($securityCount -gt 0) {"Yellow"} else {"Green"})

    $history    = $updateSearcher.QueryHistory(0, [Math]::Min(50, $updateSearcher.GetTotalHistoryCount()))
    $lastUpdate = ($history | Where-Object { $_.ResultCode -eq 2 } | Sort-Object Date -Descending | Select-Object -First 1).Date

    if ($lastUpdate) {
        $daysAgo = ([datetime]::Now - $lastUpdate).Days
        $updColor = if ($daysAgo -le 30) { "Green" } else { "Yellow" }
        Write-KV "Son Yukleme" "$daysAgo gun once ($($lastUpdate.ToString('dd.MM.yyyy')))" $updColor
    }

    if ($criticalCount -gt 0) { Add-Finding "CRITICAL" "$criticalCount kritik guncellestirme bekliyor!" 20 }
    if ($pendingCount -gt 10) { Add-Finding "MEDIUM"   "$pendingCount guncellestirme bekliyor." 10 }
    elseif ($pendingCount -gt 0) { Add-Finding "LOW"   "$pendingCount kucuk guncellestirme bekliyor." 5 }
}
catch {
    Write-KV "Durum" "COM nesnesi acilamadi - alternatif kontrol yapiliyor" "DarkGray"

    try {
        $regPath     = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install"
        $lastInstall = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).LastSuccessTime
        if ($lastInstall) { Write-KV "Son Yukleme (Reg)" $lastInstall }
    }
    catch { }

    Add-Finding "INFO" "Windows Update COM nesnesi sorgulanamadi." 0
}

# ------------------------------------
# 6. TARAYICI ONBELLEKLERI
# ------------------------------------

Write-Section "6. TARAYICI ONBELLEKLERI"

$userProfiles = Get-ChildItem "C:\Users" -Directory |
    Where-Object { $_.Name -notin @("Public","Default","Default User","All Users") }

$browsers = @(
    @{ Name = "Chrome";  RelPath = "AppData\Local\Google\Chrome\User Data\Default\Cache" },
    @{ Name = "Edge";    RelPath = "AppData\Local\Microsoft\Edge\User Data\Default\Cache" },
    @{ Name = "Firefox"; RelPath = "AppData\Local\Mozilla\Firefox\Profiles" },
    @{ Name = "Brave";   RelPath = "AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Cache" }
)

$totalBrowserCacheMB = 0

foreach ($user in $userProfiles) {
    foreach ($browser in $browsers) {
        $cachePath = Join-Path $user.FullName $browser.RelPath

        if (Test-Path $cachePath) {
            $sizeBytes = (
                Get-ChildItem $cachePath -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object Length -Sum
            ).Sum

            $sizeMB = [math]::Round($sizeBytes / 1MB, 1)
            $totalBrowserCacheMB += $sizeMB
            $cacheColor = if ($sizeMB -gt 1000) { "Red" } elseif ($sizeMB -gt 500) { "Yellow" } else { "White" }

            Write-KV "$($user.Name)/$($browser.Name)" "$sizeMB MB" $cacheColor
        }
    }
}

if ($totalBrowserCacheMB -eq 0) {
    Write-Host "  Tarayici onbellegi bulunamadi." -ForegroundColor DarkGray
}
else {
    $totalCacheGB = [math]::Round($totalBrowserCacheMB / 1024, 2)
    Write-Host ""
    Write-KV "Toplam Onbellek" "$totalBrowserCacheMB MB ($totalCacheGB GB)" $(if ($totalBrowserCacheMB -gt 2048) {"Yellow"} else {"White"})

    if ($totalBrowserCacheMB -gt 2048) {
        Add-Finding "LOW" "Tarayici onbellekleri toplami $totalCacheGB GB. Temizlenebilir." 5
    }
}

# ------------------------------------
# 7. GECICI DOSYALAR
# ------------------------------------

Write-Section "7. GECICI DOSYALAR"

$tempPaths = @(
    @{ Label = "Kullanici Temp"; Path = $env:TEMP },
    @{ Label = "Windows Temp";   Path = "C:\Windows\Temp" },
    @{ Label = "Prefetch";       Path = "C:\Windows\Prefetch" }
)

$totalTempMB = 0

foreach ($t in $tempPaths) {
    if (Test-Path $t.Path) {
        $bytes = (
            Get-ChildItem $t.Path -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum
        ).Sum
        $mb = [math]::Round($bytes / 1MB, 1)
        $totalTempMB += $mb
        Write-KV $t.Label "$mb MB"
    }
}

$totalTempGB = [math]::Round($totalTempMB / 1024, 2)
Write-KV "Toplam Temp" "$totalTempMB MB ($totalTempGB GB)" $(if ($totalTempGB -gt 2) {"Yellow"} else {"White"})

if ($totalTempGB -gt 2) {
    Add-Finding "LOW" "Gecici dosyalar $totalTempGB GB. Temizlik oneriliyor." 5
}

# ------------------------------------
# 8. GUC PLANI
# ------------------------------------

Write-Section "8. GUC PLANI (POWER PLAN)"

try {
    $powerCfg = & powercfg /getactivescheme 2>$null
    $planName = if ($powerCfg -match "\((.+)\)$") { $Matches[1] } else { $powerCfg }

    Write-KV "Aktif Plan" $planName

    if ($powerCfg -match "Power saver|Tasarruf") {
        Write-KV "Degerlendirme" "Guc tasarrufu - performans dusuk" "Red"
        Add-Finding "MEDIUM" "Guc tasarrufu plani aktif. Masaustu/sunucu performansi dusuyor olabilir." 10
    }
    elseif ($powerCfg -match "Balanced|Dengeli") {
        Write-KV "Degerlendirme" "Dengeli plan - kabul edilebilir" "Yellow"
        Add-Finding "LOW" "Dengeli guc plani. Yuksek performans icin 'High Performance' tercih edilebilir." 3
    }
    else {
        Write-KV "Degerlendirme" "Yuksek performans veya ozel plan" "Green"
    }

    $fastBoot = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -ErrorAction SilentlyContinue).HiberbootEnabled
    if ($fastBoot -eq 1) {
        Write-KV "Hizli Baslangic" "Aktif (Fast Startup)" "Yellow"
        Add-Finding "INFO" "Hizli Baslangic (Fast Startup) aktif. Tam kapanma yerine hazirda bekletme kullaniliyor." 0
    }
    else {
        Write-KV "Hizli Baslangic" "Devre disi" "Green"
    }
}
catch {
    Write-KV "Durum" "Sorgulanamadi" "DarkGray"
}

# ------------------------------------
# 9. YUKLU PROGRAMLAR
# ------------------------------------

Write-Section "9. YUKLU PROGRAM ANALIZI"

$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$programs = $regPaths | ForEach-Object {
    Get-ItemProperty $_ -ErrorAction SilentlyContinue
} | Where-Object {
    $_.DisplayName -and $_.DisplayName.Trim() -ne ""
} | Select-Object DisplayName, DisplayVersion, Publisher,
    @{ Name="InstallDate"; Expression={
        if ($_.InstallDate -match "(\d{4})(\d{2})(\d{2})") {
            [datetime]::ParseExact($_.InstallDate,"yyyyMMdd",$null)
        }
    }
} | Sort-Object DisplayName -Unique

$totalPrograms = $programs.Count
Write-KV "Toplam Program" $totalPrograms

$recentPrograms = $programs | Where-Object {
    $_.InstallDate -and ([datetime]::Now - $_.InstallDate).Days -le 30
}

Write-Host ""
Write-Host "  Son 30 Gunde Yuklenenenler :" -ForegroundColor Yellow

if ($recentPrograms.Count -gt 0) {
    $recentPrograms | ForEach-Object {
        $days = if ($_.InstallDate) { "$([int]([datetime]::Now - $_.InstallDate).Days) gun once" } else { "" }
        Write-Host "    + $($_.DisplayName)  $days" -ForegroundColor White
    }
}
else {
    Write-Host "    Yok" -ForegroundColor DarkGray
}

if ($totalPrograms -gt 80) {
    Add-Finding "LOW" "Cok fazla yuklu program ($totalPrograms). Kullanilmayanlarin kaldirilmasi oneriliyor." 5
}

# ------------------------------------
# 10. BASLANGI PROGRAMLARI
# ------------------------------------

Write-Section "10. BASLANGIC PROGRAMLARI"

$startupItems = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
$startupCount = $startupItems.Count

Write-KV "Toplam" $startupCount

if ($startupCount -gt 0) {
    $startupItems | Select-Object -First 15 Name, Location | ForEach-Object {
        Write-Host "    - $($_.Name)" -ForegroundColor DarkGray
    }
    if ($startupCount -gt 15) {
        Write-Host "    ... ve $($startupCount - 15) tane daha" -ForegroundColor DarkGray
    }
}

if ($startupCount -gt 15) {
    Add-Finding "HIGH"   "Cok fazla baslangic uygulamasi ($startupCount). Acilis suresi uzuyor." 15
}
elseif ($startupCount -gt 10) {
    Add-Finding "MEDIUM" "Yuksek baslangic uygulamasi sayisi ($startupCount)." 10
}

# ------------------------------------
# 11. SISTEM CALISMA SURESI
# ------------------------------------

Write-Section "11. SISTEM CALISMA SURESI"

$uptime = (Get-Date) - $os.LastBootUpTime
$days   = [int]$uptime.TotalDays
$hours  = $uptime.Hours

Write-KV "Son Acilis"     $os.LastBootUpTime.ToString("dd.MM.yyyy HH:mm")
Write-KV "Calisma Suresi" "$days gun $hours saat"

if ($days -gt 30) {
    Add-Finding "MEDIUM" "Sistem $days gundur yeniden baslatilmamis." 8
}
elseif ($days -gt 14) {
    Add-Finding "LOW" "Sistem $days gundur yeniden baslatilmamis." 3
}

# ------------------------------------
# 12. OLAY KAYDI HATALARI
# ------------------------------------

Write-Section "12. SISTEM OLAY KAYDI (Son 7 Gun)"

$systemErrors = Get-WinEvent `
    -FilterHashtable @{ LogName="System";      Level=2; StartTime=(Get-Date).AddDays(-7) } `
    -ErrorAction SilentlyContinue

$appErrors = Get-WinEvent `
    -FilterHashtable @{ LogName="Application"; Level=2; StartTime=(Get-Date).AddDays(-7) } `
    -ErrorAction SilentlyContinue

$sysErrCount = $systemErrors.Count
$appErrCount = $appErrors.Count

$sysColor = if ($sysErrCount -gt 50) {"Red"} elseif ($sysErrCount -gt 20) {"Yellow"} else {"Green"}
$appColor = if ($appErrCount -gt 50) {"Red"} elseif ($appErrCount -gt 20) {"Yellow"} else {"Green"}

Write-KV "Sistem Hatalari"   $sysErrCount $sysColor
Write-KV "Uygulama Hatalari" $appErrCount $appColor

if ($sysErrCount -gt 0) {
    Write-Host ""
    Write-Host "  En Cok Tekrarlanan Sistem Hatalari :" -ForegroundColor Yellow

    $systemErrors |
    Group-Object Id |
    Sort-Object Count -Descending |
    Select-Object -First 5 |
    ForEach-Object {
        $msg = ($_.Group[0].Message -split "`n")[0]
        if ($msg.Length -gt 72) { $msg = $msg.Substring(0,72) + "..." }
        Write-Host "    [ID:$($_.Name) x$($_.Count)] $msg" -ForegroundColor DarkGray
    }
}

if ($sysErrCount -gt 50) { Add-Finding "MEDIUM" "Sistem hata sayisi cok yuksek: $sysErrCount (7 gun)." 10 }
if ($appErrCount -gt 50) { Add-Finding "LOW"    "Uygulama hata sayisi yuksek: $appErrCount (7 gun)." 5  }

# ------------------------------------
# 13. EN FAZLA KAYNAK KULLANANLAR
# ------------------------------------

Write-Section "13. EN FAZLA KAYNAK KULLANAN UYGULAMALAR"

Write-Host ""
Write-Host "  >> RAM (Calisma Seti - Top 10)" -ForegroundColor Yellow

Get-Process |
Sort-Object WorkingSet -Descending |
Select-Object -First 10 Name,
    @{ Name="RAM_MB"; Expression={ [math]::Round($_.WorkingSet / 1MB) } },
    @{ Name="CPU_sn"; Expression={ [math]::Round($_.CPU, 1) } } |
Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "  >> CPU (Toplam saniye - Top 10)" -ForegroundColor Yellow

Get-Process |
Sort-Object CPU -Descending |
Select-Object -First 10 Name, CPU |
Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "  $_" }

# ------------------------------------
# SKOR VE OZET
# ------------------------------------

if ($Report.Score -lt 0) { $Report.Score = 0 }

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "               SAGLIK PUANI                   " -ForegroundColor Cyan
Write-Host "  =============================================" -ForegroundColor Cyan

if ($Report.Score -ge 85) {
    $scoreColor = "Green"
    $verdict    = "SAGLIKLI"
}
elseif ($Report.Score -ge 65) {
    $scoreColor = "Yellow"
    $verdict    = "DIKKAT GEREKLI"
}
elseif ($Report.Score -ge 40) {
    $scoreColor = "DarkYellow"
    $verdict    = "SORUNLU"
}
else {
    $scoreColor = "Red"
    $verdict    = "KRITIK"
}

Write-Host ""
Write-Host "  PUAN : $($Report.Score)/100  [$verdict]" -ForegroundColor $scoreColor
Write-Host ""

$severityOrder = @{ "CRITICAL"=0; "HIGH"=1; "MEDIUM"=2; "LOW"=3; "INFO"=4 }

Write-Host "  BULGULAR VE ONERILER" -ForegroundColor Cyan
Write-Host ("  " + ("-" * 43)) -ForegroundColor DarkGray

if ($Report.Findings.Count -eq 0) {
    Write-Host "  Onemli bir sorun bulunamadi." -ForegroundColor Green
}
else {
    $Report.Findings |
    Sort-Object { $severityOrder[$_.Severity] } |
    ForEach-Object {
        $color = switch ($_.Severity) {
            "CRITICAL" { "Red"        }
            "HIGH"     { "DarkRed"    }
            "MEDIUM"   { "Yellow"     }
            "LOW"      { "DarkYellow" }
            "INFO"     { "DarkGray"   }
        }
        Write-Host "  [$($_.Severity.PadRight(8))] $($_.Message)" -ForegroundColor $color
    }
}

Write-Host ""
Write-Host ("-" * 45) -ForegroundColor DarkGray
Write-Host "  Tarama Tamamlandi : $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')" -ForegroundColor Gray
Write-Host ("-" * 45) -ForegroundColor DarkGray
Write-Host ""
