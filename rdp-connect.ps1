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
$mstscPath = "$env:SystemRoot\System32\mstsc.exe"
$hasMstsc = Test-Path $mstscPath

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
    # Khong co mstsc.exe -> hien 2 lua chon
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "KHONG TIM THAY REMOTE DESKTOP CONNECTION (mstsc.exe)" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Tunnel dang chay o: localhost:$port" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Chon mot lua chon:" -ForegroundColor White
    Write-Host "  1. Giu ket noi voi port $port (giu lien ket den khi ban tat cua so nay hoac bam Ctrl+C)" -ForegroundColor Green
    Write-Host "  2. Khoi phuc Remote Desktop Connection mac dinh cua Windows (can Administrator)" -ForegroundColor Green
    Write-Host ""

    do {
        $choice = Read-Host "Lua chon (1 hoac 2)"
        if ($choice -eq '1') {
            Write-Host ""
            Write-Host "Dang giu ket noi... Bam Ctrl+C de dung." -ForegroundColor Yellow
            Write-Host "Computer: localhost:$port" -ForegroundColor Cyan
            Write-Host ""

            # Giu ket noi cho den khi user tat
            try {
                while (-not $cfProcess.HasExited) {
                    Start-Sleep -Seconds 1
                }
            }
            catch {
                # User bam Ctrl+C
            }
            break
        }
        elseif ($choice -eq '2') {
            Write-Host ""
            Log "Dang khoi phuc Remote Desktop Connection (mstsc.exe) cua Windows..." "Yellow"

            # Kiem tra quyen quan tri truoc khi chay DISM.
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $isAdmin) {
                Log "Can chay lai script bang Run as administrator de khoi phuc mstsc.exe." "Red"
                Read-Host "Bam Enter de dong tunnel"
                break
            }

            try {
                Log "Dang bat Windows feature: Microsoft-RemoteDesktopConnection..." "Gray"
                DISM.exe /Online /Enable-Feature /FeatureName:Microsoft-RemoteDesktopConnection /All
                if ($LASTEXITCODE -ne 0) {
                    throw "DISM that bai voi ma loi $LASTEXITCODE"
                }

                if (Test-Path $mstscPath) {
                    Log "Da khoi phuc mstsc.exe. Dang mo ket noi..." "Green"
                    $mstscProcess = Start-Process -FilePath $mstscPath -ArgumentList "/v:localhost:$port" -PassThru
                    if ($mstscProcess) {
                        Wait-Process -Id $mstscProcess.Id
                    }
                }
                else {
                    Log "Feature da bat nhung mstsc.exe van bi thieu. Can sua file he thong." "Red"
                    Log "Chay Command Prompt bang quyen Administrator, sau do chay lan luot:" "Yellow"
                    Log "DISM.exe /Online /Cleanup-Image /RestoreHealth" "Cyan"
                    Log "sfc /scannow" "Cyan"
                    Log "Sau do khoi dong lai Windows va chay lai script." "Yellow"
                    Read-Host "Bam Enter de dong tunnel"
                }
            }
            catch {
                Log "Loi khi khoi phuc: $($_.Exception.Message)" "Red"
                Read-Host "Bam Enter de dong tunnel"
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
