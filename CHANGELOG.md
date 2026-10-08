# Changelog

本文件记录「C盘垃圾扫描器」的所有重要变更。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循语义化版本。

## [3.0] - 2026-10-08

### 新增
- 每个检测点新增「文件数」与「最近写入时间」两个统计维度，用于判断缓存是活跃还是陈年残留；
- 报告中超过 60 天未更新的条目自动标红；
- 新增检测点：Windows.old、C:\Config.Msi、Windows 搜索索引（ProgramData\Microsoft\Search）、Office 文件缓存（OfficeFileCache）、Discord 缓存、Steam htmlcache；
- HTML 报告新增风险等级图例说明区。

### 修复
- 修复在提权/精简环境下因 `LOCALAPPDATA`、`APPDATA`、`TEMP` 环境变量缺失或被改写，导致浏览器缓存、更新器残留等十几个检测点静默失效的问题——所有路径改为环境变量优先 + 用户目录自动推导兜底；
- 修复 `.cache` 目录内嵌套 `.cache`（HOME 变量被指到 .cache 的工具造成）被误标为低风险的问题，现单独标注为中风险「嵌套缓存目录」。

### 变更
- HTML 表格新增「文件数」「最近写入」两列，列宽重新分配；
- CSV 明细同步新增 Files、LastWrite 两列。

## [2.1] - 2026-10-07

### 修复
- 双击运行器（.bat）在中文系统下因编码问题报「不是内部命令」并反复弹窗：
  - 启动器改为**纯 ASCII**内容 + CRLF 换行，任何代码页下均可正确解析；
  - 提权检测由 `net session` 改为更可靠的 `fltmc`；
  - 脚本定位改为「从启动器自身文件名推导」，避免同目录多个 .ps1 时选错；
- `.ps1` 增加 UTF-8 BOM，保证 Windows PowerShell 5.1 在非 UTF-8 代码页下正确解码中文。

## [2.0] - 2026-10-07

### 新增
- 动态发现引擎：自动扫描 LocalAppData / ProgramData / C 盘根目录下超过阈值（100MB / 50MB）的清单外大目录；
- `-OutDir`、`-NoOpen` 参数；
- Windows.old、$WINDOWS.~BT / $Windows.~WS、System Volume Information 等系统级检测；
- 控制台三级风险彩色分组输出与小计。

### 变更
- 输出从单一 HTML 升级为 HTML 报告 + CSV 明细双输出。

## [1.0] - 2026-09-23

### 新增
- 首个版本：50+ 检测点、三级风险分级（低/中/高）、HTML 报告生成、双击运行启动器。
