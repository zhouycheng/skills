# zsh 补全：诊断与排错

本文件是 `provision-macos-env` 的参考文档，只在**诊断补全相关故障**时读取。
供给侧的声明在 `manifest/zsh/`，装载路径由 `manifest/Brewfile` 的包决定。

## 第 0 步（必做）：先判定 compinit 是否从未启用

**这是"补全不工作"最常见的真正根因，出现频率远高于插件缺失。** macOS 默认不启用 `compinit`，
用户的 `~/.zshrc` 里往往从来就没有它——此时表现不是报错，而是**所有补全静默失效**，
用户已习以为常、不会主动报告。

```bash
whence -w compdef                                   # "compdef: none" = 补全系统根本没启用
grep -nE 'compinit|fpath' ~/.zshrc /etc/zshrc 2>/dev/null
ls ~/.zcompdump* 2>/dev/null                        # 无此文件同样说明 compinit 从未跑过
```

判定要点：

- `compdef: none` → **先修 `manifest/zsh/zshrc.snippet` 与 `deploy.sh` 这条链路，再谈插件**。
  跳过这一步去装插件，问题依旧。此时 brew/docker/git 的补全全是失效的。
- 同时确认 `fpath` 包含两处：`~/.local/share/zsh/site-functions`（无主资产）与
  `$(brew --prefix)/share/zsh-completions`（brew 管辖，**须在 compinit 之前**）。

### 验证补全是否注册，只有一个正确写法

```bash
zsh -i -c 'print -r -- ${+_comps[brew]}'     # 正确：1 = 已注册
```

- ❌ `${(k)_comps[(i)brew]}`、`test -n "${_comps[brew]}"`、`${_comps[(i)brew]}` 都会给出**假阴性**。
- 经 `bash -c 'zsh -c "…"'` 这类嵌套包裹时，`$`、`()` 会被二次解析，检查结果失真。
  需要跨 shell 传递时**写进脚本文件再执行**，不要塞进命令行。

## 四个插件的角色

| 插件 | 作用 | 备注 |
|---|---|---|
| `zsh-autosuggestions` | **行内灰色虚影**，`→` 接受整条、`Ctrl+→` 接受一个词 | 用户口述的"编辑器那种虚影"就是它 |
| `fzf-tab` | Tab 弹 fzf 模糊选择器，替代原生"是否查看全部 N 行" | **硬依赖 `fzf` 二进制** |
| `zsh-syntax-highlighting` | 命令语法实时着色 | 顺带暴露"不存在的命令" |
| `zsh-completions` | 社区补全定义 | 需在 compinit 前加入 fpath |

四个都是 homebrew-core **bottled** formula，全部由 `manifest/Brewfile` 声明、`brew` 安装。
**不要再自建下载器**：曾经为它们自建过 `pins.txt` + codeload 安装器，属重复实现 brew 已有能力，已废弃。

### 装载路径（由 formula 源码核实，非 caveat 转述）

| 插件 | 装载路径 |
|---|---|
| zsh-autosuggestions | `$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh` |
| zsh-syntax-highlighting | `$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh` |
| zsh-completions | fpath 加 `$(brew --prefix)/share/zsh-completions`（**须在 compinit 之前**） |
| fzf-tab | `$(brew --prefix)/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh` |

装载路径只写在 `manifest/zsh/zshrc.snippet` 里，**不要手工改 `~/.zshrc` 的那个块**——
该块由 `deploy.sh` 从 snippet 生成，手改必然漂移。

## 加载顺序是硬性要求

```text
fpath + zstyle → compinit → fzf-tab → zsh-autosuggestions → zsh-syntax-highlighting（必须最后）
```

- `fzf-tab` 与 `zsh-autosuggestions` 都必须在 `compinit` **之后**，否则拿不到补全函数。
- `zsh-syntax-highlighting` **必须最后** source，否则其高亮会被后续插件覆盖。
- **`marlonrichert/zsh-autocomplete` 与 `zsh-autosuggestions` 互斥**：两者 hook 同一批 ZLE widget
  （`self-insert` / `orig-self-insert` / `forward-char` 等），同装会出现虚影闪烁或行为互相覆盖。
  **二选一**，不要"都装上试试"。

## 验证：必须用伪终端，且要抓功能证据

```bash
script -q /dev/null /bin/zsh -i -c 'print -r -- ${+_comps[brew]}'                  # 期望 1
script -q /dev/null /bin/zsh -i -c 'print -l ${(k)widgets}' | grep -c autosuggest  # 期望 9
```

### 四个假阴性陷阱（每一个都会让你误判"装失败了"）

| 陷阱 | 现象 | 正确做法 |
|---|---|---|
| ZLE widget 只在 ZLE 激活时创建 | 非 TTY 下 `whence autosuggest-accept` 报未定义 | 用 `script -q /dev/null` 造 pty |
| macOS **没有** `timeout` 命令 | `timeout 25 curl …` 报 command not found，易被误读为"目标不可达" | 用 `gtimeout`（coreutils）或省略超时 |
| 嵌套引号二次解析 | `$` / `()` 在 `bash -c → zsh -c` 传递中被吃掉 | 写成脚本文件再执行 |
| `zsh -i -c` 反复调用留垃圾 | 残留 `~/.zcompdump.<host>.<pid>`（约 49KB/个） | 事后清理，`mv` 进 `~/.Trash` |

### 功能级证据（唯一可信的"虚影生效"证明）

向历史喂入一条命令，再在真实终端敲它的前缀，从**终端回显**中同时抓到"前缀"与"完整命令"：

```bash
print -s 'docker compose up -d --build'     # 灌进当前会话历史
# 之后在用户终端敲 `docker c`，观察是否出现整条灰色虚影
```

⚠️ **虚影基于历史，不是基于补全定义。** 用户若抱怨"敲 `brew ` 没有虚影"，这属**预期行为**——
历史里没有记录就不会有建议。先确认用户确实跑过该命令，不要据此判定故障。

⚠️ **`→` 接受建议的机制容易被误判**：插件通过 `ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=(forward-char …)`
**包装** `forward-char`，所以 `bindkey '^[[C'` 仍显示 `forward-char` 属**正常**，不代表插件没生效。

## brew 侧两个已知注意事项

（来自 formula 源码 caveat）

- 迁移或升级后可能需要强制重建补全缓存：`rm -f ~/.zcompdump; compinit`。
- 若出现 `zsh compinit: insecure directories` 警告，需：
  ```bash
  chmod go-w '/opt/homebrew/share'
  chmod -R go-w '/opt/homebrew/share/zsh'
  ```
  **这两条涉及写系统路径权限，必须由用户本人执行**，Agent 不得代跑 `chmod`。

## fzf 集成在非交互启动时的噪音（2026-09-24 实测）

**现象**：每次 `zsh -i -c '...'`（脚本/CI/Agent 调用）启动时吐两行
`(eval):1: can't change option: zle`。

**根因**：`fzf --zsh` 生成的代码用 `options=(${(j: :)${(kv)options[@]}})` 做**全量**
选项快照，结束时 `eval` 回填；快照含 `zle on`，而 zsh 的 `zle` 选项**启动后不可改**，
回填被拒。上游 issue #2219/#2262 被官方定性为"使用侧问题"关闭，**确认不修**（0.74.4 仍如此）。

**修复（使用侧规避）**：`~/.zshrc` 中把 `source <(fzf --zsh)` 改为**条件加载**：

```zsh
[[ -t 0 && -o interactive ]] && source <(fzf --zsh)
```

**判定条件的选择（踩过的坑，不许猜）**：
- `[[ -o zle ]]` **不行**：zsh 对 `-i` 启动的 shell 即使无 tty 也会置 zle 选项，无法区分。
- `[[ -t 0 ]]` 才行：真实终端 stdin 是 tty → true；脚本/CI stdin 是管道或 /dev/null → false。
  非交互场景本来就不该加载按键绑定，语义正确。
- 验证必须**双向**：无 tty 下 stderr 为空 **且** 真实 pty 下 `widgets[fzf-history-widget]`=1
  （verify.sh §1 与 §2 的 `p_widget_fzf_hist` 探针就是这对回归测试）。

**附带发现**：macOS `/etc/zshrc` 会强制把 `HISTFILE` 重置为 `~/.zsh_history`（覆盖环境变量）。
任何想用假历史做测试的探针，必须在启动后用 `fc -R <file>` 显式灌入，并先 `SAVEHIST=0`
防止测试命令写进用户真实历史。

## `~/.zcompdump.<host>.<pid>` 残留：**根因已定论**（2026-09-24 实测）

**现象**：`$HOME` 里堆积 `.zcompdump.Justins-MacBook-Pro.local.<pid>`，每个都是完整大小。

**写入链路（已定位到行，zsh 5.9）** —— 生成者是 `compdump`，不是 `compinit`：

| 文件 | 行 | 作用 |
|---|---|---|
| `/usr/share/zsh/5.9/functions/compdump` | L21 | `_d_file=${_comp_dumpfile}.$HOST.$$` → 临时文件名 |
| 同上 | L36 | `exec {_d_fd}>$_d_file` → 创建并写满 |
| 同上 | L138 | `mv -f $_d_file ${_d_file%.$HOST.$$}` → 改名成正主 |
| `/usr/share/zsh/5.9/functions/compinit` | L486 | 先比对 dump 头部 `#files: N`；**匹配就直接 source，完全不碰临时文件** |
| 同上 | L549 | 仅在需要重建时**同步**调用 `compdump` |

**判定"断在哪一步"看文件大小即可**：所有残留都是 **56723 字节 = 与正式 `.zcompdump`
完全同尺寸** → 内容是**写完的**，断点是 L138 那句 `mv`。

**根因（决定性证据，别再猜）**：L138 的 `mv` 在 Agent 宿主里命中的不是 `/bin/mv`，
而是 **PATH 前置的 `brokered-bin` 垫片**（见 `manifest-format.md` 坑 4）。垫片按文件策略
拒绝了这次改名，并在 stderr 打印：

```
Brokered host rename source refused by file policy: prompt
```

沙箱层同时记录了对应的拒绝项：

```
[sandbox] 命令被沙箱拦截，以下操作被拒绝：
  - /Users/zhou/.zcompdump.Justins-MacBook-Pro.local.<pid> (file-unlink)
```

→ **临时件改名失败、被删除也被拒，于是原地留下。** 每个"需要重建 dump 且走了宿主
沙箱"的 zsh 启动留下一个，PID 因此在时间上连续成簇。

**为什么一度"复现不出来"（重要方法论）**：早期那些对照实验全部是在
`⚠️ Sandbox bypassed (escalation-approved)` 的**提权**环境下跑的 —— 没有垫片拦截，
`mv` 成功，于是 7 种启动方式（管道喂 exit / `-il` 登录 / 读 `/dev/null` / 经 pty /
启动后 SIGKILL / 立即 SIGKILL / 正常）**全部显示 0 残留**，从而误判为"用户态不可复现"。
**教训：在 Agent 宿主里做行为对照实验，必须先确认本次是否带沙箱**；两种环境下结论相反。

**上游触发条件（这才是要治的点）**：`compinit` **只在**「dump 头部的 `#files: N` ≠ 当前
fpath 实扫数」时才重建。实测 Agent 宿主的沙箱会挡住 `$HOMEBREW_PREFIX/share/` 下的补全目录，
使实扫数由 **1162 掉到 967**（差额 180 + 15 = `share/zsh-completions` 与
`share/zsh/site-functions` 两者之和）→ **每个 shell 都判定缓存失效**。

完整因果链：

```
沙箱挡住 /opt/homebrew/share/*
  → fpath 实扫数 1162 → 967
  → compinit 判定 dump 失效（L486）
  → 每个 shell 都调 compdump（L549）重建
  → compdump 收尾那句 mv 命中 brokered-bin 垫片，被文件策略拒绝
  → 临时件留在 $HOME ＋ stderr 噪音 ＋ 每次启动白付一次 1162 文件全量扫描
```

**修复：`~/.zshrc` 里把 compinit 改成 `-i -C`**。`-C` 令 `_i_check` 为空，compinit L486
于是走 `else` 分支直接 source 现有 dump，**既不比对计数也不重建**。

对照实验（把 dump 头部故意改成 `#files: 9999`，两种写法各跑一个 shell，与环境无关）：

| 写法 | 跑完后头部 | 是否重建 |
|---|---|---|
| `compinit -i`（旧） | `#files: 1162` | **重建了** |
| `compinit -i -C`（新） | `#files: 9999`（原样不动） | **没重建** |

代价与配套：`-C` 关掉了「新补全自动纳入」。**装完新补全后删一次 `~/.zcompdump` 即可**
（`/bin/rm -f ~/.zcompdump`，下次启动会重建一份完整的）。拿这一点点手工成本，换掉
「残留 + 噪音 + 每次启动全量扫描」，明确划算。

**边界（对使用者很重要）**：

- 这是**宿主侧行为**，`~/.zshrc` 与 `probe.sh` / `verify.sh` 都没有问题。
- **用户自己的终端不会出现**：那里命中的是 `/bin/mv`，改名正常成功。
- 残留物是**可再生缓存**，不是配置；主 `.zcompdump` 一直有效，补全照常工作。

**清理**（用绝对路径，避免又走垫片）：

```zsh
/bin/rm -f "$HOME"/.zcompdump.*      # 只删 PID 后缀的临时件，主 .zcompdump 留着
```

**`-C` 生效后不会再新增**，所以这是一次性收尾，不必反复跑。`probe.sh` 的【缓存卫生】
分区仍会报告它看到的数量（只报告、不代删），作为回归观测点。

**为什么不自动清**：`compdump` L138 是 `mv -f <临时件> <正主>`。若在启动末尾盲删
`*.zcompdump.*`，会删掉**并发启动的另一个 shell 正在写的临时件**，导致它那句 `mv`
报 "No such file or directory" 到 stderr —— 噪音比残留本身更糟。故只给手动命令。

**`-C` 与 `-D` 的区别（别混）**：两者都不重建，但
`-C` 仍会 **source 现有 dump**（快速、功能完整）；
`-D` 是关掉 dumping 且**不信任缓存**，`_i_done` 保持为空 → 每次启动都全量重扫 fpath
（本机 1162 个文件），启动变慢。所以这里选 `-C`，不选 `-D`。

**verify.sh 的配套处理**：宿主这条拒绝消息会落在 §1 冷启动的 stderr 上，使
「stderr 必须为空」断言**偶发失败**（取决于这次启动是否需要重建 dump）。已在
`verify.sh` §1 的噪音分类里把它与 fzf 噪音并列为**已知宿主噪音 → skip（并打印原消息）**，
而不是 pass —— 既不掩盖，也不误判成配置缺陷。`-C` 生效后这条噪音本应不再出现，
保留该分类纯属纵深防御（例如用户自己另外起了一个走默认 compinit 的 shell）。
