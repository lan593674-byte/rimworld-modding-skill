# 模板：带全套测试的最小模组

`MyMod\` 是一个能直接编译、能直接跑测试的最小模组仓库，SKILL.md 第四节「测试流程」里说的脚本、自测框架和测试辅助模组都在里面。新模组从它开始：复制、改名、填配置，然后把示例场景换成自己的。

## 用法

1. 把 `MyMod` 复制到 `<开发目录>\<模组名>\repo`。测试脚本把仓库的上一级当作模组主文件夹，测试数据放它下面的 `test`；再上一级是开发目录，`ModLists`、`GameRefs`、`player-log-backup` 放在开发目录的 `_shared` 里，所有模组共用。
2. 改名：文件夹 `Source\MyMod`、`Source\MyMod.Tests`，文件 `MyMod.csproj`、`MyModMod.cs`、`MyModGameComponent.cs`、`MyMod.Tests.csproj`、`Languages\*\Keyed\MyMod.xml`，以及所有文件里的 `MyMod`、`mymod`、`yourname`（命名空间、程序集名、语言键前缀、packageId、Harmony ID）。`GameTestLoader` 和 `gametest.testloader` 不改，所有模组共用。
3. 改 `Source\tools\GameTest.psd1`：模组名、packageId、日志前缀、命令行前缀、Def 前缀、依赖、发布目录。日志前缀要和 `ModLog.Prefix` 一样，命令行前缀要和 `SelfTestSetup.ArgPrefix` 一样，单元测试 `TestSettingsMatchTheCode` 会检查。
4. 改 `About\About.xml`。不用 Harmony 的模组：删掉 `About.xml` 里的依赖、`GameTest.psd1` 的 `Dependencies` 里的 Harmony、csproj 里两处 Harmony 引用和 `UsesHarmony`、`MyModMod.cs` 里的 `PatchAll`、`SelfTestSetup.DiagnosticTargets` 里的 `AccessTools`（改成反射找方法）。
5. 装了 1.7 测试版时运行一次 `Source\tools\save-game-refs.ps1`，按它的提示把版本号填进 `Source\GameRefs.props`。1.6 版不需要这一步，编译用的是 NuGet 包。
6. 编译：`dotnet build Source\MyMod\MyMod.csproj -c Release`。一次编出 `1.6\Assemblies` 和 `1.7\Assemblies` 两份 dll，编完自动同步到游戏的 Mods 文件夹。游戏开着时加 `-p:SkipSync=true`。

## 命令

| 做什么 | 命令 |
|---|---|
| 单元测试 | `dotnet test Source\MyMod.Tests` |
| 同步到游戏 | `powershell -NoProfile -ExecutionPolicy Bypass -File Source\tools\sync-to-steam.ps1` |
| 冒烟测试 | `... -File Source\tools\run-selftest.ps1 -Mode Smoke` |
| 游戏内自测 | `... -File Source\tools\run-selftest.ps1 -Profile vanilla -Language ChineseSimplified`（English 再跑一次；`-Profile core`、`-Profile full` 同理） |
| 兼容性 | `... -File Source\tools\run-selftest.ps1 -Profile full -ModList <列表>`，加 `-LoadPosition First/Middle/Last`、`-ExcludeMods a,b` |
| 截图 | `... -File Source\tools\run-capture.ps1 -Language ChineseSimplified` |
| 存档安全 | `... -File Source\tools\run-savesafety.ps1`；新增了工作类型的模组再加 `-WorkPriorities` 跑一次 |

脚本都会先拿跨模组的测试锁，别的会话正在跑游戏时会等它跑完（最多 90 分钟）。退出码 0 才算通过。

## 文件

| 文件 | 内容 |
|---|---|
| `Source\tools\GameTest.psd1` | 测试脚本唯一的配置文件。其他脚本不写模组名，可以原样复制给下一个模组 |
| `Source\tools\GameRuntime.ps1` | 各脚本共用：读配置、找游戏（注册表加 `libraryfolders.vdf`）、测试锁（可重入，清理被杀掉的上次运行留下的游戏）、1.7 日志的备份和还原、日志判定（带超时）、启动和等待游戏、测试配置（vanilla、core、full） |
| `Source\tools\sync-to-steam.ps1` | 同步发布文件。检查每个版本文件夹只有本次构建的 dll、两份 dll 的源码指纹相同；robocopy 只重试两次；保留模组运行时写的数据目录 |
| `Source\tools\run-selftest.ps1`、`run-capture.ps1`、`run-savesafety.ps1` | 游戏内自测、截图、存档安全 |
| `Source\tools\save-game-refs.ps1` | 把 1.7 的游戏程序集复制到 `<开发目录>\_shared\GameRefs` |
| `Source\tools\exclude-1.7.txt`、`exclude-full.txt` | full 配置要去掉的模组：1.7 上的优化类模组，以及会把游戏搞坏的模组 |
| `Source\tools\TestLoaderMod\` | 存档安全用的测试辅助模组（不发布）：读档、跑几百 tick、另存，按阶段汇总错误；两个游戏版本各编一份 |
| `Source\GameRefs.props`、`Source\SourceHash.targets` | 1.7 引用程序集的位置；源码指纹（嵌进 dll，启动日志打印，脚本据此确认游戏加载的是这次的构建） |
| `Source\MyMod\Engine\Engine.Unity.cs`、`Engine.Waylith.cs` | 引擎适配层：1.6 和 1.7 只有这两个文件不同 |
| `Source\MyMod\SelfTest\` | 自测框架。`SelfTestSetup.cs` 是唯一需要按模组改的文件（场景清单、截图清单、[DIAG] 目标、存档夹具），`ExampleScenarios.cs` 是示例，其余通用 |
| `Source\MyMod.Tests\` | 不用开游戏的检查：各语言的键一致、代码用到的键都存在、代码里没有中文字面量、配置和代码里的前缀一致 |

## 自测框架的约定

- 自测由模组自己的 GameComponent 驱动（`GameComponentUpdate`、`GameComponentOnGUI`），1.6 和 1.7 走同一条路径。不要为自测单独建 GameComponent：游戏会把它存进每个存档，卸载模组后报找不到类型。
- 游戏一开始就暂停是常态（读档后暂停的设置、模组首次运行弹出的强制暂停窗口、事件窗口）。所以每个场景开始前，运行器先关掉不是自测打开的 `forcePause` 窗口（`TryRemove`，Esc 关不掉的也关得掉，每关一个记一行 `[DIAG]`），把速度设成正常，等 `TicksGame` 真的变了才开始；15 秒内没变就判这个场景 FAIL，写明还被什么暂停着。场景自己要开的窗口用 `ctx.Open` 打开，运行器不会关它，场景结束时自动关掉。场景开始时游戏是在以正常速度运行的，要暂停就自己设。
- 每个场景有超时（默认 120 秒），超时就记 FAIL，并写明当时的 tick、速度、哪个窗口在强制暂停，然后接着跑下一个场景。
- 场景结束时，不管通过、失败、跳过还是超时，`ctx.Defer` 登记的清理都会执行，排队的绘制会清掉，游戏也会暂停。
- 场景运行期间，模组只要记了错误（带前缀的日志，或者堆栈经过模组代码），这个场景就判失败，哪怕它自己的检查都过了。游戏会接住 tick 里的异常，只记一条日志，所以要这样查。
- 窗口收不到 OnGUI 时（1.6 的隐藏窗口），绘制类场景记 SKIP，不会算成通过。DONE 行写成 `passed=X failed=Y skipped=Z`。
- FAIL 用普通消息记，不用 Error：开发者模式下记一条 Error 就会弹出调试日志窗口，挡住后面所有场景。
- 自测只往 `-savedatafolder` 指定的测试配置里写文件（存档、截图），没带这个参数就拒绝运行。
- 退出：1.7 上会设退出码；`Root.Shutdown` 没让游戏退出时，10 秒后强制退出。
