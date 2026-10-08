# C盘垃圾扫描器（cdrive-junk-scanner）

一个**只读、安全、开箱即用**的 Windows C 盘垃圾文件扫描工具。
扫描 60+ 个常见垃圾聚集点，按三级风险标注，输出带「文件数 / 最近写入时间」维度的 HTML 报告与 CSV 明细——**全程不删除任何文件**，删什么由你自己决定。

> 适用系统：Windows 10 / 11 · PowerShell 5.1（系统自带，无需安装任何依赖）

---

## 特性

- **绝对只读**：脚本内没有任何删除/移动/重命名逻辑，只做统计；
- **三级风险分级**：
  - 🟢 **低风险** —— 纯缓存/临时文件，删除后自动重建或可重新下载；
  - 🟡 **中风险** —— 有重建/重下代价（AI 模型、IDE 索引）或含个人数据（聊天记录、下载目录），逐项确认后处理；
  - 🔴 **高风险** —— 系统关键文件（卸载数据源、恢复环境、虚拟内存），仅列出提醒，**请勿手动删除**；
- **活跃度判断**：每个检测点输出文件总数与最近写入时间，超过 60 天未更新的条目在报告中**标红**——一眼识别陈年残留 vs 活跃缓存；
- **动态发现**：除内置清单外，自动扫描 `LocalAppData`、`ProgramData`、C 盘根目录下超过阈值（100MB/50MB）的清单外大目录，新装软件留下的垃圾也能抓到；
- **双输出**：HTML 报告（浏览器直接打开，含风险图例与逐项说明）+ CSV 明细（Excel/WPS 可开，方便筛选排序）；
- **环境无关**：不依赖 `LOCALAPPDATA`/`APPDATA` 等环境变量（提权场景下它们可能被改写），全部路径自动推导兜底。

## 快速开始

### 方式一：双击运行（推荐）

1. 下载仓库中的 `C盘垃圾扫描.ps1` 和 `C盘垃圾扫描-双击运行.bat`，放到**同一个文件夹**（桌面即可）；
2. 双击 `C盘垃圾扫描-双击运行.bat`；
3. 弹出 UAC 提示点「是」（脚本需要管理员权限读取系统目录的真实体积）；
4. 等待 30~90 秒，报告自动在浏览器打开，HTML/CSV 两个文件生成在你的**桌面**。

> 启动器为纯 ASCII 编码，任何系统代码页（GBK/UTF-8）下都不会出现乱码；`.ps1` 带 UTF-8 BOM，PowerShell 5.1 直接正确解码。

### 方式二：命令行

```powershell
# 基本用法（报告输出到桌面并自动打开）
powershell -NoProfile -ExecutionPolicy Bypass -File .\C盘垃圾扫描.ps1

# 指定输出目录、不自动打开浏览器
powershell -NoProfile -ExecutionPolicy Bypass -File .\C盘垃圾扫描.ps1 -OutDir D:\Reports -NoOpen
```

## 检测点清单（v3）

| 类别 | 检测点 |
|---|---|
| 系统临时/转储 | 用户 Temp、Windows\Temp、崩溃转储 CrashDumps、WER 错误报告（用户+系统）、Minidump、MEMORY.DMP、LiveKernelReports |
| 系统缓存 | 缩略图/图标缓存、INetCache、WebCache、FontCache、D3DSCache、传递优化缓存、Windows 更新下载缓存、Windows 搜索索引 |
| 显卡 | NVIDIA 驱动下载缓存（ProgramData）、NVIDIA 着色器缓存（DXCache/GLCache） |
| 浏览器 | Chrome / Edge 页面与代码缓存（按 Profile 通配）、Discord 缓存、Steam htmlcache、夸克浏览器 |
| 开发工具 | pip、npm（两个位置）、Yarn、uv、NuGet、Playwright / pyppeteer / Chromium 浏览器内核、puppeteer、JetBrains IDE 缓存、微信开发者工具 |
| 软件残留 | `*-updater` 更新器旧安装包（按模式自动发现全部）、Config.Msi 安装回滚 |
| 个人数据 | QQ 聊天文件、微信聊天文件（旧版 WeChat Files / 新版 xwechat_files）、剪映素材缓存、酷我音乐、Downloads 下载文件夹 |
| 系统级 | 休眠文件 hiberfil.sys、Windows.old、$WINDOWS.~BT / $Windows.~WS 升级残留、回收站 |
| 高风险提示项 | C:\Windows\Installer、C:\ProgramData\Package Cache、pagefile.sys、C:\Recovery、WinSxS（仅列出，勿删） |
| 动态发现 | LocalAppData / ProgramData / C 盘根目录下超过阈值的清单外大目录 |

## 输出说明

运行后在输出目录生成：

```
C盘垃圾扫描报告_20261008_175852.html   ← 浏览器打开，含风险分级、活跃度标红、逐项处理建议
C盘垃圾扫描明细_20261008_175852.csv    ← Excel 打开，列：风险/名称/体积MB/文件数/最近写入/路径/说明
```

CSV 列说明：

| 列 | 含义 |
|---|---|
| Risk | 低 / 中 / 高 三级风险 |
| SizeMB | 体积（MB，-1 表示未统计，如 WinSxS） |
| Files | 文件总数（-1 表示未统计） |
| LastWrite | 目录内最新文件的写入日期——判断活跃度的关键 |
| Path | 完整路径 |
| Note | 该项是什么、删除后果、建议操作 |

## 手动清理建议流程

1. **先删低风险**：报告里「低风险」表逐项删，无数据损失，一般可回收数 GB；
2. **中风险逐项确认**：报告每项都标了「可删 / 确认后删 / 建议保留」判断与删除后果。要点：
   - AI 模型缓存（HuggingFace / ModelScope / torch）：确认对应工具不再使用再删，否则会重新下载数 GB；
   - JetBrains：只删**旧版本号**子目录，保留当前在用版本；
   - 剪映 / QQ / 微信：走应用内的「缓存管理 / 存储管理」入口，不要手动删整个目录（可能含草稿与聊天记录）；
3. **高风险不动**：`C:\Windows\Installer`、`Package Cache`、`Recovery`、`pagefile.sys`、`WinSxS` 列出来只是让你知道空间去哪了；
4. 系统级兜底：管理员运行「磁盘清理 cleanmgr → 清理系统文件」，处理 Windows 升级残留等；WinSxS 精简用
   `Dism /Online /Cleanup-Image /StartComponentCleanup`。

## 常见问题

**Q：为什么有些项显示 0 KB 或「—」？**
该位置不存在、为空，或（非管理员运行时）无权限读取。用管理员权限重跑即可。

**Q：Temp 里有些文件删不掉？**
正在被运行中的程序占用，跳过即可，不影响其他文件；也可在安全模式下清理。

**Q：休眠文件 hiberfil.sys 怎么释放？**
它不是垃圾，是休眠功能的内存镜像。若不用「休眠」和「快速启动」，管理员运行：
`powercfg /h off`，文件自动消失，通常可回收 3~8 GB。

**Q：报告里的「最近写入」有什么用？**
判断缓存是活跃还是陈年：比如一个 8GB 的模型缓存如果昨天还在写入，说明有工具正在使用它，删了会重新下载；如果两年没动过，基本就是垃圾。

**Q：会收集/上传我的任何数据吗？**
不会。脚本完全离线运行，无网络请求，无遥测，报告只生成在你本机。

## 版本历史

见 [CHANGELOG.md](CHANGELOG.md)。当前版本 **v3.0**（2026-10-08）。

## 免责声明

本工具仅做只读统计，不删除任何文件；删除操作由使用者按报告自行执行，删除前请确认条目内容。对使用者按报告清理造成的任何数据损失，作者不承担责任——**中风险项删前务必逐项确认**。

## License

[MIT](LICENSE)
