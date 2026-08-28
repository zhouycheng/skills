**skills 是一套安装在 `~/.agents/skills` 的 Agent Skills 集合，覆盖文档处理、浏览器自动化、网络检索、前端规范和 Dart/Flutter 开发，供 TRAE 等 Agent 宿主按需调用。**

[技能清单](#技能清单) · [安装](#安装) · [问题反馈](https://github.com/zhouycheng/skills/issues)

## 技能清单

### 通用

| 技能 | 用途 |
|---|---|
| browser-use | 通过 CDP 直接控制浏览器，做自动化、抓取、测试和截图 |
| chatgpt-imagegen | 用 ChatGPT 订阅生成图片与 GIF/WebP 动图，无需 API key |
| composition-patterns | React 组合模式规范，处理布尔 props 膨胀、组件库设计 |
| docling | 把 PDF、DOCX、PPTX、XLSX 等文档转换成 Markdown |
| docx | 创建、读取、编辑 Word 文档，含批注与修订 |
| drawio-skill | 绘制流程图、架构图、UML、网络拓扑等各类图并导出 |
| firecrawl | 通过 Firecrawl CLI 检索网页、提取内容、下载站点 |
| frontend-design | 前端视觉设计指引，避免模板化审美 |
| hatch-pet | 创建 Codex 兼容的动画宠物精灵图集，含校验、视觉 QA 与打包 |
| mcp-builder | 构建 Python 或 TypeScript 的 MCP 服务器 |
| no-negative-echo | 交付收口，防止被否方案残留进标题、commit 和 PR |
| playwright-cli | 用 Playwright 自动化浏览器操作与页面测试 |
| pptx | 创建、读取、编辑 PowerPoint 演示文稿 |
| react-best-practices | React/Next.js 性能优化规范（Vercel 工程实践） |
| skill-creator | 创建、改进和评测 Skill 本身 |
| xlsx | 创建和处理电子表格，含公式、图表与数据清洗 |

### Dart

| 技能 | 用途 |
|---|---|
| dart-add-unit-test | 用 `package:test` 编写和组织单元测试 |
| dart-build-cli-app | 构建命令行应用，处理入口结构与退出码 |
| dart-collect-coverage | 收集测试覆盖率并生成 LCOV 报告 |
| dart-fix-runtime-errors | 抓取运行时堆栈，定位并修复报错行 |
| dart-generate-test-mocks | 用 mockito 生成外部依赖的 mock 对象 |
| dart-migrate-to-checks-package | 把 `expect` 迁移到 `package:checks` 断言 |
| dart-resolve-package-conflicts | 解决 `pub get` 的包版本冲突 |
| dart-run-static-analysis | 运行 `dart analyze` 和 `dart fix` |
| dart-setup-ffi-assets | 用 Native Assets 打包 C/C++ 动态库 |
| dart-use-doc-examples | 在 Dartdoc 中注入外部代码示例 |
| dart-use-ffigen | 用 ffigen 自动生成 FFI 绑定 |
| dart-use-pattern-matching | 使用 switch 表达式和模式匹配 |
| dart-use-primary-constructors | 使用 Dart 3 主构造函数语法 |
| dart-write-documentation | 撰写 `///` API 文档注释 |

### Flutter

| 技能 | 用途 |
|---|---|
| flutter-add-integration-test | 配置集成测试，把交互流程固化为用例 |
| flutter-add-widget-preview | 给 UI 组件添加交互式预览 |
| flutter-add-widget-test | 编写 Widget 组件级测试 |
| flutter-apply-architecture-best-practices | 按 UI、逻辑、数据三层组织应用 |
| flutter-build-responsive-layout | 用 LayoutBuilder 等做响应式布局 |
| flutter-fix-layout-issues | 修复溢出、无界约束等布局错误 |
| flutter-implement-json-serialization | 编写 `fromJson`/`toJson` 模型类 |
| flutter-setup-declarative-routing | 用 go_router 配置声明式路由 |
| flutter-setup-localization | 初始化 `flutter_localizations` 国际化 |
| flutter-use-http-package | 用 http 包请求 REST API |

## 安装

```bash
git clone https://github.com/zhouycheng/skills.git ~/.agents/skills
```

宿主在下次会话启动时会扫描该目录并加载全部技能。

## 许可

各技能目录内含各自的 LICENSE.txt，以目录内文件为准。
