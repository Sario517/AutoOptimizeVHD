# AutoOptimizeVHD 使用说明

简要说明如何将 `AutoOptimizeVHD.ps1` 作为计划任务/系统任务在 Windows 上无交互运行：

1) 将脚本复制到一个稳定位置，例如：

    `C:\ProgramData\Scripts\AutoOptimizeVHD.ps1`

2) 在 Administrator / PowerShell 窗口中创建计划任务（示例：开机运行，以 SYSTEM 身份，最高权限）：

    ```powershell
    schtasks /Create /TN "AutoOptimizeVHD" /TR "PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\Scripts\AutoOptimizeVHD.ps1" /SC ONSTART /RU "SYSTEM" /RL HIGHEST
    ```

    说明：

    - `/SC ONSTART` 表示在系统启动时运行。你也可以用 `/SC DAILY` 或自定义时间。
    - `/RU "SYSTEM"` 会以 SYSTEM 身份运行，避免 UAC 提示。

3) 测试运行（在命令行中以管理员权限执行一次，观察日志）：

    ```powershell
    PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\Scripts\AutoOptimizeVHD.ps1
    ```

    然后检查日志文件（默认）：

    `C:\ProgramData\Scripts\Log\AutoOptimizeVHD.log`

4) 注意事项与建议：
    - 本脚本假设目标主机上存在 Hyper-V PowerShell 模块（Optimize-VHD）。
    - 脚本不会自动提升权限；在计划任务中请设置为 SYSTEM 或管理员。不要在交互式桌面会话中依赖脚本进行提权。
    - 如果需要对多个 VHD 做更复杂的条件判断（例如仅对某些已下线的虚拟机磁盘操作），应在调用前先做好该逻辑或扩展脚本。

## 配置修改说明

### `$VHDXPathList`

设置 VHD / VHDX 文件的路径，注意需要双引号包裹；支持添加多个路径，以逗号分隔。

### `$OptimizeMode` ( Full / Quick )

 • Full: 彻底回收空闲块（慢但最彻底）；

 • Quick: 仅回收部分未分配空间（快但效果一般）。

### 日志与互斥锁文件位置

建议保存在 ProgramData 目录下，所有用户可读写，系统任务运行时权限无问题。

 • `$LogFile`: 日志文件保存的路径。

 • `$LockFile`: 互斥锁文件的路径。

### `$DryRun` ( $ture / $false )

测试模式：如果为 $true，只记录操作但不执行 Optimize-VHD。
