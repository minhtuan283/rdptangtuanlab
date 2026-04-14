#Requires -Version 5.1
# Agent SSH Quick Connect - Cloudflare Tunnel
$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Mark6 SSH Connector"

function Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

function Test-PortInUse {
    param([int]$Port)
    try {
        $netstat = netstat -ano | Select-String ":$Port\s" | Select-String "LISTENING"
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
        "${env:LOCALAPPDATA}\cloudflared\cloudflared.exe"
    )
    foreach ($loc in $locations) {
        if (Test-Path $loc) { 
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
    Log "Dang tai cloudflared..." "Yellow"
    $systemExe = "$env:SystemRoot\System32\cloudflared.exe"
    $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    
    try {
        $tempExe = "${env:TEMP}\cloudflared_temp.exe"
        if (Test-Path $tempExe) { Remove-Item $tempExe -Force }
        
        Invoke-WebRequest -Uri $url -OutFile $tempExe -UseBasicParsing
        
        if (-not (Test-Path $tempExe)) {
            throw "Download failed"
        }
        
        $fileSize = (Get-Item $tempExe).Length
        Log "Da tai: $([math]::Round($fileSize/1MB, 2)) MB" "Green"
        
        Copy-Item $tempExe $systemExe -Force
        Remove-Item $tempExe -Force
        Log "Cai dat thanh cong: $systemExe" "Green"
        return $systemExe
    }
    catch {
        Log "Loi: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Install-SSHServer {
    Log "Kiem tra SSH Server..." "Yellow"
    
    # Kiem tra da cai chua
    $sshService = Get-Service sshd -ErrorAction SilentlyContinue
    
    if ($sshService) {
        if ($sshService.Status -eq "Running") {
            Log "SSH Server dang chay" "Green"
            return $true
        } else {
            Log "SSH Server da cai nhung chua chay. Dang bat..." "Yellow"
            try {
                Start-Service sshd
                Set-Service -Name sshd -StartupType 'Automatic'
                Log "Da bat SSH Server" "Green"
                return $true
            }
            catch {
                Log "Loi khi bat SSH Server: $($_.Exception.Message)" "Red"
                return $false
            }
        }
    }
    
    # Chua cai dat, tien hanh cai
    Log "SSH Server chua duoc cai dat. Dang cai dat..." "Yellow"
    
    try {
        $capability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
        
        if ($capability.State -eq "Installed") {
            Log "OpenSSH Server da cai nhung service chua chay" "Yellow"
            Start-Service sshd
            Set-Service -Name sshd -StartupType 'Automatic'
            Log "Da bat SSH Server" "Green"
            return $true
        }
        
        Log "Dang tai va cai dat OpenSSH Server (co the mat 1-2 phut)..." "Yellow"
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
        
        Log "Dang cau hinh SSH Server..." "Yellow"
        Start-Service sshd
        Set-Service -Name sshd -StartupType 'Automatic'
        
        # Cau hinh Firewall
        $firewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
        if (-not $firewallRule) {
            New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
            Log "Da cau hinh Firewall" "Green"
        }
        
        Log "Cai dat SSH Server thanh cong!" "Green"
        return $true
    }
    catch {
        Log "Loi khi cai dat SSH Server: $($_.Exception.Message)" "Red"
        Log "Vui long cai dat thu cong hoac kiem tra ket noi internet" "Yellow"
        return $false
    }
}

function Setup-SSHConfig {
    param([string]$Hostname)
    
    $sshDir = "$env:USERPROFILE\.ssh"
    $configFile = "$sshDir\config"
    
    # Tao thu muc .ssh neu chua co
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        Log "Da tao thu muc .ssh" "Green"
    }
    
    # Kiem tra xem host da co trong config chua
    $hostExists = $false
    if (Test-Path $configFile) {
        $content = Get-Content $configFile -Raw
        if ($content -match "Host\s+$([regex]::Escape($Hostname))") {
            $hostExists = $true
            Log "Host $Hostname da co trong config" "Yellow"
        }
    }
    
    # Them host vao config neu chua co
    if (-not $hostExists) {
        $configEntry = @"

Host $Hostname
  ProxyCommand C:\Windows\system32\cloudflared.exe access ssh --hostname %h
"@
        Add-Content -Path $configFile -Value $configEntry -Encoding ASCII
        Log "Da them $Hostname vao SSH config" "Green"
    }
    
    # Fix permission
    try {
        icacls $sshDir /reset | Out-Null
        icacls $sshDir /inheritance:r | Out-Null
        icacls $sshDir /grant:r "${env:USERNAME}:RX" | Out-Null
        
        if (Test-Path $configFile) {
            icacls $configFile /reset | Out-Null
            icacls $configFile /inheritance:r | Out-Null
            icacls $configFile /grant:r "${env:USERNAME}:R" | Out-Null
        }
        Log "Da fix permission cho .ssh" "Green"
    }
    catch {
        Log "Canh bao: Khong the fix permission" "Yellow"
    }
}

# Main
Clear-Host
Log "=== AGENT SSH CONNECTOR ===" "Cyan"
Log "Kiem tra moi truong..." "Gray"

# Kiem tra cloudflared
$cfPath = Get-CloudflaredPath
if (-not $cfPath) {
    Log "Khong tim thay cloudflared. Dang cai dat..." "Yellow"
    $cfPath = Install-Cloudflared
    if (-not $cfPath) { 
        Log "Cai dat that bai!" "Red"
        Read-Host "Nhan Enter de thoat"
        exit 1 
    }
}
Log "Cloudflared: $cfPath" "Green"
Write-Host ""

# Kiem tra/cai dat SSH Server
$sshReady = Install-SSHServer
if (-not $sshReady) {
    Log "Khong the tiep tuc vi SSH Server chua san sang." "Red"
    Read-Host "Nhan Enter de thoat"
    exit 1
}
Write-Host ""

# Nhap hostname
do {
    $hostname = Read-Host "Nhap host URL"
    if ([string]::IsNullOrWhiteSpace($hostname)) {
        Log "Hostname khong duoc de trong!" "Red"
    }
} while ([string]::IsNullOrWhiteSpace($hostname))

# Setup SSH config
Setup-SSHConfig -Hostname $hostname

# Nhap port
do {
    $portInput = Read-Host "Nhap port reverse (mac dinh 2222)"
    if ([string]::IsNullOrWhiteSpace($portInput)) {
        $port = 2222
        break
    }
    if ($portInput -match '^\d+$') {
        $port = [int]$portInput
        break
    }
    Log "Port khong hop le! Nhap lai..." "Red"
} while ($true)

# Kiem tra port co bi chiem khong
if (Test-PortInUse -Port $port) {
    Log "Port $port dang bi chiem!" "Red"
    do {
        $newPort = Read-Host "Nhap port khac"
        if ($newPort -match '^\d+$') {
            $testPort = [int]$newPort
            if (-not (Test-PortInUse -Port $testPort)) {
                $port = $testPort
                break
            }
        }
        Log "Port $testPort van bi chiem. Thu lai..." "Red"
    } while ($true)
}

Log "Port reverse: $port" "Green"

# Nhap username
do {
    $username = Read-Host "Nhap username SSH"
    if ([string]::IsNullOrWhiteSpace($username)) {
        Log "Username khong duoc de trong!" "Red"
    }
} while ([string]::IsNullOrWhiteSpace($username))

# Thong bao
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "THONG TIN KET NOI:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Host    : $hostname" -ForegroundColor Yellow
Write-Host "  User    : $username" -ForegroundColor Yellow
Write-Host "  Port    : $port (reverse tunnel)" -ForegroundColor Yellow
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Log "Dang ket noi SSH..." "Green"
Write-Host ""

# Chay SSH voi reverse tunnel
$sshCommand = "ssh -R ${port}:localhost:22 ${username}@${hostname}"
Log "Lenh: $sshCommand" "Gray"
Write-Host ""

# Thuc thi SSH
Invoke-Expression $sshCommand

# Sau khi SSH ket thuc
Write-Host ""
Log "Da ngat ket noi." "Yellow"
Read-Host "Nhan Enter de thoat"
