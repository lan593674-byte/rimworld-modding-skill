# rimworld skill

给 AI 编程 agent 开发环世界（RimWorld）模组用的 skill：目录和发布结构、上传创意工坊、全自动的测试流程，以及开发中踩过的坑。覆盖 1.6 正式版和 1.7 测试版（Waylith 引擎，实测到 1.7.4979 rev109）。

## 安装

- 用 Claude Code、Codex 等支持 `SKILL.md` 格式的 agent：把整个 `rimworld` 文件夹放进它的 skills 目录（Claude Code 是 `~/.claude/skills/`，Windows 上是 `%USERPROFILE%\.claude\skills\`；其他 agent 的位置看各自的文档），重开 agent。
- agent 不支持 skill 的：在它的项目说明文件（如 `AGENTS.md`）里写明「开发环世界模组前先读 `<rimworld 文件夹的完整路径>\SKILL.md`」，路径写绝对路径。
- 想让 agent 每次都先读，可以在它的全局说明文件（Claude Code 是 `CLAUDE.md`，Codex 是 `AGENTS.md`）里加一句「凡是涉及环世界开发的任务，开始前先调用 rimworld skill」。

## 第一次用之前

打开 `SKILL.md`，在「第一次使用」那张表里填上自己的开发目录和游戏目录；也可以直接告诉 agent 你的路径，让它填。

## 文件

| 文件 | 内容 |
|---|---|
| `SKILL.md` | 主文件：目录约定、同步和发布、上传创意工坊、测试流程、通用的坑 |
| `references/ui.md` | 界面开发：中文排版、文字测量、自制控件、1.6 的像素对齐问题、从截图查毛病 |
| `references/rimworld-1.7.md` | 1.7 测试版：Waylith 引擎、两个版本分开构建、测试脚本要注意的变化、其他模组的已知问题 |
| `mods/_template.md` | 单个模组专用规则的模板，开发新模组时复制一份改名 |
| `templates/MyMod/` | 带全套测试的最小模组：同步脚本、游戏内自测、截图、存档安全的脚本和自测框架、测试辅助模组，1.6 和 1.7 两份构建。新模组从它复制改名，用法见 `templates/README.md` |

## 说明

- 整套流程只在 Windows 上用过（同步用 robocopy，测试脚本是 PowerShell，游戏数据在 LocalLow 下）。
- 测试流程里提到的同步脚本、自测框架、测试辅助模组都在 `templates/MyMod/` 里，在 1.7.4979 上跑通过；1.6 部分只编译过，没有在 1.6 游戏里跑过。模板里的脚本按 skill 的要求写，两者不一致时以 skill 为准，改好模板。
- 兼容性测试要一个模组多、种类杂的环境。你自己订阅的模组不够时，agent 会建议用网上热门的模组合集来测，并先跟你说明要订阅什么、有什么影响，你同意了才做。
- 里面的游戏行为都是查反编译源码或实测得来的。1.7 测试版还在更新，以当前版本的反编译源码为准。
- skill 要求 agent 把开发中遇到的新问题写回来：通用的写进 `SKILL.md` 或 `references`，只属于某个模组的写进 `mods/<模组名>.md`。

## 许可证

MIT，见 `LICENSE`。可以自由使用、修改、再分发，包括用在商业项目里，只要保留版权和许可声明。
