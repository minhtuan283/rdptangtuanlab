#Requires -Version 5.1
# Mark6 SSH Quick Connect - Cloudflare Tunnel
$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Agent SSH Connector"

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
    
    # Chua cai dat, tai va cai tu GitHub Win32-OpenSSH
    Log "SSH Server chua duoc cai dat. Tai OpenSSH tu GitHub..." "Yellow"
    
    $tempZip = "${env:TEMP}\OpenSSH-Win64.zip"
    $installDir = "${env:ProgramFiles}\OpenSSH"
    $url = "https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip"
    
    try {
        # Xoa file cu va thu muc cu neu co
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
        if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue }
        
        # Tai file
        Log "Dang tai OpenSSH-Win64.zip..." "Yellow"
        Invoke-WebRequest -Uri $url -OutFile $tempZip -UseBasicParsing -TimeoutSec 120
        if (-not (Test-Path $tempZip)) {
            throw "Download failed"
        }
        $fileSize = (Get-Item $tempZip).Length
        Log "Da tai: $([math]::Round($fileSize/1MB, 2)) MB" "Green"
        
        # Giai nen
        Log "Dang giai nen..." "Yellow"
        Expand-Archive -Path $tempZip -DestinationPath $installDir -Force
        
        # Kiem tra - file co the nam trong thu muc con
        $sshdExe = "$installDir\sshd.exe"
        $altSshdExe = "$installDir\OpenSSH-Win64\sshd.exe"
        
        # Neu sshd.exe khong o thu muc goc, kiem tra thu muc con
        if (-not (Test-Path $sshdExe) -and (Test-Path $altSshdExe)) {
            # Copy noi dung tu thu muc con ra ngoai
            Copy-Item "$installDir\OpenSSH-Win64\*" "$installDir\" -Recurse -Force
            Remove-Item "$installDir\OpenSSH-Win64" -Recurse -Force
            Log "Da chuyen noi dung thu muc con" "Green"
        }
        
        $sshdExe = "$installDir\sshd.exe"
        if (-not (Test-Path $sshdExe)) {
            throw "Giai nen that bai - khong tim thay sshd.exe"
        }
        Log "Giai nen thanh cong" "Green"
        
        # Xoa file zip
        Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        Log "Da xoa file zip" "Green"
        
        # Cai dat SSH Server
        Log "Dang cai dat SSH Server..." "Yellow"
        
        # Chay install script
        $installScript = "$installDir\install-sshd.ps1"
        if (Test-Path $installScript) {
            & $installScript
        }
        
        # Bat service
        Start-Service sshd -ErrorAction SilentlyContinue
        Set-Service -Name sshd -StartupType 'Automatic'
        
        # Cau hinh Firewall
        $firewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
        if (-not $firewallRule) {
            New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
            Log "Da cau hinh Firewall" "Green"
        }
        
        # Xoa thu muc cai dat sau khi xong
        # Comment dong nay neu muon giu lai de lan sau nhanh hon
        # Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
        # Log "Da xoa thu muc cai dat" "Green"
        
        Log "Cai dat SSH Server thanh cong!" "Green"
        return $true
    }
    catch {
        Log "Loi khi cai dat SSH Server: $($_.Exception.Message)" "Red"
        Log "Vui long cai dat thu cong" "Yellow"
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
Log "Kiem tra ket noi..." "Gray"

# Kiem tra host co reachable khong
try {
    $dns = [System.Net.Dns]::GetHostAddresses($hostname)
    if ($dns.Count -gt 0) {
        Log "DNS resolved: $($dns[0].ToString())" "Green"
    }
} catch {
    Log "WARN: Khong the phan giai DNS cua $hostname" "Yellow"
}

# Kiem tra SSH config da co chua
$configFile = "$env:USERPROFILE\.ssh\config"
$configOk = $false
if (Test-Path $configFile) {
    $content = Get-Content $configFile -Raw -ErrorAction SilentlyContinue
    if ($content -and $content -match "Host\s+$([regex]::Escape($hostname))") {
        if ($content -match "ProxyCommand") {
            $configOk = $true
            Log "SSH config OK - ProxyCommand ton tai" "Green"
        }
    }
}

if (-not $configOk) {
    Log "WARN: SSH config chua co ProxyCommand cho $hostname" "Yellow"
    Log "Vui long kiem tra lai Cloudflare Tunnel" "Yellow"
}

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
