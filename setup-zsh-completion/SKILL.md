---
name: setup-zsh-completion
description: 在 macOS 上启用、修复和配置 zsh 补全——既包括 Tab 候选选择，也包括编辑器式的行内灰色虚影（ghost text）。用于「Tab 补全不工作」「按 Tab 只弹出 do you wish to see all N possibilities」「brew/git/docker 的补全没用」「想要编辑器那种虚影/半透明补全」「装个 zsh 补全插件」这类需求。覆盖先判定 compinit 是否从未启用这个真正根因、四个插件的角色与硬依赖、加载顺序硬约束与插件互斥、pins 驱动的幂等安装、必须用伪终端做功能级验证及四个假阴性陷阱、以及分层回退。
agent_created: true
---

# 启用与修复 macOS 上的 zsh 补全

交付两件事：**Tab 候选选择**（fzf 选择器，替代原生"是否查看全部 N 行"）与**行内灰色虚影**（ghost text，`→` 接受整条）。

## 何时使用

- 「补全不工作」「按 Tab 弹出 `zsh: do you wish to see all 117 possibilities`」
- 「想要代码编辑器那种虚影 / 半透明补全」「ghost text」
- 「brew / git / docker 的补全一直没用」
- 在新 Mac 上重建终端补全环境

## 第 0 步（必做）：先判定 compinit 是否从未启用

**这是"补全不工作"最常见的真正根因，出现频率远高于插件缺失。** macOS 默认不启用 `compinit`，用户的 `~/.zshrc` 里往往从来就没有它——此时表现不是报错，而是**所有补全静默失效**，用户已习以为常、不会主动报告。

```bash
whence -w compdef                                   # 输出 "compdef: none" = 补全系统根本没启用
grep -nE 'compinit|fpath' ~/.zshrc /etc/zshrc 2>/dev/null
ls ~/.zcompdump* 2>/dev/null                        # 无此文件同样说明 compinit 从未跑过
```

判定要点：

- `compdef: none` → **先修 compinit，再谈装插件**。跳过这一步去装插件，问题依旧。
- 同时确认 `fpath` 是否包含插件目录（`~/.local/share/zsh/site-functions` 与 `zsh-completions/src`）。

### 验证补全是否注册，只有一个正确写法

```bash
zsh -i -c 'print -r -- ${+_comps[brew]}'     # 正确：1 = 已注册
```

- ❌ `${(k)_comps[(i)brew]}`、`test -n "${_comps[brew]}"`、`${_comps[(i)brew]}` 都会给出**假阴性**。
- 经 `bash -c 'zsh -c "…"'` 这类嵌套包裹时，`$`、`()` 会被二次解析，检查结果失真。需要跨 shell 传递时**写进脚本文件再执行**，不要塞进命令行。

## 插件清单与角色

| 插件 | 作用 | 备注 |
|---|---|---|
| `zsh-users/zsh-autosuggestions` | **行内灰色虚影**，`→` 接受整条、`Ctrl+→` 接受一个词 | 用户口述的"编辑器那种虚影"就是它 |
| `Aloxaf/fzf-tab` | Tab 弹 fzf 模糊选择器，替代原生"是否查看全部 N 行" | **硬依赖 `fzf` 二进制**，先 `command -v fzf` |
| `zsh-users/zsh-syntax-highlighting` | 命令语法实时着色 | 顺带暴露"不存在的命令" |
| `zsh-users/zsh-completions` | 社区补全定义 | 需把其 `src` 加入 `fpath` |

配套 `zstyle`（否则仍会走原生询问式列表）：

```zsh
zstyle ':completion:*' menu select
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{cyan}%d%f'
```

## 加载顺序是硬性要求

```text
fpath + zstyle → compinit → fzf-tab → zsh-autosuggestions → zsh-syntax-highlighting（必须最后）
```

- `fzf-tab` 与 `zsh-autosuggestions` 都必须在 `compinit` **之后**，否则拿不到补全函数。
- `zsh-syntax-highlighting` **必须最后** source，否则它的高亮会被后续插件覆盖。
- **`marlonrichert/zsh-autocomplete` 与 `zsh-autosuggestions` 互斥**：两者 hook 同一批 ZLE widget（`self-insert` / `orig-self-insert` / `forward-char` 等），同装会出现虚影闪烁或行为互相覆盖。**二选一**，不要"都装上试试"。

## 安装：pins 驱动、幂等、不 vendor

插件本体**不纳入 git**，只把 commit SHA 声明进 pins 文件。macOS 无需 git，按 commit 走 codeload 即可：

```bash
curl -fsSL "https://codeload.github.com/<owner>/<repo>/tar.gz/<full-sha>" -o /tmp/p.tgz
tar -xzf /tmp/p.tgz -C /tmp/extract          # 解包后顶层是 <repo>-<sha>/，需拍平
```

- `codeload.github.com` 在本机可达（HTTP 200），无需 sudo。
- GitHub 匿名配额 60 次/小时；批量下载会中途静默失败，需单条退避重试。
- 目标目录 `~/.local/share/zsh/plugins/<name>/`。
- 装完把 `owner/repo  sha  date` 写进同目录 `VERSIONS.txt`，作为**实际状态**，供与 pins（**期望状态**）比对漂移。

本机的权威实现是 `~/.agents/env/zsh/`（`pins.txt` + `install.sh` + `zshrc.snippet`），**优先直接调用它**而不是每次手搓命令：

```bash
~/.agents/env/zsh/install.sh check     # 只读：报告 pins / 磁盘 / .zshrc 三者漂移
~/.agents/env/zsh/install.sh           # 安装或修复（幂等）
```

## 验证：必须用伪终端，且要抓功能证据

```bash
script -q /dev/null /bin/zsh -i -c 'print -r -- ${+_comps[brew]}'
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

⚠️ **虚影基于历史，不是基于补全定义。** 用户若抱怨"敲 `brew ` 没有虚影"，这属**预期行为**——历史里没有记录就不会有建议。先确认用户确实跑过该命令，不要据此判定故障。

⚠️ **`→` 接受建议的机制容易被误判**：插件通过 `ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=(forward-char …)` **包装** `forward-char`，所以 `bindkey '^[[C'` 仍显示 `forward-char` 属**正常**，不代表插件没生效。

## 回退

改动只应落在两处，回退即覆盖这两处：

1. `~/.zshrc` 中由标记行（`# ---- zsh 补全系统`）起、到文件末尾的整个块
2. `~/.local/share/zsh/plugins/` 下的插件目录

```bash
~/.agents/env/zsh/rollback.sh basic --apply   # 只保留 compinit，撤掉四个插件
~/.agents/env/zsh/rollback.sh full  --apply   # 连 compinit 一并撤掉
```

两者都幂等，移除一律走 `~/.Trash`，不用 `rm`。

## 本机约定与三个坑

1. **唯一真相源是 `~/.agents/env/zsh/`**。`~/.zshrc` 里的块由 `install.sh` 从 `zshrc.snippet` 生成。**不要手工改 `.zshrc` 而不改 snippet**，否则必然漂移——这正是"补全失效却长期无人察觉"的同类问题。
2. **`~/.workbuddy/skills` 不是 `~/.agents/skills/scripts/sync.py` 的同步目标**：该脚本的 `AGENT_NAMES` 只有 `.trae-cn / .codex / .claude / .gemini`。这是**刻意的**——一旦加入 `.workbuddy`，同步会把仓库全部 70+ 技能批量建成符号链接涌进 WorkBuddy，污染技能列表并增加每轮上下文开销。因此新技能要在 WorkBuddy 生效，需**手工建一条**符号链接：
   ```bash
   ln -s ~/.agents/skills/<name> ~/.workbuddy/skills/<name>
   ```
3. **编辑 `~/.zshrc` 前先备份**到 `<workspace>/.workbuddy/backup/`；改动只追加，不改既有行。
