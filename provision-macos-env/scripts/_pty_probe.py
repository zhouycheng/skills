#!/usr/bin/env python3
"""pty 功能探针 —— 在伪终端里跑一个真实的交互式 zsh，验证补全 / 高亮 / 虚影是否真的生效。

为什么**必须**用 pty（这是本文件存在的唯一理由）：
  1. ZLE 只在「交互式 + 有终端」时激活。`zsh -i -c '...'` 里 ZLE 不激活，
     widget 表不完整，`zle -la` 的结论不可信。
  2. 虚影（zsh-autosuggestions）靠 ZLE 重绘产生输出。非 pty 下终端里根本没有
     那段暗淡文字，也就无输出可观测 —— 只能验证「函数被定义」，不能验证「渲染出来」。

输出协议：每行一个 KEY=VALUE，交由 verify.sh 断言。本脚本自身不做判定。
只读探针：不改任何配置，只写一个自己的临时 HISTFILE。

设计要点（v2，修复两个真实踩过的坑）：
  - **不依赖提示符**。用户的 ~/.zshrc 用 starship，会覆盖 PS1/PROMPT，
    「等提示符出现」永远等不到。改为 fork 后固定 drain，让 .zshrc 跑完即可。
  - **nonce 哨兵 + 行锚定解析**。pty 会把输入的命令原样回显，直接搜
    `P_x=1` 会把回显里的 `P_x=$((...` 误当结果。每条探针输出带一次性
    nonce 前缀，且要求独占一行、值域不含 `$ ( "` 三个字符：
    回显里的命令文本必然含 `$(`，双重过滤下不可能误判。
"""
import os
import pty
import re
import secrets
import select
import sys
import tempfile
import time

# 注入的历史：用于虚影测试。zsh 历史格式为 ": <ts>:<dur>;<cmd>"
FAKE_HISTORY = [
    (1700000000, "git status --porcelain"),
    (1700000001, "brew bundle list --all"),
]
# 输入前缀 -> 期望在终端里看到的虚影余下文本（历史中该条目的后半段）
GHOST_PREFIX = "git stat"
GHOST_EXPECT = "us --porcelain"

STARTUP_DRAIN = 2.0   # fork 后先静默等待，让 .zshrc 开始执行
READY_TIMEOUT = 25.0  # 自适应「就绪握手」的总预算（慢机 / 沙箱下启动可能远超固定 drain）
PROBE_TIMEOUT = 6.0   # 单条探针的往返超时
PROBE_RETRY = 2       # 单条探针的尝试次数

NONCE = "VP" + secrets.token_hex(3) + "_"

# (emit_key, zsh 表达式)。表达式会被包进 print "NONCE<key>=<expr>" 发给 shell。
PROBES = [
    ("p_comps_brew",        "$(( ${+_comps[brew]} ))"),
    ("p_widget_fzftab",     "$(( ${+widgets[fzf-tab-complete]} ))"),
    ("p_widget_fzf_hist",   "$(( ${+widgets[fzf-history-widget]} ))"),
    ("p_widget_autosug",    "$(( ${+widgets[autosuggest-accept]} ))"),
    # zsh-syntax-highlighting 的**正确**检查点：它挂的是 zle-line-pre-redraw 钩子。
    # `widgets[_zsh_highlight]` 恒为 0 —— _zsh_highlight 是函数不是 widget。
    ("p_widget_predraw",    "$(( ${+widgets[zle-line-pre-redraw]} ))"),
    ("p_fn_zsh_highlight",  "$(whence -w _zsh_highlight)"),
    # 只数 9 个面向用户的 widget：模式不允许数字，
    # 从而排除 autosuggestions 给每个既有 widget 包出的 autosuggest-orig-1-*
    ("p_n_autosug_widgets", "$(zle -la | grep -cE '^autosuggest-[a-z-]+$')"),
]


def read_for(fd, seconds, stop=None):
    """读取 seconds 秒；stop(buf) 为真则提前返回。返回累计原始字节。"""
    buf = b""
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.15)
        if not r:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        if stop is not None and stop(buf):
            break
    return buf


def emit(key, value):
    # 值里不允许出现换行，避免污染 KEY=VALUE 协议
    print("%s=%s" % (key, str(value).replace("\r", " ").replace("\n", " ").strip()))


def main():
    hist = tempfile.NamedTemporaryFile("w", delete=False, suffix=".zsh_history")
    for ts, cmd in FAKE_HISTORY:
        hist.write(": %d:0;%s\n" % (ts, cmd))
    hist.close()

    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env["HISTFILE"] = hist.name
    env["HISTSIZE"] = "500"
    env["SAVEHIST"] = "500"
    # 注意：macOS /etc/zshrc 会把 HISTFILE 强制重置为 ~/.zsh_history（覆盖这里的 env），
    # 所以假历史必须在启动后用 fc -R 显式灌入（见下方 main 流程）。
    # 清掉可能干扰的变量；不设置 PS1（starship 会覆盖，设了也没用）
    for k in ("PS1", "PROMPT", "PROMPT2", "PROMPT_COMMAND", "ZDOTDIR"):
        env.pop(k, None)

    pid, fd = pty.fork()
    if pid == 0:
        # 子进程：直接用真实用户 shell 启动，等价于「新开一个终端窗口」
        try:
            os.execve("/bin/zsh", ["/bin/zsh", "-i"], env)
        finally:
            os._exit(127)

    # 把 pty 拉宽到 200 列，避免长探针命令被 ZLE 折行重绘（干扰行锚定解析）
    try:
        import fcntl
        import struct
        import termios
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 200, 0, 0))
    except Exception:
        pass  # 拉宽失败不致命，nonce 协议仍有三重过滤兜底

    try:
        # ---- 阶段 1：就绪握手（不用固定 drain）----
        # 固定 drain 不可靠：starship / zoxide / fzf + 四个插件在慢机或 Agent 沙箱下
        # 启动可能远超几秒，此时投递的探针会被**正在执行的 .zshrc 吞掉**（pty 的 stdin
        # 就是那个 tty），现象是「全部探针无应答」—— 把「环境慢」误判成「功能坏」。
        # 改为反复投递哨兵直到 shell 回话。就绪判定要求行尾紧跟数字，
        # 这样 ZLE 回显的 `print "NONCE...ready=1"` 因末尾是引号而不会被当成结果。
        startup = read_for(fd, STARTUP_DRAIN)
        pat = re.compile(
            rb"(?m)^" + re.escape(NONCE.encode()) + rb"([A-Za-z_]+)=([^\r\n$(\"]*)"
        )
        ready_pat = re.compile(
            rb"(?m)^" + re.escape(NONCE.encode()) + rb"ready=([0-9]+)[ \t]*\r?$"
        )
        t0 = time.time()
        ready = False
        while time.time() - t0 < READY_TIMEOUT:
            os.write(fd, ('print "%sready=1"\n' % NONCE).encode())
            startup += read_for(fd, 0.6, stop=lambda b: ready_pat.search(b))
            if ready_pat.search(startup):
                ready = True
                break
        emit("startup_bytes", len(startup))
        emit("startup_wait", "%.1f" % (time.time() - t0))
        emit("startup_ready", 1 if ready else 0)
        if not ready:
            # 无应答时交出尾部原始输出：用于区分「环境慢/被沙箱限制」与「配置真坏」
            emit("startup_raw_tail", startup[-200:].decode("utf-8", "replace"))

        # 历史卫生（只读探针的底线）：
        #   1. SAVEHIST=0 —— 退出时不把探针命令写进用户真实历史
        #   2. fc -R 灌入假历史 —— /etc/zshrc 已把 HISTFILE 重置为 ~/.zsh_history，
        #      虚影测试必须有确定性语料；fc -R 读入的条目位于历史表末尾（最新），
        #      history 策略取「最近匹配」，因此必然命中假历史中的条目
        os.write(fd, b"SAVEHIST=0\n")
        read_for(fd, 0.6)
        os.write(fd, ("fc -R %s\n" % hist.name).encode())
        read_for(fd, 0.8)

        # 解析规则：nonce 前缀 + 行首锚定 + 值域黑名单（$ ( " 与引号）
        #   真实输出:  VP9f3a2c_p_comps_brew=1            <- 独占一行，命中
        #   ZLE 回显:  print "VP9f3a2c_p_comps_brew=$((  <- 行首是 print，且含 $(，双杀
        for key, expr in PROBES:
            cmd = 'print "%s%s=%s"' % (NONCE, key, expr)
            value = ""
            for _attempt in range(PROBE_RETRY):
                os.write(fd, (cmd + "\n").encode())
                buf = read_for(fd, PROBE_TIMEOUT, stop=lambda b: pat.search(b))
                m = pat.search(buf)
                if m:
                    value = m.group(2).decode("utf-8", "replace")
                    break
            emit(key, value)

        # ---- 虚影回显：输入前缀，看终端里是否吐出补全的余下文本 ----
        os.write(fd, GHOST_PREFIX.encode())
        ghost = read_for(fd, 6.0, stop=lambda b: GHOST_EXPECT.encode() in b)
        ok_ghost = GHOST_EXPECT.encode() in ghost
        emit("p_ghost_text", 1 if ok_ghost else 0)
        # fg=240 在 256 色终端下渲染为 \e[38;5;240m；出现即说明是「暗淡虚影」而非普通输出
        emit("p_ghost_dimmed", 1 if re.search(rb"\x1b\[38;5;240m", ghost) else 0)
        if not ok_ghost:
            emit("p_ghost_raw_tail", ghost[-160:].decode("utf-8", "replace"))

        # 收尾：清行 + 退出，避免把探针输入写进用户历史
        os.write(fd, b"\x15")          # Ctrl-U 清空当前行
        time.sleep(0.3)
        os.write(fd, b"exit\n")
        read_for(fd, 3.0)
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass
        try:
            os.unlink(hist.name)
        except OSError:
            pass


if __name__ == "__main__":
    if not hasattr(os, "fork"):
        sys.stderr.write("本探针依赖 POSIX pty，仅支持类 Unix\n")
        sys.exit(2)
    main()
