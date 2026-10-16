# `<模组中文名>`（`<模组名>`）

只在开发这个模组时适用，不要套用到其他模组。新模组开始开发时，把本文件复制成 `mods\<模组名>.md` 再填（复制后删掉这句）。

## 基本信息

- 仓库 `<开发目录>\<模组名>`，开发分支：（填）。packageId：`<作者>.<模组名>`。创意工坊 ID：（第一次上传后看 `About\PublishedFileId.txt`）。
- 开发文档在 `<开发目录>\<模组名>Dev`，测试数据在 `<开发目录>\<模组名>Test`。
- 设计文档：（路径）。规则细节以它为准。
- 日志前缀「[<模组中文名>]」，语言键前缀 `<前缀>_`，自测命令行参数前缀 `-<前缀>-`。
- 支持的游戏版本：1.6、1.7。
- 运行时数据文件夹：（模组运行时往自己文件夹里写数据的，写明文件夹名：同步时排除，上传前挪走。没有就删掉这一条。）
- 测试用的数据目录参数：`-<前缀>-data=<路径>`（没有就删掉这一条）。

## 代码约束（本模组专用）

- （例如：只用 Harmony Postfix；不改原版 Def。）

## 用户定下的决定

- （日期）：（决定内容，以及原因。）

## 测试命令

- 单元测试：`dotnet test Source\<模组名>.Tests`
- 游戏内自测：`powershell -NoProfile -ExecutionPolicy Bypass -File Source\tools\run-selftest.ps1 -Profile vanilla -Language ChineseSimplified`（English 再跑一次）
- 存档安全：`powershell -NoProfile -ExecutionPolicy Bypass -File Source\tools\run-savesafety.ps1`
- 界面截图：`powershell -NoProfile -ExecutionPolicy Bypass -File Source\tools\run-capture.ps1 -Language ChineseSimplified`（English 再跑一次）
- full 配置用的模组列表：（用户自己的列表，还是哪个合集；列表文件在 `<开发目录>\ModLists\` 下的哪一份。）
- full 配置要去掉的互斥模组：（packageId，以及为什么互斥。）
- 本模组特有的测试场景：

## 自测依赖的内部接口

自测、截图直接调用的内部类和成员，改名或改签名前先改自测：

- （填）

## 踩过的坑（只属于本模组的）

- （填）
