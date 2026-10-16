# 界面开发的坑

写或改界面代码之前读。只在 1.7 上有的绘制接口（`IGuiBackend`、`DrawPrimitives`、`GL.LINES` 的颜色问题）见 `rimworld-1.7.md`；截图前要等什么（地图淡入、信件滑入、调试日志窗口）见 SKILL.md 第五节。

## 文字

- 游戏字体没有 ⚙ 这类符号（画出来是空白），按钮用文字或贴图；▾ ▴ ‹ › » − 这几个能正常显示。
- `Widgets.Label` 默认会换行（`Text.WordWrap` 默认是 true）：窄单元格里的长数字会折到下一行，被裁掉看不见。单行的文字画之前关掉 `Text.WordWrap`，画完一定恢复（不恢复的话，下一帧开头 `Text.StartOfOnGUI` 报 `Word wrap was false at end of frame.`）。
- 量文字宽度、高度之前先切到实际绘制的字号，量完恢复：当前字号是上一个面板留下的，按 Tiny 量、按 Small 画，文字就会挤在一起。
- `Text.CalcSize`、`Text.CalcHeight` 量之前先去掉全部富文本标签（`StripTags`，1.6 和 1.7 都是），所以 `<b>粗体</b>` 量出来是常规字重的宽高。要按画出来的样子量，直接用标签样式：`Text.CurFontStyle.CalcSize(new GUIContent(s))`、`Text.CurFontStyle.CalcHeight(content, width)`（两个版本的标签样式都开着 richText；GUIContent 可以复用一个，免得每帧分配）。粗体量窄了，自己排的行实际比框宽，绘制时又会被折一次（出现过一行只剩一个单词）。
- Unity IMGUI 给中文自动换行时不避头尾：「。」「，」「】」会单独甩到下一行行首；一行里有空格时还会优先在空格处断，「第一款 很长的条款」会让「第一款」单独占一行。要好看就自己断行再交给 Label：
  - 逐字量宽度：用标签样式量，两个字的宽度减一个字的宽度，抵消样式内边距；粗体包 `<b>` 量；不能用 `Text.CalcSize`（它先去掉富文本标签再量，见上面讲 `StripTags` 的那条）。
  - 按宽度贪心排行，不让收尾标点开头、不让开头标点结尾、拉丁单词不拆，富文本标签不算宽度。
  - 可用宽度先减去标签样式的左右内边距（`Text.CurFontStyle.padding.horizontal`：标签在 `宽度 − 内边距` 里排版和算高度，1.7 是 0，1.6 不是 0），再留 2 px 余量，免得 Unity 再断一次。
  - 段末一行只剩一个汉字加标点（如「知。」）时，从上一行挪一个字下来。
  - 自测里这样查「有没有被标签再折一次」：同一段断好的文字，`CalcHeight(内容, 宽度)` 和 `CalcHeight(内容, 100000)` 应该相等。把模组里所有多行文字在几种宽度下断一遍，检查行首行尾标点、末行孤字、文字没丢、标签不会再折一次。
  - 1.6 上字体整局不变（`Text` 静态构造里加载一次），按字缓存宽度是安全的；1.7.4977 起换语言会换字体（`ImGuiHost.SetTextLanguage` 按语言选回退字体，`FontGeneration` 加一），缓存要在 `LanguageDatabase.activeLanguage` 变了时清空。
- 每帧都要量的标签宽度按字号缓存（1.6 上字体整局不变，1.7 换语言会换字体，所以换语言时清空缓存）；`Truncate` 前先判断放不放得下，省一次测量。截断的结果也要缓存：`GenText.Truncate` 不传 cache 参数时每去掉一个字就 `Text.CalcSize` 一次，实测满页 15 行名称都要截断时一帧多 0.25 ms。缓存按游戏实际用的字号存：语言不支持小字或玩家勾了「禁用微小字体」时（`Text.TinyFontSupported` 为 false），`Text.Font = Tiny` 实际是 Small；自己复制 `Text.textFieldStyles[(int)字号]` 时也要先这样换算。
- 同一段文字两个版本量出的宽度不一样：1.7 的 UnityStubs 里 `GUI.skin.label` 左右内边距是 0（`padding = new RectOffset(0, 0, 3, 3)`，`_engine\UnityStubs\UnityEngine\GUISkin.cs`），1.6 的 Unity 标签样式左右带内边距。按宽度截断、按标签算按钮宽度时都留几像素余量，不要按一个版本的测量结果卡死。1.7 的字体是 ImGui 加 FreeType：Tiny 是 `Calibri_tiny.TTF` 12 px，Small 是 `Arial_small.ttf` 14 px，Medium 是 `Arial_medium.ttf` 21 px（`_engine\RimWorld\RimWorldWaylith.Imgui\ImGuiHost.cs` 的 `GameFontPixelSizes`、`FontFiles`），简体中文回退到 `msyh.ttc`（`FontFallbacks`），Small 下每个汉字 14 px。所以英文宽度可以拿 Windows 的 arial.ttf 离线估算（例如估出「No trades」是 62 px，游戏里也确实放不进 60 px 的标签）。

## 绘制

- 自绘的图形（`DrawAtlas`、贴图、几何）只在 `EventType.Repaint` 时画；按钮、输入框这类控件要在每个事件里都调用，才收得到点击和键盘输入。
- 自绘圆角：`Widgets.DrawAtlas(rect, 白色贴图)` 配 `GUI.color` 染色就能画任意颜色的圆角矩形，角的大小是贴图宽度的 1/4（UI 像素），再被矩形高宽的一半截住；所以 32 px 贴图里画 6 px 圆角的形状就得到 6 px 圆角，64 px 贴图画 16 px 圆角的形状，在 32 px 以下的高度上就是两头全圆的胶囊。模组贴图尺寸用 2 的幂，否则开了贴图压缩会被重新载入、少几级 mipmap。
- 小人圆形头像：`PortraitsCache.Get(pawn, size, Rot4.South, new Vector3(0, 0, 0.27f), 2.05f)` 是头和肩的取景（相机正交半高 = 1/zoom）；画完头像再盖一张「圆外不透明、圆内透明」的遮罩贴图，染成头像背后的底色，就裁成了圆。头像只在 Repaint 时取；死亡或已销毁的小人改画首字母。
- 两个窗口画同一份状态（例如标签页和全屏的图表）时，"这份状态属于哪个对象"的标记要和状态放在一起，不能每个窗口各记一份，否则一个窗口改了，另一个窗口下次绘制会当成变化把它重置。
- 图标：游戏字体缺很多符号，用 PIL 按 4 倍超采样画 64×64 的白色透明底 PNG 放进 `Textures`，`ContentFinder<Texture2D>.Get` 读，画时 `GUI.color` 染色。模组贴图加载时带 mipmap、三线性过滤（开了贴图压缩还会 DXT 压缩），缩到 14 像素画也清楚。圆角、胶囊、环、勾这类形状同样可以用脚本生成白色贴图，改形状就改脚本重新生成。

## 自己做一套界面组件

1.6 和 1.7 都验证过的做法：

- 圆角的另一种画法：OnGUI 里第一次用到时生成白色 RGBA32 贴图（`new Texture2D(n, n, TextureFormat.RGBA32, false)`、`SetPixels32`、`Apply`），四角按像素到圆心的有符号距离做抗锯齿，中间留 4 像素均匀边带；用 `GUI.DrawTextureWithTexCoords` 按九宫格画（四边和中心只采样边带中间两像素，免得双线性过滤采到角），`GUI.color` 染色。贴图按「半径 × `Prefs.UIScale`」取整后的像素缓存，换界面缩放也清楚。描边（环）和柔和阴影同理。像素和切分是纯计算，可以放进不引用 Unity 的 Core 做单元测试。1.7 版画贴图要改用等价的 Verse 包装 `GenUI.DrawTextureWithMaterial(rect, tex, null, uv)`，或者干脆用三角形画（见 `rimworld-1.7.md`），否则过不了 Unity 用量的允许清单检查。
- 没有灰框的输入框：`new GUIStyle(Text.textFieldStyles[(int)字号])` 复制一份，把 normal、hover、active、focused 和四个 on 状态的 `background` 设成 null、`textColor` 设成想要的颜色，再 `GUI.TextField(rect, text, style)`；底色、描边、焦点框自己画（焦点用 `GUI.SetNextControlName` + `GUI.GetNameOfFocusedControl()` 判断）。两个版本都是 background 为 null 就不画框。
- 主题窗口：`Window` 的构造函数有 `IWindowDrawing customWindowDrawing` 参数（1.6、1.7 都有），自己实现 `IWindowDrawing`（背景、右上角关闭按钮 `DoClostButtonSmall`（原版就是这个拼写）、置灰），对话框在构造时传进去；`MainTabWindow` 只有无参构造，只能反射设私有字段 `windowDrawing`（找不到就保持原样）。
- 隐藏游戏的灰色滚动条：`Widgets.BeginScrollView(..., showScrollbars: false)`，滚轮照样能滚（1.7 在 `GUI.EndScrollView` 里处理滚轮、下一帧生效），细滑块自己画、自己处理拖动。
- 拖动类控件（滑块、滚动条）照抄 `Widgets.HorizontalSlider`：用屏幕坐标、尺寸、范围的哈希当控件编号，`Event.current.rawType == MouseUp` 时放开。不要用 `GUIUtility.GetControlID`，1.7 的 UnityStubs 里它只是个递增计数器。

## 1.6 上边落在像素中心的两种毛病

1.7 都没有。光栅化只给中心落在框内的像素上色，一条边正好在像素中心时，浮点误差决定那一列（行）画不画：

- 九宫格的两块共用一条边、这条边又在像素中心（例如宽 63.25 的按钮配 4 像素圆角，右侧圆角块从 x.5 开始），1.6 有时两块都不画那一列，形状中间留一条一像素的暗缝。按钮、7 像素的状态圆点、单选框和滑块里的小圆点都出现过。修法：矩形四边先按光栅化的取舍对齐到整像素，`Math.Ceiling(v * UIScale - 0.5) / UIScale`（像素中心在左边或上边上算这块的，在右边或下边上不算）；角取遮罩的像素数 / UIScale，这样中间的分界线也在整像素上。两个圆角占满一条边时（奇数像素的圆点），两块共用同一个中点值，不要再取整，否则圆点一半 3 像素一半 4 像素，看着歪。所在分组本身的偏移是半像素时，这样对齐只能保证不出缝，形状仍可能差一像素。原版 `Widgets.DrawAtlas` 没有这个问题：它先把矩形四舍五入到整像素，角的大小用 `UIScaling.AdjustCoordToUIScalingCeil` 向上取整（界面缩放不是 1 时取整到物理像素），各块的分界线都在整像素上；圆角全用它画的界面，1.6 截图里扫不出缝。
- 单行标签的裁剪框上沿落在像素中心时，1.6 会削掉中文字的第一行像素：「不」显示成「小」，「买」成「头」，「开」成「廾」，「平」成「半」，「万」成「力」。同一个标签换个位置就正常，所以截图里时有时无。给不换行的标签上下各多留 2 个单位（高度至少 `行高 + 4`，以中心为准往两边扩），文字位置不变。标签框本身在整像素上也会被削：见过三行副标题的框都在整数 y 上，框高 18、比微小字号的一行矮，结果两行被削、一行没削；所以要看的是框比一行矮，不是坐标有没有小数。顶部或底部对齐的单行标签不能以中心往两边扩（文字会跟着挪），要往远离对齐边的方向扩；居中的每边扩一样多、总量取偶数，中心和高度的奇偶都不变，文字仍落在原来的像素上（行高按「国W」量、按实际字号缓存、换语言清空）。也别把一行字放进只有一行高、顶部对齐（会换行）的段落框，下半截会被裁掉（见过图表价格轴两端的涨跌幅就这样丢了小数点）。

## 从截图里查毛病

- 被削的字：截图里逐行数同一个字有几行墨迹，被削的少一行。
- 暗缝：用脚本找「一像素宽、比两侧暗、两侧颜色相同」的列（或行），只看 16 像素以上的长线，短的都是文字笔画（浅色底上的深色横笔画、「一」连着下一个字的横画）。1.7 上用 `GL.LINES` 画的 1 像素网格线也会被报成缝，判断时先认出它（见 `rimworld-1.7.md`）。
- 修好后把修改前后的截图在窗口范围内逐像素比：应该只多出补回来的那一行字顶。小人名字、头像每次随机，名字长短还会让表格列宽和段落折行跟着变，这些区域单独排除，或按行统计墨迹数（列平移不影响每行的墨迹数）。
