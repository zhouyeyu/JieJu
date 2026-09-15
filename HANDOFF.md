# JieJu Agent Handoff

## 本次交接

- 日期：2026-09-14
- Agent：Codex
- 阶段：`WIN-401` PDF 阅读基础完成；下一项为 `WIN-402` PDF 文本选择、上下文与页码 locator
- 分支：`codex/windows-development`
- 基线：`91222f2 feat: create Windows app foundation`
- Windows 工程：`Apps/Windows/JieJu.Windows.sln`，依赖方向为 Windows → Domain；Domain 不引用
  WinUI、WebView2 或平台存储实现
- 当前能力：原生侧栏与设置页；受限 EPUB 解析和资源加载；章节目录与前后章；原书 Ruby；
  白纸、夜间、羊皮纸和护眼绿主题；字号、行距、边距、注音开关；最近阅读和章内位置恢复
- 划词能力：选区移除 Ruby 注音并提取句子语境，常驻解句栏仅在用户点击后调用 `IStreamingReadingAI`；
  Ollama `/api/chat` NDJSON 流、`temperature=0`、JSON Schema 和选区引用校验均已实现
- 学习记录：最终解释可写入共享 v5 `library.json`；重复选区更新、损坏文件备份、列表/详情、确认
  删除和从记录返回 EPUB 章节/章内位置均已实现，平台绝对路径未进入共享资料
- 生词本：独立 v4 词语解释、Unicode Prompt、中文输出校验与一次修复、收藏合并、列表/详情、确认
  删除和返回最近来源已实现；解句越界条目改为安全清洗，不再整体失败
- 选区路由：自动区分词语/表达/句子/段落，保留人工切换；英文与日语残缺词均可保守建议完整边界
- 渐进解释：翻译、主干、语法和重点表达随 Ollama NDJSON 中完整字段逐步显示，预览继续过滤越界
  引用，最终校验前不能保存
- 深入解析/显示：支持句型、成分、从句、深度语法和整句理解，侧边栏/弹窗选择持久化且不重建
  Reader；解释面板顶部可即时互切，弹出式覆盖阅读区且解释列宽为 0，不触发正文变窄；日语词语
  的读音、原形、词性和活用已由本地 MeCab/IPADic 覆盖模型输出。弹出式可按住“解读”标题拖动，
  位置在当前运行期间保留并限制在阅读区内
- EPUB 注音：日语章节自动生成本地词典 Ruby，跳过原书 Ruby 与活动内容；章内多读音表记不猜测，
  错误英文元数据可由强日文证据纠正，中文短引用不会触发整章注音；阅读工具栏提供即时“注音”
  开关。用户设备已开启注音，真实保存位置 EPUB 已验证 Ruby 可见
- EPUB 目录：优先使用 EPUB 2 NCX / EPUB 3 nav 标题，再使用正文标题和首个简短正文块；忽略
  `Unknown` / `Untitled` 占位。用户指定《ノルウェイの森》已识别第一章至第十一章及あとがき
- 日语解释：选区、词语与深入解析显示本地词典读音；深入解析直接生成助词、句型、谓语、原形和
  活用，日语身份字段不依赖模型，并支持从词形卡片加入生词本
- 云端解释：支持 OpenAI-compatible Chat Completions SSE、词语/深入解析、连接检查和隐私提示；
  API Key 仅保存在 Windows 凭据管理器，未使用真实云端凭据或产生推理流量
- 随手温习：收藏生词自动生成识别卡，旧 Windows v5 生词自动补卡；先回想再揭示答案，支持空格、
  数字 1～4 评分、返回最近原文、10 张温和暂停和 `jieju-interval-v1` 只追加日志
- 页面布局：学习记录、生词本、随手温习等资料页和设置页在宽窗口中从内容区左侧开始，分别保留
  920 / 760 最大内容宽度；学习记录及云端设置冒烟会检查内容没有被居中推离左边缘
- 阅读设置：主题、字号、行距和左右边距调整时实时更新设置页 EPUB 正文预览与当前 EPUB；点击
  “保存设置”后写入设备状态并跨启动保留。专用冒烟会同时检查原生预览属性与书页计算样式
- PDF 基础：文件选择、签名/大小校验、WebView2 内置阅读、内容哈希去重、关闭及最近阅读重开已
  完成；PDF 选区、上下文和页码定位尚未接入
- 验证：Solution 0 警告；C# 102 项、Node 契约/Bridge 11 项通过；WinUI + WebView2
  `152.0.4191.66` 完成 PDF 受限打开和最近阅读重开；EPUB 注音冒烟检查生成与实际可见状态，解释
  冒烟检查从侧边栏即时切换弹出式且不压缩阅读栏；所有 App 冒烟使用临时设备目录
- 环境：Windows 11 `10.0.26100` x64、.NET SDK `10.0.401` / MSBuild `18.9.11`、Windows App SDK
  WinUI `1.8.260803003`、Windows SDK Build Tools `10.0.26100.9169`；未使用 Visual Studio
- 测试入口：`./scripts/test-windows.ps1`；加 `-Smoke` 会依次验证欢迎页和生成的最小 EPUB
- 根目录 `scripts/test-all.sh` 已尝试执行，但这台 Windows 主机没有 zsh、Swift 和 Xcode，无法运行
  macOS 套件；本任务以 Windows 入口覆盖 Node 共享测试、Solution build、C# test 和真机冒烟
- 视觉检查限制：本轮 Codex 远程截图对 WinUI 合成表面返回纯白，无法作为颜色和间距验收证据；
  启动、布局树、WebView2 消息和 EPUB 路径已由程序化检查覆盖，仍需在本机窗口人工查看一次
- 本地模型：Ollama `0.34.0` 位于 `E:\JieJu\Ollama\App`，模型目录由用户环境变量固定为
  `E:\JieJu\Ollama\Models`；启动快捷方式指向 E 盘。1.5B 为 986MB，实测 100% GPU、约
  133.5 tokens/s。安装包保留在 `E:\JieJu\Ollama\Downloads` 供离线重装
- 下一步：执行 `WIN-402`，为 PDF 建立可测试的文本层、选择事件、所在句/有限上下文和页码 locator；
  完成前不把 PDF 选区接入 AI 或学习资料，后者由 `WIN-403` 单独验证

### 2026-09-09 macOS 基线交接

- 日期：2026-09-09
- Agent：Codex
- 阶段：基线 `6ba8245` 已推送 GitHub；Windows Agent 已开始开发，macOS 侧转为独立任务分支协作。
- 最新产品原则：复习是可选的“随手温习”，不是每日任务。界面不显示积压数、完成率或精确间隔，
  不做提醒/红点/连续打卡；每轮 10 张后温和暂停，并始终提供“回到阅读”。四档反馈的持久化 raw
  value 未变，仅用户文案改为熟悉程度，因此无需数据迁移。
- “随手温习”底部始终展示弱化的理念文案：“语言不是一条需要赶完的路。读一点，记一点，忘了
  也没关系；在漫长的相遇里，它终会成为你的一部分。”
- 当前统一测试全绿：共享契约/Reader Bridge 11 项、语言包 65 项、macOS App 77 项、UI 2 项。
  UI 测试已通过忽略窗口恢复状态、显式等待主窗口和稳定侧栏标识消除启动假失败。
- 当前 macOS 分支：`chore/macos-collaboration`（协作规则 PR）；后续功能使用新的任务分支。
- 远程：`git@github.com:zhouyeyu/JieJu.git`
- Windows 接手入口：`Docs/WINDOWS_DEVELOPMENT.md`；先创建并真机验证 WinUI 3 + WebView2 Solution，
  不要试图编译 SwiftUI/PDFKit，也不要绕过 `Shared/Contracts/v1…v5` 建立另一套 DTO。
- 协作：两端均通过任务分支向 `main` 创建 PR；先完成独立里程碑并测试，再交审查，不直接推送 main。
  Windows 分支名由对端决定，本机尚未发现远程 Windows 分支；不要据此判断对端未开工。
- `.workbuddy/`、个人 EPUB、评测结果和构建产物继续保持忽略。
- 基线提交：`fbdf02f chore: create macOS project foundation`
- 模块集成提交：`3529d0f feat: build parallel reader language and storage modules`
- 语言修复提交：`a427e01 fix: bind target language into Ollama JSON schema`

### 2026-09-09 Windows 真机接手

- `WIN-001` 是 Windows 上的第一项任务：创建 `JieJu.Windows`、`JieJu.Domain`、
  `JieJu.Windows.Tests` 和 Solution，记录真实 SDK 版本，并让最小 WinUI 窗口与 WebView2 真机运行。
- C# 客户端读取 `learning-library` v1～v5，新增数据写 v5；句子解释使用 v1，独立单词解释使用
  v4，来源“回到原文”使用 v5 locator。API Key、绝对路径和平台文件令牌不得进入共享 JSON。
- `Shared/ReaderWeb` 目前只有 `jiejuBridge`；成熟 EPUB CSS、分页、选区、正文锚点和日语 Ruby 逻辑
  仍在 macOS `EPUBWebReaderView.swift`。按 `XPLAT-101`～`105` 逐项迁移并先补 Web 测试，禁止
  一次性复制重写。
- Windows 第一条产品闭环为“打开 EPUB → WebView2 分页 → 选句 → Ollama 流式解句 → 保存 →
  回到原文”；PDF.js、自动 MeCab 注音、云端 Provider 和完整生词复习随后拆分。
- 2026-09-09 交接验证：`./scripts/test-all.sh` 完整通过，包含 Node 11 项、JieJuLanguage 65 项、
  macOS App 77 项和 UI 2 项；`git diff --check` 与全 Target `build-for-testing` 通过。

### 2026-09-06 日语注音失效修复

- 根因不是设置丢失：用户当前 EPUB 的 `content.opf` 与每章 `<html>` 均把日语正文错误标成 `en`，
  `JA-013` 的“明确非日语立即拒绝”规则因此让自动 Ruby 完全不注入。
- `EPUBFuriganaPolicy` 现在允许章节级强日文证据纠正错误语言标签：至少 12 个假名，假名占 CJK
  不低于 20%，且占字母类字符不低于 15%。中文/英文中的短日语引用测试保持不触发。
- Computer Use 已在真实《ノルウェイの森》上验证：设置为开启，重启新构建并恢复原章节后，正文
  汉字上方可见假名；动态分页从无注音的 37 页重排为 38 页，阅读锚点仍恢复。
- 新增两项回归，App 测试源码共 77 项；`git diff --check` 与全 Target `build-for-testing` 通过。
- 一次 App 单元测试中两项新增注音回归均通过；同轮 77 项里唯一失败是旧 EPUB 阅读位置测试仍
  期望不保存章节 ID/路径。断言已更新并重新编译；再次执行时 XCTest runner 因系统 Developer
  Mode 关闭卡在 materialize 阶段，未能形成新的完整通过结果。

### 2026-09-06 来源跳转收尾

- 新增 PDF 来源页优先于当前阅读页的回归测试，以及 PDF/EPUB locator JSON 字段与 Reader Bridge
  契约一致性测试；App 测试源码总数更新为 75，所有 Target 再次完成 `build-for-testing`。
- 统一脚本中 Node 11 项、JieJuLanguage 65 项通过；XCTest 最终报告 `The test runner hung before
  establishing connection` 和 daemon control session 超时。`DevToolsSecurity -status` 仍为 disabled。
  这是系统测试宿主阻塞，不是用例断言失败；按提交关卡继续不创建 commit。

### 2026-09-05 来源“回到原文”检查点

- `learning-library` 当前版本为 v5；`SavedExplanationRecord` 与每条 `VocabularySource` 可保存
  `DocumentLocator`。旧 v1/v2/v3 数据迁移后 locator 保持空值，不会伪造内容位置。
- PDF 选区保存来源页；EPUB 选区脚本按排除 `rt`/`rp` 的规范正文生成 UTF-16 偏移、引用和章内
  比例，并连同 manifest 章节路径、章内显示页保存。解句记录、生词详情和温习卡片均有返回入口。
- 跳转由 AppShell 发送一次性导航意图，常驻 Reader 解析最近文档 bookmark 后打开；来源 locator
  优先于用户后来阅读的位置。旧数据按 `pageIndex` 回退；文件移动后的自动匹配仍待 `LIB-007` 指纹。
- `git diff --check`、Node 契约/Bridge 11 项、JieJuLanguage 65 项及 App/UI `build-for-testing` 已通过。
  App 测试源码为 75 项，受 Developer Mode disabled 影响尚待实际执行，故仍不创建提交。

### 2026-09-05 EPUB 自动注音语言门控检查点

- `EPUBSchemeHandler` 接收整书语言；`EPUBFuriganaPolicy` 按章节根语言 → EPUB 元数据 → 保守假名
  启发式判断是否调用本地 MeCab。明确中文、英文等文档不会自动注入日语 Ruby。
- 章节 `lang`/`xml:lang` 可覆盖整书元数据，支持多语言 EPUB。语言未知时要求至少两个假名，且在
  假名+CJK 字符中占比不低于 5%；纯中文或偶尔引用一个「の」不触发。
- 原书自带 Ruby 仍由“日语汉字注音”设置显示/隐藏；本任务只门控 JieJu 自动生成的 Ruby。
- 新增 3 组测试，App 测试源码总数为 70；`git diff --check` 和 `build-for-testing` 通过。统一测试
  中 Node 10 项、语言包 65 项通过；Developer Mode 关闭导致 XCTest 等待 runner materialize，
  43.5 秒后终止为 `TEST INTERRUPTED`。已结束残留 xcodebuild 进程，未提交。

### 2026-09-05 EPUB 稳定正文锚点检查点

- `EPUBReadingPosition` 新增可选章节 ID、资源路径与 `EPUBTextAnchor`；锚点包含 UTF-16 正文偏移、
  80 字符引用和章内比例。旧版仅含章节索引/动态页码的数据保持可解码。
- 打开 EPUB 时按资源路径 → 章节 ID → 旧索引恢复章节。Web 阅读器按正文 `Range` 的分栏几何捕获
  页首，排除 Ruby 注音与非正文节点；引用不匹配时在规范正文中选择离旧偏移最近的同引用。
- 重排会保留最近一次用户锚点，异步字体/图片/导航二次布局不再把它覆盖成新页首；只有用户显式
  翻页才更新锚点。动态页码仍保存用于展示和旧数据回退。
- 真实临时长章节 EPUB 回归：字号 20、章内 `3 / 5` 页捕获偏移 `279`；改为字号 24 后页码变为
  `1 / 6`，同一引用仍可见且偏移保持 `279`；退出并从最近阅读重开后数据仍一致。
- 新增 ReadingPosition 往返/旧 JSON 兼容、资源路径优先恢复及锚点更新测试；Web 脚本测试覆盖
  Ruby 排除、Range 列几何、引用修复和重排锚点保留。`git diff --check` 与 Debug 构建通过；统一
  测试中 Node 10 项、语言包 65 项通过，App/UI Target 构建和签名通过。Developer Mode 关闭导致
  XCTest 在 `Testing started` 后 117.6 秒仍等待 runner materialize，已主动终止，结果为
  `TEST INTERRUPTED`，无残留 xcodebuild 进程；新增 App 测试只可标记为编译通过。
- 已发现但未在本任务扩展：当前自动注音未依据 EPUB 元数据语言限制，中文书开启注音也可能被
  MeCab 处理。应作为独立日语显示任务修复，不能混入锚点实现。

### 2026-09-05 最近阅读检查点

- 新增 `RecentDocumentStore`：最近 PDF / EPUB 最多 12 条、规范化路径去重、位置更新、
  security-scoped bookmark 解析、失效错误、重新定位和单条移除。记录保存在设备本地
  `UserDefaults`，不改变 `learning-library` 共享契约。
- `ReaderViewModel` 在打开会话持有并释放安全访问权限；PDF 翻页、EPUB 翻章与章内翻页都会更新
  最近位置。关闭文档只关闭当前会话，不删除最近记录，也不会把详细 EPUB 页位降级为仅章节。
- 阅读空状态现在显示“回到阅读”、打开按钮和最近书籍列表；第一本标记“继续阅读”，菜单支持打开、
  重新定位与移除。应用不会在启动时自动暴露上次阅读内容。
- 新增 `RecentDocumentStoreTests` 4 组测试；首屏 UI 测试已更新为当前可访问性标识。
- `xcodebuild build` 已通过。Computer Use 真实验证最小 EPUB 的打开、关闭、最近列表重开以及 App
  重启后位置持久化均正常；结束后已从最近列表移除该测试记录，未改动用户内容。
- `./scripts/test-all.sh` 本轮结果：Node 10 项和语言包 65 项通过；App/UI Target 编译成功后卡在
  `Testing started`，`DevToolsSecurity -status` 明确为 disabled。单独排除 UI Target 重试仍无法
  建立 App 测试宿主，因此新增测试不能标记为已执行；测试会话已终止且无残留 xcodebuild 进程。
- 下一步优先恢复 Developer mode 后运行完整 UI Runner；产品功能可继续 `EPUB-207` 稳定正文锚点，
  再实现学习记录/生词来源“回到原文”。

### 2026-09-05 开源就绪度检查点

- 新增 `LICENSE`（Apache-2.0）、`NOTICE`、`CONTRIBUTING.md`、`CODE_OF_CONDUCT.md`、
  `SECURITY.md`、`PRIVACY.md`、`CHANGELOG.md`、`Docs/RELEASE.md` 和 `Docs/DEMO_ASSETS.md`。
- README 已从早期工程说明更新为 0.1 Alpha 的公开项目入口；明确 macOS/Xcode/Node/Ollama 环境、
  本地与云端数据流、当前限制、测试和项目结构。
- `.github` 新增 PR 模板及缺陷、功能、模型质量、EPUB 兼容性四类 Issue 表单。远程仓库尚未配置，
  因此 Private Vulnerability Reporting 和真实下载/源码链接仍列在 TODO；CI 不在本轮范围。
- 不使用仓库中的个人 EPUB 制作演示素材。后续截图必须使用自编、公有领域、可再分发或程序生成
  的最小文档，并遵守 `Docs/DEMO_ASSETS.md`。
- 本轮只新增/修改文档和 GitHub 元数据，没有改动现有功能代码；工作树中更早的 Reader、AI、契约
  改动仍需整体保留。`.workbuddy/` 仍为用户未跟踪内容，不得删除或提交。
- 静态验证通过：`git diff --check`、占位词扫描、5 个 GitHub YAML 表单解析。完整测试中契约 10 项、
  语言包 65 项、App 单元测试 60 项通过；UI Runner 等待 387 秒后以
  `The test runner hung before establishing connection.` 失败，且 `DevToolsSecurity -status` 为
  disabled。按仓库提交关卡未 commit；开启开发者模式后应重跑 `./scripts/test-all.sh`。

### 2026-09-04 最新检查点

- **2026-09-05 补充**：`PDF-119` 已完成。`ReaderSelectionBoundarySuggester` 仅对句中唯一、单一
  token 内的残缺选区提出完整词建议；原始选区不变，用户可点击建议或从菜单保留原文。新增纯逻辑
  与 ViewModel 请求测试。真实日语 EPUB 局部选择“飛行”时，界面正确显示“查『飛行機』”和
  “保留原选区『飛行』”，未调用模型、未写入生词本。
- 本次统一验证：Node 10 项、语言包 65 项、App 单元测试 60 项通过。`JieJuUITests-Runner` 因
  Developer mode disabled 在 automation mode 初始化超时；因此仍不创建 commit。恢复系统 Runner
  后可直接重跑 `./scripts/test-all.sh`。

- `WORD-001` 至 `WORD-005` 已实现：语言包新增 `VocabularyAI.swift`，包含独立请求/结果 DTO、Mock、
  Ollama、OpenAI-compatible、严格解析、一次修复与流式接口；日语的读音、原形、词性及活用由缓存
  的 MeCab/IPADic 本地覆盖。App 新增 provider adapter、词卡状态和 UI，保存时使用所在完整句作为来源。
- `Shared/Contracts/v4` 固定上下文词语解释交换格式，不改 v3 learning library。语言包 65 项和 v4
  契约测试通过，macOS App 构建通过。真实 EPUB 选择“飛行機”验证为“ひこうき / noun / 飞机”，
  流式到最终状态正常，未保存测试数据。
- 新发现：用户只划到复合词一部分时，本地词法也只能解释残缺文本，例如“行機”。已新增
  `PDF-119`，后续应利用所在句和选区范围建议完整词边界，不能静默改写用户原选区。
- `./scripts/test-all.sh` 的 Node 10 项和语言包 65 项通过，App/UI 测试已由 `build-for-testing` 编译；
  运行宿主在 `waiting for workers to materialize` 阶段约 298 秒仍未启动。系统
  Developer mode 仍 disabled。按提交关卡，本轮暂不 commit；恢复 Runner 后先跑
  `./scripts/test-all.sh`，通过再提交当前完整工作树（排除 `.workbuddy/`）。

- 完成一次真实用户路径走查：打开仓库内《挪威的森林》EPUB、检查分页与注音、划选日语内容，
  并查看生词本与随手温习。发现旧逻辑把“僕は三十七歳で”当作单词，已经污染到一条现有生词和
  对应温习卡；本轮不擅自删除用户数据，可在生词本中手动删除该条目。
- 新增 `ReaderSelectionClassifier`，英语使用 NaturalLanguage，日语复用 MeCab/IPADic 的词性与
  形态结果。选区现在分为词、表达、句子、段落和不确定；按钮文案随类型变化，并有菜单允许用户
  明确选择解释方式。仅明确词/表达可直接收藏，专用 `VocabularyAI` 已在本检查点完成。
- 界面默认宽度已调整：解释栏由最大 480pt 收窄到 360pt；应用导航和生词/学习记录列表也更紧凑。
  最新构建中实测解释栏分隔位置从约 613pt 移到 719pt（1080px 窗口），正文宽度明显增加。
- 验证结果：跨平台契约 **9 项**、语言包 **57 项**、App 单元测试 **57 项**通过，真实界面复验
  通过。`./scripts/test-all.sh` 与单独重试 UI Target 都在系统启用自动化模式时超时，错误为
  `Timed out while enabling automation mode`，并非用例断言失败。本轮遵守提交关卡，暂未创建 commit。

### 2026-09-03 最新检查点

- 间隔复习首个闭环已实现：保存生词自动建 recognition card；“今日复习”先问词形，再揭示读音、
  词义和来源，四档按钮和 1～4 键会持久化下一到期时间。`jieju-interval-v1` 是明确标记的过渡算法，
  不是 FSRS；ReviewLog 只追加并记录 schedulerVersion，后续可重算。`PersistenceLibrary` 已到 v3，
  v1/v2 自动迁移，删除生词会同步清理其卡片和日志。最新验证：Node **9**、语言包 **57**、App
  **54** 项通过。尚未实现 cloze 卡、暂停/难词、复杂统计和 FSRS 对照。
- Track H 首个闭环已实现：重点表达、日语词形和直接划选词均可收藏；侧栏新增生词本列表、详情和
  删除。生词结构最初由 `Shared/Contracts/v2` 引入，随后由最新 v3 增加复习数据；旧版本均未改写。
  当前直接选词仍复用句子解释
  Provider，原形暂以表面词形保存；更丰富的词性/原形/语境义需后续 `WORD-001/002` 专用协议。
  最新验证：Node **8 项**、JieJuLanguage **57 项**、App **52 项**通过。
- 已建立跨平台骨架：`Shared/Contracts/v1` 是新的跨语言数据事实来源，`Shared/ReaderWeb` 是 EPUB
  Web 代码的渐进迁移目标，`Apps/Windows` 只记录经确认的边界，尚未伪造 WinUI 工程。完整顺序见
  `Docs/CROSS_PLATFORM.md` 和 TODO Track I。
- 现有 macOS EPUB 仍使用 `EPUBWebReaderView.swift` 内联脚本，不能误称已经迁移。下一步应先做
  `XPLAT-101`，以兼容方式引入统一 `jiejuBridge`，再逐项迁移排版、分页和选区；禁止一次性替换。
- `scripts/test-all.sh` 现在先跑 Node 内置测试。此测试无 npm 依赖，但开发机/CI 需要 Node 20+。
- 本检查点验证结果：跨平台 Node 测试 **7 项通过**、JieJuLanguage **57 项通过**、App 单元测试
  **48 项通过**。首次 App 全量运行曾因测试进程从源码目录读取 schema 而卡住；已改为 App 侧只
  校验稳定 v1 编码键，schema 本体及 `$ref` 由 Node 与 Swift Package 契约测试负责，复跑通过。

- Ollama 仍是默认解释服务；设置页新增“云端 API（OpenAI 兼容）”，当前实现面向
  `/v1/chat/completions`、`response_format=json_object` 和 SSE `data:` 流，API 地址应填写到
  API 版本根路径（例如 `https://api.openai.com/v1`）。
- 云端 API Key 通过 `KeychainAPIKeyStore` 存在 macOS 钥匙串，设置与模型名仍用 UserDefaults；
  测试验证密钥不会写入 `ai.cloudAPIKey`。不要把 API Key 加进配置文件、日志或测试 fixture。
- 云端 Provider 复用 `QwenPrompt`、`ExplanationParser` 和领域校验，最终格式错误时修复一次；
  流式中间值仅用于展示，保存仍等待最终校验结果。当前没有使用真实 Key 做外网端到端测试。
- 阅读器自绘工具栏加入 AppKit 可拖动背景；侧边栏模式在文档打开期间始终存在，关闭解句只切换
  到引导空状态。Computer Use 打开 `minimal.epub` 后确认 AX 树中阅读区与
  `reader.explanationSidebar` 同时存在，分栏位置在解释前后不会新增或消失。
- 验证结果：语言包 **55 项通过**、App 单元测试 **47 项通过**、macOS Debug App 构建成功。
- `.workbuddy/` 仍是用户未跟踪目录，本轮没有修改或纳入提交。

### 2026-09-02 额度中断检查点（接手者先读）

- 本轮修复了注音混入选区、翻页残留选区、误选下一句残片、侧栏重排定位、保存反馈和学习记录详情；
  日语本地语法同时纠正「十八で」并增加「た形＋ばかり」。
- 语言包 **51 项通过**；App 单元测试 **46 项通过**；随后加入的 `forceLayout()` 原生回退已通过
  `xcodebuild build`，但因用户中断，尚未重新跑单元测试。
- XCTest UI Runner 仍因 `Timed out while enabling automation mode` 无法启动，这不是产品断言失败。
- 重要：真实 EPUB 首版“稳定两次才上报”曾导致一直停在“正在排版”，已改为有限重试，并新增
  `WKNavigationDelegate.didFinish` 一秒后的 `forceLayout()` 回退。最后构建成功，但界面复测恰好被
  中断。下一位 Agent 的第一项任务应是打开《ノルウェイの森》，确认约 1 秒后从“正在排版”进入
  `本章 P / N 页`；若仍不退出，优先检查 `EPUBWebReaderView.Coordinator.didFinish` 的 JS 返回类型。
- `.workbuddy/` 仍是用户未跟踪目录，未修改、未纳入提交。

## 本次完成内容

- 完成 `EPUB-211C`：设置页 EPUB 排版区域增加实时页面预览，字号、行距、左右边距和四种主题均
  立即反馈。注入 CSS 进一步对 `p/li/blockquote/dd/dt` 显式覆盖字号与行距，解决 EPUB 自带
  固定段落样式导致滑块看似无效的问题，同时不覆盖标题字号层级。
- 完成 `INT-015`：`AppShellView` 不再用互斥 `switch` 创建/销毁 Reader。Reader 始终保留在详情
  区域，设置与学习记录以覆盖层显示；隐藏期间禁用点击、键盘快捷键和辅助功能暴露。返回阅读页
  会复用同一个 `ReaderViewModel`，因此已打开文档、章节、章内页和选区不会丢失。
- 完成 `EPUB-211B`：设置页新增白纸、夜间、羊皮纸、护眼绿四种阅读背景并持久化。主题会同时
  设置 WKWebView 底色、HTML/body 背景，以及正文全部子元素的前景色，防止透明 WebView 与系统
  深色模式、书内固定白字叠加后出现白底白字。默认白纸为 `#FAFAF8` + `#1C1C1E`。
- 主题变化会重建当前 EPUB 渲染视图并保留章内阅读位置；新增四主题 CSS 覆盖与设置持久化测试，
  App 单元测试现为 43 项全部通过。
- EPUB 分页强制规范原章节 `body` 的视口宽高、边距和多栏属性，并通过横向滚动偏移翻页；曾尝试
  把正文 DOM 搬入独立容器，但实际 EPUB 出现整页空白，现已撤销该方案并补回归测试。长章节仍按
  当前窗口拆页，资源处理同时覆盖 `application/xhtml+xml` 与 `text/html` 章节。
- 章内底栏新增页进度条及“第 X/Y 章 · 本章 P/C 页”；窗口、图片和字体加载变化会防抖重排，
  上一页/下一页及方向键均先在章内逐页移动，到边界后才跨章。
- 阅读位置由仅保存章节扩展为“章节索引 + 章内页码”，打开、跨章和调整排版后均恢复最近书页；
  保留旧章节位置键作为兼容回退。新增存储和分页注入回归测试，App 单元测试 42 项全部通过。
- 完整 App 界面验收仍需 macOS 允许辅助功能控制；自动控制本轮停在授权等待，因此 `EPUB-214`
  仍保留，不能把离线测试误记成完整 UI 测试。
- 完成 Ollama 快速解句流式链路：新增可取消的 URLSession NDJSON 行流、增量 JSON 字符串/对象
  解析和 App `streaming` 状态。翻译、主干、合法语法点和短语会随生成逐步刷新，最终严格校验
  通过前不提供保存或深度分析按钮；格式损坏仍保留一次修复。
- Prompt 固定字段生成顺序为翻译→主干→语法→短语；可解码结果优先本地清洗，避免仅因一个
  越界条目再次等待模型。CLI 增加 `stream` 实验命令。真实 1.5B 测试首次内容约 1.45 秒、
  翻译完成约 1.78 秒、最终约 3.92 秒。
- 修复 EPUB “16 页等于 16 章”的误导：工具栏现明确显示章节进度，章内底栏继续显示动态页数；
  WebKit 分页从仅测 `documentElement.scrollWidth` 改为测正文真实多栏宽度，避免长章被算成一页。
- 日语注音设置明确为“关闭/开启”；关闭时隐藏原书和自动 Ruby，开启时 `rt/rp` 使用不可选择
  样式。选区桥接对 Range 和整章正文分别克隆并移除 `rt/rp`，保证假名不进入目标句或上下文。
- 新增分页脚本、Ruby 选区与章节标签回归测试；两项针对性 App 测试实跑通过，语言包 47 项通过。
- 完成 `JA-003`：以固定 revision `1f096492...` 接入 Mecab-Swift + IPADic，默认本地 Provider
  现在返回分词、平假名读音、词性、词典原形、活用状态及汉字对齐区间；tokenizer 使用锁保护。
  IPADic Bundle 约 51MB，Debug App 约 136MB。高频小词典仅保留为初始化失败回退。
- 完成 `JA-006`：EPUB 开启“汉字注音”时，从本地词典结果生成安全 JSON，在 DOMContentLoaded
  阶段遍历正文 Text Node 注入 `<ruby>`；跳过原书 Ruby、rt、script、style、head 和 textarea。
  章节内同一表层形有多个读音时不注入，避免多音词被全局错误替换；注入结果按资源路径缓存。
- 修复日语深入解析超时和内容空洞：不再让 1.5B 填充庞大的日语 Deep Schema，而由本地
  `JapaneseGrammarAnalyzer` 基于 MeCab token 生成助词功能、日语句式骨架、谓语、原形和常见
  「〜ている／〜ました／〜ません／〜たい」活用说明。实测「私は日本語の本を読んでいます。」
  从模型失败/可能 60 秒超时变为约 0.013 秒，并稳定解释「は／の／を／〜でいます」。
- 外部依赖已同时锁定在 Swift Package 与 Xcode workspace 的 `Package.resolved`。上游独立探针
  21 项测试通过；本项目语言包 47 项测试通过，App/App Tests/UI Tests build-for-testing 通过。

- 开始 Track G 日语阅读：新增可持久化 `ReadingSegment(surface, reading)`、日语自动识别、
  日语无空格片段校验和可替换 `JapaneseReadingProviding`。当前本地实现仅注音明确命中的高频词，
  未知汉字保持原样，禁止使用模型猜测结果作为正文注音。
- 解句面板新增可换行 Furigana/Ruby 布局，设置页增加“不显示/汉字注音”并持久化；深入解析
  JSON 增加日语词语的原形、假名、活用类型和句中语法功能，并在 UI 标为“AI 参考”。
- 新增 12 条日语读音评测数据，覆盖多音字、姓名、活用、日期数字、熟字训和未知词；
  `Docs/JAPANESE_READING_ENGINE.md` 记录 Sudachi、MeCab/UniDic 与 Apple NaturalLanguage 的取舍。
- 尚未完成：正式形态词典接入与全量汉字—假名对齐（`JA-003`）、无原书 Ruby 的 EPUB 正文
  批量注音注入（`JA-006`）。后续 Agent 不应扩充手写小词典来冒充完整形态分析器。

- 重排后续计划为 Track E（WebKit 动态分页）、Track F（深度句法）和 Track G（日语假名）。
- 完成 `EPUB-201`：`EPUBDocument.resources` 暴露 manifest 资源数据、MIME 类型和标准包内路径；
  `EPUBChapter.resourcePath` 记录章节 XHTML 位置，并增加资源路径与内容回归测试。
- 完成 EPUB WebKit 正式阅读主链路：受限自定义 scheme、CSP 离线边界、XHTML/CSS/图片、
  动态多栏分页、页内/跨章翻页、方向键、章节菜单和 WebKit 选区解句桥接。
- 设置页新增 EPUB 字号、行距和页边距，变化后自动重新排版并持久化；系统明暗模式自动适配。
- 完成 Track F 功能主链路：新增 `DeepAnalysis` 领域模型、原文片段校验、独立深度 Prompt/
  Schema/解析/一次修复和 Ollama 调用；App 在快速结果后提供“深入解析句式与结构”，按层展示
  句型、成分、修饰关系、从句、深度语法和整句理解。深度分析不会随快速解句自动运行。
- 深度分析新增 `JieJuAILab deep` 独立入口和命令解析测试；`component.modifies` 也纳入目标句
  原文校验。新增 12 句句法冒烟集并完成 1.5B 实测：6/12 通过严格结构校验，平均约 20.1 秒；
  小模型常把语法标签写进原文片段字段，且通过项仍有句型误判。结论是 1.5B 暂不应作为
  “可靠深度语法老师”，下一步需完成 3B 对照（本机目前未安装 3B）。

- **EPUB 阅读界面**（`EPUB-101`）：统一打开面板支持 PDF/EPUB；以 `NSTextView` 实现
  原生可重排正文和滚动阅读，工具栏支持上一章/下一章并显示当前章节，章节进度可恢复。
- **EPUB 解句闭环**（`EPUB-102`）：原生选区生成统一 `ReaderSelection`，自动提取前后句，
  复用 Ollama 翻译/语法讲解、侧边栏/弹窗和学习记录保存，不另建一套 AI 接口。
- EPUB 解析移至后台任务，打开较大图书时不阻塞主界面；关闭或重新打开会取消旧加载。
- EPUB 错误增加可读中文说明；阅读入口及学习记录空状态文案改为 PDF/EPUB。

- **完善解句布局**（`PDF-113`）：解句面板增加独立滚动容器，翻译、主干、语法点、
  重点表达改为分区卡片；数组条目逐项显示，长文本固定纵向展开，避免字体拥挤和内容裁切。
- **侧边栏/弹窗切换**（`PDF-114`）：设置页增加分段选择并持久化；默认侧边栏通过
  `HSplitView` 与 PDF 并排，弹窗模式保留选区锚定交互。两种模式复用同一个解释面板。
- 选中原文改为默认折叠的 `DisclosureGroup`；失败状态增加明确图标与文本，不再只依赖颜色。
- 新增显示方式默认值及持久化回归测试。

- 修复 `AI-211`：Ollama JSON Schema 字段描述现在携带
  `explanationLanguage`/`sourceLanguage`（如 `translation` 描述为
  "Translate targetText into Chinese. Write the translation in Chinese, never in English."）。
  实测 0.5B/1.5B 均恢复输出正确中文翻译。
- 修复 `AI-212`：`validated(against:)` 在双语请求下拦截
  `translation` 与 `targetText` 完全相同（含大小写变体）；repair 提示补语言约束。
- 跑通 0.5B 批量冒烟评测（20 条，45 秒），建立真实模型基线；1.5B 对照已启动。
- **保存并恢复最近阅读页码**（`PDF` 阅读闭环补全）：
  - 新增 `ReadingPositionStore`（UserDefaults，按文档标准化路径存页码）；
  - `ReaderViewModel` 打开文档时恢复上次页码，翻页即保存，关闭时兜底保存；
  - `PDFReaderView` 增加 `initialPageIndex`，`makeNSView`/文档切换时 `go(to:)` 定位；
  - 新增 `ReadingPositionStoreTests`（6 项）。
- **修复上一轮 `ca53263` 引入的编译错误**：`AppSettings`/`AppShellView` 中
  `OllamaReadingAI.defaultModel` 是泛型静态成员、无法裸引用，
  已改为非泛型常量 `OllamaDefaults.model`（此前该错误无法编译验证，本轮用类型检查抓到）。
- **EPUB 解析核心**（`JieJu/Infrastructure/EPUB/EPUBCore.swift`，无第三方依赖）：
  自研 ZIP 解包（系统 zlib）+ container/OPF + spine + 章节文本抽取（XML 模式/实体解码/正则回退）。
  测试 fixture：`JieJuTests/Fixtures/{minimal,messy,nocontainer}.epub`（已入测试 Target 资源）。
  实测 7 项测试通过、真实《挪威的森林》EPUB 解析成功（16 章 3169 段）。
  **渲染与阅读界面尚未实现，待选方案（WebKit 排版 vs 重排文本），见 DECISIONS.md。**
- **可配置解释语言**（`INT-012`）：设置页选择解释语言（预设 6 种 + 自定义），
  `AppSettings.explanationLanguage` 持久化；请求与学习记录使用实际语言。
- **修复 `PDF-112`**：移除由 AI 设置驱动的 `ReaderView.id`，改为原位更新 Provider
  与解释语言；当前 PDF、页码和选区不再因设置输入而丢失，并增加配置更新回归测试。
- **真实解句成为默认**（`1a55765`）：旧版 Mock 默认偏好一次性迁移到 Ollama 1.5B；
  修复轮逐项删除越界内容而非清空全部讲解，并明确要求中文翻译/语法/词义。

## 验证

- JieJuLanguage 包测试：**44 项通过**（`swift test`）。
- App、App Tests 与 UI Tests：`xcodebuild build-for-testing` 通过；新增日语识别和注音设置测试。
- Ollama 1.5B 端到端：中文翻译、英文主干、中文语法说明通过；不再返回 Mock 示例。
- 单句实测：0.5B「火车于六点出发。」、1.5B「火车六点出发。」均正确。
- `xcodebuild build`：通过。
- `xcodebuild build-for-testing`：通过，App 单元测试与 UI 测试目标均成功编译。
- 本轮 `xcodebuild build` 与 `build-for-testing` 均通过；JieJuLanguage 35 项测试通过。
- macOS App/UI 测试：**无法运行**。本机 `DevToolsSecurity -status` 为 disabled，
  Runner 卡在 `The test runner hung before establishing connection.`。
- Xcode 人工启动：待用户确认。

## 真实模型基线（2026-09-02，Qwen 2.5 冒烟集 20 条）

### 0.5B（可在设置中选择）

- 结构化成功率 **75%**（15/20），平均 2.2 秒 —— 未达 95% 门槛
- 失败 5 条：3 条英文照抄被 AI-212 正确拦截（passive-01、ambiguity-02、literary-01），
  2 条 JSON 解析失败（nonfinite-01、ambiguity-01）
- 通过条目中 ≥2 条英文释义漏网（nonfinite-02、relative-02）：
  AI-212 只拦「与原文完全一致」，拦不住「同语言释义」
- 长句翻译截断、复杂结构（被动/文学/指代）质量差
- **结论：0.5B 暂不满足 MVP 门槛，不建议作为默认模型**

数据：`Evaluation/results-0.5b.jsonl`、`Evaluation/report-0.5b.md`
（两者均已在 `.gitignore` 中，未入库）

### 1.5B

- 结构化成功率 **100%**（20/20），平均 4.1 秒 —— 达标（门槛 ≥95%）
- 全部翻译正确中文；0.5B 全灭的类别（被动/文学/指代消解/非谓语）全部通过
- 语法点 10/20、短语 10/20，共 50 条目
- **已定为默认模型**：`OllamaDefaults.model` 单一来源，CLI/App 设置/设置页展示均引用

数据：`Evaluation/results-1.5b.jsonl`、`Evaluation/report-1.5b.md`（均 gitignore，未入库）

## 已定位但未修的缺陷

1. **英文释义漏网**：AI-212 只拦截翻译与原文完全相同；同语言释义仍能通过校验。
   可在 `validated(against:)` 增加启发式（如检测翻译为源语言字符集）或交给评测门槛把关。
3. 无障碍小项：`LearningRecordsView` 删除仅 contextMenu，缺键盘/VoiceOver 路径。

## 已知问题

- 真实模型质量未达标（0.5B 75%，门槛 95%）；默认模型 1.5B 已定档（DECISIONS.md）
- EPUB：基础阅读、章节导航与选区解句已完成；目录、排版设置和富文本样式尚未实现。
- 缺少固定测试 PDF 和完整 UI 流程；
- 尚未实现「重新解释已保存句子」（INT-009）与学习记录详情页；
- 本机开发者模式关闭，App/UI 测试全线阻塞；
- 工作区中的 `.workbuddy/` 未纳入版本控制，接手者不得擅自删除。
- EPUB Agent 当前正在修改 Reader/EPUB 文件；`1a55765` 未包含这些并行未提交改动。

## 环境注意事项

- **App 层编译验证的可行办法（重要，替代 xcodebuild）**：
  本工具无法跑 `xcodebuild build`（本地 SwiftPM 解析时 `sandbox_exec` 被拒），
  但可以用裸 `swiftc` 完成等效验证：
  ```bash
  # 1) 先构建本地包（--disable-sandbox）
  cd Packages/JieJuLanguage && swift build --disable-sandbox
  # 2) 整个 App 模块类型检查（先剥离 #Preview，宏插件服务器同样被沙箱挡）
  xcrun swiftc -typecheck -sdk $(xcrun --show-sdk-path) -target arm64-apple-macosx14.0 \
    -I Packages/JieJuLanguage/.build/arm64-apple-macosx/debug/Modules $(find JieJu -name '*.swift')
  # 3) 测试目标：先 emit-module -enable-testing 出 JieJu 模块，再对测试文件 typecheck
  #    （加 -F .../MacOSX.platform/Developer/Library/Frameworks 供 XCTest；
  #     XCTAssertNil 等 C 宏在独立 swiftc 下报 "function like macros not supported"，属正常，Xcode 里没问题）
  ```
  用这个方法在 2026-09-02 实际抓出了 `ca53263` 里的泛型静态成员编译错误。
- 本机 Ollama 已装可达（`:11434`），已拉取 `qwen2.5:0.5b-instruct` 与 `qwen2.5:1.5b-instruct`；
  默认模型为 1.5B（`OllamaDefaults.model`），0.5B 可在设置中选择。
- CLI 二进制：`Packages/JieJuLanguage/.build/arm64-apple-macosx/debug/JieJuAILab`
  - 单句：`JieJuAILab explain --text "..." [--before "..." ] [--after "..."] [--raw] [--model N] [--url U]`
  - 批量：`JieJuAILab batch --input X.jsonl --output Y.jsonl --report Z.md [--model N]`
  - 注意 `--raw/` 之类的尾部斜杠是非法参数，参数之间用空格。
- 本工具无法构建带本地 SwiftPM 依赖的 Xcode 工程（`sandbox_exec` 被拒），
  验证 App 编译只能靠包测试 + 读代码 + 用户在 Xcode 里确认。

## 下一任务建议

1. **人工评分 0.5B/1.5B 输出**（`Evaluation/report-*.md` 的 Manual scoring 表）：
   translationAccuracy / sentenceCoreAccuracy / grammarAccuracy / phraseValue / hallucination。
2. 用户开启开发者模式（`sudo DevToolsSecurity -enable` + 重启）后跑 App/UI 测试与 `PDF-009`。
3. `AI-403`：扩展到 100 条正式评测句（在模型定档之后做，避免反复返工）。

任务结束后更新本文件，不要只把交接信息留在聊天中。
