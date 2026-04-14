#Requires -Version 5.1
# Mark6 SSH Quick Connect - Cloudflare Tunnel
$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "AGENT SSH Connector"

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
    
    # Tai va cai tu GitHub Win32-OpenSSH
    Log "SSH Server chua duoc cai dat. Tai OpenSSH tu GitHub..." "Yellow"
    
    $tempZip = "${env:TEMP}\OpenSSH-Win64.zip"
    $installDir = "${env:ProgramFiles}\OpenSSH"
    $url = "https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip"
    
    try {
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
        if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue }
        
        Log "Dang tai OpenSSH-Win64.zip..." "Yellow"
        Invoke-WebRequest -Uri $url -OutFile $tempZip -UseBasicParsing -TimeoutSec 120
        if (-not (Test-Path $tempZip)) {
            throw "Download failed"
        }
        $fileSize = (Get-Item $tempZip).Length
        Log "Da tai: $([math]::Round($fileSize/1MB, 2)) MB" "Green"
        
        Log "Dang giai nen..." "Yellow"
        Expand-Archive -Path $tempZip -DestinationPath $installDir -Force
        
        $sshdExe = "$installDir\sshd.exe"
        $altSshdExe = "$installDir\OpenSSH-Win64\sshd.exe"
        
        if (-not (Test-Path $sshdExe) -and (Test-Path $altSshdExe)) {
            Copy-Item "$installDir\OpenSSH-Win64\*" "$installDir\" -Recurse -Force
            Remove-Item "$installDir\OpenSSH-Win64" -Recurse -Force
            Log "Da chuyen noi dung thu muc con" "Green"
        }
        
        if (-not (Test-Path $sshdExe)) {
            throw "Giai nen that bai - khong tim thay sshd.exe"
        }
        Log "Giai nen thanh cong" "Green"
        
        Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        Log "Da xoa file zip" "Green"
        
        Log "Dang cai dat SSH Server..." "Yellow"
        
        $installScript = "$installDir\install-sshd.ps1"
        if (Test-Path $installScript) {
            & $installScript
        }
        
        Start-Service sshd -ErrorAction SilentlyContinue
        Set-Service -Name sshd -StartupType 'Automatic'
        
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
        return $false
    }
}

function Setup-SSHConfig {
    param([string]$Hostname)
    
    $sshDir = "$env:USERPROFILE\.ssh"
    $configFile = "$sshDir\config"
    
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        Log "Da tao thu muc .ssh" "Green"
    }
    
    $hostExists = $false
    if (Test-Path $configFile) {
        $content = Get-Content $configFile -Raw
        if ($content -match "Host\s+$([regex]::Escape($Hostname))") {
            $hostExists = $true
            Log "Host $Hostname da co trong config" "Yellow"
        }
    }
    
    if (-not $hostExists) {
        $configEntry = @"

Host $Hostname
  ProxyCommand C:\Windows\system32\cloudflared.exe access ssh --hostname %h
"@
        Add-Content -Path $configFile -Value $configEntry -Encoding ASCII
        Log "Da them $Hostname vao SSH config" "Green"
    }
}

# ==================== MAIN ====================

try {
    # Cleanup function
    function Stop-SSHServer-Local {
        $sshService = Get-Service sshd -ErrorAction SilentlyContinue
        if ($sshService -and $sshService.Status -eq "Running") {
            Log "Dang tat SSH Server..." "Yellow"
            Stop-Service sshd -ErrorAction SilentlyContinue
            Log "Da tat SSH Server" "Green"
        }
    }
    
    # Catch Ctrl+C
    $script:isExiting = $false
    
    # Main
    Clear-Host
    Log "=== AGENT AI SSH CONNECTOR ===" "Cyan"
    Log "Khi tat cua so nay, SSH Server se tu dong tat." "Gray"
    Write-Host ""
    
    # Kiem tra cloudflared
    $cfPath = Get-CloudflaredPath
    if (-not $cfPath) {
        Log "Khong tim thay cloudflared. Dang cai dat..." "Yellow"
        $cfPath = Install-Cloudflared
        if (-not $cfPath) { 
            Log "Cai dat that bai!" "Red"
            exit 1 
        }
    }
    Log "Cloudflared: $cfPath" "Green"
    Write-Host ""
    
    # Kiem tra SSH Server
    $sshReady = Install-SSHServer
    if (-not $sshReady) {
        Log "Khong the tiep tuc vi SSH Server chua san sang." "Red"
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
    
    # Kiem tra port local co bi chiem khong
    if (Test-PortInUse -Port $port) {
        Log "Port $port tren may nay dang bi chiem!" "Red"
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
    
    # Kiem tra host
    try {
        $dns = [System.Net.Dns]::GetHostAddresses($hostname)
        if ($dns.Count -gt 0) {
            Log "DNS resolved: $($dns[0].ToString())" "Green"
        }
    } catch {
        Log "WARN: Khong the phan giai DNS" "Yellow"
    }
    Write-Host ""
    
    Log "Dang ket noi SSH..." "Green"
    Log "Lenh: ssh -R ${port}:localhost:22 ${username}@${hostname}" "Gray"
    Log "Neu port da bi chiem tren server, lenh se that bai ngay." "Gray"
    Write-Host ""
    
    # Chay SSH voi reverse tunnel + ExitOnForwardFailure
    $sshCommand = "ssh -o ExitOnForwardFailure=yes -R ${port}:localhost:22 ${username}@${hostname}"
    Invoke-Expression $sshCommand
    
    # Neu SSH ngat (Ctrl+C hoac loi)
    $script:isExiting = $true
    
} finally {
    # Luon chay khi script ket thuc (Ctrl+C, tat window, loi...)
    Write-Host ""
    Log "Dang cleanup..." "Yellow"
    
    # Tat SSH Server
    $sshService = Get-Service sshd -ErrorAction SilentlyContinue
    if ($sshService -and $sshService.Status -eq "Running") {
        Stop-Service sshd -ErrorAction SilentlyContinue
        Log "Da tat SSH Server" "Green"
    }
    
    # Xoa SSH config
    $configFile = "$env:USERPROFILE\.ssh\config"
    if (Test-Path $configFile) {
        Remove-Item $configFile -Force -ErrorAction SilentlyContinue
        Log "Da xoa SSH config" "Green"
    }
    
    Log "Cleanup hoan tat" "Green"
}
