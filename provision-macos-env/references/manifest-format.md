# 清单格式与维护

## 为什么用 Brewfile 原生格式

`brew bundle` 的全套工具可直接作用于它，**零转换层**。曾评估过 YAML/TOML + 生成器方案，
被否决：那会引入"两种表示"，必然漂移，且需要维护一个额外的生成器。

前车之鉴：本项目早期曾为四个 zsh 插件自建 `pins.txt` + codeload 下载器，属重复实现 `brew bundle`
已有能力，已整体废弃。**结论：能用 brew 原生格式表达的东西，不自定义格式。**

## Brewfile 语法要点

```ruby
# ==== <分类名> ====          ← 分类标记（本项目的约定）
brew "formula-name"           # formula，可带行内注释说明用途
cask "app-name"               # 应用
tap "owner/repo"              # 第三方 tap
mas "App Name", id: 123456    # App Store（需 mas 命令）
```

- 注释以 `#` 开头，`brew bundle` 会忽略，因此行内说明是安全的。
- 分类标记必须独占一行，格式固定为 `# ==== 名称 ====`（前后各两个空格 + 四个等号）。
  `declare.sh` 与 `probe.sh` 都按这个正则解析，改格式会让两个脚本同时失准。

## 三类不该进清单

1. **有上游的第三方代码**（zsh 插件本体、下载的二进制）→ 交给包管理器
2. **作为依赖被装入的包** → `brew bundle` 会自行解析，无需声明
3. **一时试验的包** → 先用着，下次对账时再决定

反过来：**自己写的、没有上游的脚本应当进 `manifest/assets/`**。它没有上游可竞争，丢了就没了。
判断口诀：**不 vendor 有上游的东西；无上游的自建资产应当纳管。**

## 声明与实际必须分离

| | 载体 | 是否提交 |
|---|---|---|
| 声明（期望） | `manifest/Brewfile` | ✅ 提交，人工维护 |
| 实际（探测） | `~/.local/state/env/`（仓库外） | ❌ 永不提交 |

**绝不能拿 `brew bundle dump` 的输出覆盖 `manifest/Brewfile`**——那会把人工意图冲掉。
两者的差异才是对账报告本身。仓库外的状态目录同时满足约束"声明与实际物理分离"，
避免每次部署都弄脏 git 工作区。

## brew bundle 命令速查（实测语义）

| 命令 | 作用 | 退出码语义 |
|---|---|---|
| `brew bundle list --file=X --all` | 列出 X 中的全部条目（**不加 `--all` 只列 formula**） | **仅语法错误返回 1**；包不存在**不**报错 |
| `brew bundle check --file=X --verbose` | 检查 X 中条目是否都已安装 | 0 = 全部满足 |
| `brew bundle install --file=X` | 安装 X 中的全部条目 | — |
| `brew bundle dump --force --file=Y` | 把**当前已装**导出为 Y（用于产出"实际状态"） | — |

两个必须记住的点：

1. `brew bundle list` **只校验语法，不校验包名是否存在**。所以它能防止格式写坏，
   但不能防止写错包名——写错包名会在下次 `check` 或 `install` 时才暴露。
2. `brew bundle list` 默认只列 formula，要列 cask 必须加 `--all`。

## 脚本维护：四个已验证的坑

### 坑 1：`$VAR` 后紧跟中文标点会被吞进变量名

UTF-8 locale 下 bash 的 `isalnum()` 会把多字节前导字节判为标识符字符，于是：

```bash
warn "未声明 $PKG，无需移除。"     # ✗ set -u 下报 "PKG，: unbound variable" 并中断
warn "未声明 ${PKG}，无需移除。"   # ✓ 始终加花括号
```

**规则：变量后面只要紧跟非 ASCII 字符，一律写成 `${VAR}`。** 这个 bug 不会在语法检查
（`bash -n`）中暴露，只在运行时炸，且在 `set -u` 下会直接中断脚本。

排查方法（**必须用 `[^ -~]` 这种 POSIX 写法**）：

```bash
grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' scripts/*.sh ../manifest/zsh/deploy.sh
```

⚠️ **不要用 `[^\x00-\x7F]`**：BSD grep（macOS 自带）不解析括号表达式里的 `\xNN` 十六进制转义，
`\x00-\x7F` 会被当成字面字符集 `{ \, x, 0, -, 7, F }`，于是「非此集合」几乎匹配任意字符，
**每一行含 `$VAR` 的行都会假报**。本项目实测踩过：用它审计时 4 个脚本报出十几处假阳性。

### 坑 2：判断"顶层包"不能用 `brew list`

`brew list --formula` 会包含依赖。本机实测：**96 个 formula 里有 76 个是依赖（79%）**。
若用它做对账集合，"清单外·已装"会列出 76 个用户从未主动装过的包，报告立刻失去可信度。

正确做法（一次调用同时拿到过滤、版本、日期）：

```bash
brew info --json=v2 --installed | python3 -c '
import json,sys
d=json.load(sys.stdin)
for f in d["formulae"]:
    i=(f.get("installed") or [{}])[0]
    if i.get("installed_on_request"):      # ← 只保留用户主动装的
        print(f["name"], i.get("version"), i.get("time"))
'
```

`installed_on_request` 为真的集合与 `brew leaves` 完全一致（本机均为 20 项），但一次调用即可
同时得到版本与安装时间，比 `brew leaves` 更省调用。

cask 侧同理：`brew list --cask` 已天然是顶层，安装日期可从 `/opt/homebrew/Caskroom/<name>` 的
目录 mtime 廉价取得。

### 坑 3：zsh 下空 glob 会中断整条复合命令

Agent 宿主常以 zsh 执行命令。zsh 默认 `nomatch`：**glob 匹配不到任何文件时报错，
并中止它所在的整个命令列表**——同一行里 glob 之前的 `echo` 都不会执行。这与 bash（保留字面量）行为相反，
极易把「没匹配到」误判成「脚本没跑」。

```bash
# ✗ 若 /tmp/env-verify.* 不存在，整条命令直接中止，前面的 echo 也不输出
for f in /tmp/a /tmp/env-verify.*; do mv "$f" ~/.Trash/; done

# ✓ 方案 A：开空 glob（放脚本开头）
setopt NULL_GLOB 2>/dev/null || true
# ✓ 方案 B：用 zsh 的 (N) 限定符，无匹配时展开为空
for f in /tmp/env-verify.*(N); do ...; done
# ✓ 方案 C：先判存在（最省心的可移植写法）
[ -e "$f" ] || continue
```

### 坑 4：Agent 环境里 `rm` 不是真删，而是被拦截进回收站

| 环境 | `rm` 身份 | 行为 |
|---|---|---|
| Agent 宿主 shell | shell 函数，转发到 `trash(1)` | 目标**移入 `~/.Trash`**，不销毁 |
| 用户自己的 login shell | `/bin/rm` | 标准真删 |

```bash
type rm        # agent 环境: "rm is a shell function from zsh"；用户终端: "rm is /bin/rm"
```

**两个推论：**

1. 脚本 EXIT trap 里的 `rm -rf "$TMP"` 在 Agent 环境下会把临时目录**沉进 `~/.Trash`**，
   于是每跑一次脚本回收站就多一个空目录。这是**环境行为，不是脚本缺陷**——
   用 `type rm` 判定即可，不要在脚本里为此加补丁。
2. 反过来说，这也是**安全正向**：在 Agent 手上没有真正被销毁的东西。
   用户本人在终端运行时则是标准语义，无需任何适配。

需要确认「某次操作是否真的删掉了」时，**以 `[ -e <path> ]` 为准，不要以 `rm` 无报错为准**。
