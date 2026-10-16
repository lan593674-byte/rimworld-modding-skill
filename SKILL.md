---
name: rimworld
description: 环世界（RimWorld）模组开发规则。凡是涉及环世界开发的任务，包括写或改模组代码、Defs、翻译、测试、上传创意工坊、查游戏源码，开始前都必须先读这个 skill。
---

# 环世界开发规则

这份 skill 是开发几个环世界模组时总结出来的工作流程和踩坑记录，覆盖 1.6 正式版和 1.7 测试版（Waylith 引擎，实测到 1.7.4979 rev109）。文中的「agent」指按这份 skill 干活的 AI 编程助手（Claude Code、Codex 等都行），「用户」指模组作者本人。

## 第一次使用

正文里的路径用了下面几个占位符。第一次用时把「本机路径」一栏填好（或者把路径告诉 agent，让它填）；还没填时先问用户。

| 占位符 | 含义 | 本机路径 |
|---|---|---|
| `<开发目录>` | 模组开发的根目录，仓库、开发文档、测试数据都放这里 | （待填，例如 `D:\RimWorldDev`） |
| `<Steam 库>` | 装着游戏的 Steam 库文件夹，创意工坊的模组也下载到这里 | （待填，例如 `D:\SteamLibrary`） |
| `<游戏目录>` | 游戏安装目录 | （通常是 `<Steam 库>\steamapps\common\RimWorld`） |
| `<用户数据目录>` | 游戏自己的配置、存档、日志 | `%USERPROFILE%\AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios` |

另外几个占位符不用填：`<模组名>` 是模组的英文名，仓库、文件夹、dll 都用它；`<前缀>` 是模组的短前缀，语言键（`<前缀>_`）和自测的命令行参数（`-<前缀>-selftest` 这样）都用它；`<Test>` 是 `<开发目录>\<模组名>Test`；`<配置>` 是测试配置的名字（`vanilla`、`full` 等）。

整套流程只在 Windows 上用过。用到的工具：

- .NET SDK：1.6 版编 net472，引用 NuGet 包 `Krafs.Rimworld.Ref`；1.7 版编 net10.0，要 .NET 10 SDK。
- `ilspycmd`（`dotnet tool install -g ilspycmd`），反编译游戏源码。
- git 和 Git Bash。文中的 shell 命令按 Git Bash 写（`grep`、`timeout`、`cat -A`、`diff -rq`、`tar`），测试脚本按 PowerShell 写，同步用 Windows 自带的 robocopy。agent 只能用 PowerShell 时换成对应的写法，比如 `tasklist | findstr /i rimworld`。
- Python；用脚本画图标要装 Pillow。

**各模组的专用规则：** 放在本目录的 `mods\<模组名>.md`，照 `mods\_template.md` 建。开发某个模组时，先读本文件，再只读那个模组的文件；一个模组的规则（代码约束、判定规则、语言要求等）不要套用到其他模组。新模组开始开发时为它建一份。

**按需再读的参考文件：**

- `references\ui.md`：写或改界面（IMGUI 绘制、中文排版、自制控件、截图检查）之前读。
- `references\rimworld-1.7.md`：模组要支持 1.7，或者要在 1.7 上编译、测试时读。

**维护这个 skill：** 环世界开发中出现的重要信息都要同步写进来，并删掉过时的内容。适用于所有模组的（目录、流程、游戏本身的坑）写进本文件或参考文件；只属于某个模组的（它的设计、判定、测试命令、用户对它的决定）写进 `mods\<模组名>.md`。

## 一、目录：所有模组开发都放在 `<开发目录>` 下

| 路径 | 用途 |
|---|---|
| `<开发目录>\<模组名>` | 开发仓库。改代码、构建、git 提交都在这里 |
| `<开发目录>\<模组名>Dev` | 开发过程文档：核查报告、草稿等，不进仓库 |
| `<开发目录>\<模组名>Test` | 测试数据：独立的游戏配置和存档、自测日志、截图 |
| `<开发目录>\RimWorld-decompiled` | 反编译的 1.6 游戏源码（ilspycmd 生成，`RimWorld\`、`Verse\` 等子目录） |
| `<开发目录>\RimWorld-decompiled-1.7` | 反编译的 1.7 游戏源码，含引擎部分（见 `references\rimworld-1.7.md`） |
| `<开发目录>\GameRefs` | 1.7 版编译用的游戏程序集，所有模组共用，不进仓库（见 `references\rimworld-1.7.md`「两份构建的做法」） |
| `<游戏目录>\Mods\<模组名>` | 发布副本，只能由同步脚本生成 |

- Steam 下的模组文件夹由游戏读取，创意工坊上传的也是它。里面只能有发布文件（`About`、`Defs`、`Languages`、`Textures`、`1.6`、`1.7` 等版本文件夹），不能有 `.git`、`Source`、`docs` 之类的开发文件。不要直接在这里改东西，下次同步会被覆盖。
- **每个支持的游戏版本单独一个文件夹，内容完全相同也一样**（和多数模组的做法一致）：
  - `About.xml` 的 `supportedVersions` 列了哪些版本，就各建一个同名文件夹（`1.6`、`1.7`）。里面放这个版本的 `Assemblies`，以及只属于这个版本的 Defs、Patches。
  - 各版本共用、和版本无关的内容（`About`、`Languages`、`Textures`、共用的 `Defs`）放根目录。
  - `LoadFolders.xml` 里每个版本只加载根目录和自己的文件夹：`v1.6` 加载 `/` 和 `1.6`，`v1.7` 加载 `/` 和 `1.7`。不要让一个版本去读另一个版本的文件夹。
  - 每个版本文件夹放针对这个版本编译的 dll（1.7 版怎么编见 `references\rimworld-1.7.md`）。dll 都由构建自动生成，不要手工复制，免得某个版本漏掉更新。
  - 以后某个版本要单独改代码或 XML，只动它自己的文件夹，结构不用再调整。
- 同步脚本放在仓库里（例如 `Source\tools\sync-to-steam.ps1`）：用 `robocopy /MIR` 把发布文件镜像到 Steam 模组文件夹，并删掉其他所有东西。
  - 编译时自动同步：csproj 里加一个构建后执行的同步目标，带条件 `Condition="'$(SkipSync)' != 'true'"`；一次编出 1.6、1.7 两份的多目标工程再加上 `and '$(TargetFramework)' == ''`，两份都编完才同步（见 `references\rimworld-1.7.md`「两份构建的做法」）。游戏开着时构建加 `-p:SkipSync=true`，只编译不同步（原因见第五节「构建和工具」）。
  - 只改了 XML、贴图等不用编译的文件时，手动运行一次：
    `powershell -NoProfile -ExecutionPolicy Bypass -File Source\tools\sync-to-steam.ps1`
  - 游戏内测试脚本启动游戏前也会自动同步。
  - 发布目录列表要包含所有版本文件夹。某个版本文件夹缺 dll 就报错；几个版本的 dll 修改时间相差 10 分钟以上就拒绝同步（多半有一份是旧构建）；同步完比对哈希。
  - 模组运行时会往自己文件夹里写数据（下载的文件、缓存等）的，镜像时排除那个子文件夹，否则每次同步都会把它删光。
- 新建模组照此办理：仓库、Dev、Test 三个文件夹都建在 `<开发目录>`，复制同步脚本，按需要改其中的发布目录列表。

## 二、上传创意工坊

1. 确认改动已提交，游戏没在运行（`tasklist | grep -i rimworld`）。
2. 运行同步，检查 Steam 模组文件夹里只有发布文件。
3. 请用户在游戏里点上传。不需要临时挪走任何文件；只有模组运行时往自己文件夹里写了数据时例外，那些数据要在上传前挪走、传完再放回来。上传是用户在游戏里点的，所以这一步也由用户来做，或者等用户说好了再做。

- 在 1.7 里上传时，确认框有两个勾选项（`Dialog_ConfirmModUpload`，中文界面也是英文）：「Build asset pack」默认勾上，「Don't upload source textures」默认不勾。勾上前者时，游戏先把每个加载目录里的 `Textures`、`Sounds` 打包成该目录下的 `Assets.zip`，旁边还有 `.fingerprint`、`.roles`、`.stamps` 三个文件，都留在 Steam 模组文件夹里；然后复制到临时目录上传，复制时跳过这三个旁文件（`Workshop.BakeAndUpload`、`BuildStagingDirectory`）。1.7 玩家加载打包好的资源更快。后者**不能勾**：勾上就只上传 `Assets.zip`、不传原始 PNG，1.6 读不了 `Assets.zip`，1.6 玩家会没有贴图（游戏自带的提示也这样说）。同步脚本的 `/MIR` 会删掉这些打包文件，没有关系，下次上传时会重新生成。命令行 `-BakeModAssetPacks=<模组根目录;...>` 可以不上传、只打包（`RimWorldWaylith\ModAssetPackBake.cs`）。
- 封面：游戏只认 `About\Preview.png`（`ModMetaData.PreviewImagePath`），上传时原样交给 `SteamUGC.SetItemPreview`；Steam 的预览图上限是 1 MB。用户给的大图先缩小，存成普通 RGB 的 PNG，控制在 1 MB 以内（例如 1254×1254 的图缩到 720×720，942 KB），原图存进仓库 `docs\art-source`。不要用 256 色调色板 PNG 来压大小：1.6 的 Unity 能读，1.7 读模组贴图时托管的快速解码器（`Waylith.Rendering.PngDecoder`）只认 8 位 RGB、RGBA，调色板图要交给原生解码库，能不能读没有核实。
- 上传后，用户本地订阅的那份要等 Steam 下载更新才会变（`<Steam 库>\steamapps\workshop\appworkshop_294100.acf` 里 `WorkshopItemDetails` 的 `timeupdated` 比 `WorkshopItemsInstalled` 新就是还没下载）。要确认传上去的内容，就等下载完后看 `<Steam 库>\steamapps\workshop\content\294100\<创意工坊 ID>`，比如 `Textures` 还在不在。

## 三、通用约束

- 上传创意工坊、接受协议都由用户在游戏里自己点。
- 不修改用户自己的 RimWorld 配置和存档（`<用户数据目录>`），测试一律用 `<开发目录>\<模组名>Test` 里的独立数据。查问题时可以只读地看用户的 `Player.log`。
- 判断游戏行为前先查反编译源码，不凭记忆。游戏更新后要重新反编译：1.6 是 `ilspycmd -p -o <开发目录>\RimWorld-decompiled <游戏目录>\RimWorldWin64_Data\Managed\Assembly-CSharp.dll`，1.7 见 `references\rimworld-1.7.md`。
- 移动文件夹前先 `dotnet build-server shutdown`，否则常因句柄被占用而失败。

## 四、测试流程（所有模组的基础）

测试要完整，方方面面都覆盖。所有环世界模组的测试都以这套流程为基础，各模组只在此基础上增减场景。测试脚本、自测框架和测试辅助模组的现成实现在 `templates\MyMod\`：一个能直接编译、直接跑测试的最小模组（用法见 `templates\README.md`）。新模组从它复制、改名、填 `Source\tools\GameTest.psd1`，再把示例场景换成自己的。下面写的是这套东西要做到什么，改模板时以这里为准。

### 总原则

- **全部自动化**，不需要人工操作。只有界面外观要看截图，由 agent 看截图检查。
- **测试数据隔离**：测试用的配置和存档放在 `<Test>\<配置>\`，每个配置有自己的 `Config\ModsConfig.xml` 和 `Config\Prefs.xml`（`devMode = true`），游戏用 `-savedatafolder=` 启动。绝不修改用户自己的配置和存档。模组有自己的数据目录的，加一个命令行参数（如 `-<前缀>-data=<路径>`），测试时指到 Test 目录。
- **测试配置**：
  | 配置 | 启用的模组 |
  |---|---|
  | `vanilla` | Core + 全部 DLC +（如果用了）Harmony + 本模组 |
  | `core` | 只有 Core +（如果用了）Harmony + 本模组。本模组不要求 DLC 时，用它确认玩家没买 DLC 也不报错；要求某几个 DLC 时，就只开那几个 |
  | `full` | 一个复杂的模组环境，再加入本模组：用户自己的模组列表（`<用户数据目录>\Config\ModsConfig.xml`）够大、够杂就复制它，不够就用网上热门的模组合集（见下） |
  | `uninstalled` | `vanilla` 去掉本模组，加上测试辅助模组 |
  | `reinstall` | `vanilla` 加上测试辅助模组 |
- **`full` 配置的模组从哪来**：
  - 先看用户自己的列表够不够用。玩家装几百上千个模组的很常见，列表不到两百个模组就算太少；数量够了，下面「一定要有」的缺了任何一类、「常见大类」缺了好几类，也不够全面。
  - 一定要有：
    - 前置框架和库：Harmony、HugsLib、XML Extensions、Vanilla Expanded Framework、Humanoid Alien Races 等。很多模组靠它们，装的人很多。
    - 和本模组改同一块原版逻辑的热门模组：补丁打在同一批原版方法上的最容易冲突。自测开头的 `[DIAG]` 行会列出还有谁给这些方法打了补丁；再去创意工坊搜同一领域的热门模组。
    - 和本模组功能相近、玩家常一起装的模组。功能重复的同类模组也试一下：能共存最好；不能共存的，在 `About.xml` 的 `incompatibleWith` 里声明，测试配置里去掉。
  - 常见大类：
    - 大型内容模组：Vanilla Expanded 系列，新的阵营、动物、武器服装、建筑。
    - 种族、异种模组和它们的扩展：基于 Humanoid Alien Races 的种族（很受欢迎，中文社区尤其多）、加基因和异种的模组，连同同一作者出的扩展包（种族专属的建筑、科研、文化、阵营）。它们自带身体结构和身体部位、外观和画法、工作和服装限制、阵营和文化，牵动面很广；本模组涉及小人的身体、健康、头像、工作或阵营时，这一类算「一定要有」。第五节「开新档缺阵营」和「新开的地图没有小人」两条，都是种族模组或它的扩展引起的。
    - 玩法大改：改战斗的（如 Combat Extended）、改需求和医疗的、改经济和交易的，以及中世纪、太空这类整体大改。
    - 删改原版 Def 的模组：去掉某些科技或物品、把原版内容换掉的（多见于整体大改）。本模组引用的原版 Def 可能已经不在了。
    - 工作和小人 AI：改工作分配、搬运、优先级的（如 Pick Up And Haul、Work Tab、Common Sense）。
    - 界面：改主按钮栏、窗口、信息面板、研究界面的（如 UI Not Included、RimHUD、Numbers、研究树类）。
    - 画面：改贴图、渲染、镜头的（如 Camera+）。本模组自己画东西或带贴图时要有。
    - 地图、世界生成和开局：新的生物群系和地形、改世界生成的，以及开局编辑器（如 Prepare Carefully、Character Editor）。
    - 事件和说书人：加新事件、新说书人的。
    - 优化和加载加速：改 tick 频率、缓存、寻路、渲染、加载流程的（如 Performance Optimizer、Dubs Performance Analyzer）。它们改的正是「多久执行一次」「什么时候执行」，依赖执行时机的代码最容易在这里出问题。1.6 上要有；1.7 上一律剔除（见 `references\rimworld-1.7.md`「优化类模组」）。
  - 不够时上网找热门的模组合集或整合包，搭一个复杂的模组环境：Steam 创意工坊环世界的「合集」栏目按订阅数或热门排序，再看看中文社区常推荐的合集；挑支持当前游戏版本、两百个模组以上、覆盖上面各类的，需要时再把和本模组相关的热门模组补进去。优先用创意工坊合集；网盘里来路不明的整合包不用，里面的 dll 可能被改过，转载也可能侵犯模组作者的权利。
  - 动手前主动向用户说明：用户的列表为什么不够（多少个模组、缺哪几类）；打算用哪个合集（链接、模组数、大概占多少硬盘、支持哪些游戏版本）；要用户做什么（在 Steam 里订阅这个合集，订阅由用户自己点）；对用户有什么影响（只是多订阅了一批模组，测试配置有自己的 `ModsConfig.xml`，不会改用户自己的模组列表；测完可以退订，但退订不删模组运行时生成的文件，见第五节「Steam 退订创意工坊模组时只删它发布的文件」）。用户同意了再做。
  - 下载好以后，按各模组 `About.xml` 的 `modDependencies`、`loadBefore`、`loadAfter` 排好加载顺序（Harmony、Core、DLC 在最前；合集作者给了顺序就照用），缺的前置补上，写成一份 ModsConfig 列表交给测试脚本（`-ModList`，见下）。验收报告里写明用的是哪个合集、哪些模组。
  - 有条件时准备两份不同的列表各跑一遍，比如用户自己的一份、热门合集一份。
- **`full` 配置的细节**：
  - 脚本留一个 `-ModList <ModsConfig 文件>` 参数，从指定的列表复制；不给就复制用户当前的列表。列表都放在 `<开发目录>\ModLists\`，所有模组共用：用户列表的副本叫 `user-YYYY-MM-DD.xml`，平时有机会就存一份；按合集写好的叫 `<合集名>.xml`。
  - 跑之前看一眼复制到的模组数（脚本要打印出来）。不到 10 个，多半是列表被游戏重置成只剩 Core 了（1.6、1.7 来回切换就会，见 `references\rimworld-1.7.md`），这时脚本直接拒绝跑 full，改用存下的副本；10 个以上、不到两百个的能跑，但要按上面的办法再补一份合集来测。
  - 用户订阅了本模组的创意工坊版本、Mods 里又有同 packageId 的开发副本时，游戏给创意工坊那份的 packageId 加 `_steam` 后缀。复制列表时把它原位换成本地的 packageId，测的才是本地构建，也不会两份同时加载。
  - 要从 full 配置里去掉的模组（都只改测试配置，不动用户自己的）：
    - 和本模组互斥的模组（记在 `mods\<模组名>.md` 里）；
    - 会让开新档缺阵营的模组（见第五节「开新档缺阵营」）；
    - 在 1.7 上：所有优化类模组，以及会让窗口画不出来的 NebulaeFlood's Lib（清单和原因见 `references\rimworld-1.7.md`）。
  - 只复制模组列表，不复制用户各个模组的设置（里面可能有 API 密钥之类）。
- **代码约束（方便测试检查）**：代码里不写中文字面量（界面文字全走语言键），唯一例外是日志前缀（如 `"[模组名]"`）；语言键统一加模组前缀；定时逻辑、后台线程回调、Harmony 补丁都要 try/catch，异常只记带前缀的错误日志，同一位置只报一次（`Log.ErrorOnce`）。
- **核对加载的构建**：测试脚本要确认游戏加载的正是这次编的 dll。比如编译时把源码哈希嵌进 dll，启动日志打印 `loaded build=<版本> source=<哈希>`，脚本比对正在运行的那个版本；另一个版本文件夹里的 dll 按哈希或修改时间核对是不是这次编的。
- **同一时间只跑一个游戏**：各个测试脚本（包括别的模组的）共用 Mods 里的模组和同一套测试配置，1.7 上还共用同一个日志文件。每个脚本先拿一个跨进程互斥量（例如 `Local\RimWorld.GameTest`），拿到之后再同步发布文件、写测试配置、启动游戏；拿不到就等，等待上限要明显长于单次测试的超时（比如 full 给 3600 秒，等锁就给 90 分钟）。锁要能重入：一个脚本借用另一个脚本的准备步骤时（`-PrepareOnly`，只同步、写配置，不启动游戏），先拿锁，再在同一个进程里调用它（`& 脚本`，不要另开 `powershell -File`），子脚本照常拿锁，在同一线程上重入成功；只有最外层的持有者做准备和清理（细节见 `references\rimworld-1.7.md`「测试」）。拿到锁后先结束上次被强行终止的脚本留下的测试游戏（命令行带 `-savedatafolder=<开发目录>\` 的游戏进程：这时锁在自己手里，它不可能是别人正在跑的测试）。编译时的同步也拿这个锁，但只等一两分钟，等不到就失败，提示加 `-p:SkipSync=true`。
- **每次验收都写报告** `docs\compat-test-YYYY-MM.md`：游戏版本、命令、结果、原始日志位置、发现的问题和原因、其他模组自己的报错（只记录，不处理）。

### 1. 单元测试（`dotnet test Source\<模组名>.Tests`）

- 核心逻辑放在不引用 RimWorld 和 Unity 的 `<模组名>.Core` 工程里，以源码链接方式编进主工程，最终只发布一个 dll；Core 全部用单元测试覆盖，包括边界值和随机生成的性质测试（例如资金守恒）。
- 用到"现在的时间"、随机数、网络的地方都通过可注入的接口，测试时替换。
- 解析外部数据的代码：录真实样本做测试，另外测空响应、错误页、字段变化等异常输入，不能抛未处理的异常。连真实网络的测试单独放（比如设了环境变量才跑），改了数据源地址或解析之后跑一次：样本测试发现不了地址和真实数据的问题。
- 固定的几类检查（建议的测试类名：`DefXmlTests`、`LanguageParityTests`、`UiContentTests`）：
  - Def XML 的关键数值和设计文档一致；
  - 中英文语言文件的键完全一致，所有 Def 标签都有两种语言；
  - 代码里用到的每个语言键在两种语言里都存在；代码里没有中文字面量。这类检查按前缀找代码里的语言键，所以控件名（`GUI.SetNextControlName`）等其他字符串别用语言键的前缀，否则会被当成缺失的键。
- 读源码、语言文件的测试从测试程序集所在的目录往上找解决方案文件（`.sln`）或 `About\About.xml` 来定位仓库根，所以测试输出要留在仓库里，不能用 `-o`、`OutputPath` 挪到外面，否则这类测试会大批假失败。

### 2. 游戏内自测（`Source\tools\run-selftest.ps1`）

- 启动：`RimWorldWin64.exe -quicktest -<前缀>-selftest -savedatafolder=<Test>\<配置> -logfile <Test>\<配置>\selftest.log`。脚本启动前先同步发布文件。
- 脚本先认出装的是哪个版本：游戏根目录里是 `RimWorld.exe` 就是 1.7，是 `RimWorldWin64.exe` 就是 1.6。1.7 的 exe 名、日志位置、窗口参数都变了（见 `references\rimworld-1.7.md`「测试」），脚本按版本分开处理。
- 脚本参数（每个都在脚本开头写上说明）：
  - `-Profile vanilla|core|full`：用哪套测试配置。
  - `-Mode Smoke|SelfTest`：Smoke 只检查能不能顺利进到地图，SelfTest（默认）跑全部场景。
  - `-TimeoutSeconds`：超时。原版配置 900 秒够了，完整列表给 3600。
  - `-WindowStyle Hidden|Minimized|Normal`：窗口，见下面「窗口」那条。
  - `-ContinueOnFail`：有场景失败也跑完全部场景，一次看到所有失败。
  - `-ExcludeMods <packageId...>`：从测试配置里去掉这些模组，排查是哪个模组引起的问题。
  - `-ModList <ModsConfig 文件>`：full 配置从这份列表复制（见上面「`full` 配置的细节」）。
  - `-LoadPosition First|Middle|Last`：本模组放在加载顺序的哪里（见「4. 兼容性」）。
  - `-Language ChineseSimplified|English`：游戏语言。
  - `-PrepareOnly`：只同步发布文件、写测试配置，不启动游戏，给别的脚本在同一进程里调用（见上面「同一时间只跑一个游戏」）。
  - `-ExtraArgs <参数...>`：额外传给游戏的命令行参数，比如打开默认不跑的场景。
- `powershell -File 脚本.ps1 -ExcludeMods a,b` 传进去的是一个字符串 `"a,b"`（`-File` 不解析数组），`[string[]]` 参数只有一个元素，一个模组都排除不掉。脚本里先按逗号拆一遍，或改用 `powershell -Command "& '脚本.ps1' -ExcludeMods @('a','b'); exit $LASTEXITCODE"`；脚本要把实际排除了哪些打印出来，跑完先核对。
- 窗口：1.6 上默认用最小化（隐藏窗口不派发 OnGUI，界面场景只走逻辑、什么都没画，结果照样是 PASS）；1.7 上最小化会卡住，脚本要把 Hidden、Minimized 都换成：进程按 Normal 启动，再给游戏加 `-NoWindow`（由游戏自己隐藏窗口，照常渲染；见 `references\rimworld-1.7.md`）。
- 判定：日志出现 `[SELFTEST] FAIL`、没有出现 `[SELFTEST] DONE`、`DONE` 里 `passed=0`、或出现本模组的错误，脚本就返回非零退出码。
  - 1.6 的日志不标级别，所以模组自己的错误一律经日志帮助类写成「`<前缀> [ERROR] ...`」，两个版本都按这个标记认。
  - 游戏在模组代码外面接住的异常不带前缀，要看错误的堆栈里有没有模组的命名空间。1.6 默认不给错误带堆栈，模组构造函数第一件事就调 `Application.SetStackTraceLogType(LogType.Error, StackTraceLogType.ScriptOnly)`（放在 1.6 的适配层：1.7 没有这个 API）。
  - 1.7 给每一行日志都带堆栈，普通消息也带，所以 1.7 上只看 `[LOGERROR]` 行下面的堆栈，否则模组自己的普通消息也会被当成错误。
- 自测框架 `SelfTestRunner`：只在命令行带自测参数时启用；进入地图后按顺序执行 `ISelfTestScenario`（协程，按帧推进，可以快进时间），每个场景输出 `PASS`、`FAIL <原因>` 或 `SKIP <原因>`，最后输出 `DONE passed=X failed=Y skipped=Z` 并退出游戏（`Root.Shutdown()`）。场景需要的东西（白银、小人、敌人、建筑）都由场景自己生成，清理登记在场景上下文里，结束时统一执行。
  - 由模组自己的 GameComponent 驱动（`GameComponentUpdate`、`GameComponentOnGUI`），1.6 和 1.7 走同一条路径。不要为自测单独建 GameComponent：游戏会把它存进每个存档，卸载模组后报找不到类型。
  - 每个场景有超时（默认 120 秒），超时记 FAIL，写明当时的 tick、速度、哪个窗口在强制暂停，然后接着跑下一个：一个卡住的场景不能拖垮整次测试。
  - 场景运行期间模组只要记了错误，这个场景就判失败，哪怕它自己的检查都过了：游戏会接住 tick 里的异常、只记一条日志，场景自己发现不了。
  - FAIL 用普通消息记，不用 Error：开发者模式下一条 Error 就会弹出调试日志窗口，挡住后面所有场景。
  - 窗口收不到 OnGUI 时（1.6 的隐藏窗口），绘制类场景记 SKIP，不能算通过。
  - 只往 `-savedatafolder` 指定的测试配置里写存档和截图，没带这个参数就拒绝运行。
- 开始时清空说书人的事件组件和事件队列，否则快进时随机事件（商队、资源舱）会干扰结果。
- 开始时关闭自动存档：模组按第五节「卸载模组时，如果某个小人正在做这个模组的工作」那条，在存档时结束本模组的工作以后，原版每次自动存档都会打断工作类场景；没有小人工作（JobDef）的模组不受影响。关法和数值上限也在那一条。
- 自测要改模组设置的，改之前先存一份，结束时放回，场景失败也要放回：设置存在测试配置里，不放回会影响后面的场景、截图和下一次运行。
- 开始时输出其他模组在本模组相关原版方法上打的 Harmony 补丁（`[DIAG]` 行），出问题时可以直接看出是谁拦截了。
- 开发计划里每一项要进游戏验证的内容，只要不涉及界面外观，都写成自测场景；这一项完成之前，要在 `-Profile vanilla` 下跑通，中英文都要跑。
- 依赖外部数据（网络等）的功能：交易、结算类场景用注入的模拟数据，结果可重复；另设单独的场景用真实数据只检查连通和格式，慢不算失败，只有请求和解析出错才算。解析代码再设一个场景（用命令行参数打开），在游戏里、de-DE 区域的线程上解析录好的样本：游戏运行时缺的编码、后台线程的区域设置，单元测试里测不出来。等网络、真实时钟相关的结果时按真实时间等（`Stopwatch`），不要数帧：帧率随机器和模组列表变化，1800 帧可能只有十几秒；等待的上限要比数据源失败后的重试间隔长（比如失败后隔一分钟重试，就等 90 秒）。

### 3. 存档安全（`Source\tools\run-savesafety.ps1`）

- 测试辅助模组 `Source\tools\TestLoaderMod\`（不随本模组发布，不需要 Harmony）：命令行带 `-<前缀>-loadsave=<存档名>` 时，在主菜单自动读该存档，最快速度跑 600 tick，另存为 `<存档名>-resaved`，按阶段（启动、读档、运行、存档）汇总日志里所有错误和异常，然后退出。脚本运行时把它临时复制进 Mods 目录，在 try/finally 里保证结束时删除。脚本被强行中断时它可能留在 Mods 里：启动前检查，有残留就停下来，让用户确认后删掉。
- 流程：
  1. 在 `vanilla` 下用 `-<前缀>-makesave=<名称>` 生成一个包含本模组全部数据的存档，日志输出数据统计。
  2. 在 `uninstalled` 下读这个存档：游戏要能正常运行并存档；读档阶段只允许出现预期中的"找不到类型或 Def"错误，逐条写进报告。
  3. 再读另存的存档：读档阶段 0 条错误，不再残留本模组的类型或 Def。
  4. 在 `reinstall` 下读第 1 步的存档，带 `-<前缀>-reportload`，数据统计和第 1 步完全一致。
  5. 中途加入：用从没装过本模组的存档，加入后读档，0 条本模组错误，功能马上可用。
- 有小人工作（JobDef）的模组，加一项「正在工作时卸载」，按严格标准判定（再存的档 0 错误），并检查存档文本里没有本模组的 JobDef、JobDriver、WorkGiver 名字（原因和做法见第五节「卸载模组时，如果某个小人正在做这个模组的工作」）。
- 新增了 `WorkTypeDef` 的模组，在 full 配置下量一次优先级错列：存档，卸载后读档，逐个比较每个工作类型的优先级，错开的写进报告和简介（原因见第五节「工作优先级」那条）。完整列表启动要十几分钟，测试辅助模组的超时也做成命令行参数，由脚本传进去。

### 4. 兼容性（`full` 配置）

- 用 full 配置的完整模组列表跑全部自测场景（列表从哪来见上面「总原则」）。完整列表启动可能要十几分钟，`-TimeoutSeconds` 给足（比如 3600）。有的模组在隐藏窗口下加载时会崩溃（1.6 上测到 DawnNewDay 在后台加载线程里访问 `Verse.Text`），所以 1.6、1.7 跑 full 都用 `-WindowStyle Normal`（可见窗口）。
- 场景失败就用 `-ExcludeMods` 逐个排除，找出原因。如果是其他模组本身的设计导致的（例如 Dont Hit Allies 取消了友军伤害），写明证据，不算本模组的 bug。完整列表里失败一串时，先找最早失败的那个（见第五节「一个自测场景中途抛异常」）。
- 本模组在加载顺序的最前、中间、最后各跑一次（脚本参数如 `-LoadPosition First|Middle|Last`，只改测试配置里复制的 ModsConfig）。
- 日志检查：带本模组前缀的错误必须为 0；其他模组自己的报错逐条记录来源。

### 5. 性能

- 自测里加性能场景：对本模组每帧或每 tick 运行的代码计时，原版和 full 两个配置的数据都写进报告。只在明显超标时判失败，避免机器慢误报。

### 6. 界面截图（`Source\tools\run-capture.ps1`）

- 在 1280×720 的可见窗口里启动游戏，自动打开模组的各个界面并截图，存到 `<Test>\shots\`，中英文各一套，脚本检查预期的截图文件都生成了且大小正常。agent 逐张检查布局有没有重叠、截断、错位，有问题就改了重新截。
- 截图用 Verse 的 `ScreenshotTaker.TakeNonSteamShot(名字)`（1.6、1.7 都有）：文件写进 `-savedatafolder` 下的 `Screenshots`，下一帧弹出「截图已保存」的消息，截下一张前先 `Messages.Clear()`。
- 截图前要等的东西（地图淡入、信件滑入、调试日志窗口）见第五节；怎样从截图里查出毛病见 `references\ui.md`。
- 创意工坊宣传图另设一个模式（比如 `-Promo`，1920×1080）：关掉教学助手、清掉测试信件，不出现正常游戏里不可能有的状态。

### 7. 长时间运行

- 有持续运行逻辑（后台线程、定时器、小人工作）的模组，在 full 配置下用最高速度跑几个游戏日，每个游戏日强制回收一次再记内存，检查内存不持续增长、日志无报错、数据前后一致。

## 五、踩过的坑

### 游戏机制

- 英文信件排版会把冒号后的首字母改成大写（"none: no payout" 变成 "No payout"），测试比对信件文本时要忽略大小写。
- Odyssey 的浅熔岩（`LavaShallow`）是临时地形，铺下时会毁掉地板；测试清理时要把原地形放回去。
- 游戏在格子上生成墙时会把站在上面的小人挤开。
- `Pawn.Kill` 之后，小人的 `Position` 仍是死亡所在格，地图要从尸体取（`MapHeld`）。
- 工作优先级按工作类型在 `DefDatabase` 里的序号存成列表（`DefMap.ExposeData`），不记名字；读档时只在末尾补齐或截断。新增 `WorkTypeDef` 的模组中途加入或卸载，会让加载顺序在它之后、也新增了工作类型的模组的优先级错开一列。原版机制，无法避免，只能在简介里说明。工作栏的列顺序由 `naturalPriority` 决定（原版研究是 100，最后一列）。
- 1.6 的 Mono 运行时没有 `I18N.CJK.dll`，`Encoding.GetEncoding(936)` 解不了 GBK；要处理 GBK 数据只能自带对照表。1.7（.NET 10）没实测，按 .NET 的常规行为，要先 `Encoding.RegisterProvider(CodePagesEncodingProvider.Instance)` 才能用 936；两个版本共用源码时，自带对照表最省事。
- 研究的智识经验是每 tick `0.1 × delta`（`JobDriver_Research`）。
- 1.6 起小人的工作按 tick 间隔推进（`Thing.DoTick` 每 `min(max(UpdateRateTicks, MinTickIntervalRate), MaxTickIntervalRate)` tick 调一次 `TickInterval(delta)`）：原版 `UpdateRateTicks` 在镜头里是缩放档位加 1、不在镜头里是 15，上限 15。玩家常装的 Slower Pawn Tick Rate 默认把未征召小人的 `UpdateRateTicks` 乘 10、把上限改成 60：装了它时，小人即使在镜头最近处 `UpdateRateTicks` 也是 10，不在镜头里的小人 60 tick 才动一次。自测里等工作进度、技能经验时要循环等到值变了（上限给 150 tick 左右），或按 `UpdateRateTicks` 算窗口，不要固定等几十 tick（只等 30 tick 的检查在装了它的完整列表里会偶发失败）。1.7 的测试配置不带它（见 `references\rimworld-1.7.md`「优化类模组」），但自测要经得起玩家的环境。
- 游戏在主线程（`Root`）和长事件线程（`LongEventHandler`）都强制把区域设成 en-US（`CultureInfoUtility.EnsureEnglish`），所以玩家 Windows 用逗号做小数点时，只有模组自己开的后台线程会受影响。测试"逗号区域"不要把主线程改成 de-DE 再存整个游戏：原版自己的世界数据会写成逗号、读档报一堆 `SaveableFromNode exception`。只单独存读模组数据，并让后台线程在 de-DE 下运行：在那个线程里显式设 `Thread.CurrentThread.CurrentCulture`。在启动线程前后临时改 `CultureInfo.DefaultThreadCurrentCulture`、又马上改回去不起作用：没有自己区域设置的线程，用到区域时读的是那一刻的默认值。
- RimWorld 的 Def 解析器不支持 `decimal`（`ParseHelper` 只注册到 double）。需要精确小数的 Def 字段用 double，代码里再转 decimal（保留 15 位有效数字）；不要自己全局注册 decimal 解析器，别的模组也注册的话会重复键报错。
- `Verse.Messages` 和 `RimWorld.TradeAction` 这类常见名字容易和模组自己的类重名，模组类避开这些名字。
- `Scribe_Values.Look` 存 `Rect` 存得进去读不回来：写出的是 `Rect.ToString()` 的 `(x:0.00, y:..)`，`ParseHelper.FromStringRect` 只认 `(x,y,w,h)`，读档报 FormatException。模组设置里的窗口位置要拆成四个 float 存。
- `pawn.health.forceDowned = true` 再反射调 `MakeDowned`，小人倒地只是一时的：`forceDowned` 只在倒地那一刻跳过「倒地即死」的判定，下一次 `CheckForStateChange` 发现 `ShouldBeDowned()` 为 false，健康的小人就站起来了（`Verse\Pawn_HealthTracker.cs`）。自测要观察倒地后的一段时间，就得在小人站起来时马上处理，比如征召，否则它会回去接着干活，把场景的状态搅乱。
- 卸载模组时，如果某个小人正在做这个模组的工作（存档里 `curJob` 是模组的 JobDef、`curDriver` 是模组的 JobDriver 类），读档后原版 `Pawn_JobTracker.ExposeData` 会尝试 `EndCurrentJob(Errored)` 清理，但 `curJob.def` 为 null，清理本身抛 NRE，这个小人从此每 tick 报错，再存档也带着。卸载后模组代码不再运行，所以要在**每次存档时**避免写出这种工作：在 GameComponent 的 `ExposeData` 里判断 `Scribe.mode == LoadSaveMode.Saving`，对所有地图的小人删掉队列里的本模组工作、`EndCurrentJob(InterruptForced, startNewJob: false)` 结束当前工作（`Game.ExposeData` 先写游戏组件、再写世界和地图，`Verse\Game.cs`，所以之后写出的小人已经干净；结束动作里的收尾，比如退还资源，也会落进随后写出的数据）。下一个 tick 小人自己重新接活。这样卸载后只剩原版对缺失类型和 Def 的一次性报错，存一次档就没了。副作用：自测期间原版自动存档会打断工作类场景，所以自测开始时关闭自动存档：用反射取 `Prefs` 的私有静态字段 `data`（`PrefsData`），直接写它的 `autosaveIntervalDays`（不走 `Prefs.AutosaveIntervalDays` 的 setter，它会调 `Prefs.Apply` 重设分辨率），值不能超过 35791 天——`AutosaveIntervalTicks` 是 int，溢出成负数后游戏每 tick 自动存档，换档时存到已释放的旧地图，报几百条 `Exception while saving Verse.FogGrid` 后卡死。
- 发电机本身就是传电的：自测里不要把电线铺在发电机下面（日志报 `Multiple nets on the same cell`），也不要把发电机生成在已有建筑上（`GenSpawn` 会把原来的东西清掉）。电器会接到 6 格内最近的传电体，可能接到一台孤立的发电机上形成单独的电网，要用电线把几台发电机连起来。
- `interactionCellOffset` 按建筑朝北时写，放置时随朝向旋转（`ThingUtility.InteractionCell`：`interactionOffset.RotatedBy(rot)`）。默认朝南放置（`defaultPlacingRot` 为 South）、贴图正面朝下的建筑，操作位要写 z 为正的偏移（原版通讯台 3×2，写的是 `(0,0,2)`；1×1 的写 `(0,0,1)`），写成负的，小人会站到建筑背后（屏幕上方那一侧）。
- Prepatcher 会把所有模组程序集打补丁后从内存重新加载，这时 `Assembly.Location` 是空字符串。要找模组自己的文件夹用 `ModContentPack.RootDir` 或模组的加载文件夹，不要靠 `Assembly.Location`。
- Steam 退订创意工坊模组时只删它发布的文件，模组运行后在自己文件夹里生成的东西连文件夹一起留下，而且从此不在 `appworkshop_294100.acf` 里（见过 5 GB 的 Python 虚拟环境，也见过游戏生成的 `Textures\*.dds.zstd` 贴图缓存）。所以「数据放模组文件夹里，退订就一起删掉」不成立；模组要往自己文件夹写大文件时，得给玩家一个清理按钮。找残留：`<Steam 库>\steamapps\workshop\content\294100` 下不在 acf 里的文件夹。
- 后台联网：
  - 1.6 上用 `HttpWebRequest`（游戏的 Mono 上要用它）；1.7 上 `HttpClient` 也行，但 `UnityWebRequest` 不能在后台线程用（见 `references\rimworld-1.7.md`）。
  - Mono 上 `HttpWebRequest` 的 `Timeout`、`ReadWriteTimeout` 只管单个步骤，域名解析、服务器一点一点往外吐数据时都不管，一个不返回的请求会一直卡住，拖住模组这一轮的数据更新。给整个请求设一个硬截止（比如超时的 2 倍）：用 `Timer` 到点时 `Abort()` 请求，同时 `Dispose()` 响应流（光 `Abort` 打断不了正在读的流）；响应流分块读，每块之间也检查截止。
  - 一直失败的请求只在开始失败时记一次日志：按数据来源记，同一来源任何一次请求成功就算恢复。按请求名记的话，换个名字的请求成功了也清不掉旧的失败记录，第二次断网时就一条日志都不记了。

### 自测框架和夹具

- 读档过程中 `Find.CurrentMap` 会抛 `ArgumentOutOfRangeException`（地图列表还是空的）。自测框架的 Update 里要先判断 `LongEventHandler.ShouldWaitForEvent` 和 `Current.Game.Maps.Count`，再取 `Find.CurrentMap`。
- 隐藏窗口（`-WindowStyle Hidden`）启动时游戏不派发 OnGUI，`UI.screenWidth/Height` 也可能是 0；1.6 上界面绘制类自测要用最小化窗口（最小化窗口照常派发 OnGUI；1.7 不同，见第四节「窗口」）。`Verse.Text` 的静态构造要求在 OnGUI 里，`new FloatMenuOption(...)` 也会触发它，所以构造菜单的检查也要放进 OnGUI 回调。
- 自测框架的协程如果 `yield return` 另一个 IEnumerator，框架要自己展开（用栈逐层 MoveNext），否则子协程根本不执行、测试假通过。
- 1.6 的最小化窗口偶尔报告屏幕接近 0（`UI.screenWidth/Height` 小于 100），这时打开的窗口按屏幕算出的大小会退回默认值。窗口恢复后 `WindowStack.AdjustWindowsIfResolutionChanged` 会调 `Notify_ResolutionChanged`，窗口重新排版，游戏里没问题；但自测要是在同一帧拿屏幕检查「窗口在屏幕内」，就会误报。屏幕尺寸无效时只检查退回的默认值。
- 地图载入后 `Root_Play` 有半秒从黑屏淡入（`ScreenFader.StartFade(Color.clear, 0.5f)`，按真实时间）。截图前先等 `ScreenFader.IsFading()` 变成 false（1.6、1.7 都是公开方法），否则第一张会是暗的。淡入期间 `Game.PlayerHasControl` 是 false，设 `TickManager.CurTimeSpeed` 会被悄悄忽略（1.6、1.7 都是），读档后马上调速的自测场景会一直按正常速度跑到超时。自测框架开始每个场景前、读档后都先等淡入结束，调速后检查是否真的改了。
- 测试要推进游戏时间时（例如存档安全的辅助模组读档后跑几百 tick），直接调 `Find.TickManager.DoSingleTick()`，每帧一批，不要设好速度等时钟自己走：淡入期间调速会被忽略（见上一条），模组弹出的强制暂停对话框会让时钟一直不走（见下一节「游戏一开始就处于暂停」那条）。实测：完整列表下靠调速推进的辅助模组卡满 900 秒超时，改成自己推进后通过（模板的 `TestLoader.cs` 就是这样做的）。
- 刚收到的信件要滑入右侧信件栏，约需 180 帧；截图前不等的话，信件标签会叠在一起。
- 开发者模式下任何模组一报错，调试日志窗口（`LudeonTK.EditWindow_Log`）就会自动弹出；完整模组列表启动时总有报错，截图会被它挡住。截图前先 `Find.WindowStack.TryRemove(typeof(LudeonTK.EditWindow_Log), false)`。
- 1.6 上，测试配置 `Config\Prefs.xml` 里的 `screenWidth/screenHeight` 优先于命令行 `-screen-width/-screen-height`，要换截图分辨率得改 Prefs.xml（1.7 没有 `-screen-width`，窗口大小也看 Prefs.xml，见 `references\rimworld-1.7.md`）。
- 自测随机生成的殖民者可能带「懦夫」：休克疼痛阈值 0.8 − 0.5 = 0.3，而新鲜断臂的疼痛就有 30 × 0.0125 = 0.375，截肢当场倒地。`HealthUtility.DamageUntilDowned` 遇到已经倒地的小人直接返回。需要小人受伤后还站着的场景，先去掉懦夫特性（`TraitDefOf.Wimp`），并在受伤后断言没倒地，让失败原因一目了然。
- 一个自测场景中途抛异常，会留下半截状态（例如一笔还没结算的业务），之后在别的场景的观察时间里结算，让按物品数量判断的场景跟着失败。完整列表里失败一串时，先找最早失败的那个，排除引起它的模组后再看剩下的还在不在。
- 自测夹具找空地不要只在地图中心附近找：随机地图可能是山地或满是遗迹，要在全图按离中心的距离找。生成的小人直接放进夹具清理过的区域（随机放的小人可能被水或岩石和空地隔开）；失败信息列出每一项检查的结果，偶发失败才查得出原因。
- 长时间运行的自测里，测试小人在户外待几天会冻死、中暑或被野兽攻击，要每帧清掉负面状态并在小人死亡时直接报原因。
- 自测里替换模组的数据条目之前，先走正常流程结束它（例如先结束工作、让收工动作退还资源），直接覆盖会悄悄丢掉里面的东西，守恒类检查会报错。
- `Verse.Log` 记满 10000 条就停止写日志（`Reached max messages limit. Stopping logging to avoid spam.`，1.6 和 1.7 都是）。完整列表里有模组每帧报错时很快就会刷满，之后自测的 PASS/FAIL/DONE 都写不进日志，脚本只能报「游戏在测试完成前退出」。自测运行器每帧检查私有静态字段 `reachedMaxMessagesLimit`（反射），为 true 就调用公开的 `Log.ResetMessageCount()`，只在自测模式下这样做；再加一个场景，把这个字段设成 true，检查一帧后日志重新打开。
- 自测脚本等待结果时，要先查游戏进程是否退出、再读日志判定；反过来的话，游戏在两次检查之间写完 DONE 并退出，会误报「Game exited before … completed」。
- 自测在 OnGUI 回调里画一个已经打开的窗口后，游戏在同一帧还会用自己的窗口栈再画一遍这个窗口。判断「这一次画了什么」的状态（例如用没用缓存）必须在绘制回调里读，等下一帧再读，拿到的就是游戏那一次的结果。

### 测试环境和其他模组

- 完整列表的英文截图里，底部主菜单栏（连本模组的按钮）显示成中文，不一定是模组的翻译问题：UI Not Included（2588873455）把每个按钮的文字存进自己的设置（测试配置 `Config\Mod_2588873455_UINI_Mod.xml` 里的 `ButtonConfig.label`），设置是中文运行时写的，换语言后照旧显示存下的文字。核对按钮的英文名看原版配置的截图。
- 用户说新开的地图没有小人、界面大量报错时，先只读地看用户的 `Player.log`，查是不是 Steam 正在更新创意工坊模组：新文件已经下到 `<Steam 库>\steamapps\workshop\downloads\294100\<id>` 还没装上，旧文件已经删了一部分。见过的一例：某个种族模组的定义文件先被删掉，种族没了，它的 PawnKindDef 的 race 为空，原版 `ScenPart_StartingAnimal.PossibleAnimals` 里 `td.RaceProps` 报 NRE，整个开局生成中断，所以没有殖民者；研究窗口 `LabelSuffixForUnlocked` 同样因此报错。判断方法：`<Steam 库>\steamapps\workshop\appworkshop_294100.acf` 里已装的 manifest 和最新的不同、downloads 里有这个 id。处理：关掉游戏让 Steam 装完更新（或在 Steam 里验证、重新订阅那个模组）。
- 开新档缺阵营（例如自测报 "Core mechanoid kind or faction is missing"）：先查日志里的 `Error in WorldGenStep`。某个阵营的 `allowedCultures` 引用了不存在的文化时，`IdeoFoundation.RandomizePlace` 因 `ideo.culture` 为空抛 NRE，`WorldGenStep_Factions` 中断，排在后面的阵营全都不生成。见过的一例：RatKin Extraordinary clique（`RatKin.Extraordinary.Mechanic.clique`）引用了 NewRatkinPlus 里已经没有的 `RatkiniaTraditionCulture`，1.6、1.7 都会这样，测试时排除它。
- **游戏一开始就处于暂停要当成常态来设计。** 很多模组和游戏情况都会让游戏暂停：模组弹出的强制暂停对话框（见下一条）、原版选项「读档后暂停」（`Prefs.PauseOnLoad`）、信件和教程、长事件、选地块、引力船过场。原版 `TickManager.Paused` 已经把这些都算进去：`curTimeSpeed == Paused`，或 `ForcePaused`（`WindowStack.WindowsForcePause`、`LongEventHandler.ForcePause`、`TilePicker.Active`、引力船过场，`Verse\TickManager.cs`）。做法：模组里按时间判断的逻辑（超时、冷却、看门狗）只累计 `!Find.TickManager.Paused` 的时间，不用墙钟；自测运行器在第一个场景前和每个场景前主动让游戏走起来：关掉不是自测自己开的 `forcePause` 窗口（`Find.WindowStack.TryRemove(w, false)`，Esc 关不掉的也能关，每关一个记一行 `[DIAG]`），把速度设成正常，并等到 `TicksGame` 真的变了；等不到就判失败，写明还被什么暂停着。模板里有现成的实现：`SelfTestRunner.GameRuns`、`CloseForeignPauses`，场景自己的窗口用 `ctx.Open` 打开就不会被关；内置场景「the game runs before each scenario」检查它。
- 全新的 full 测试配置上第一次跑自测，依赖游戏时间的场景全部失败（「1 秒走了 0 tick」「The game is paused」，速度设置却是正常）：Milira Imperium（`ariandel.miliraimperium`，3588393755）第一次进档时弹「模组设置引导」对话框（AriandelLibrary 的 `Dialog`，`forcePause` 默认 true，不能用 Esc 关），弹完把设置写成不再弹，所以第二次起就正常。办法：照上一条在自测开始时关掉强制暂停的窗口，或者先跑一次让它弹过，或者排除它。用二分找这类元凶时，要么每次都从全新配置开始，要么都不是，混着比会被「第一次运行」的差别误导。

### 构建和工具

- `dotnet build` 偶尔卡住不动（编译服务器挂起）：`dotnet build-server shutdown` 后重试；构建命令加 `timeout`，不要把提交接在一个可能失败的构建后面用 `;` 连接。
- 用户的游戏开着时，游戏锁住 Mods 里模组的 dll，构建时的同步（robocopy /MIR）会一直重试，直到命令被超时杀掉（robocopy 默认重试一百万次、每次等 30 秒，等于卡死；同步脚本最好用 `/R:`、`/W:` 设个上限）。构建前先 `tasklist | grep -i rimworld`；游戏开着就只编译（`-p:SkipSync=true`）、跑单元测试、提交，等用户关游戏后再同步和跑游戏内测试。
- agent 通过工具执行的命令，反斜杠可能在交给 bash 之前就少了一层：命令里连写的两个反斜杠，到 bash 那里只剩一个，和后面跟什么字符无关，单引号和 `<<'EOF'` 里也一样（直接在 Git Bash 里敲不会这样，是 agent 发命令时多处理了一层转义）。用 heredoc 写内联 Python 时最容易出事：`'\\r'` 到 Python 变成回车，`'\\b'` 变成退格（0x08），`'\\1'` 变成 0x01；`\t`、`\f`、`\n` 同理，`Source\tools` 会变成制表符加 `ools`，`MyModTest\full` 会变成换页符加 `ull`。写含 Windows 路径或正则的内容时，用原始字符串加单反斜杠（`r'D:\Dev\x'`、`rb'...'`），或者直接用 agent 的文件编辑工具；改完用 `cat -A` 或按字节检查有没有控制字符。很长的 heredoc 内联 Python 也会被截断（报 `here-document ... delimited by end-of-file`），带撇号的长脚本有时还被 bash 报引号不配对，长脚本先写成 .py 文件再运行。
- agent 用工具写文件时，内容里的 `\uXXXX` 转义有时会被直接写成那个字符本身（实测：`'\u9FFF'` 落盘成字符「鿿」，触发了「界面代码不许有中文」的测试；写文件和改文件的工具都碰到过；和上一条是同一个原因，工具参数多处理了一层转义）。源码里需要码位时写数值（`c >= 0x2E80 && c <= 0x9FFF`），写完按字节检查有没有意外的非 ASCII 字符。
- Git Bash 的 grep 数不出回车：`grep -c $'\r$'` 对 LF 文件也报每行都以 CR 结尾。查换行符按字节数（Python `data.count(b'\r\n')`）。仓库开着 `core.autocrlf=true` 时，工具写出的 .cs 可能是 LF，git 不显示差异；Git Bash 的 `sed -i` 也会写成 LF。批量改文件时沿用每个文件原来的换行符，不要从另一份检出里整个拷过来。
- 几个会话或子代理同时改同一个仓库时：动手前后都看 `git status`，不是自己改的文件不碰；提交只加自己的文件（`git add -- <文件>`、`git commit -- <文件>`），不用 `git add -A`、`commit -a`。编译和单元测试放到从 HEAD 导出的副本里做：先建好副本目录，`git archive HEAD | tar -x -C <副本目录>`（或者开一个临时 worktree），再把自己还没提交的改动复制进去；构建加 `-p:SkipSync=true --disable-build-servers`，不用关别人在用的编译服务器。这样验证的正好是要提交的内容，也不会把别人没改完的代码编进仓库的 dll。验证完把同样的改动写回主仓库再提交。游戏内测试由一个会话统一跑（游戏读的是 Steam 模组文件夹，只能由主仓库同步）；dll 也由这个会话统一编译、提交，不再用的语言键由它统一删，其他会话只追加。
