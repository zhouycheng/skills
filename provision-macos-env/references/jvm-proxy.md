# JVM 系工具的代理配置（Android Studio / sdkmanager / Gradle）

**一句话结论**：JVM 进程**不读** macOS 系统代理设置，也**不读** `HTTP_PROXY` / `HTTPS_PROXY`
环境变量。在国内网络下，表现为「浏览器和 curl 都能上的站点，Android Studio 却下不动」。

这是 macOS 上配置 Android / Flutter 工具链时**最高频的网络故障**，且反复出现——
因为它伪装成「网络问题」，实际是「配置没传给 Java」。

---

## 一、原理

Java 的网络栈只认两种来源：

1. **JVM 系统属性**：`-Dhttp.proxyHost` / `-Dhttp.proxyPort` / `-Dhttps.proxyHost` /
   `-Dhttps.proxyPort`（还有 `-Dhttp.nonProxyHosts`）
2. **程序自身的配置界面**（IntelliJ 平台的 `HttpConfigurable`、Gradle 的 `systemProp.*`）

macOS 的「系统设置 → 网络 → 代理」对这些程序**不可见**——系统代理只影响使用
CFNetwork/NSURLSession 的程序（Safari、curl、大部分原生 App）。

> 判定口诀：**能在终端 `curl` 通、但图形/Java 程序不通 → 先怀疑 JVM 代理未配置。**

---

## 二、三条配置通道

| 通道 | 作用范围 | 写法 |
|---|---|---|
| `JAVA_TOOL_OPTIONS` 环境变量 | 该 shell 下**所有** JVM 进程（含 sdkmanager、gradle、AS 启动器） | 见下 |
| `~/.gradle/gradle.properties` | Gradle 构建（Android 项目依赖下载） | `systemProp.https.proxyHost=127.0.0.1` 等 |
| IDE 自身设置 | 该 IDE（插件市场、更新检查） | Settings → HTTP Proxy |

### 通道 1：JAVA_TOOL_OPTIONS

```bash
export JAVA_TOOL_OPTIONS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7897 \
-Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7897"
```

- JVM 会把它打印成 `Picked up JAVA_TOOL_OPTIONS: ...`，**看到这行才说明生效**。
- 端口替换为你本机代理端口：`scutil --proxy` 可读（`HTTPPort` / `HTTPSPort`）。
- 副作用：**所有** JVM 程序都走代理，包括访问内网/本地服务的程序。若内网服务不可达，
  补 `-Dhttp.nonProxyHosts="localhost|127.0.0.1|*.local"`。

### 通道 2：Gradle

`~/.gradle/gradle.properties`（**不要**写进项目里的 gradle.properties）：

```properties
systemProp.http.proxyHost=127.0.0.1
systemProp.http.proxyPort=7897
systemProp.https.proxyHost=127.0.0.1
systemProp.https.proxyPort=7897
systemProp.http.nonProxyHosts=localhost|127.0.0.1|*.local
```

### 通道 3：IntelliJ 平台（Android Studio / IDEA / PyCharm）

**Settings → Appearance & Behavior → System Settings → HTTP Proxy**

- 选 **Manual proxy configuration** → **HTTP** → Host `127.0.0.1`、Port `7897`
  → 点 **Check connection** 填 `https://plugins.jetbrains.com` 验证
- ⚠️ **不要选「Auto-detect proxy settings」（PAC）**，除非系统真的配了 PAC。
  实测坑：配置文件里留下 `USE_PROXY_PAC=true`，而系统 `ProxyAutoConfigEnable: 0`
  （PAC 未启用）→ IDE 落到直连 → 插件下载 TLS 握手被切断，报
  `Remote host terminated the handshake`。
- 端口填**代理端口**（`7897`），不是 `80`。切到 Manual 时 AS 会保留上一次的默认值 `80`，
  **Host 是空的、Port 显示 80 → 必须两个都改**，否则等于没配。
- **AS 2026.1.x 的这个对话框只有一个 Port 字段**（选 HTTP 时 HTTP 与 HTTPS 共用），
  没有旧版的「Same port for HTTPS」勾选框 —— 别去找那个框，填完 Port 就是两者都生效。
- 建议在 **No proxy for** 填 `localhost,127.0.0.1,*.local`。
  这里填的是**目标主机**的排除列表，不影响代理自身所在的 `127.0.0.1:7897`，可放心填。

#### 顶部黄色警告「You have JVM property https.proxyHost set to 127.0.0.1…」是什么

完整原文：
> You have JVM property https.proxyHost set to 127.0.0.1. This may lead to incorrect
> behaviour. Proxy should be set in Settings | HTTP Proxy. This JVM property is old and
> its usage is not recommended by Oracle. (Note: it could have been assigned by some code
> dynamically.)

**这不是错误，也不是"代理配错了"**。含义是：AS 启动时**从外部环境**继承了 JVM 代理属性
——最常见就是「启动它的那个终端里 `export JAVA_TOOL_OPTIONS=...`」（例如刚跑完
`sdkmanager --licenses`）。后果是**代理来源有两处并存**（环境变量 + IDE 设置），
Oracle/IntelliJ 都不建议这样。

处置（二选一，推荐第一种）：

1. **以 IDE 设置为准**：退出 AS → 在终端 `unset JAVA_TOOL_OPTIONS`（或直接从
   Dock/Finder 启动 AS）→ 重启。警告消失。
2. 继续用环境变量：功能上可行（前提是四个属性都齐：http/https 的 host **和** port），
   但每次都要从那个终端启动，且与 IDE 设置冲突时行为不确定。

> 排查提示：确认这个属性从哪来，先看 `~/.zshrc` / `~/.zshenv` / `~/.zprofile` 有没有
> `JAVA_TOOL_OPTIONS`，再看 `launchctl getenv JAVA_TOOL_OPTIONS`（决定 Dock 启动的 App
> 会不会继承）。两处都没有却仍出现 → 就是"某个终端临时 export 后启动的"。

对应配置文件（**只读排查用，不要手改**——`~/Library` 属受保护区）：

```
~/Library/Application Support/Google/AndroidStudio<版本>/options/proxy.settings.xml
```

---

## 三、诊断方法：对照实验

**最有效的判定法**：同一个目标，一次**不带**代理参数、一次**带上**，比较结果。

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
SDK="$HOME/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager"

# 对照组：模拟「没配代理」的现状
"$SDK" --licenses </dev/null 2>&1 | grep -c 'IO exception while downloading manifest'

# 实验组：显式注入 JVM 代理
export JAVA_TOOL_OPTIONS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7897 \
-Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7897"
"$SDK" --licenses </dev/null 2>&1 | head -20
```

实测结论（2026-09-24 本机）：
- 对照组：manifest 下载失败 **14 次**，无法列出许可证
- 实验组：**成功列出「4 个 SDK 许可证，3 个未接受」**

即：**同一命令、同一网络，仅差代理参数，结果相反**。这是最干净的证据。

---

## 四、插件手动安装（网络彻底不通时的兜底）

IDE 内置的市场走不通时，可手动下载插件包再用 **Install Plugin from Disk**：

1. 用 `pluginManager` 端点取**权威下载地址**（IDE 自己就是用这个）：
   ```bash
   AS_BUILD="$(/bin/cat '/Applications/Android Studio.app/Contents/Resources/build.txt')"
   curl -sI "https://plugins.jetbrains.com/pluginManager?action=download&id=<PLUGIN>&build=$AS_BUILD" \
     | grep -i '^location'
   ```
   → 得到形如 `https://plugins.jetbrains.com/files/9212/1159004/Flutter-96.0.0-ff8b8ec.zip?updateId=...`

2. 下载并**校验**（务必验，避免拿到被中途切断的半包）：
   ```bash
   curl -sL -o Dart.zip "<上一步的地址>"
   unzip -t Dart.zip          # 必须 "No errors detected"
   ```

3. IDE → Settings → Plugins → ⚙ → **Install Plugin from Disk…** → 选 zip → 重启
   - **依赖要按序装**：先 Dart，再 Flutter（Flutter 依赖 Dart）
   - 用 `curl -x http://127.0.0.1:<port>` 走代理下载，比让 IDE 自己下更可控

### ⚠️ `build=` 必须是「带 AI- 前缀的完整 build」，且 `id=` 要用插件 XML id

这一节是 2026-09-24 实测踩出来的，三条都不能想当然：

| 项 | 错误写法 | 正确写法 | 说明 |
|---|---|---|---|
| `build=` 取值 | `261.26222.65.2614.16379836`（裸数字） | `AI-261.26222.65.2614.16379836` | 裸数字**不返回重定向**（静默失败，极易误判为"插件不存在"）。直接从 `Android Studio.app/Contents/Resources/build.txt` 读，那里已经带 `AI-` |
| `id=` 取值 | `Flutter`（市场页面名） | `io.flutter`（插件 XML id） | `id=Flutter` → **404 Can't find Plugin with id Flutter**；`id=io.flutter` → 301 ✓ |
| pluginId 编号 | `9112` | `9212` | 这两个数字只差一位，且 **9112 确实存在过一个已失效条目**，`api/plugins/9112` 返回 404。只有 9212 能下到文件 |

**权威解析顺序**（当 `id=` 猜不出来时）：用 IDE 自己调用的 compatibleUpdates 端点，
按**插件 XML id**反查出 `pluginId` / `updateId`：

```bash
curl -s -X POST "https://plugins.jetbrains.com/api/search/compatibleUpdates" \
  -H 'Content-Type: application/json' \
  -d '{"build":"AI-261.26222.65.2614.16379836","pluginXMLIds":["io.flutter","org.jetbrains.plugins.dart"]}'
# → [{"id":1159004,"pluginId":9212,"version":"96.0.0","pluginXmlId":"io.flutter"}]
```

返回的 `updateId`（1159004）应与你看到的 IDE 报错里的编号一致 —— 一致即证明
「请求的就是同一个文件」，可放心手动下载。

> **判据链**：`build.txt` 原文 → `compatibleUpdates` 的 updateId → IDE 报错里的 updateId。
> 三者对齐才动手；不对齐说明 id 或 build 猜错了，继续猜只会下到不兼容版本。

⚠️ 该端点与 `pluginManager` 都**可能偶发无响应**（实测同一 `build=` 先成功后失败）。
重试即可，不要据此判定"端点不可用"。

⚠️ **判据：`unzip -t` 通过 + 字节数与 API 声明一致**。只看 HTTP 200 不够——
被中间设备切断的连接也可能先回 200 再断（本次 AS 的报错正是
`response: 200 OK` 但握手终止）。

### 实测可信样例（2026-09-24，AS build `AI-261.26222.65.2614.16379836`）

| 插件 | 解析地址 | 字节数 | 校验 |
|---|---|---|---|
| Dart（`id=Dart`，pluginId 6351） | `files/6351/1159005/Dart-509.0.0-af26c2f.zip` | 3,415,585 | `unzip -t` 无损 |
| Flutter（`id=io.flutter`，pluginId **9212**） | `files/9212/1159004/Flutter-96.0.0-ff8b8ec.zip` | 23,152,307 | `unzip -t` 无损 |

包内都是标准 JetBrains 布局（`flutter-intellij-96/lib/*.jar`、`Dart/lib/*.jar`），
`plugin.xml` 在 jar 内部，故用 `unzip -l` 看不到顶层 `META-INF/` —— 这是正常的，不是坏包。

---

## 五、已知坑清单

| # | 坑 | 表现 | 处置 |
|---|---|---|---|
| 1 | JVM 不读系统代理 | 浏览器通、AS/sdkmanager 不通 | 见第二节三条通道 |
| 2 | 配了 PAC 但系统 PAC 未启用 | `Remote host terminated the handshake` | IDE 改 Manual，别用 PAC |
| 3 | `flutter doctor --android-licenses` 拉不到清单 | `IO exception while downloading manifest` | 先 export `JAVA_TOOL_OPTIONS` |
| 4 | Gradle 下载依赖失败 | 构建卡在依赖解析 | `~/.gradle/gradle.properties` 加 `systemProp.*` |
| 5 | 下载"成功"但包损坏 | 安装时报 zip 错误 | 必做 `unzip -t` |
| 6 | 用裸 URL 下插件得到 403 AccessDenied | AmazonS3 拒绝 | 用 `pluginManager` 端点取带签名参数的地址 |
| 7 | `id=` 填了市场页面名而非插件 XML id | `404 Can't find Plugin with id Flutter` | Flutter 要用 `io.flutter`（Dart 恰好同名，容易以偏概全） |
| 8 | `build=` 少了 `AI-` 前缀 | **无声失败**（不返回重定向），易误判为"插件不存在" | 直接读 `Android Studio.app/Contents/Resources/build.txt` 原文 |
| 9 | 用 `9112` 当作 Flutter 的 pluginId | `api/plugins/9112` → 404 | 真实 pluginId 是 **9212**；用 `compatibleUpdates` 反查 |
| 10 | 插件端点偶发无响应就断言"不可用" | 同参数一次成功一次空 | 重试 2–3 次再下结论 |
| 11 | 切到 Manual 后只改 Host 没改 Port | Host 空、Port 还是默认 `80` | 两个字段都要填：`127.0.0.1` + `7897` |
| 12 | 从已 export 的终端启动 AS | 顶部黄色警告 JVM property `https.proxyHost` | 不算错误；从 Dock 启动或先 `unset` |

---

## 六、不要做的事

- **不要为了省事把代理参数写进项目的 `gradle.properties`**——会随仓库分发给别人，
  污染他人构建。只写用户级 `~/.gradle/gradle.properties`。
- **不要直接编辑 `~/Library/Application Support/...` 下的 IDE 配置**（受保护区）。
  通过 IDE 界面改；确需脚本化时先备份并取得用户明确同意。
- **不要用「全局设置 JAVA_TOOL_OPTIONS 到 shell 启动文件」作为默认方案**——
  它会影响所有 JVM 程序（含访问内网的）。优先按需 `export`，或走通道 2/3。
