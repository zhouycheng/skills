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
