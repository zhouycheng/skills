---
name: provision-macos-env
description: 重建或对账 macOS 整机开发环境——先扫描当前环境、比对声明清单、逐项协商后再安装，覆盖 brew formula/cask、无上游自建资产与 shell 配置。用于「重装系统后恢复环境」「从零配一台新 Mac」「我装了哪些但清单里没有」「哪些声明了还没装」「环境漂移对账」这类需求；也用于排查 zsh 补全失效（Tab 补全不工作、弹出 do you wish to see all N possibilities、想要行内灰色虚影 ghost text）。核心纪律：扫描先于建议、逐项确认、绝不批量静默安装。
agent_created: true
---

# macOS 环境供给与对账

按声明重建或校正本机开发环境。**这是一个对账向导，不是安装器。**

## 何时使用

- 重装系统 / 换新机后，要恢复出需要的工具链
- 想知道"我现在装了哪些、清单里少了什么、声明了哪些还没装"
- 日常维护：把新装的包纳入清单，或把不再需要的从清单移除
- 排查 zsh 补全失效（Tab 不补全、弹出候选询问、缺行内灰色虚影）
- 排查 JVM 系工具走不了代理（Android Studio / sdkmanager / Gradle 下不动插件或依赖，
  报 `Remote host terminated the handshake`、`IO exception while downloading manifest`）

## 三条红线（任何时候不得违反）

1. **禁止静默安装。** 任何 `brew install` / `cask` / 写配置文件之前，必须就该项获得用户明确同意。
2. **禁止一次性安装清单全部。** 「执行技能 → 全装好」是**错误行为**，不是便利。
3. **扫描先于任何建议。** 未跑过 `probe.sh` 之前不得给安装建议——否则建议基于想象而非事实。

## 五阶段

### 阶段 0 · 判定机器状态

跑 `scripts/probe.sh`，读它的分区 0：

- **brew 缺失** → 属「全新机器」。打印下面两条命令后**停止**，不要尝试自动安装：
  ```
  xcode-select --install
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```
  ⚠️ **Homebrew 安装脚本必须交互输入 sudo 密码，Agent 环境执行不了**（`sudo` 报
  `operation not permitted`）。明确告诉用户"此步请由你本人执行"。
- 状态目录不存在 → 「全新供给」；存在 → 「增量对账」。

### 阶段 1 · 扫描（只读，强制）

```bash
~/.agents/skills/provision-macos-env/scripts/probe.sh          # 完整报告
~/.agents/skills/provision-macos-env/scripts/probe.sh --brief  # 只看汇总
```

产出四个分区：

| 分区 | 含义 | 后续 |
|---|---|---|
| 1 清单内 · 未安装 | 已声明但尚未落地 | 候选安装，**需询问** |
| 2 清单外 · 已直接安装 | 用了但没记，或该卸 | **需对比判断** |
| 3 清单内 · 已安装 | 一致 | 不动，仅计数 |
| 4 作为依赖装入 | 非用户意图 | 仅信息展示，**不进建议** |

### 阶段 2 · 呈现与协商

- 先给结论，再给明细。**用表格**呈现分区 1 与 2。
- **分区 1**：**按分类分组**询问是否安装，不逐条问。新机上清单可能有数十项，逐条问是折磨。
- **分区 2**：对每项按下面的「对账判断准则」给出判断与依据，**由用户裁决**。
- **明确告知每项将执行的确切命令**，不要模糊表述为"帮你装好"。

### 阶段 3 · 执行（逐项确认后）

- 只做用户批准的项，一次一个。
- 每项执行后立即验证（`brew list <pkg>` / `command -v <cmd>`），**失败即停**，不继续后续项。
- **涉及 `sudo` / `chmod` 的步骤不由 Agent 执行**，改为输出命令请用户本人跑。
- 配置类改动走 `manifest/zsh/deploy.sh`（它自带备份与 `zsh -n` 校验）。
  **它只管「标记行起至文件末尾」的那一段**；标记行**之前**是用户自有配置
  （starship / zoxide / fzf 的初始化等），不归它管——需要改时直接改并单独备份，
  改完用 `deploy.sh --check` 确认没有碰坏受管块。

### 阶段 4 · 回写声明（闭环）

**这一步不做，下次扫描会重复报同样的差异。** 它是对账机制的一半。

```bash
scripts/declare.sh <包名> --section "<分类>"   # 纳入清单
scripts/declare.sh --remove <包名>             # 移出清单
```

- 移除声明**不等于**卸载。是否真的卸载需单独确认。
- 收尾提示用户复核与提交，**Agent 不自动 commit**。

## 对账判断准则（针对分区 2）

按顺序判断。**能判断就给依据；判断不了就如实说，不许编造理由。**

| # | 情形 | 建议 |
|---|---|---|
| 1 | 是清单内某包的直接依赖 | 不单列（`installed_on_request` 已自动剔除） |
| 2 | 与清单内某项**功能重叠** | 指出重叠，建议二选一，说明各自取舍，用户裁决 |
| 3 | 是清单内某项的**替代/升级** | 建议替换，并说明原项是否应一并移除 |
| 4 | 无法归入任何现有分类 | 建议**新增分类**，不要硬塞进最接近的那一段 |
| 5 | **判断不了** | 只呈现客观事实（装机日期、版本、依赖数），明确说"需要你的输入" |

第 5 条是刻意的。一部分包在缺少上下文时确实无法判断用途。宁可留白，也不用听起来合理的话把它填满
——填满的代价是用户基于错误依据做决定。

## 两种模式

| | 全新重建 | 增量对账 |
|---|---|---|
| 触发 | `brew` 缺失，或状态目录不存在 | 日常调用 |
| 协商粒度 | **按分类分组**询问 | **逐项**询问 |
| 典型差异量 | 清单全部为「未安装」 | 通常只有数项 |

## 边界：本技能不做什么

- **不批量安装、不静默安装**（红线 1、2）。
- **不自定义包管理格式**。能用 `brew bundle` 原生表达的一律不另造，历史上自建 `pins.txt`
  + codeload 下载器属重复实现 brew 已有能力，已废弃。
- **不预建空壳目录**。需要管 npm 全局包时再加 `manifest/npmfile.txt`，用到才建，
  避免"看起来已经支持"的错觉。
- **不写 `~/.zshrc` 的那段配置块**——它由 `zshrc.snippet` 生成，手改必然漂移。
- **不把受管块里的 `compinit -i -C` 改回单个 `-i`**。`-C` 是刻意加的：Agent 宿主的沙箱
  会挡住 `$HOMEBREW_PREFIX/share/` 下的补全目录，使 fpath 实扫数与缓存头部声明不符，
  于是每个 shell 都判定缓存失效并重建，而收尾的 `mv` 又被宿主垫片拒绝 → `$HOME` 堆积
  `.zcompdump.<host>.<pid>` 临时件、启动变慢。`-C` 直接采用现有缓存，一次解决三者。
  代价是「新补全不再自动纳入」→ **装完新补全后删一次 `~/.zcompdump`**。
  细节与对照实验见 `references/zsh-completion.md`。
- **不代跑 `sudo` / `chmod`**。

## 文件与脚本速查

```
scripts/probe.sh              只读扫描，对账唯一入口（静态：清单 vs 装机）
scripts/verify.sh             功能级验证（运行时：补全能不能补、虚影画没画出来）
scripts/declare.sh            把包写进/移出 Brewfile 分类段（只改声明，不装不卸）
manifest/Brewfile             唯一手工维护点
manifest/README.md            清单维护规则
manifest/zsh/zshrc.snippet    ~/.zshrc 受管块的唯一真相源
manifest/zsh/deploy.sh        对齐 ~/.zshrc + 落位 assets
manifest/assets/              无上游的自建资产
```

`probe.sh` 与 `verify.sh` 是**互补**的两层，都要通过才算真的交付：
前者看声明与资产的静态对账，后者在伪终端里验证运行时行为（`verify.sh` 依赖同目录的
`_pty_probe.py`，需要 `python3`；无 python3 时该项自动跳过并说明原因）。

**深入细节时读**：

- `references/zsh-completion.md` — 补全故障诊断：compinit 根因判定、四个假阴性陷阱、插件互斥、
  正确验证方法、fzf 启动噪音、shell 历史卫生、`.zcompdump.<host>.<pid>` 残留的源码级机制。**只在诊断补全问题时读。**
- `references/manifest-format.md` — Brewfile 格式与分类约定、`brew bundle` 命令语义、
  脚本维护的五个已验证坑（`$VAR`+中文标点、BSD grep 的 `\xNN` 陷阱、zsh 空 glob 中断、
  **Agent 宿主 PATH 垫片劫持 `rm` 等 21 个命令**、macOS `/bin` 与 `/usr/bin` 绝对路径核实）。
  **只在改清单或改脚本时读。**
- `references/jvm-proxy.md` — JVM 系工具（Android Studio / sdkmanager / Gradle）的代理配置：
  为什么系统代理与 `HTTP_PROXY` 都不生效、三条配置通道、对照实验诊断法、
  插件手动安装（`pluginManager` 端点 + `unzip -t`，含 `id=`/`build=` 取值陷阱：
  Flutter 必须用 `io.flutter` 而非 `Flutter`，`build` 必须带 `AI-` 前缀）。**只在排查这类网络故障时读。**
