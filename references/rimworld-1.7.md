# 1.7 测试版（Waylith 引擎）

模组要支持 1.7，或者要在 1.7 上编译、测试时读。1.7 测试版 2026-10-12 公布，在 Steam 的 beta 分支 `unstable` 上，正式分支仍是 1.6。下面的内容实测到 1.7.4979 rev109；测试版随时会更新，判断前先看当前版本的反编译源码（更新以后怎么做见最后一节）。

## 基本情况

- 官方说法：模组一般不用改；1.6 和 1.7 的存档互通。所以模组要同时支持两个版本：`supportedVersions` 写上 1.6 和 1.7，按 SKILL.md 第一节各建一个版本文件夹。
- 针对 1.6 编译的 dll 在 1.7 上也能直接加载（`UnityEngine*` 被重定向到 `UnityStubs`）。但按下面的推荐做法，`1.7` 文件夹放针对 1.7 编译的 dll，不借用 1.6 的构建。
- 选加载目录：模组没有 `v1.7` 条目或 `1.7` 文件夹时，1.7 取不高于当前版本的最高版本条目（通常是 v1.6，见 `Verse\ModContentPack.cs`）。不要依赖这一点。
- 安装目录变了：没有 `RimWorldWin64.exe` 和 `RimWorldWin64_Data`；exe 是 `RimWorld.exe`，`Assembly-CSharp.dll` 直接在游戏根目录，运行时是 Ludeon 自改的 .NET 10（`10.0.10-waylithclr`）。`RimWorld.runtimeconfig.json` 把 `UnityEngine*` 重定向到 `UnityStubs.dll`，所以对 1.6 编译的模组照样加载。
- 反编译：游戏本身是 `<游戏目录>\Assembly-CSharp.dll`，引擎是游戏根目录的 `RimWorld.dll`、`Waylith.dll`、`UnityStubs.dll`、`Waylith.UnityCompat.dll`，全部约 30 秒。在 Git Bash 里这样跑：

  ```bash
  G=<游戏目录，用正斜杠>; O=<开发目录，用正斜杠>/RimWorld-decompiled-1.7
  ilspycmd -p -o "$O" "$G/Assembly-CSharp.dll"
  for n in RimWorld Waylith UnityStubs Waylith.UnityCompat; do ilspycmd -p -o "$O/_engine/$n" "$G/$n.dll"; done
  ```

  下文的 `_engine\...` 路径都指这里。路径里一律用正斜杠：agent 发命令时反斜杠可能少一层（见 SKILL.md 第五节「构建和工具」），`$n` 前面的反斜杠会把它转义掉，四个引擎 dll 都报找不到文件。反编译完数一下输出文件夹里的 .cs 文件数，和上一版比对，确认每个 dll 都出来了。
- 编译 1.6 版不再引用本机游戏：用 NuGet 包 `Krafs.Rimworld.Ref`（版本 1.6.4871，`ExcludeAssets="runtime"`），本机装哪个分支都能编 1.6 的 dll。

## 推荐做法：1.7 版不拿 Unity 开发

**1.7 及以后的版本不拿 Unity 开发，用原生的 Waylith 开发。** 原因是 Ludeon 以后可能删掉 Unity 转译层（`UnityStubs`、`Waylith.UnityCompat`）。这不是说一个 Unity 类型都不许出现：

- 1.7 版对 1.7 的游戏程序集编译（`Assembly-CSharp.dll`、`Waylith.dll`、`UnityStubs.dll` 等，net10.0），不借 1.6 的 Unity 参考程序集和运行时重定向；游戏接口参数里带的 `Rect`、`Color`、`TextAnchor` 等照常用；模组自己要直接碰引擎的地方用 Waylith 原生接口（见下一节）。
- 两个版本都要测；什么时候停止支持 1.6，由用户决定。
- **接口优先顺序**：在 1.7 上，模组自己要做的事按这个顺序选接口，能不用 Unity 就不用。
  1. Waylith 原生接口（`_engine\Waylith` 里的 `Waylith.Rendering`、`Waylith.Input`、`Waylith.Logging` 等）。
  2. Ludeon 1.7 自己的接口（例如下面说的 `UnityStubs.Gui.IGuiBackend`），以及游戏自带的 Verse 接口（`Widgets`、`Text`、`GenUI`、`UI` 等）。
  3. 以上都做不到时才用 Unity 的接口（UnityStubs 模拟的 `UnityEngine` 功能），用了要在代码注释和文档里写明为什么换不了。
  - 不碰引擎的事（计时、数学），直接用 .NET 自带的 `Stopwatch`、`System.Math`，两个版本共用。把 `Mathf` 换掉时，取整规则要和 Unity 一致（`Mathf.Round`、`RoundToInt` 遇到 .5 取偶数），写单元测试对照。
  - 和引擎打交道的调用集中放在一个薄的适配层里，以后换引擎只改这一处。
  - 常见的换不了、只能保留的 Unity 用量：输入框和焦点（Verse 自己的输入框也这样做）、`GUI.color`、`Event.current`、标签 `GUIStyle` 的文字测量、游戏接口自带的 `Rect`、`Color` 和贴图类型、`RenderTexture`（`PortraitsCache.Get` 的返回值）、`Material`（`GenUI.DrawTextureWithMaterial` 的参数）。
- 现状（1.7.4977 rev1248）：游戏自己的 Assembly-CSharp 仍有 2149 个文件用 `UnityEngine`（经 UnityStubs 转译；这是 `RimWorld`、`Verse` 两个文件夹的数，整个 Assembly-CSharp 是 2534 个），直接用 Waylith 的有 28 个，其中 16 个是 1.7 新加的帧分析器 `Verse.ProfilerUI`，其余是 `GenTexture`、`GenCommandLine`、`GlobalTextureAtlasManager`、`LoadedModManager`、`Log`、`ParseHelper`、`PlayDataLoader`、`ShaderDef`、`ShaderDefRegistry`、`ShaderWarmup`、`StaticTextureAtlas`、`Workshop`。所以模组只要调用 Verse，就离不开 `Rect`、`Color`、`GUI` 这些 Unity 类型。等 Ludeon 把 Verse 迁到 Waylith 上，模组跟着改。

## Waylith 和 1.7 的界面

- Waylith 本身没有 2D 界面接口（查的是 1.7.4977 rev1248 的反编译）：`Waylith.dll` 里只有三维渲染、贴图、着色器、网格、输入、日志这些，连 Brutal.ImGui 都不引用。1.7 的界面是这样一条链：UnityStubs 模拟 Unity 的 `GUI`、`GL`，交给公开接口 `UnityStubs.Gui.IGuiBackend`（静态单例 `GuiBackend.Current`，`-Headless` 时为 null）；宿主 RimWorld.dll 里 internal 的 `RimWorldWaylith.Imgui.ImGuiGuiBackend` 实现它，再调 Brutal.ImGui（ImGui 1.92），最后到 Vulkan。
  - Ludeon 在 1.7 新写的帧分析器界面直接调 `GuiBackend.Current` 的 `FillRect`、`DrawTextureQuad`（贴图传 null 就是实心四边形）、`DrawText`、`MeasureText`、`PushClipRect`，用 `Event.current.type` 是不是 Repaint 把关；同时照样用 `GUI.BeginGroup` 和 `Input.GetMouseButton`。这是官方唯一的 1.7 原生 2D 绘制样板。`IGuiBackend` 还有 `FillRectRounded`、`DrawPrimitives`（顶点 `GuiVertex`：位置、UV、Color32），用 GUI 局部坐标，后端自己套 `GUI.matrix`、分组偏移、裁剪和像素取整，不在 Repaint 时不画。它也在转译层里，从 1.7.4976 到 1.7.4977 rev1248 加过一个成员（`SetTextLanguage`），只调用不实现就不受影响。
  - 文本框、焦点（`GUI.TextField`、`SetNextControlName`、`GetNameOfFocusedControl`）、`GUI.BeginGroup`、画贴图都只有 UnityStubs 这一层，Waylith 里没有替代，Verse 自己也靠它们。截屏 Waylith 里也没有，用 Verse 的 `ScreenshotTaker.TakeNonSteamShot`（见 SKILL.md 第四节「界面截图」）。1.7 上 `Shader.Find`、`Material` 对界面里的 GL 不起作用（GL 只读材质的 mainTexture）；界面贴图的采样器固定是 Linear 加 ClampToEdge，`filterMode`、`wrapMode` 不起作用。
  - Waylith 里模组能直接用的：
    - `Waylith.Logging.LogStream.MessageReceived`：日志回调，在打日志的线程上同步调用，要写成线程安全；编译要引用游戏目录的 `Microsoft.Extensions.Logging.Abstractions.dll`；有监听者时每条日志都带堆栈，所以 1.7 不需要 `SetStackTraceLogType`。
    - `Waylith.Input.InputState.IsMouseButtonDown`：主线程读。
    - `Waylith.Rendering.Texture2D`：能建，但界面画不了：GUI 只收 `UnityEngine.Texture`，包装它的构造是 internal；游戏自己是先建 `UnityEngine.Texture2D`，再用它的 `.CoreTexture`、`.GpuTexture` 做原生操作。
  - 不属于 Waylith、但在 1.7 上也常用的：计时直接用 .NET 的 `System.Diagnostics.Stopwatch`，两个版本通用；1.7.4977 rev1248 起 UnityStubs 的 `Input.compositionString` 返回输入法组合串（`ImeComposition.Text`），直接读这个属性，不用再反射。
  - 直接调 Brutal.ImGui 的 draw list 可以绕开转译层画线和多边形，但不建议用：
    - 它是宿主的实现细节，宿主说换就能换；
    - 画不了贴图；
    - 坐标是物理像素，裁剪和分组偏移要自己对；
    - 只能在 Repaint 里、`RenderTexture.active == null` 时用。
  - 有几个 Verse 包装和直接调 Unity 完全等价（1.6、1.7 的 Verse 都是原样转调，已核对反编译）：`GUI.BeginGroup`/`EndGroup` 换 `Widgets.BeginGroup`/`EndGroup`（多一步 Steam Deck 鼠标修正）；`GUI.DrawTexture`、`DrawTextureWithTexCoords` 换 `GenUI.DrawTextureWithMaterial(rect, tex, null[, uv])`；`GUI.FocusControl(null)` 换 `UI.UnfocusCurrentControl()`，按名字给焦点换 `UI.FocusControl(name, window)`（多通知一次窗口栈）；自测里 Unity 的日志回调可以换成数 Verse 的 `Log.Messages`（要算上重复次数）。
- 每帧回调用 `Waylith.EngineApplication.Instance.PrePollEvents += app => ...`，不用 MonoBehaviour：它在主线程上每帧调一次，在读输入和游戏更新之前（`EngineApplication.cs` 的主循环）。`Waylith.Input.InputState` 的鼠标键状态和 UnityStubs 的 `Mouse` 来自同一组 GLFW 窗口事件：Waylith 的 `GlfwInputSource` 总是由 `EngineApplication` 创建，窗口失焦时两边都清零。所以 `InputState.IsMouseButtonDown(MouseButton.Left)` 可以直接替换 `Input.GetMouseButton(0)`。
- 帧回调和退出回调的两个细节（核对的是 1.7.4977 rev1248 的 `_engine\Waylith\Waylith\EngineApplication.cs`）：`PrePollEvents` 由主循环直接调用（`:491`，无窗口时 `:690`），外面没有专门接回调异常的 try/catch，回调里要自己接住异常、同一位置只报一次；`OnShutdown` 是公开字段，不是事件（`:94`，退出时在 try 里调用，`:843`），只能 `+=`、`-=`，写成 `=` 会把别人挂的回调冲掉。
- `GuiBackend.Current` 可能为 null（`-Headless`、窗口建好之前的几帧）：每次用之前取一次，为 null 就退回 Verse 的画法或者不画。自测用一个作用域临时把它设成 null，测这条路不抛异常。
- `IGuiBackend.DrawPrimitives(mode, 顶点, 贴图, screenSpace)` 的实测要点（`_engine\RimWorld\RimWorldWaylith.Imgui\ImGuiGuiBackend.cs:568-651`，mode 的数值见 UnityStubs 的 `GL.cs`）：
  - mode 用 UnityStubs 的 GL 常数：1 线段、4 三角形、7 四边形。线段走 ImGui 带抗锯齿的 `AddLine`，颜色取每段第二个顶点的；三角形每三个顶点一个，四边形每四个顶点拆两个三角形，都不抗锯齿。每个顶点自带颜色，不乘 `GUI.color`。
  - 贴图传 null 时 uv 取字体图集的白像素，画出来就是纯色。
  - `screenSpace=false` 时坐标是当前分组里的 UI 单位：后端先加分组偏移（分组原点对齐到整个设备像素），再乘 `GUI.matrix`（界面缩放），按分组裁剪。要落在整像素上，坐标取 k / `Prefs.UIScale`，不要自己再乘一次缩放。
  - 只在 Repaint 时画，其余事件直接返回。
  - 开销（实测）：500 根 K 线每帧交约 1.6 万个顶点，一半是线段，0.2～0.37 ms；一个窗口一帧约 70 个圆角形状、每个约 260 个顶点，算几何约 0.24 ms，交给后端约 0.3 ms。比画好一张贴图、每帧贴一次慢，但还在预算内；要省就缓存几何、把线段换成四边形。
- 用三角形自己画抗锯齿的圆角、描边、阴影，代替运行时生成的遮罩贴图（几何计算放进 Core，可以做单元测试）：
  - 透明度按像素中心到形状边的距离算（`clamp01(R + 0.5 − d)`，弧边外有一像素宽的渐隐带），直边落在整像素上，和 1.6 的遮罩逐像素对得上。
  - 判断一条边要不要切块，按像素比（`(hi − lo − 2c) × 缩放 > 0.5`）。直接比 float 的话，对齐后宽高差一个 ulp 就会把一个圆点分成两半，中间留一条压在像素中心上的缝。
  - 单元测试照 1.6 的画法（九宫格切片配遮罩字节）算期望图，逐像素比；另用半透明颜色画一遍，查有没有缝、有没有叠画两次（不透明时这两种错都看不出来）。
- 1.7 上用 `GL.LINES` 画的 1 像素线颜色不准：同样颜色的网格线，1.6 上画出来颜色准确；1.7 上随线的小数位置忽深忽浅，有的比背景还暗，网格线淡得几乎看不见（rev926、rev1248 都一样）。原因：1.7 的 `GL.Begin(GL.LINES)`（还有 `GL.LINE_STRIP`）走 `ImGuiGuiBackend.DrawPrimitives`，交给 ImGui 带抗锯齿的 `drawList.AddLine`，线落在两行像素之间时摊到两行、颜色随亚像素位置变；`GL.QUADS` 走 `PrimReserve`/`PrimVertex`，不抗锯齿。修法：横线、竖线（网格、边框、零轴、虚线）改画对齐整像素的 1 像素矩形（GL.QUADS 或 `Widgets.DrawBoxSolid`），坐标乘 `Prefs.UIScale` 换成设备像素后向下取整、再除回去，斜线照旧用 GL 线。注意分批画时的先后：如果先画全部矩形、再画全部线，网格从线改成矩形以后，就从压在别的线条（比如价格折线、K 线影线）上面，变成了垫在它们下面。
- 声音：1.7 上 `AudioClip.Create` + `SetData` + `AudioSource` 能出声（UnityStubs 转到 miniaudio，`_engine\UnityStubs\UnityEngine\AudioClip.cs:240-295`），但 `AudioClip` 不是 `IDisposable`，`Object.Destroy` 只释放 `IDisposable` 的对象（`_engine\UnityStubs\UnityEngine\Object.cs:76-103`），每建一个 clip 就永久占一块原生内存。动态生成的声音（语音合成等）直接用 Waylith：`Waylith.Audio.AudioBackend.Current.LoadSoundFromPcm16(...)` 或 `LoadSoundFromMemory(...)`（能解 WAV/MP3/FLAC/Ogg）、`Play(sound, null, paused: false, autoRelease: true)`、`IAudioVoice.SetVolume/IsPlaying/Stop`、用完 `IAudioSound.Release()`；流式用 `CreateStreamSound(channels, rate, lengthFrames, IAudioStreamSource)`（`_engine\Waylith\Waylith.Audio.MiniAudio\MiniAudioBackend.cs:490-544`，后端 48 kHz 立体声）。游戏主音量 `AudioListener.volume` 设的是后端主音量，对这些声音同样生效。
- `Application.quitting` 只在「退出到系统」（`Root.cs:195` 调 `Application.Quit()`）时触发；点窗口的叉、Alt+F4、崩溃都不触发（`EngineApplication.cs:677, 830-856`），`OnApplicationQuit` 从不派发。`AppDomain.ProcessExit` 会触发（`RimWorldWaylith\Program.cs:46` 调 `Environment.Exit`）。模组启动了子进程的，要在启动后马上把它放进 Windows 作业对象（`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`），游戏怎么死子进程都跟着死；和子进程通信走标准输入输出管道，不开端口。靠 `Application.quitting` 关子进程的模组，在 1.7 上关窗口就会留下残余进程。
- `UnityWebRequest` 不能在后台线程用：它把自己加进一个没加锁的静态列表（`_engine\UnityStubs\UnityEngine.Networking\UnityWebRequest.cs:34, 603`），主线程每帧遍历（`:617`）。后台联网用 `HttpWebRequest`（1.6、1.7 都能用）；`HttpClient` 只在 1.7 上用，1.6 的 Mono 上要用 `HttpWebRequest`（见 SKILL.md 第五节「后台联网」）。
- 1.7 游戏进程的错误模式是 0：对一个不是程序的文件（损坏的 exe、文本文件）调 `Process.Start`，Windows 弹出模态的系统错误框（「不支持的 16 位应用程序」，`#32770` 窗口），游戏主线程卡在 `Process.Start` 里，直到有人点掉。dotnet testhost 和 PowerShell 继承的是模式 3，单元测试里碰不到，要在测试里先把错误模式设成 0 才能复现。修法：`SetThreadErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX)` 包住 `Process.Start`、调完恢复；启动前再检查 exe 是否以 `MZ` 开头。游戏进程本身仍是模式 0，别的模组启动进程时照样可能弹框。
- Harmony 3.0（1.7 的 Harmony 模组）打补丁时会禁用目标方法的内联：只有一行的小方法打了补丁，也不会被 .NET 10 的 JIT 内联进调用方、绕过补丁。
- 帧时间用 `Waylith.Time.DeltaTime`（UnityStubs 的 `Time.deltaTime` 读的就是它）。窗口失焦又没开后台运行时整帧跳过，回来那一帧的值很大，按帧累计时间的逻辑要截断（比如每帧最多计 0.1 秒）。
- System.Text.Json 的两个坑（1.7 的 .NET 10 上实测）：默认把无效 UTF-8 换成 U+FFFD 而不报错（要报错就先用 `new UTF8Encoding(false, true)` 解码）；`JsonObject` 的重复键是懒检查的，第一次访问那个对象（包括嵌套对象）时才抛 `ArgumentException`，解析完要把整棵树走一遍，让错误在解析时就出来。

## 两份构建的做法

- 还要支持 1.6 时：`1.6` 文件夹放针对 Krafs.Rimworld.Ref 1.6 编译的 dll；`1.7` 文件夹放针对 1.7 的游戏程序集编译、直接调用 Waylith 原生接口的 dll（SKILL.md 第一节的版本文件夹约定）。两份由同一套源码构建，引擎相关的代码放进适配层，按目标框架选 1.6（Unity）或 1.7（Waylith）的实现。不要用「两个版本放同一份 1.6 构建、运行时判断引擎、再反射调用 Waylith」的办法：那样 1.7 版仍然是拿 Unity 开发的。
- 1.7 的参考程序集放 `<开发目录>\GameRefs`，所有模组共用。`<版本>\` 放游戏根目录的 `Assembly-CSharp`、`UnityStubs`、`Waylith`、`Waylith.UnityCompat`、`RimWorld`、`Microsoft.Extensions.Logging.Abstractions` 和 `Version.txt`；版本取自 `Version.txt`，空格换成短横线，如 `1.7.4977-rev1248`。`Harmony-1.7\` 放 Harmony 模组 1.7 文件夹里的 `0Harmony.dll`（创意工坊版在 `<Steam 库>\steamapps\workshop\content\294100\2009463077\1.7\Assemblies\0Harmony.dll`）。写个脚本（如 `Source\tools\save-game-refs.ps1`）在装着 1.7 时复制这些文件，之后本机切回 1.6，1.7 版照样能编。游戏更新后重跑这个脚本（新版本进新文件夹），再改构建里的版本号（放在共用的 props 文件里，如 `Source\GameRefs.props` 的 `Rw17Version`）。装的 1.7 和这个版本号不一致时，构建报警告。
- 一个 csproj 写 `<TargetFrameworks>net472;net10.0</TargetFrameworks>`，再写 `<AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>`（输出目录自己指定），按 `$(TargetFramework)` 分两套：net472 引用 Krafs.Rimworld.Ref 1.6 和 Lib.Harmony 2.x（两个包都加 `ExcludeAssets="runtime"`，不然 `0Harmony.dll` 会被复制进 `1.6\Assemblies`，跟着模组发布出去），输出到 `..\..\1.6\Assemblies\`；net10.0 用 HintPath 引用 GameRefs 里的 `Assembly-CSharp`、`UnityStubs`、`Waylith` 和 `Harmony-1.7\0Harmony.dll`，用到 `LogStream` 时再加 `Microsoft.Extensions.Logging.Abstractions`（都加 `Private="false"`），输出到 `..\..\1.7\Assemblies\`。一次 `dotnet build` 两份都出来。
  - net10.0 还要加 `<GenerateDependencyFile>false</GenerateDependencyFile>`，不然 Assemblies 里会多一个 `.deps.json`。
  - 关了 `AppendTargetFrameworkToOutputPath` 时，两个目标的中间目录也不再分开，都是 `obj\Release`，并行编译时抢同一个 `obj\Release\<模组>.dll`（报文件被占用、`refint\<模组>.dll` 不存在）；每个目标的 PropertyGroup 里再写 `<IntermediateOutputPath>obj\$(Configuration)\net472\</IntermediateOutputPath>`（net10.0 同理），改完删掉旧的 `obj\Release`。
  - 不要用 `-p:OutputPath=` 给这种多目标工程换输出目录：两个目标会写进同一个文件夹，互相覆盖。
- 适配层有两种组织方法：成员相同的两个文件（如 `Engine.Unity.cs`、`Engine.Waylith.cs`），或者两个文件夹（如 `Platform\Unity\`、`Platform\Waylith\`），里面是同名、同成员的类（帧回调和退出回调、引擎日志、鼠标按键、画贴图、输入法等）。csproj 里按目标框架用 `<Compile Remove>` 去掉另一份，源码里不用写 `#if`。
- 同步目标只在外层构建跑：条件加 `'$(TargetFramework)' == ''`，两份都编完才同步；只编一个目标（`-f`）时不同步。同步脚本再比一下两个 dll 的修改时间，相差 10 分钟以上就拒绝同步。
- 1.7 的 Harmony 是 3.0.0.0（Harmony 模组的 1.6 文件夹里是 2.4.3），1.7 版对它编译。1.7 用 `Assembly.LoadFrom` 把模组 dll 加载进默认加载上下文（`Verse\ModAssemblyHandler.cs`），引用 2.x 的旧 dll 也会绑到已经加载的 3.0。
- 单元测试用 System.Reflection.Metadata 读两个 dll 的程序集引用。1.6 版应引用 `UnityEngine.CoreModule` 和 1.6 的 Assembly-CSharp；1.7 版应引用 `System.Runtime` 10、1.7 的 Assembly-CSharp 和 `Waylith`，一个 `UnityEngine*` 都没有。再把 1.7 dll 用到的每个 UnityStubs 类型和成员列出来，和仓库里的允许清单（如 `Unity17Allowlist.txt`，每行写成 `条目 # 理由`）双向比对：清单里每一项都要写理由（是哪个 Verse 或 Ludeon 接口逼着用的），多用了不在清单上的、清单上有但已经不用的都算失败。改了界面代码后它失败时，能换成 Waylith 或 Verse 的就换；换不了的，在清单里写上理由。
- 测试辅助模组（SKILL.md 第四节「存档安全」）也照这个做法分成两份，带 `LoadFolders.xml`：1.7 版用 `LogStream` 收错误，用 `EngineApplication.PrePollEvents` 做每帧更新，不用 MonoBehaviour。
- 查 1.7 缺哪些 API：拆成两份构建以后，1.7 版的正式构建就会报出来；还没拆的时候，建一个 net10.0 的临时工程，引用 1.7 的 `Assembly-CSharp.dll`、`UnityStubs.dll`（用 Harmony 的再加 Harmony 1.7 的 `0Harmony.dll`），把模组源码编译一遍，编译错误就是 1.7 没有的 API。.NET 按整个方法即时编译，方法里只要引用了不存在的成员，调用这个方法时就抛 `MissingMethodException`，写在同一个方法里的 try/catch 接不住（异常在进入方法前就发生）。已知缺：`Application.SetStackTraceLogType` 和 `StackTraceLogType`（改用反射按名字找）、`UnityEngine.Rendering.BlendMode`/`CullMode`（枚举强转 int 编译成常量，运行时无害，源码里直接写数值）。`GL`、`RenderTexture`、`ScreenCapture`、`Application.logMessageReceived` 在 UnityStubs 里有实现；`Shader.Find` 只找文件型资源，可能返回 null，要有退路。
- 一份 dll 两个版本共用时（不推荐，见上），可以把 1.7 没有的调用单独放进一个 `[MethodImpl(MethodImplOptions.NoInlining)]` 方法，调用处 try/catch 包住。分开构建后，1.7 没有的接口在 1.7 版编译时就报错，用不着这一招。无论哪种做法，都千万不要把可能缺失的调用写在 `[StaticConstructorOnStartup]` 的静态构造里：整个静态构造失败，`PatchAll` 不执行，模组在 1.7 上所有补丁都不生效，日志里只有一条 TypeInitializationException。
- 源码编译通过不等于二进制兼容（签名变了但源码兼容的情况）。另做一次二进制检查：写个小工具（如 `refcheck17`，用 NuGet 包 Mono.Cecil，把 `UnityEngine*` 映射到 `UnityStubs.dll`），逐个解析已编译 dll 的类型和成员引用，输出解析不了的引用。参数是模组 dll、游戏根目录、Harmony 1.7 的 Assemblies 文件夹和 .NET 运行时目录（`C:\Program Files\dotnet\shared\Microsoft.NETCore.App\10.0.x`）。对 1.7 编译的 dll 应当一个解析不了的都没有。

## 测试

- 日志：`-logfile` 没了，日志固定写 `<用户数据目录>\Logs\Player.log`，启动时把旧的改名为 `Player-prev.log`；文件头有 `Process:   pid N` 和 `Command:` 行，每行前缀 `yyyy-MM-dd HH:mm:ss.fff LEVEL [分类] `，错误级别是 ERROR。测试脚本只认文件头写着自己进程号的日志，去掉前缀后给 ERROR 行加 `[LOGERROR] ` 标记再判定；启动前备份、结束后还原用户自己的两份日志。
  - 备份时在备份文件夹里写一个 `pending` 标记，还原后删掉；标记在，就说明还有备份没还原。
  - 备份和还原只由测试锁最外层的持有者做（锁可重入，见下一条）：一个脚本在备份期间调用另一个脚本的准备步骤（`-PrepareOnly`）时，子脚本要是在 finally 里照样还原，会提前用掉备份、删掉标记，父脚本之后启动的游戏覆盖了用户的日志，最后的还原又被跳过，用户原来的两份日志就丢了。
  - 备份文件夹所有模组共用一个（例如 `<开发目录>\player-log-backup`），不要每个模组各放一个：哪个模组的脚本中途被杀掉，下一个拿到锁的脚本（不管是哪个模组的）都能先把上次的备份还原回去。
  - 备份时不要用测试日志覆盖备份里用户自己的日志（文件头 Command 行带 `-savedatafolder=<开发目录>` 的是测试日志），这样某次没还原成功，下一次运行还能放回去。
  - 这些放进一个各脚本共用的 `Source\tools\GameRuntime.ps1`；几个模组各有一份时，内容保持一致，改了要同步。
- 同一时间只能跑一个游戏（大家写同一个日志）：测试脚本都拿跨模组互斥量 `Local\RimWorld.GameTest`（拿不到就等，等待上限要明显长于单次测试的超时，比如 full 给 3600 秒时等 90 分钟）。锁要能重入：父脚本拿着锁、在同一进程里调用子脚本的准备步骤（`-PrepareOnly`）时，子脚本照常拿锁，同一线程上重入成功，不会死等（.NET 的 `Mutex` 本身可重入；另开 `powershell -File` 就成了另一个进程，会死等）。同步发布文件、写测试配置也要在拿到锁之后：别的会话正在跑的游戏用着 Mods 里的模组和同一套测试配置。dll 被游戏锁住时，robocopy /MIR 按默认设置重试（一百万次、每次等 30 秒），等于卡死；1.7 运行中窗口位置一变就 `Prefs.Save()` 重写整个 `Prefs.xml`（`WindowPlacement.Track`，每 30 帧查一次），可能把别人刚写进去的语言等设置改回去。所以 robocopy 要加 `/R:2 /W:2`，会调用 `-PrepareOnly` 的脚本要先拿锁再调它。不能靠多开提速：1.7 的日志目录固定取 `SHGetKnownFolderPath(LocalAppDataLow)`（`_engine\RimWorld\RimWorldWaylith\Bootstrap.cs` 的 `ResolvePersistentDataRoot`），`-savedatafolder` 只影响存档和缓存；第二个实例会用 `FileMode.Create` 截断同一个 `Player.log` 并交错写入（`Waylith.Logging.FileLog.StartLocked`）。
- `-savedatafolder`、`-quicktest` 照旧；测试配置的 `ModsConfig.xml` 里 `<version>` 必须是当前游戏版本（脚本读 `Version.txt` 自动写），否则 1.7 打印 "Mods config data is from version ... Resetting." 只剩 Core。
- 用户自己的配置也一样：主版本或次版本不同（1.6 和 1.7 来回切）就重置（`Verse\ModsConfig.cs` 静态构造），`Reset()` 只留 Core 和 `VersionCompatible` 的 DLC；1.7.4977 的 DLC `About.xml` 只写了 1.6，所以 DLC 也一个不剩。用户在 1.6 上玩过后切回 1.7，第一次启动就会丢掉整个模组列表（`Player.log` 里有 `Mods config data is from version 1.6.4871 rev591 while we are running 1.7.4977 rev1248. Resetting.` 这样的行）。
  - 之后 `full` 配置复制到的只有 Core，完整列表测试等于没测（SKILL.md 第四节的 `-ModList` 就是为这个）。没拦住时的样子：只有 Core 加本模组，连 Harmony 都没有，1.7 读模组类型时报 `TypeLoadException: Could not load type 'HarmonyLib.HarmonyPatch' from assembly '0Harmony…'`，接着打印 `Resetting mods config and trying again`，只用 Core 继续跑，自测场景一个都不执行，脚本一直等到超时。
  - 用户自己恢复：读一个旧存档，弹出模组不一致的对话框时点「从存档载入Mod列表」（`Dialog_ModMismatch` 的 `ChangeLoadedMods`，每个存档都记着当时的列表）；模组管理器的「保存/读取列表...」只读以前存进 `ModLists` 的列表。不要替用户改配置。
- 窗口：最小化时引擎照常跑 Update 但不渲染帧，OnGUI 不执行，自测和 quicktest 卡住；不要用最小化，改为进程按 Normal 启动、再给游戏加 `-NoWindow`（由游戏自己隐藏窗口，Windows 上照常渲染）。测试脚本里把 Hidden、Minimized 都换成这样。窗口大小仍看测试配置 `Prefs.xml` 的 screenWidth/screenHeight，`-screen-width` 没了（也有 `-WindowSize=宽,高`）。
- 崩溃弹窗：1.7 崩溃后（日志出现 `=== CRASH ===`，报告写进 `<用户数据目录>\Crashes`）默认在屏幕上弹消息框，进程一直挂着等人点，用户会看到测试一直在弹报错。测试启动一律加 `-NoCrashDialog`（`RimWorldWaylith\Program.cs`）；脚本看到 `=== CRASH ===` 立即判失败。崩溃报告固定写在用户的 `Crashes` 文件夹，`-savedatafolder` 不影响，测试留下的报告要在验收报告里告诉用户。
- 日志判定正则：在 1.7 日志上，`(?:[ \t]+[^\r\n]*\r?\n)*?` 这种每行有多种匹配方式的写法会灾难性回溯，脚本卡死并一直占着锁；每行只能有一种匹配方式（原子组、首字符互斥）。1.7 会在堆栈中间插入不缩进的 `[Ref XXXXXXXX]` 行；有的行中间夹着单独的 \r，正则结尾不要写 `[^\r\n]*$`。PowerShell 的 `-match` 没有超时，在脚本里设 AppDomain 的 `REGEX_DEFAULT_MATCH_TIMEOUT` 对 PS 5.1 也无效；日志判定一律走一个带超时的函数（如 `GameRuntime.ps1` 里的 `Test-LogMatch`，内部是 `[regex]::IsMatch($content, $pattern, 'IgnoreCase', [TimeSpan]::FromSeconds(10))`，超时把日志存到 `<日志>.check-timeout.txt` 并报错）。1.6 上认错误用的 `Verse\.Log:Error` 堆栈正则（见 SKILL.md 第四节「游戏内自测」的判定那条），放到 1.7 的长堆栈上就卡死过。
- 优化类模组：1.7 引擎本身优化得很好，在 1.7 上测试一律不带优化类模组，full 测试配置把它们全部剔除，支不支持 1.7 都一样（1.6 上不剔除）。
  - 已知的有：Prepatcher（主菜单阶段引擎崩溃）、Kingfisher（`ListerBuildingsRewrite` 抛 BadImageFormatException，生成建筑就炸）、Performance Optimizer、Dubs Performance Analyzer、Missile Girl、Loading Progress、PurePatcher、Smart Speed、Adaptive TPS、Better GC（Mothballed and World Pawns）、Slower Pawn Tick Rate、Performance Esmolas，以及它们的汉化包。
  - 前十个不支持 1.7（About.xml 的 supportedVersions 没有 1.7，也没有 1.7 文件夹或 LoadFolders 条目）；后两个声明了 1.7，也一样剔除。Smarter Construction 改的是建造顺序，不算优化类，保留。
  - `-ExcludeMods` 用的 packageId：`zetrith.prepatcher`、`vortex.kingfisher`、`taranchuk.performanceoptimizer`、`optimizer.zh`、`dubwise.dubsperformanceanalyzer.steam`、`cc.chinese.rimworld.dubsperformanceanalyzer`、`vr.missilegirl`、`ilyvion.loadingprogress`、`ilyvion.loadingprogress.zh`、`vortex.purepatcher`、`sarg.smartspeed`、`soulwolf.ch.smartspeed`、`blue.adaptivetps`、`blue.adaptivetps.zh`、`gwinnbleidd.mothballedanddeadpawns`、`gwinnbleidd.mothballedanddeadpawns.zh`、`arkymn.slowerpawntickrate`、`arkymn.slowerpawntickrate.zh`、`arkymn.performanceesmolas`。把这份清单存成仓库里的一个文件（如 `Source\tools\exclude-1.7.txt`，每行一个 packageId），脚本在 1.7 上准备 full 配置时自动读它剔除；`-ExcludeMods` 留给临时排查。
  - 列表里以后新出现的模组，按名字和简介判断（Performance、Optimizer、TPS、GC、tick rate、加载加速一类）；拿不准就问用户。
- 完整列表下偶尔在加载阶段（`KeyPrefs.Init` 之后）进程以 0xC0000005 退出，没有崩溃报告，同样的配置重跑就过，先重跑再查。同一位置也会卡住不动：进程不占 CPU、窗口无响应，日志停在 `KeyPrefs.Init` 的按键冲突警告，主线程的 `ExecuteWhenFinished`（模组的静态构造在其中）一直不执行，脚本要等到超时（rev1248 上完整列表 4 次里碰到过 1 次，核对命令行后手动结束）。
- 切回 1.6 后测试日志开头有两条 `XML error: <windowPositionX>/<windowPositionY> doesn't correspond to any field in type PrefsData`：1.7 运行中把窗口位置存进 `Prefs.xml`（见上面锁的那条），1.6 的 `PrefsData` 没有这两个字段。两个版本共用同一套测试配置就会这样，和模组无关；准备测试配置时在 1.6 上删掉这两个节点。玩家自己的配置两个版本也是共用的，同样会报，不用管。

## 其他模组在 1.7 上的问题

- 完整列表的引擎崩溃 `InvalidOperationException: Collection was modified` 在 `LongEventHandler.get_AnyEventWhichDoesntUseStandardWindowNowOrWaiting`（调用方 `RimWorldWaylith.Rendering.WorldRenderFeature.CaptureFrame`），是启动或主菜单阶段渲染线程和长事件队列的竞态，由 Prepatcher 等未适配的模组触发；模组只用 `LongEventHandler.ExecuteWhenFinished` 时不走那个列表，与它无关。
- 1.7 上自测通过、截图里却只有地图没有窗口：查日志里的 `Root level exception in OnGUI`。NebulaeFlood's Lib（`nebulae.rimworld`，Simply More Roofs 的前置，只写了 1.5/1.6）给 `WindowStack.WindowStackOnGUI` 打了前缀补丁，补丁里的 `InputUtility` 静态构造要用 `UnityEngine.UIElements.MouseButton`，`UnityStubs` 里没有这个类型。于是每帧都抛异常，窗口栈一次都不画，游戏里所有窗口都打不开；它每帧报错，还会刷满 10000 条的日志上限。测试时排除 `nebulae.rimworld` 和 `nebulae.simplymoreroofs`，也提醒用户自己玩 1.7 时停用这两个。自测能过，是因为界面场景直接调用绘制代码，不走窗口栈。

## 测试版更新以后

- 测试版会随时更新（看 `Version.txt` 和 `Assembly-CSharp.dll` 的修改时间）。版本号不变也可能换了构建：4977 的 rev926 和 rev1248，`Version.txt` 都写 1.7.4977，`Assembly-CSharp.dll` 的程序集版本却从 1.7.9782.27799 变成了 1.7.9782.37458，引擎 dll 的 ProductVersion 也变了；所以要比程序集版本，不能只看 `Version.txt`。
- 更新后：
  1. 旧的反编译改名留着（如 `RimWorld-decompiled-1.7.4977-rev1248`），重新反编译到 `<开发目录>\RimWorld-decompiled-1.7`；新旧两份用 `diff -rq` 比一下就知道改了什么。
  2. GameRefs 存一份新版本，改构建里的版本号，重新编译。
  3. 用二进制检查（refcheck17）重查模组 dll。
  4. 测试配置的 `ModsConfig.xml` 版本号由脚本按 `Version.txt` 自动写。
  5. 验收报告里写明是在哪个版本上测的。
- 已知的版本变化：
  - 4976 → 4977：设置语言时会通知界面后端换字体；`LongEventHandler.QueuedLongEvent` 改成了 internal；其余是引擎内部的排版和渲染改动。除了 `QueuedLongEvent`，模组能用的 API 没变。4976 的 Core 只带 `Languages\English`，中文配置下原版文字显示成带重音的占位英文（如 `15 ðàỳṣ`）；4977 起 Core 带上了各语言（`Data\Core\Languages\*.tar`）。
  - 4977 rev926 → rev1248：Assembly-CSharp 只变了版本号；引擎加了 Windows 输入法支持（`GUI.TextField` 把正在输入的拼音连同下划线画进框里、设置候选窗位置，`Input.compositionString` 有值了）。字体回退的 `FontFallbacks.LocaleFor` 改成先去掉语言文件夹名里的括号后缀再匹配；Windows 上简体中文不管匹配上没有，第一个回退字体都是 `msyh.ttc`，中文字宽不变，按字缓存的断行宽度不受影响。
  - 4977 rev1248 → 4979 rev109（改了 29 个文件），模组可能碰到的：
    - UnityStubs 的 `GUI`：每次 Repaint 结束时，如果有焦点的输入框这一帧没画（这一帧也没换过焦点），就把 `GUIUtility.keyboardControl` 清成 0。输入框只在某些帧画，就会丢焦点；要一直保留焦点，就每帧都画。
    - 启动时新增 `Bootstrap.DeleteOldUnityLogs`：删掉 `<用户数据目录>` 根目录下的 `Player.log`、`Player-prev.log`，这是 1.6（Unity）写的日志。所以开过 1.7 以后，玩家 1.6 的日志就没了；要看 1.6 的日志，得在切到 1.7 之前拷出来。1.7 自己的日志仍在 `Logs\Player.log`，位置和改名规则都没变；测试脚本在 1.6 上用 `-logfile`，不受影响。
    - 创意工坊上传的临时目录从 `%TEMP%\RimWorldWorkshopUpload` 改到存档目录（`<用户数据目录>`，或 `-savedatafolder` 指定的目录）下的 `WorkshopUpload\<packageId>`（`Verse.Steam\Workshop.cs`）。
    - Verse 只多了 `Prefs.PreferredMonitor`（选显示器）；`ThingWithComps` 的 `compsByType` 改成组件数量或最后一个组件变了就重建；`Application.onBeforeRender` 回调里的异常现在会被接住、记进日志。`EngineApplication.PrePollEvents`、`OnShutdown` 没变，其余是 Vulkan 启动、显示器、渲染线程、崩溃报告等引擎内部改动。
