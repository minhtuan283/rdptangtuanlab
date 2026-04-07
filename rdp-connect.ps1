#Requires -Version 5.1
# Claudflare RDP Quick Connect
# Run with: irm https://bit.ly/rdptangtuanlab | iex

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Claudflare RDP Connector"

function Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

function Test-PortInUse {
    param([int]$Port)
    try {
        $connections = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | 
                       Where-Object LocalPort -eq $Port
        return $connections.Count -gt 0
    }
    catch {
        return $false
    }
}

# ============================================================
# 1. KIEM TRA VA CAI CLOUDFLARED
# ============================================================
Log "Dang kiem tra cloudflared..." "Cyan"

if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
    Log "Chua cai cloudflared. Dang cai dat tu dong..." "Yellow"
    try {
        winget install --id Cloudflare.cloudflared -e `
            --accept-source-agreements `
            --accept-package-agreements `
            --silent | Out-Null
        Log "Cai dat cloudflared thanh cong" "Green"
    }
    catch {
        Log "Cai dat that bai. Vui long cai thu cong: winget install Cloudflare.cloudflared" "Red"
        pause
        exit
    }
}
else {
    Log "Cloudflared da duoc cai dat" "Green"
}

Write-Host ""

# ============================================================
# 2. MENU CHINH
# ============================================================
Log "=== CLAUDFLARE RDP CONNECTOR ===" "Cyan"
Write-Host ""
Write-Host "1. Nhap host ngan (abc -> abc.tangtuanlab.io.vn)"
Write-Host "2. Nhap host day du (hehehe123.abc.com.vn)"
Write-Host "0. Thoat"
Write-Host ""

$choice = Read-Host "Nhap lua chon (1/2/0)"

if ($choice -eq '0') {
    Log "Da thoat" "Yellow"
    exit
}

# ============================================================
# 3. LAY HOSTNAME VA PORT
# ============================================================
$hostname = ""
$port = 3390

if ($choice -eq '1') {
    $shortHost = Read-Host "Nhap host ngan (vi du: abc)"
    if ([string]::IsNullOrWhiteSpace($shortHost)) { $shortHost = "default" }
    $hostname = "$shortHost.tangtuanlab.io.vn"
    Log "Hostname: $hostname" "Cyan"
}
else {
    $fullHost = Read-Host "Nhap host day du (vi du: hehehe123.abc.com.vn)"
    if ([string]::IsNullOrWhiteSpace($fullHost)) { $fullHost = "default.tangtuanlab.io.vn" }
    $hostname = $fullHost
    Log "Hostname: $hostname" "Cyan"
}

$portInput = Read-Host "Nhap port (mac dinh 3390, Enter de dung mac dinh)"
if (-not [string]::IsNullOrWhiteSpace($portInput)) {
    $port = [int]$portInput
}

Log "Port: $port" "Cyan"
Write-Host ""

# ============================================================
# 4. KIEM TRA PORT CO BI CHIEU KHONG
# ============================================================
if (Test-PortInUse -Port $port) {
    Log "Port $port dang bi chiem. Vui long chon port khac." "Red"
    do {
        $newPort = Read-Host "Nhap port moi (3390-4000)"
        if ($newPort -match '^\d+$') {
            $port = [int]$newPort
            if (-not (Test-PortInUse -Port $port)) {
                Log "Port $port da san sang" "Green"
                break
            }
            else {
                Log "Port $port van bi chiem" "Yellow"
            }
        }
    } while ($true)
}

# ============================================================
# 5. CHAY TUNNEL
# ============================================================
Log "Dang mo Cloudflare Tunnel cho $hostname :$port ..." "Green"
Log "Lenh dang chay: cloudflared access rdp --hostname $hostname --url rdp://localhost:$port" "Gray"

$command = "cloudflared access rdp --hostname `"$hostname`" --url rdp://localhost:$port"

try {
    Start-Process -FilePath "cloudflared" -ArgumentList "access rdp --hostname `"$hostname`" --url rdp://localhost:$port" -NoNewWindow -PassThru | Out-Null
    Log "Tunnel da duoc khoi dong" "Green"
}
catch {
    Log "Khong the khoi dong tunnel: $($_.Exception.Message)" "Red"
    Log "Thu chay thu cong: $command" "Yellow"
    pause
    exit
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "HDSG nhap vao Computer: localhost:$port de ket noi" -ForegroundColor Green
Write-Host "KHONG TAT CUA SO NAY TRONG KHI DANG REMOTE" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

# Mo Remote Desktop
Log "Dang mo Remote Desktop Connection..." "Cyan"
Start-Process "mstsc.exe" -ArgumentList "/v:localhost:$port"

Log "Hoan tat. Ban co the dong cua so nay sau khi da ket noi thanh cong." "Green"
Write-Host ""
pause
