<#
.SYNOPSIS
    C 盘垃圾文件扫描脚本 v3（只读扫描，不删除任何文件）
.DESCRIPTION
    扫描 C 盘 60+ 个垃圾聚集点：临时文件、各类缓存、崩溃转储、软件更新残留、
    聊天工具文件、下载目录、清单外大目录自动发现等，并输出三个判断维度：
      体积 / 文件数 / 最近写入时间（用于判断是活跃缓存还是陈年垃圾）
    风险分级：
      低 = 纯缓存/临时文件，删除后自动重建或可重新下载，无个人数据
      中 = 有重建/重下代价（模型/索引/应用数据）或含个人数据，删前逐项确认
      高 = 系统关键文件（卸载/修复/恢复/内存管理），仅列出，请勿手动删除
    结果输出：
      1) 控制台摘要
      2) <输出目录>\C盘垃圾扫描报告_时间戳.html
      3) <输出目录>\C盘垃圾扫描明细_时间戳.csv
    输出目录默认为当前用户桌面。本脚本只读取统计，绝不删除、移动或修改任何文件。
.PARAMETER OutDir
    报告输出目录（默认：桌面）
.PARAMETER NoOpen
    生成报告后不自动用浏览器打开
.EXAMPLE
    双击同目录下的「C盘垃圾扫描-双击运行.bat」即可；或：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\C盘垃圾扫描.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\C盘垃圾扫描.ps1 -OutDir D:\Reports -NoOpen
#>
param(
    [string]$OutDir = '',
    [switch]$NoOpen
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()
$scanTime = Get-Date

# ============ 0. 环境 ============
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = $env:USERPROFILE }
}
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

# 用户目录与各派生路径：优先环境变量，缺失时自行推导（不依赖提权后可能被改写的环境）
$UP = $env:USERPROFILE
if ([string]::IsNullOrWhiteSpace($UP)) { $UP = [Environment]::GetFolderPath('UserProfile') }
if ([string]::IsNullOrWhiteSpace($UP)) { $UP = 'C:\Users\' + $env:USERNAME }
$LA = $env:LOCALAPPDATA
if ([string]::IsNullOrWhiteSpace($LA) -or -not (Test-Path -LiteralPath $LA)) { $LA = Join-Path $UP 'AppData\Local' }
$RA = $env:APPDATA
if ([string]::IsNullOrWhiteSpace($RA) -or -not (Test-Path -LiteralPath $RA)) { $RA = Join-Path $UP 'AppData\Roaming' }
$DOC = [Environment]::GetFolderPath('MyDocuments')
if ([string]::IsNullOrWhiteSpace($DOC) -or -not (Test-Path -LiteralPath $DOC)) { $DOC = Join-Path $UP 'Documents' }

$results = New-Object System.Collections.Generic.List[object]
$script:covered = New-Object System.Collections.Generic.List[string]

# ============ 1. 工具函数 ============
function Add-Covered([string]$p) {
    if ($p) { $script:covered.Add($p) }
}

function Get-DirStats([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $it = Get-Item -LiteralPath $p -Force
    if (-not $it.PSIsContainer) {
        return [pscustomobject]@{ Bytes = [long]$it.Length; Files = 1; LastWrite = $it.LastWriteTime }
    }
    $files = @(Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue)
    $sum = [long](($files | Measure-Object -Property Length -Sum).Sum)
    $lw = ($files | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    return [pscustomobject]@{ Bytes = $sum; Files = $files.Count; LastWrite = $lw }
}

function Add-Row([string]$risk, [string]$name, [string]$path, [long]$bytes, [string]$note, [int]$files = -1, $lastWrite = $null) {
    $results.Add([pscustomobject]@{ Risk = $risk; Name = $name; Path = $path; Bytes = $bytes; Note = $note; Files = $files; LastWrite = $lastWrite })
}

function Test-Covered([string]$p) {
    foreach ($c in $script:covered) {
        if (-not $c) { continue }
        if ($p.StartsWith($c, [StringComparison]::OrdinalIgnoreCase) -or
            $c.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Scan-One([string]$risk, [string]$name, [string]$path, [string]$note) {
    Write-Progress -Id 1 -Activity '正在扫描 C 盘垃圾（只读）' -Status $name
    Add-Covered $path
    $s = Get-DirStats $path
    if ($s) { Add-Row $risk $name $path $s.Bytes $note $s.Files $s.LastWrite }
}

function Scan-Glob([string]$risk, [string]$name, [string]$pattern, [string]$note) {
    # 通配多个目录/文件，体积求和合并为一行（文件数与时间取全部合计/最大值）
    Write-Progress -Id 1 -Activity '正在扫描 C 盘垃圾（只读）' -Status $name
    $sum = [long]0; $cnt = 0; $lw = $null; $hit = $false; $paths = @()
    Get-Item -Path $pattern -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $hit = $true; $paths += $_.FullName; Add-Covered $_.FullName
        if ($_.PSIsContainer) {
            $s = Get-DirStats $_.FullName
            if ($s) { $sum += $s.Bytes; $cnt += $s.Files; if ($s.LastWrite -and (-not $lw -or $s.LastWrite -gt $lw)) { $lw = $s.LastWrite } }
        } else {
            $sum += [long]$_.Length; $cnt += 1
            if ($_.LastWriteTime -and (-not $lw -or $_.LastWriteTime -gt $lw)) { $lw = $_.LastWriteTime }
        }
    }
    if ($hit) { Add-Row $risk $name ($paths -join '  ;  ') $sum $note $cnt $lw }
}

function Scan-PatternDirs([string]$risk, [string]$namePrefix, [string]$parent, [string]$filter, [string]$note) {
    if (-not (Test-Path -LiteralPath $parent)) { return }
    Get-ChildItem -LiteralPath $parent -Directory -Filter $filter -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Progress -Id 1 -Activity '正在扫描 C 盘垃圾（只读）' -Status $_.Name
        Add-Covered $_.FullName
        $s = Get-DirStats $_.FullName
        if ($s) { Add-Row $risk ($namePrefix + ' - ' + $_.Name) $_.FullName $s.Bytes $note $s.Files $s.LastWrite }
    }
}

function MbLabel($bytes) {
    if ($bytes -lt 0) { return '—' }
    if ($bytes -ge 1GB) { return '{0:N2} GB' -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return '{0:N0} MB' -f ($bytes / 1MB) }
    return '{0:N0} KB' -f ($bytes / 1KB)
}

function FmtCount([int]$f) {
    if ($f -lt 0) { return '—' }
    return '{0:N0}' -f $f
}
function FmtDate($d) {
    if ($d) { return $d.ToString('yyyy-MM-dd') }
    return '—'
}
function DaysSince($d) {
    if (-not $d) { return -1 }
    return [int]((Get-Date) - $d).TotalDays
}

function HtmlEsc([string]$s) {
    if ($null -eq $s) { return '' }
    return (($s -replace '&', '&amp;') -replace '<', '&lt;') -replace '>', '&gt;'
}

function Show-Group([string]$risk, [string]$title, [string]$color, [bool]$showSum) {
    $rows = @($results | Where-Object { $_.Risk -eq $risk } | Sort-Object Bytes -Descending)
    if ($rows.Count -eq 0) { return }
    Write-Host ''
    Write-Host $title -ForegroundColor $color
    $sum = [long]0
    foreach ($r in $rows) {
        if ($r.Bytes -ge 0) { $sum += $r.Bytes }
        Write-Host ("  [{0,10}|{1,8} 个文件|最近 {2}] {3}" -f (MbLabel $r.Bytes), (FmtCount $r.Files), (FmtDate $r.LastWrite), $r.Name) -ForegroundColor $color
        Write-Host ("               {0}" -f $r.Path) -ForegroundColor Gray
        if ($r.Note) { Write-Host ("               说明: {0}" -f $r.Note) -ForegroundColor DarkGray }
    }
    if ($showSum) { Write-Host ("  ---------- 小计: {0}（{1} 项）" -f (MbLabel $sum), $rows.Count) -ForegroundColor $color }
}

# ============ 2. 开始扫描 ============
Write-Host '==================== C 盘垃圾扫描 v3（只读，不删除任何文件） ====================' -ForegroundColor White
Write-Host ("时间: {0}    权限: {1}" -f $scanTime.ToString('yyyy-MM-dd HH:mm:ss'), $(if ($isAdmin) { '管理员' } else { '普通用户（部分系统目录体积可能偏小）' }))
$d = Get-PSDrive C
Write-Host ("C 盘: 总 {0:N1} GB | 已用 {1:N1} GB | 可用 {2:N1} GB" -f (($d.Used + $d.Free) / 1GB), ($d.Used / 1GB), ($d.Free / 1GB))

# ---- 低风险：纯缓存 / 临时文件 ----
Scan-One '低' '用户临时目录' "$LA\Temp" '程序运行残留的临时文件；清理时被占用的文件会跳过'
Scan-One '低' 'Windows 临时目录' 'C:\Windows\Temp' '系统临时文件'
Scan-One '低' 'Windows 更新下载缓存' 'C:\Windows\SoftwareDistribution\Download' '更新安装完成后可清理'
Scan-One '低' '传递优化缓存' 'C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache' 'Windows 更新 P2P 分发缓存'
Scan-One '低' '崩溃转储（用户）' "$LA\CrashDumps" '程序崩溃转储，非排查需要可删'
Scan-One '低' '错误报告 WER（用户）' "$LA\Microsoft\Windows\WER" 'Windows 错误报告队列'
Scan-One '低' '错误报告 WER（系统）' 'C:\ProgramData\Microsoft\Windows\WER' '同上（系统级）'
Scan-One '低' '蓝屏小转储 Minidump' 'C:\Windows\Minidump' '蓝屏记录，非排查需要可删'
if (Test-Path -LiteralPath 'C:\Windows\MEMORY.DMP') {
    $s = Get-DirStats 'C:\Windows\MEMORY.DMP'
    if ($s) { Add-Row '低' '完整内存转储' 'C:\Windows\MEMORY.DMP' $s.Bytes '蓝屏完整转储，非排查需要可删' $s.Files $s.LastWrite }
}
Scan-One '低' '内核实时报告' 'C:\Windows\LiveKernelReports' '内核实时报告文件'
Scan-One '低' '缩略图/图标缓存' "$LA\Microsoft\Windows\Explorer" 'thumbcache 等，自动重建'
Scan-One '低' '系统网络缓存 INetCache' "$LA\Microsoft\Windows\INetCache" '系统组件网络缓存'
Scan-One '低' 'WebCache 数据库' "$LA\Microsoft\Windows\WebCache" '系统 Web 缓存'
Scan-One '低' 'D3DSCache' "$LA\D3DSCache" 'DirectX 着色器缓存，自动重建'
Scan-One '低' 'NVIDIA 着色器缓存' "$LA\NVIDIA" 'DXCache/GLCache，自动重建'
Scan-One '低' 'NVIDIA 驱动缓存' 'C:\ProgramData\NVIDIA Corporation' '含驱动下载缓存 Downloader，驱动装好后可清'
Scan-Glob '低' 'Chrome 页面缓存' "$LA\Google\Chrome\User Data\*\Cache" '网页缓存，不影响登录状态（Cookie 不在这里）'
Scan-Glob '低' 'Chrome 代码缓存' "$LA\Google\Chrome\User Data\*\Code Cache" 'JS 编译缓存'
Scan-Glob '低' 'Edge 页面缓存' "$LA\Microsoft\Edge\User Data\*\Cache" '网页缓存，不影响登录状态'
Scan-Glob '低' 'Edge 代码缓存' "$LA\Microsoft\Edge\User Data\*\Code Cache" 'JS 编译缓存'
Scan-Glob '低' 'Discord 缓存' "$RA\discord\*\Cache" 'Discord 网页缓存'
Scan-One '低' 'Steam 界面缓存' "$LA\Steam\htmlcache" 'Steam 客户端内嵌网页缓存'
Scan-One '低' '字体缓存' 'C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache' 'Windows 字体缓存，自动重建'
Scan-One '低' 'pip 缓存' "$LA\pip\cache" 'Python 包下载缓存'
Scan-One '低' 'npm 缓存' "$LA\npm-cache" 'Node 包下载缓存'
Scan-One '低' 'npm 缓存(Roaming)' "$RA\npm-cache" '旧版 npm 缓存位置'
Scan-One '低' 'Yarn 缓存' "$LA\Yarn\Cache" 'Yarn 包下载缓存'
Scan-One '低' 'uv 缓存' "$LA\uv" 'Python uv 包缓存'
Scan-One '低' 'Playwright 浏览器内核' "$LA\ms-playwright" '自动化测试内核，下次运行自动重新下载'
Scan-One '低' 'pyppeteer 浏览器内核' "$LA\pyppeteer" '同上'
Scan-One '低' '回收站' 'C:\$Recycle.Bin' '清空回收站即可'
Scan-One '低' 'Config.Msi 安装回滚' 'C:\Config.Msi' '安装过程的回滚临时文件，正常情况很小'
Scan-PatternDirs '低' '更新器残留安装包' $LA '*-updater' '桌面软件更新器遗留的旧安装包，纯垃圾'

# ---- 中风险：确认后再处理 ----
Scan-One '中' '休眠文件 hiberfil.sys' 'C:\hiberfil.sys' '休眠功能的内存镜像，不是垃圾；不用休眠可管理员运行 powercfg /h off 释放'
Scan-One '中' '旧系统 Windows.old' 'C:\Windows.old' '旧系统回滚用；确认新系统正常后建议用磁盘清理(cleanmgr)删除'
Scan-One '中' 'Windows 升级残留 BT' 'C:\$WINDOWS.~BT' '系统升级临时文件；建议用磁盘清理(cleanmgr)的「Windows 升级清理」处理'
Scan-One '中' 'Windows 升级残留 WS' 'C:\$Windows.~WS' '同上'
Scan-One '中' 'Windows 搜索索引' 'C:\ProgramData\Microsoft\Search\Data' '搜索索引文件；删后 Windows 搜索需重新建索引（期间搜索结果不全）'
Scan-Glob '中' 'Office 文件缓存' "$LA\Microsoft\Office\*\OfficeFileCache" 'Office 上传/同步缓存；若有未上传完的文档会被清，确认无待同步文件再删'
Scan-One '中' 'JetBrains IDE 缓存' "$LA\JetBrains" 'IDE 索引缓存；建议只删旧版本号子目录，当前版本删后需重建索引'
Scan-One '中' '剪映素材缓存' "$LA\JianyingPro" '可能含草稿索引；建议走剪映「设置-缓存管理」清理，勿直接删目录'
Scan-One '中' 'QQ 聊天文件' "$DOC\Tencent Files" '聊天记录与接收的文件（个人数据），建议走 QQ 内置存储清理'
Scan-One '中' '微信聊天文件(旧版)' "$DOC\WeChat Files" '个人数据，建议走微信内置存储清理'
Scan-One '中' '微信聊天文件(新版)' "$DOC\xwechat_files" '个人数据，建议走微信内置存储清理'
Scan-One '中' '下载文件夹' "$UP\Downloads" '个人下载的文件，自行筛选'
Scan-One '中' '夸克浏览器' "$LA\Quark" '应用数据与缓存，走应用内清理更稳'
Scan-One '中' '微信开发者工具' "$LA\微信开发者工具" 'IDE 缓存与项目数据'
Scan-One '中' '酷我音乐' "$LA\kwmusic" '音乐缓存，应用内清理'
Add-Covered "$UP\.cache"
if (Test-Path -LiteralPath "$UP\.cache") {
    Get-ChildItem -LiteralPath "$UP\.cache" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $s = Get-DirStats $_.FullName
        if ($s -and $s.Bytes -ge 30MB) {
            if ($_.Name -in @('modelscope', 'huggingface', 'torch')) {
                Add-Row '中' ('模型缓存 - ' + $_.Name) $_.FullName $s.Bytes '已下载的 AI 模型/框架文件，删后需重新下载' $s.Files $s.LastWrite
            } elseif ($_.Name -eq '.cache') {
                Add-Row '中' ('嵌套缓存目录 - ' + $_.Name) $_.FullName $s.Bytes '嵌套出现的 .cache（HOME 变量被指到 .cache 的工具留下），内容来源不明，先确认再决定' $s.Files $s.LastWrite
            } else {
                Add-Row '低' ('开发缓存(.cache) - ' + $_.Name) $_.FullName $s.Bytes '工具缓存，可重新获取' $s.Files $s.LastWrite
            }
        }
    }
}

# ---- 高风险：系统关键文件，仅列出提醒 ----
Scan-One '高' 'Windows Installer 缓存' 'C:\Windows\Installer' '【勿删】所有 MSI 软件卸载/修复的数据源，删后软件卸不掉'
Scan-One '高' '安装器包缓存' 'C:\ProgramData\Package Cache' '【勿删】VC++/VS 等运行库修复卸载数据源'
Scan-One '高' '页面文件 pagefile.sys' 'C:\pagefile.sys' '【勿删】虚拟内存；最多在系统高级设置里调整大小或挪盘'
Scan-One '高' '系统恢复环境' 'C:\Recovery' '【勿删】WinRE 恢复环境'
Add-Row '高' 'WinSxS 组件存储' 'C:\Windows\WinSxS' -1 '【勿删】不可手动清理；如需精简用 DISM /Online /Cleanup-Image /StartComponentCleanup'

# ---- 动态发现：清单外的大目录 ----
function Sweep-Dirs([string]$root, [string]$label, [long]$minBytes, [string[]]$excludeNames) {
    if (-not (Test-Path -LiteralPath $root)) { return }
    Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($excludeNames -contains $_.Name) { return }
        if (Test-Covered $_.FullName) { return }
        Write-Progress -Id 1 -Activity '正在扫描 C 盘垃圾（只读）' -Status ($label + ' - ' + $_.Name)
        $s = Get-DirStats $_.FullName
        if ($s -and $s.Bytes -ge $minBytes) {
            Add-Row '中' ($label + ' - ' + $_.Name) $_.FullName $s.Bytes '清单外内容，先确认用途再决定；优先走应用内清理入口' $s.Files $s.LastWrite
        }
    }
}
Sweep-Dirs $LA '其他应用数据' 100MB @('Google', 'Microsoft', 'Packages', 'Temp')
Sweep-Dirs 'C:\ProgramData' 'ProgramData 其他项' 100MB @('Microsoft')
$rootWhite = '^Windows$|^Program Files$|^Program Files \(x86\)$|^Users$|^ProgramData$|^Recovery$|^System Volume Information$|^\$Recycle\.Bin$|^Config\.Msi$|^Documents and Settings$|^Intel$|^NVIDIA Corporation$|^perflogs$'
if (Test-Path -LiteralPath 'C:\') {
    Get-ChildItem -LiteralPath 'C:\' -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $rootWhite } | ForEach-Object {
        if (Test-Covered $_.FullName) { return }
        Write-Progress -Id 1 -Activity '正在扫描 C 盘垃圾（只读）' -Status ('根目录 - ' + $_.Name)
        $s = Get-DirStats $_.FullName
        if ($s -and $s.Bytes -ge 50MB) {
            Add-Row '中' ('根目录其他项 - ' + $_.Name) $_.FullName $s.Bytes 'C 盘根目录的非常规目录（装机工具/构建产物等），确认无用可删' $s.Files $s.LastWrite
        }
    }
}
Write-Progress -Id 1 -Activity '正在扫描 C 盘垃圾（只读）' -Completed

# ============ 3. 控制台摘要 ============
$sumLow  = [long]((($results | Where-Object { $_.Risk -eq '低' -and $_.Bytes -ge 0 }) | Measure-Object Bytes -Sum).Sum); if (-not $sumLow)  { $sumLow  = 0 }
$sumMid  = [long]((($results | Where-Object { $_.Risk -eq '中' -and $_.Bytes -ge 0 }) | Measure-Object Bytes -Sum).Sum); if (-not $sumMid)  { $sumMid  = 0 }

Show-Group '低' '[ 低风险 · 可放心清理 ]' 'Green' $true
Show-Group '中' '[ 中风险 · 确认后再处理 ]' 'Yellow' $true
Show-Group '高' '[ 高风险 · 请勿手动删除（仅列出） ]' 'Red' $false
Write-Host ''
Write-Host ("预计可安全回收（低风险小计）: {0}" -f (MbLabel $sumLow)) -ForegroundColor Green
Write-Host ("需确认后处理（中风险小计）  : {0}" -f (MbLabel $sumMid)) -ForegroundColor Yellow

# ============ 4. 生成报告文件 ============
$stamp = $scanTime.ToString('yyyyMMdd_HHmmss')
$htmlPath = Join-Path $OutDir ('C盘垃圾扫描报告_{0}.html' -f $stamp)
$csvPath  = Join-Path $OutDir ('C盘垃圾扫描明细_{0}.csv' -f $stamp)

$template = @'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>C 盘垃圾扫描报告 v3 · __STAMP__</title>
<style>
  :root{--bg:#fafafa;--ink:#161616;--muted:#6b6b6b;--hair:#d9d9d4;--hair2:#e8e8e3;--accent:#0d6b4f}
  *{margin:0;padding:0;box-sizing:border-box}
  body{background:var(--bg);color:var(--ink);font-family:"Segoe UI","Microsoft YaHei","PingFang SC",sans-serif;font-size:15px;line-height:1.6;padding:40px 20px 60px}
  .c{max-width:1280px;margin:0 auto}
  .k{font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);font-family:Consolas,monospace}
  h1{font-size:32px;font-weight:600;letter-spacing:-.02em;margin:8px 0 6px}
  .m{font-family:Consolas,monospace;font-size:12px;color:var(--muted);display:flex;gap:22px;flex-wrap:wrap;margin-bottom:24px}
  .metrics{display:flex;flex-wrap:wrap;border:1px solid var(--hair);border-right:none;margin-bottom:14px}
  .mi{flex:1 1 170px;padding:14px 16px;border-right:1px solid var(--hair)}
  .mi .k2{font-size:11px;letter-spacing:.08em;color:var(--muted);margin-bottom:4px}
  .mi .v{font-size:22px;font-weight:600;font-variant-numeric:tabular-nums;color:var(--accent)}
  .mi .n{font-size:11px;color:var(--muted);margin-top:2px;font-family:Consolas,monospace}
  .legend{border:1px solid var(--hair);padding:12px 16px;margin-bottom:26px;font-size:12.5px;color:#444}
  .legend b{font-weight:600}
  h2{font-size:19px;font-weight:600;margin:28px 0 4px}
  .s{color:var(--muted);font-size:13px;margin-bottom:6px;max-width:90ch}
  table{width:100%;border-collapse:collapse;margin-top:8px}
  th{text-align:left;font-size:11px;letter-spacing:.08em;color:var(--muted);font-weight:500;padding:7px 9px;border-bottom:1px solid var(--ink)}
  td{padding:9px;border-bottom:1px solid var(--hair2);font-size:13px;vertical-align:top}
  td.num{font-family:Consolas,monospace;text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums}
  td.ctr{font-family:Consolas,monospace;text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums;font-size:12px}
  td.path{font-family:Consolas,monospace;font-size:11.5px;color:var(--muted);word-break:break-all}
  .nm{font-weight:600}
  .stale{color:#991b1b;font-weight:600}
  .sum{font-family:Consolas,monospace;font-size:12.5px;margin-top:8px}
  .ft{border-top:1px solid var(--hair);margin-top:44px;padding-top:14px;font-family:Consolas,monospace;font-size:11.5px;color:var(--muted);display:flex;justify-content:space-between;flex-wrap:wrap;gap:8px}
</style>
</head>
<body><div class="c">
<div class="k">DISK JUNK SCAN v3 &middot; C:\ &middot; READ-ONLY</div>
<h1>C 盘垃圾扫描报告</h1>
<div class="m"><span>时间 __STAMP__</span><span>权限 __ADMIN__</span><span>__DRIVE__</span><span>扫描用时 __ELAPSED__ 秒</span><span>共 __ROWS__ 项</span></div>
<div class="metrics">
<div class="mi"><div class="k2">低风险合计（可放心清理）</div><div class="v">__SUMLOW__</div><div class="n">__CNTLOW__ 项</div></div>
<div class="mi"><div class="k2">中风险合计（确认后处理）</div><div class="v">__SUMMID__</div><div class="n">__CNTMID__ 项</div></div>
<div class="mi"><div class="k2">高风险（勿手动删除）</div><div class="v">__SUMHIGH__</div><div class="n">__CNTHIGH__ 项</div></div>
<div class="mi"><div class="k2">C 盘可用空间</div><div class="v">__FREE__</div><div class="n">总容量 __TOTAL__</div></div>
</div>
<div class="legend">
<b>风险等级说明</b>：低 = 纯缓存/临时文件，删除后自动重建或可重新下载，无个人数据；中 = 有重建/重下代价（模型/索引/应用数据）或含个人数据，删前逐项确认；高 = 系统关键文件（卸载/修复/恢复/内存管理），请勿手动删除。<b>「最近写入」</b>列用于判断活跃度：距今天数越久（标红 = 超过 60 天未更新），越可能是陈年垃圾。
</div>
__SECTIONS__
<div class="ft"><span>由「C盘垃圾扫描.ps1」v3 生成 &middot; 只读扫描，未删除任何文件</span><span>__STAMP__</span></div>
</div></body></html>
'@

$secDefs = @(
    @{ Risk = '低'; Title = '低风险 · 可放心清理'; Desc = '纯缓存、临时文件、崩溃转储与可重新下载的内容，删除后自动重建或重新下载，不影响个人数据与软件运行。' },
    @{ Risk = '中'; Title = '中风险 · 确认后再处理'; Desc = '需要确认后再处理：删了要付出重建/重新下载的代价，或本身就是你的个人数据。每一项建议先看一眼再决定。' },
    @{ Risk = '高'; Title = '高风险 · 请勿手动删除'; Desc = '系统与软件卸载/修复/运行的关键文件，仅列出供知情，不建议任何手动删除操作。' }
)
$secs = New-Object System.Text.StringBuilder
foreach ($sd in $secDefs) {
    $rows = @($results | Where-Object { $_.Risk -eq $sd.Risk } | Sort-Object Bytes -Descending)
    if ($sd.Risk -ne '高') { $rows = @($rows | Where-Object { $_.Bytes -ge 0 }) }
    if ($rows.Count -eq 0) { continue }
    $gsum = [long]((($rows | Where-Object { $_.Bytes -ge 0 }) | Measure-Object Bytes -Sum).Sum); if (-not $gsum) { $gsum = 0 }
    [void]$secs.AppendLine(('<h2>{0}</h2><div class="s">{1}</div>' -f (HtmlEsc $sd.Title), (HtmlEsc $sd.Desc)))
    [void]$secs.AppendLine('<table><thead><tr><th style="width:20%">项目</th><th style="width:8%;text-align:right">体积</th><th style="width:7%;text-align:right">文件数</th><th style="width:8%;text-align:right">最近写入</th><th style="width:27%">位置</th><th>说明</th></tr></thead><tbody>')
    foreach ($r in $rows) {
        $days = DaysSince $r.LastWrite
        $dateCell = FmtDate $r.LastWrite
        if ($days -ge 60) { $dateCell = '<span class="stale">' + $dateCell + '（' + $days + ' 天前）</span>' }
        [void]$secs.AppendLine(('<tr><td class="nm">{0}</td><td class="num">{1}</td><td class="ctr">{2}</td><td class="ctr">{3}</td><td class="path">{4}</td><td>{5}</td></tr>' -f (HtmlEsc $r.Name), (MbLabel $r.Bytes), (HtmlEsc (FmtCount $r.Files)), $dateCell, (HtmlEsc $r.Path), (HtmlEsc $r.Note)))
    }
    [void]$secs.AppendLine('</tbody></table>')
    [void]$secs.AppendLine(('<div class="sum">小计：{0}（{1} 项）</div>' -f (MbLabel $gsum), $rows.Count))
}

$html = $template
$html = $html.Replace('__STAMP__', $scanTime.ToString('yyyy-MM-dd HH:mm:ss'))
$html = $html.Replace('__ADMIN__', $(if ($isAdmin) { '管理员' } else { '普通用户' }))
$html = $html.Replace('__DRIVE__', ('C 盘已用 {0:N1} GB / {1:N1} GB' -f ($d.Used / 1GB), (($d.Used + $d.Free) / 1GB)))
$html = $html.Replace('__ELAPSED__', [string][int]$swTotal.Elapsed.TotalSeconds)
$html = $html.Replace('__ROWS__', [string]$results.Count)
$html = $html.Replace('__SUMLOW__', (MbLabel $sumLow))
$html = $html.Replace('__SUMMID__', (MbLabel $sumMid))
$sumHigh = [long]((($results | Where-Object { $_.Risk -eq '高' -and $_.Bytes -ge 0 }) | Measure-Object Bytes -Sum).Sum); if (-not $sumHigh) { $sumHigh = 0 }
$html = $html.Replace('__SUMHIGH__', (MbLabel $sumHigh))
$html = $html.Replace('__CNTLOW__', [string]@($results | Where-Object { $_.Risk -eq '低' -and $_.Bytes -ge 0 }).Count)
$html = $html.Replace('__CNTMID__', [string]@($results | Where-Object { $_.Risk -eq '中' -and $_.Bytes -ge 0 }).Count)
$html = $html.Replace('__CNTHIGH__', [string]@($results | Where-Object { $_.Risk -eq '高' }).Count)
$html = $html.Replace('__FREE__', (MbLabel ($d.Free)))
$html = $html.Replace('__TOTAL__', ('{0:N0} GB' -f (($d.Used + $d.Free) / 1GB)))
$html = $html.Replace('__SECTIONS__', $secs.ToString())

[System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding($true)))

$results | Sort-Object @{ e = { switch ($_.Risk) { '低' { 1 } '中' { 2 } '高' { 3 } default { 4 } } } }, @{ e = 'Bytes'; Descending = $true } |
    Select-Object Risk, Name,
        @{ n = 'SizeMB'; e = { if ($_.Bytes -ge 0) { [math]::Round($_.Bytes / 1MB, 1) } else { -1 } } },
        Files,
        @{ n = 'LastWrite'; e = { FmtDate $_.LastWrite } },
        Path, Note |
    Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

# ============ 5. 收尾 ============
if (-not $NoOpen) { Start-Process $htmlPath }
Write-Host ''
Write-Host '==================== 扫描完成 ====================' -ForegroundColor White
Write-Host ("HTML 报告: {0}" -f $htmlPath) -ForegroundColor White
Write-Host ("CSV 明细 : {0}" -f $csvPath) -ForegroundColor White
Write-Host ("耗时: {0:N0} 秒 | 本扫描为只读操作，未删除任何文件" -f $swTotal.Elapsed.TotalSeconds) -ForegroundColor DarkGray
