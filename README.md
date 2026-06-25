# Android 共享 Workflow 模板

> 可复用的 Android CI/CD 工作流集合。新老项目只需一个 YAML 文件即可接入完整的 PR 门禁、主 CI、内部分发、商店上架流水线。

## 设计理念

```
┌─────────────────────────────────────┐
│     android-template (本仓库)        │  ← 只在这里维护 CI/CD 逻辑
│  ├── pr-check.yml                   │
│  ├── ci.yml                         │
│  ├── deploy-internal.yml            │
│  └── release-store.yml              │
└──────┬──────┬──────┬────────────────┘
       │      │      │
   uses:@v1 uses:@v1 uses:@v1
   ┌───┐  ┌───┐  ┌───┐
   │老A│  │老B│  │新C│  ← 各项目只写一个薄包装文件
   └───┘  └───┘  └───┘
```

**零侵入** — 不需要改源码、包名或 Gradle 配置  
**版本隔离** — 锁定 `@v1` 标签，本仓库升级不会影响消费项目  
**渐进接入** — 可以先只接 PR Check，跑通了再加其他流程  

## 快速开始

### 前提条件

消费项目需要满足（绝大多数 Android 项目天然满足）：

| 条件 | 说明 |
|------|------|
| Gradle 项目 | 根目录有 `gradlew` |
| 标准任务名 | `assembleDebug`, `lintDebug`, `testDebugUnitTest` 存在 |
| 非标任务可配 | 如果任务名不同，通过 `with:` 参数覆盖（见下文） |

### Step 1：在消费项目创建包装文件

在你的 Android 项目 `.github/workflows/` 目录下创建一个文件，例如 `call-pr-check.yml`：

```yaml
name: PR Check

on:
  pull_request:
    branches: [main, develop]

jobs:
  pr-check:
    uses: CSDchenshaodong/android-template/.github/workflows/pr-check.yml@v1
    secrets: inherit
```

### Step 2：配置 Secrets（按需）

| Secret | 哪些 Workflow 需要 |
|--------|-------------------|
| `KEYSTORE_BASE64` | `deploy-internal`, `release-store` |
| `KEYSTORE_PASSWORD` | `deploy-internal`, `release-store` |
| `KEY_ALIAS` | `deploy-internal`, `release-store` |
| `KEY_PASSWORD` | `deploy-internal`, `release-store` |
| `FIREBASE_APP_ID` | `deploy-internal`, `ci`(启用内部分发) |
| `FIREBASE_CREDENTIALS` | `deploy-internal`, `ci`(启用内部分发) |
| `PLAY_STORE_JSON_BASE64` | `release-store` |
| `CODECOV_TOKEN` | `pr-check`, `ci`（可选） |
| `SLACK_WEBHOOK_URL` | 所有（可选） |

> GitHub Actions 自动注入 `GITHUB_TOKEN`，无需手动添加。

### Step 3：提一个 PR 验证

提交包装文件，提 PR。如果一切正常，PR 会自动触发门禁检查并评论结果。

---

## 可用 Workflow

### 1. PR Check (`pr-check.yml`)

**作用**：PR 提交流水线 — Lint、单元测试、构建验证、依赖安全扫描，5 分钟内完成。

**消费项目包装示例**：

```yaml
# .github/workflows/pr-check.yml
name: PR Check
on:
  pull_request:
    branches: [main, develop, 'release/**']
jobs:
  check:
    uses: CSDchenshaodong/android-template/.github/workflows/pr-check.yml@v1
    secrets: inherit
```

**可覆盖的输入参数**（默认值匹配标准 Android 项目）：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `java-version` | `'17'` | JDK 版本 |
| `ja va-distribution` | `'temurin'` | JDK 发行版 |
| `lint-task` | `'lintDebug'` | Android Lint 任务 |
| `ktlint-task` | `'ktlintCheck'` | ktlint 任务（留空跳过） |
| `detekt-task` | `'detekt'` | Detekt 任务（留空跳过） |
| `spotless-task` | `'spotlessCheck'` | Spotless 任务（留空跳过） |
| `unit-test-task` | `'testDebugUnitTest'` | 单元测试任务 |
| `coverage-task` | `'jacocoTestCoverageVerification'` | 覆盖率任务（留空跳过） |
| `build-task` | `'assembleDebug'` | 构建任务 |
| `dependency-check-task` | `'dependencyCheckAnalyze'` | 依赖扫描任务（留空跳过） |
| `pr-title-types` | `'feat,fix,...'` | PR 标题允许的 type |
| `max-pr-size` | `'1000'` | PR 最大行数 |

### 2. Main CI (`ci.yml`)

**作用**：合并到 develop 后触发 — 多 JDK 测试矩阵、多风味构建、可选仪器化测试和内部分发。

```yaml
# .github/workflows/ci.yml
name: Main CI
on:
  push:
    branches: [develop]
  workflow_dispatch:
jobs:
  ci:
    uses: CSDchenshaodong/android-template/.github/workflows/ci.yml@v1
    secrets: inherit
    with:
      build-flavors: '["dev", "staging", "prod"]'
```

**常用输入参数**：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `java-matrix` | `'["17"]'` | JDK 版本矩阵 |
| `build-flavors` | `'["debug"]'` | 构建风味矩阵 |
| `run-instrumented` | `false` | 是否运行 UI 测试 |
| `enable-internal-distribution` | `false` | 是否在 CI 后自动内部分发 |
| `firebase-groups` | `'qa-team,dev-team'` | Firebase 测试组 |

### 3. Deploy Internal (`deploy-internal.yml`)

**作用**：构建签名 APK → 上传 Firebase App Distribution → 通知 Slack。

```yaml
# .github/workflows/deploy-internal.yml
name: Deploy Internal
on:
  push:
    branches: [develop]
  workflow_dispatch:
    inputs:
      groups:
        description: '测试组'
        default: 'qa-team,dev-team'
jobs:
  deploy:
    uses: CSDchenshaodong/android-template/.github/workflows/deploy-internal.yml@v1
    secrets: inherit
    with:
      firebase-groups: ${{ github.event.inputs.groups || 'qa-team,dev-team' }}
```

### 4. Release Store (`release-store.yml`)

**作用**：上架 Google Play Store — 支持 internal / alpha / beta / 渐进发布 / 紧急暂停。

```yaml
# .github/workflows/release-store.yml
name: Release to Play Store
on:
  push:
    tags: ['v[0-9]+.[0-9]+.[0-9]+']
  workflow_dispatch:
    inputs:
      track:
        description: '发布轨道'
        type: choice
        options: [internal, alpha, beta, production_staged, production_full, halt_rollout]
jobs:
  release:
    uses: CSDchenshaodong/android-template/.github/workflows/release-store.yml@v1
    secrets: inherit
    with:
      track: ${{ github.event.inputs.track || 'internal' }}
```

### 5. Nightly (`nightly.yml`)

**作用**：夜间全面构建 — 在模拟器上跑完整测试套件。

```yaml
# .github/workflows/nightly.yml
name: Nightly Build
on:
  schedule:
    - cron: '0 2 * * *'
jobs:
  nightly:
    uses: CSDchenshaodong/android-template/.github/workflows/nightly.yml@v1
    secrets: inherit
```

---

## 版本策略

```
@v1    — 主版本，可能有破坏性变更
@v1.0  — 次版本，向后兼容的新功能
@v1.0.0 — 补丁版本，Bug 修复
```

**推荐做法**：
- 生产项目锁定 `@v1`（自动跟随补丁和次版本）
- 保守项目锁定 `@v1.0`（只跟随 Bug 修复）
- 需要绝对稳定时锁定完整 SHA

---

## 老项目接入指南

### 兼容性检查清单

在接入前，确认你的老项目：

- [ ] 使用 Gradle 构建（有 `gradlew`）
- [ ] 以下标准任务至少有一个可用：
  - `assembleDebug` 或等价构建任务
  - `lintDebug` 或 `lint`
  - `testDebugUnitTest` 或 `test`

如果任务名不同，通过 `with:` 参数覆盖即可，**无需修改 build.gradle**。

### 典型接入步骤

```
1. 复制 templates/consumer-workflows/pr-check.yml 到你的项目
   → .github/workflows/pr-check.yml

2. 修改 uses: 中的组织名为你的实际组织

3. 如果 Gradle 任务名不同，在 with: 中覆盖

4. 提 PR 验证

5. 跑通后，按需依次接入 ci.yml → deploy-internal.yml → release-store.yml
```

### 老项目常见问题

**Q: 我的项目没有 ktlint/Detekt/Spotless，会报错吗？**

不会。将对应参数设为空字符串即可跳过：
```yaml
with:
  ktlint-task: ''
  detekt-task: ''
  spotless-task: ''
```

**Q: 我的项目用 JDK 11/21，不是 17？**

覆盖 `java-version`：
```yaml
with:
  java-version: '11'
```

**Q: 我的 app 模块不是 `app/`？**

Workflow 通过 `build-task`、`unit-test-task` 等参数指定任务，不直接写死模块路径。只要 Gradle 任务名能匹配即可。如果是多模块项目，确保任务名包含模块前缀即可，如 `:app:assembleDebug`。

---

## 项目文件说明

```
android-template/
├── .github/workflows/          # 🔧 可复用 Workflow（核心资产）
│   ├── pr-check.yml            #   PR 门禁
│   ├── ci.yml                  #   主 CI
│   ├── deploy-internal.yml     #   内部分发（Firebase）
│   ├── release-store.yml       #   商店上架（Play Store）
│   └── nightly.yml             #   夜间构建
├── templates/                  # 📋 消费项目模板文件
│   ├── consumer-workflows/     #   包装 Workflow 示例（复制到项目）
│   ├── scripts/                #   辅助脚本
│   │   ├── ci-local.sh         #     本地模拟 CI
│   │   ├── install-git-hooks.sh #    安装 Git Hook
│   │   └── setup.sh            #     新成员环境初始化
│   ├── .github/                #   GitHub 配置模板
│   │   ├── ISSUE_TEMPLATE/     #     Issue 模板
│   │   ├── pull_request_template.md
│   │   ├── CODEOWNERS
│   │   └── dependabot.yml
│   ├── fastlane/               #   fastlane 配置模板
│   ├── lefthook.yml            #   Git Hook 配置
│   ├── detekt-config.yml       #   Detekt 规则
│   └── gradle-ci.properties    #   CI Gradle 优化参数
└── README.md
```

---

## 辅助工具

### 一键初始化开发环境

将 `templates/scripts/` 下的文件复制到项目 `scripts/` 目录，然后执行：

```bash
./scripts/setup.sh           # 检查 JDK/SDK、安装 Hook、快速验证
./scripts/ci-local.sh        # 推送前模拟完整 CI 流程
./scripts/install-git-hooks.sh  # 单独安装 Git Hook
```

### Git Hook（lefthook）

将 `templates/lefthook.yml` 复制到项目根目录，运行 `./scripts/install-git-hooks.sh`：

- **pre-commit**：自动格式化（ktlint + spotless）+ Detekt 静态分析
- **commit-msg**：强制 Conventional Commits 格式
- **pre-push**：本地完整 CI 检查（lint + 测试 + 构建）

### Detekt 配置

将 `templates/detekt-config.yml` 复制到项目根目录（Gradle 中配置 `detekt.config = rootProject.file("detekt-config.yml")`）。

---

## 与方案1（Template Repository）的关系

如果你启动新项目，可以从本仓库的 `templates/` 目录快速搭建"完整脚手架"：

```
1. 创建 Android 新项目
2. 复制 templates/.github/ 下的文件到项目
3. 从 consumer-workflows/ 复制包装 workflow
4. 从 templates/scripts/ 复制脚本
5. 从 templates/ 复制 lefthook.yml、detekt-config.yml 等
```

同时，核心 CI/CD 仍然通过 `uses:` 引用本仓库的 Workflow，确保 CI/CD 逻辑统一维护。

---

## 贡献

1. 修改 workflow 时确保向后兼容（新增 inputs 有默认值）
2. 破坏性变更时打新 major tag（`v2`, `v3`...）
3. 在 CHANGELOG.md 中记录每个版本的变更

## License

Internal use.
