# ===========================================
# AutoOptimizeVHD_prod.ps1
# 生产就绪版：静默、可由计划任务以 SYSTEM 运行的 VHDX 压缩脚本
# 要点：
# - 不做交互式提权（应通过计划任务/服务以 SYSTEM 或管理员运行）
# - 文件日志 + 可选事件日志（在有权限时）
# - 简单互斥锁，避免并发运行
# - 跳过被占用的 VHD 文件，记录原因
# ===========================================

## ----- 配置 -----
$VHDXPathList = @(
    "C:\Volumes\drive_e.vhdx"
)

# 日志与互斥文件位置（ProgramData 可由 SYSTEM 写入）
$LogFile = "C:\ProgramData\Scripts\Log\AutoOptimizeVHD.log"
$LockFile = "C:\ProgramData\Scripts\LockFile\AutoOptimizeVHD.lock"

# 压缩模式（Full / Quick，依据 Optimize-VHD 支持）
$OptimizeMode = 'Full'

# 测试模式：如果为 $true，只记录操作但不执行 Optimize-VHD
$DryRun = $false

## ----- 工具函数 -----
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO'
    )

    $ts = (Get-Date).ToString('u')
    $line = "[$ts] [$Level] $Message"

    try {
        $dir = Split-Path $LogFile -Parent
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        Add-Content -Path $LogFile -Value $line -ErrorAction Stop
    }
    catch {
        # 如果写文件失败，降级为写主机（应尽量量避免出现）
        Write-Host $line
    }

    # 当以管理员/ SYSTEM 运行时，尝试写 Event Log（如果 source 可用）
    if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
        try {
            $source = 'AutoOptimizeVHD'
            if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
                New-EventLog -LogName Application -Source $source -ErrorAction SilentlyContinue
            }
            switch ($Level) {
                'INFO'  { Write-EventLog -LogName Application -Source $source -EntryType Information -EventId 2000 -Message $Message -ErrorAction SilentlyContinue }
                'WARN'  { Write-EventLog -LogName Application -Source $source -EntryType Warning -EventId 2001 -Message $Message -ErrorAction SilentlyContinue }
                'ERROR' { Write-EventLog -LogName Application -Source $source -EntryType Error -EventId 2002 -Message $Message -ErrorAction SilentlyContinue }
            }
        }
        catch {
            # 忽略事件写入失败
        }
    }
}

## ----- 主流程 -----

# 要求：脚本设计为由计划任务以 SYSTEM 或管理员运行。
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
if (-not $isAdmin) {
    Write-Log "The script is not running with administrator privileges; please run this script via Task Scheduler as SYSTEM/administrator. Exiting." 'WARN'
    exit 2
}

# 简单互斥：检查并写入 lock 文件（包含 PID），避免并发运行
try {
    if (Test-Path $LockFile) {
        $existingPid = Get-Content $LockFile -ErrorAction SilentlyContinue
        if ($existingPid) {
            try { $proc = Get-Process -Id [int]$existingPid -ErrorAction SilentlyContinue } catch { $proc = $null }
            if ($proc) {
                Write-Log "A script instance is already running (PID $existingPid), exiting to avoid conflicts." 'WARN'
                exit 3
            }
            else {
                # 残留 lock 文件，移除后继续
                Remove-Item $LockFile -ErrorAction SilentlyContinue
            }
        }
        else {
            Remove-Item $LockFile -ErrorAction SilentlyContinue
        }
    }
    "$PID" | Out-File -FilePath $LockFile -Encoding ascii -Force
}
catch {
    Write-Log -Message ("Failed to create mutex mutex mutex lock file $LockFile : $($_.Exception.Message)") -Level 'ERROR'
    exit 4
}

try {
    # 检查 Hyper-V 模块
    if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
        Write-Log "Hyper-V PowerShell module is unavailable, skipping all optimization operations." 'WARN'
        exit 0
    }
    Import-Module Hyper-V -ErrorAction Stop

    foreach ($vhd in $VHDXPathList) {
        if (-not (Test-Path $vhd)) {
            Write-Log "VHD file does not exist, skipping: $vhd" 'WARN'
            continue
        }

        # 检查文件是否被锁定（如果能以 ReadWrite 打开则认为未被占用）
        $inUse = $false
        try {
            $fs = [System.IO.File]::Open($vhd, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $fs.Close()
        }
        catch {
            $inUse = $true
        }

        if ($inUse) {
            Write-Log "VHD file is in use or locked, skipping: $vhd" 'WARN'
            continue
        }

        if ($DryRun) {
            Write-Log "DRYRUN: Will optimize (mode=$OptimizeMode) $vhd" 'INFO'
            continue
        }

        $wasAttached = (Get-VHD -Path $vhd).Attached

        try {
            Write-Log "Starting optimization: $vhd (mode=$OptimizeMode)" 'INFO'

            if ($wasAttached) {
                Dismount-VHD -Path $vhd
            }

            Optimize-VHD -Path $vhd -Mode $OptimizeMode -ErrorAction Stop
            Write-Log "Optimization completed: $vhd" 'INFO'

            if ($wasAttached) {
                Mount-VHD -Path $vhd
            }
        }
        catch {
            Write-Log "Optimization failed: $vhd — $($_.Exception.Message)" 'ERROR'
            # 继续处理其他 VHD
        }
    }
}
catch {
    Write-Log "An unhandled exception occurred during script execution: $($_.Exception.Message)" 'ERROR'
}
finally {
    # 清理互斥锁
    try { Remove-Item $LockFile -ErrorAction SilentlyContinue } catch {}
}

exit 0
