#Requires -Version 5.1
# Claudflare RDP Quick Connect - Version 2 (Fixed)
$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Claudflare RDP Connector"

function Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

function Test-PortInUse {
    param([int]$Port)
    try {
        $netstat = netstat -ano | Select-String ":$port\s" | Select-String "LISTENING"
        return ($null -ne $netstat)
    }
    catch {
        return $false
    }
}

function Get-CloudflaredPath {
    $locations = @(
        "$env:SystemRoot\System32\cloudflared.exe",
        "${env:ProgramFiles}\cloudflared.exe",
        "${env:LOCALAPPDATA}\cloudflared\cloudflared.exe",
        "${env:TEMP}\cloudflared.exe"
    )
    foreach ($loc in $locations) {
        if (Test-Path $loc) { 
            # Verify file is valid PE executable
            try {
                $bytes = [System.IO.File]::ReadAllBytes($loc)
                if ($bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) {
                    return $loc 
                }
            }
            catch {}
        }
    }
    return $null
}

function Install-Cloudflared {
    Log "Dang chuan bi tool..." "Yellow"
    $tempExe = "${env:TEMP}\cloudflared.exe"
    $systemExe = "$env:SystemRoot\System32\cloudflared.exe"
    $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    
    try {
        # Remove old temp file
        if (Test-Path $tempExe) { Remove-Item $tempExe -Force }
        
        Invoke-WebRequest -Uri $url -OutFile $tempExe -UseBasicParsing
        
        # Verify download
        if (-not (Test-Path $tempExe)) {
            throw "Download failed - file not created"
        }
        
        $fileSize = (Get-Item $tempExe).Length
        Log "Da tai: $([math]::Round($fileSize/1MB, 2)) MB" "Green"
        
        # Copy to System32 (in PATH)
        Copy-Item $tempExe $systemExe -Force
        Log "Cai dat thanh cong: $systemExe" "Green"
        return $systemExe
    }
    catch {
        Log "Loi: $($_.Exception.Message)" "Red"
        return $null
    }
}


function Get-MstscPath {
    # Xu ly ca truong hop PowerShell 32-bit chay tren Windows 64-bit.
    $candidates = @()
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $candidates += "$env:SystemRoot\Sysnative\mstsc.exe"
    }
    $candidates += "$env:SystemRoot\System32\mstsc.exe"
    $candidates += "$env:SystemRoot\SysWOW64\mstsc.exe"

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

function Get-MstscInstallerUrl {
    # Link tai setup.exe duoc Microsoft cong bo trong tai lieu cai dat lai Remote Desktop Connection.
    $architecture = $null
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        switch ([int]$cpu.Architecture) {
            12 { $architecture = 'ARM64' }
            9  { $architecture = 'AMD64' }
            0  { $architecture = 'X86' }
            default { $architecture = $null }
        }
    }
    catch {
        $archText = $env:PROCESSOR_ARCHITEW6432
        if ([string]::IsNullOrWhiteSpace($archText)) {
            $archText = $env:PROCESSOR_ARCHITECTURE
        }
        if ($archText -match 'ARM64') { $architecture = 'ARM64' }
        elseif ($archText -match 'AMD64') { $architecture = 'AMD64' }
        elseif ($archText -match '86') { $architecture = 'X86' }
    }

    switch ($architecture) {
        'ARM64' { return 'https://go.microsoft.com/fwlink/?linkid=2247577' }
        'AMD64' { return 'https://go.microsoft.com/fwlink/?linkid=2247659' }
        'X86'   { return 'https://go.microsoft.com/fwlink/?linkid=2247660' }
        default { throw "Khong xac dinh duoc kien truc Windows de chon bo cai mstsc (Architecture: $architecture)." }
    }
}

function Install-Mstsc {
    $installerPath = Join-Path $env:TEMP "mstsc-setup-$PID.exe"
    try {
        Log "Xac dinh kien truc Windows..." "Gray"
        $downloadUrl = Get-MstscInstallerUrl
        Log "Dang tai bo cai Remote Desktop Connection chinh chu tu Microsoft..." "Yellow"

        # TLS 1.2 cho cac may Windows PowerShell 5.1 cu.
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        }
        catch {}

        if (Test-Path -LiteralPath $installerPath) {
            Remove-Item -LiteralPath $installerPath -Force
        }
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop

        if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
            throw "Khong tai duoc file setup.exe."
        }

        $fileInfo = Get-Item -LiteralPath $installerPath
        if ($fileInfo.Length -lt 100KB) {
            throw "File setup.exe tai ve qua nho, co the la trang loi thay vi bo cai."
        }

        # Chi chay bo cai neu chu ky so hop le va thuoc Microsoft.
        $signature = Get-AuthenticodeSignature -FilePath $installerPath
        if ($signature.Status -ne 'Valid') {
            throw "Chu ky so cua bo cai khong hop le: $($signature.Status). Da huy de tranh chay file khong xac minh duoc."
        }
        if ($signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
            throw "Nha phat hanh bo cai khong phai Microsoft Corporation. Da huy cai dat."
        }

        Log "Da tai va xac minh chu ky Microsoft. Dang chay bo cai voi quyen Administrator..." "Green"
        $installProcess = Start-Process -FilePath $installerPath -Verb RunAs -Wait -PassThru

        if ($installProcess.ExitCode -notin @(0, 3010)) {
            throw "Bo cai ket thuc voi ma loi: $($installProcess.ExitCode)."
        }

        Start-Sleep -Seconds 2
        $installedMstsc = Get-MstscPath
        if (-not $installedMstsc) {
            throw "Bo cai da chay nhung chua tim thay mstsc.exe. Hay khoi dong lai Windows roi kiem tra lai."
        }

        Log "Da khoi phuc Remote Desktop Connection: $installedMstsc" "Green"
        if ($installProcess.ExitCode -eq 3010) {
            Log "Windows yeu cau khoi dong lai de hoan tat cai dat." "Yellow"
        }
        return $installedMstsc
    }
    catch {
        Log "Khong the cai dat mstsc.exe: $($_.Exception.Message)" "Red"
        return $null
    }
    finally {
        if (Test-Path -LiteralPath $installerPath) {
            Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Main
Log "=== CLAUDFLARE RDP CONNECTOR ===" "Cyan"
Log "Kiem tra moi truong..." "Gray"

$cfPath = Get-CloudflaredPath
if (-not $cfPath) {
    Log "Khong tim thay tool. Cai dat..." "Yellow"
    $cfPath = Install-Cloudflared
    if (-not $cfPath) { 
        Log "That bai." "Red"
        exit 1 
    }
}
Log "San sang ket noi den server." "Green"
Write-Host ""

# Menu
do {
    Write-Host "1. Nhap Host"
    Write-Host "2. Nhap full URL"
    Write-Host "0. Thoat"
    $choice = Read-Host "Lua chon"
    if ($choice -match '^[0-2]$') { break }
    Log "Chi nhap 0, 1 hoac 2 thoi" "Red"
} while ($true)

if ($choice -eq '0') { exit }

# Host input
if ($choice -eq '1') {
    do {
        $short = Read-Host "Nhap Host (vd: abc)"
        if ([string]::IsNullOrWhiteSpace($short)) {
            Log "Host khong duoc de trong" "Red"
        }
    } while ([string]::IsNullOrWhiteSpace($short))

    $hostname = "$short.tangtuanlab.io.vn"
} else {
    do {
        $hostname = Read-Host "Nhap full URL (vd: hehehe123.abc.com.vn)"
        if ([string]::IsNullOrWhiteSpace($hostname)) {
            Log "URL khong duoc de trong" "Red"
        }
    } while ([string]::IsNullOrWhiteSpace($hostname))
}

# Port input
$portInput = Read-Host "Port (mac dinh 3390)"
$port = if ($portInput -match '^\d+$') { [int]$portInput } else { 3390 }

Log "Tunnel: $hostname : $port" "Cyan"

# Check port
if (Test-PortInUse -Port $port) {
    Log "Port $port bi chiem! Chon port khac..." "Red"
    do {
        $newPort = Read-Host "Port moi"
        if ($newPort -match '^\d+$') {
            $port = [int]$newPort
            if (-not (Test-PortInUse -Port $port)) { break }
        }
        Log "Port $port van bi chiem. Thu lai..." "Red"
    } while ($true)
}

Log "Mo tunnel..." "Green"

# FIX: Start cloudflared as background job
# Dung Start-Process don gian voi -PassThru
$cfProcess = Start-Process -FilePath $cfPath `
    -ArgumentList "access", "rdp", "--hostname", $hostname, "--url", "rdp://localhost:$port" `
    -PassThru `
    -NoNewWindow

if (-not $cfProcess) {
    Log "Khong the khoi dong cloudflared!" "Red"
    exit 1
}

# Wait a moment for tunnel to establish
Start-Sleep -Seconds 2

# Check if process is still running
if ($cfProcess.HasExited) {
    Log "Cloudflared da thoat co loi!" "Red"
    exit 1
}

Log "Da mo tunnel thanh cong! (PID: $($cfProcess.Id))" "Green"

# Thong bao
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "DA SAN SANG KET NOI!" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Computer: localhost:$port" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Remote Desktop dang mo..." -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  LUU Y: KHONG TAT CUA SO NAY TRONG KHI REMOTE!" -ForegroundColor Red
Write-Host "  ---> Tool create by TangTuanLab <----" -ForegroundColor Gray
Write-Host ""

# Kiem tra mstsc.exe co ton tai khong
$mstscPath = Get-MstscPath
$hasMstsc = -not [string]::IsNullOrWhiteSpace($mstscPath)

if ($hasMstsc) {
    # Co mstsc.exe -> chay nhu binh thuong
    Log "Mo Remote Desktop Connection..." "Gray"
    $mstscProcess = Start-Process -FilePath $mstscPath -PassThru

    # Khong hoi Enter; cho den khi user dong Remote Desktop thi moi tat tunnel
    if ($mstscProcess) {
        Wait-Process -Id $mstscProcess.Id
    }
}
else {
    # Khong co mstsc.exe -> cho phep cai lai ban desktop co san cua Windows.
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "KHONG TIM THAY REMOTE DESKTOP CONNECTION (mstsc.exe)" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Tunnel dang chay o: localhost:$port" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Chon mot lua chon:" -ForegroundColor White
    Write-Host "  1. Giu tunnel chay de ket noi bang RDP client khac" -ForegroundColor Green
    Write-Host "  2. Tai va cai lai mstsc.exe desktop chinh chu tu Microsoft" -ForegroundColor Green
    Write-Host ""

    do {
        $choice = Read-Host "Lua chon (1 hoac 2)"
        if ($choice -eq '1') {
            Write-Host ""
            Write-Host "Dang giu tunnel... Bam Ctrl+C de dung." -ForegroundColor Yellow
            Write-Host "Computer: localhost:$port" -ForegroundColor Cyan
            Write-Host ""
            try {
                while (-not $cfProcess.HasExited) {
                    Start-Sleep -Seconds 1
                }
            }
            catch {
                # Nguoi dung bam Ctrl+C.
            }
            break
        }
        elseif ($choice -eq '2') {
            Write-Host ""
            $mstscPath = Install-Mstsc

            if ($mstscPath) {
                Log "Dang mo Remote Desktop Connection..." "Green"
                try {
                    $mstscProcess = Start-Process -FilePath $mstscPath -PassThru
                    if ($mstscProcess) {
                        Wait-Process -Id $mstscProcess.Id -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    Log "Khong the mo mstsc.exe: $($_.Exception.Message)" "Red"
                }
            }
            else {
                Write-Host ""
                Log "Khong cai duoc mstsc.exe. Tunnel van se duoc giu de ban khong mat ket noi." "Yellow"
                Write-Host "Bam Ctrl+C de dung tunnel khi khong can nua." -ForegroundColor Yellow
                try {
                    while (-not $cfProcess.HasExited) {
                        Start-Sleep -Seconds 1
                    }
                }
                catch {
                    # Nguoi dung bam Ctrl+C.
                }
            }
            break
        }
        else {
            Write-Host "Chi nhap 1 hoac 2 thoi!" -ForegroundColor Red
        }
    } while ($true)
}

Log "Dang dong tunnel (PID: $($cfProcess.Id))..." "Yellow"
if (-not $cfProcess.HasExited) {
    Stop-Process -Id $cfProcess.Id -Force
}
Log "Da dong." "Green"
