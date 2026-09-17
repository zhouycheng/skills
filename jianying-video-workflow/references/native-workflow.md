# macOS 剪映原生草稿操作指南

## 已验证依据和边界

2026-09-12，本机剪映 Info.plist 的版本字段为 11.4.13189 / 11.5.0-beta5。当前草稿 `new_version=187.0.0`，`version=360000`，读写接口报告 `cipherType=256`。这些是样本事实，不是其他版本必须填写的常量。

剪映自带 `/Applications/VideoFusion-macOS.app/Contents/Frameworks/videoeditor_addon.node`，Node 23.11 可加载。原生 `draft.setDraft` 接受 VectCutAPI 快照并返回 `draftSnapshot`；`readFile` 和 `writeFile` 能完成原生加密读写。写入后完全重启剪映，成功显示 6 个视频片段、2 条音轨、9 个文字片段和 60 秒时长；磁盘经剪映再次保存仍保留这些轨道。文字视觉质量当时尚不合格，不能把该案例当作画面样板。

## 定位环境

- 当前 app 默认位置如上，可通过 `JIANYING_APP` 指向实际安装包。核实 Info.plist；不要从陌生位置下载/替换原生模块。
- 当前默认草稿根目录是 `~/Movies/JianyingPro/JianyingPro Drafts`，以新工程界面“保存位置”为准。旧工具的 `User Data/Projects/com.lveditor.draft` 不一定有效。
- 本次 VectCutAPI 位于 `/Users/leftzhou/Documents/Codex/2026-09-12/d/work/VectCutAPI`，只是发现线索，不是 skill 依赖的固定位置；后续先检查它是否存在或发现当前安装位置。参考上游 `https://github.com/sun-guannan/VectCutAPI`，本机接口签名优先。
- 使用工具能力做 UI 操作；通常 Cmd+W 保存关闭工程，Cmd+Q 退出应用。确认主进程确实退出。不要强制终止有未保存工作的应用。

## 可重复步骤

1. 创建本任务专用空工程，保存并关闭；记录其绝对路径。保留该工程原有 metadata、`Timelines/project.json` 和 timeline ID。不要把上次 ID 写进去。
2. 准备 VectCutAPI 明文 JSON 和所有媒体。校验路径，修复 Windows 字体路径（也可能藏在 text.content JSON 字符串中）。按当前剪映的文字样本校准字号、缩放和换行。素材优先复制到持久工程 assets 下并修复引用。
3. 保存用户工作，正常退出剪映。仅返回首页不充分；打开状态的旧内存可能在关闭时覆盖外部修改。之前“全文件写入后关闭空工程”的次序导致修改丢失；应先关再写。
4. 使用下面的脚本，target 指向刚新建的专用工程。它备份原工程、转换快照、继承当前 ID/平台/版本、写入主时间线及其镜像、更新时长并读回校验。脚本拒绝仍在运行的剪映及已有非空工程，避免误覆盖。

```bash
node /Users/leftzhou/.agents/skills/jianying-video-workflow/scripts/native-draft.cjs inspect '/absolute/project'
node /Users/leftzhou/.agents/skills/jianying-video-workflow/scripts/native-draft.cjs apply '/absolute/vectcut/draft_content.json' '/absolute/new-blank-project'
```

升级后可先创建隔离测试目录，再运行 `native-draft.cjs roundtrip '/absolute/test-directory'`。它写入独立测试文件、原生读取并比较内容；测试成功仅证明该版本的加密读写可用。`self-test` 校验时间范围与缺失媒体保护。`apply` 出错会保留完整备份并退出，不能在未检查目标状态时盲目重试。

5. 重新启动剪映，从首页打开此工程。检查真实时间线、预览和音频，修正视觉质量，再保存并重新打开。磁盘读回成功不能替代此步骤。无需单独改 `template.tmp`；主要加载文件是根目录和 `Timelines/<main_timeline_id>/` 下的 `draft_content.json`、`template-2.tmp`。
6. 在剪映中命名工程、导出 MP4、打包素材。命名后重新读实际路径，不能只从文件夹重命名推断首页索引已更新。备份位于工程旁 `*.before-native-*`，恢复时应用必须关闭并使用完整备份，避免混合两个版本文件。

## 原生请求协议

`initialize('{}')` 后，持久化读写请求为：

```javascript
{id:'read', domain:'draft', operation:'readFile',
 params:{rootPath:projectAbsolutePath, path:absoluteFilePath}, protocolVersion:1}
```

`path` 必须是 rootPath 内的绝对文件路径；仅传 draftPath 或相对文件名会返回 `draft_path_invalid`。writeFile 同样参数加 `content: JSON.stringify(snapshot)`；返回 accepted/encrypted/cipherType。不要自行实现或猜测加密算法。

播放器请求使用 `method` 和 `sessionId`，不能把服务层的 targetId 原样当播放器 sessionId：

```javascript
{method:'create', params:{kind:'draft'}}
{method:'load', sessionId, params:{draftJson:jsonString, workspacePath:root}}
{domain:'edit', operation:'draft.setDraft', targetId:sessionId,
 params:{draftSnapshot:sourceObject}, protocolVersion:1}
```

工具返回 `accepted:true` 仍需检查 snapshot、片段数量、duration。旧快照直接 load 曾得到 ready 但 duration=0；通过 setDraft 得到正确 duration。原生 add-video 测试曾在进程退出时发生 mutex 异常，不能将其包装为稳定的公共 SDK。发生崩溃后检查目标是否已修改，必要时从备份恢复并在隔离副本测试。
