# Android 全流程自动化搭建方案（GitHub 版）

> 从需求到应用商店上架，每一环的自动化配置详解

---

## 目录

- [1. 整体架构](#1-整体架构)
- [2. 项目结构总览](#2-项目结构总览)
- [3. GitHub 仓库基础配置](#3-github-仓库基础配置)
- [4. 需求自动化](#4-需求自动化)
- [5. PR 门禁检查](#5-pr-门禁检查)
- [6. 主 CI 流水线](#6-主-ci-流水线)
- [7. 自动化测试](#7-自动化测试)
- [8. 依赖管理自动化](#8-依赖管理自动化)
- [9. 代码质量自动化](#9-代码质量自动化)
- [10. 构建与签名](#10-构建与签名)
- [11. 内部分发（Firebase）](#11-内部分发firebase)
- [12. 应用商店上架（Play Store）](#12-应用商店上架play-store)
- [13. 渐进式发布与自动回滚](#13-渐进式发布与自动回滚)
- [14. 监控告警闭环](#14-监控告警闭环)
- [15. 本地开发环境一键初始化](#15-本地开发环境一键初始化)
- [16. Secrets 配置清单](#16-secrets-配置清单)
- [17. 跨项目复用](#17-跨项目复用)
- [18. 实施路线图](#18-实施路线图)

---

## 1. 整体架构

```
需求(Issue) ──→ 开发分支 ──→ PR 门禁 ──→ 主 CI ──→ 分发/上架 ──→ 监控反馈
                                                    │
                              ┌───────────────────┼───────────────────┐
                              ↓                   ↓                   ↓
                         Firebase            Google Play          Slack/钉钉
                      (内部测试分发)         (生产发布)            (告警通知)
```

### 各阶段耗时目标

| 阶段 | 触发方式 | 目标耗时 | 干什么 |
|------|---------|---------|--------|
| PR 门禁 | 提 PR | < 5 分钟 | Lint、单元测试、构建验证 |
| 主 CI | 合并到 develop | < 15 分钟 | 完整测试、多 API 验证 |
| 内部分发 | 合并到 develop | < 20 分钟 | 构建 → 签名 → 上传 Firebase |
| 商店上架 | 推送 tag | < 30 分钟 | 构建 AAB → fastlane → Play Store |

---

## 2. 项目结构总览

```
your-android-project/
├── .github/
│   ├── workflows/                      # 🔧 所有 CI/CD 流水线
│   │   ├── pr-check.yml               #   PR 门禁（快，5分钟内）
│   │   ├── ci.yml                     #   主 CI（完整检查）
│   │   ├── deploy-internal.yml        #   内部分发 Firebase
│   │   ├── release-store.yml          #   上架 Play Store
│   │   ├── nightly.yml                #   夜间全面构建
│   │   └── auto-issue-from-crash.yml  #   崩溃自动提 Issue
│   ├── ISSUE_TEMPLATE/                # 📋 需求/Bug 模板
│   │   ├── feature-request.yml
│   │   ├── bug-report.yml
│   │   └── tech-debt.yml
│   ├── pull_request_template.md       # 📝 PR 描述模板
│   ├── CODEOWNERS                     # 👥 自动分配 Reviewer
│   ├── release-drafter.yml            # 📦 自动生成 Release Notes
│   └── dependabot.yml                 # 📌 依赖自动更新
├── fastlane/                          # 🚀 发布自动化
│   ├── Fastfile
│   ├── Appfile
│   └── metadata/android/              # 🏪 Play Store 物料
│       └── en-US/
│           ├── title.txt
│           ├── short_description.txt
│           ├── full_description.txt
│           └── changelogs/
├── scripts/                           # 🛠 辅助脚本
│   ├── ci-local.sh                    #   本地模拟 CI
│   ├── install-git-hooks.sh           #   安装 Git Hook
│   ├── fetch-crashes.sh               #   抓取 Firebase 崩溃数据
│   └── setup.sh                       #   新成员环境一键初始化
├── app/
│   └── build.gradle.kts
├── build.gradle.kts
├── gradle.properties                  #   CI 优化参数
├── detekt-config.yml                  #   Detekt 规则配置
├── lefthook.yml                       #   Git Hook 管理
└── CLAUDE.md                          #   项目文档
```

---

## 3. GitHub 仓库基础配置

### 3.1 仓库设置

进入仓库 **Settings** 依次配置：

#### Branches → Branch protection rules → Add rule

| 设置项 | 值 |
|--------|---|
| Branch name pattern | `main` |
| Require a pull request before merging | ✅ |
| Require approvals | 1 |
| Dismiss stale reviews | ✅ |
| Require status checks to pass | ✅ |
| Require branches to be up to date | ✅ |
| Status checks | `pr-meta`, `lint`, `unit-test`, `build-check`, `dependency-scan` |
| Require conversation resolution | ✅ |

同样为 `develop` 和 `release/*` 设置保护规则。

#### General → Pull Requests

| 设置项 | 值 |
|--------|---|
| Allow squash merging | ✅ (推荐) |
| Allow rebase merging | ❌ |
| Default to squash | ✅ |
| Automatically delete head branches | ✅ |

### 3.2 分支策略

```
main              ← 生产代码，禁止直接 push
  └── develop      ← 开发主线，feature 合并的目标
        ├── feature/xxx-需求描述   ← 功能开发
        ├── bugfix/xxx-问题描述    ← Bug 修复
        └── chore/xxx-描述         ← 构建/CI/依赖更新
release/1.0.0     ← 发布分支，只做稳定修复
hotfix/xxx        ← 紧急修复，从 main 拉，合并回 main+develop
```

---

## 4. 需求自动化

### 4.1 功能需求 Issue 模板

```yaml
# .github/ISSUE_TEMPLATE/feature-request.yml
name: ✨ Feature Request
description: 提出新功能需求
title: "[Feature] "
labels: ["feature", "triage"]
body:
  - type: textarea
    id: user-story
    attributes:
      label: 用户故事
      description: 用标准格式描述
      placeholder: |
        作为 <角色>
        我希望 <功能>
        以便 <价值>
    validations:
      required: true

  - type: textarea
    id: acceptance-criteria
    attributes:
      label: 验收标准
      description: 按照 Given/When/Then 格式
      placeholder: |
        - [ ] **Given** 用户已登录
          **When** 用户点击"购买"按钮
          **Then** 跳转到支付页面
        - [ ] **Given** 用户未登录
          **When** 用户点击"购买"按钮
          **Then** 跳转到登录页面
    validations:
      required: true

  - type: dropdown
    id: priority
    attributes:
      label: 优先级
      options:
        - "P0 - 紧急（阻塞其他工作）"
        - "P1 - 高（本周必须完成）"
        - "P2 - 中（本迭代完成）"
        - "P3 - 低（有空再做）"
    validations:
      required: true

  - type: textarea
    id: figma-link
    attributes:
      label: Figma 设计稿链接
      placeholder: https://www.figma.com/file/...

  - type: textarea
    id: api-doc
    attributes:
      label: 相关 API 文档
      placeholder: Swagger / Postman 链接

  - type: input
    id: estimate
    attributes:
      label: 预估工时（小时）
      placeholder: "4"
```

### 4.2 Bug 报告 Issue 模板

```yaml
# .github/ISSUE_TEMPLATE/bug-report.yml
name: 🐛 Bug Report
description: 提交 Bug 报告
title: "[Bug] "
labels: ["bug", "triage"]
body:
  - type: textarea
    id: steps
    attributes:
      label: 复现步骤
      placeholder: |
        1. 打开 App
        2. 点击 xxx
        3. 观察到 yyy
    validations:
      required: true

  - type: textarea
    id: expected
    attributes:
      label: 期望行为
    validations:
      required: true

  - type: textarea
    id: actual
    attributes:
      label: 实际行为
    validations:
      required: true

  - type: input
    id: version
    attributes:
      label: App 版本
      placeholder: "1.2.3 (42)"

  - type: dropdown
    id: device
    attributes:
      label: 设备信息
      options:
        - "真机 - Android"
        - "模拟器 - Android"
        - "两者都有"

  - type: dropdown
    id: severity
    attributes:
      label: 严重程度
      options:
        - "🔴 崩溃 - App 闪退"
        - "🟠 严重 - 核心功能不可用"
        - "🟡 一般 - 功能可用但有错误"
        - "🟢 轻微 - UI 或体验问题"
```

### 4.3 PR 模板

```markdown
<!-- .github/pull_request_template.md -->
## 📝 描述
<!-- 简要描述这个 PR 做了什么 -->

## 🔗 关联 Issue
Closes #

## 🎯 变更类型
- [ ] 新功能 (feat)
- [ ] Bug 修复 (fix)
- [ ] 重构 (refactor)
- [ ] 构建/CI (build/ci)
- [ ] 文档 (docs)

## 📸 截图 / 录屏（UI 变更必须提供）
| 之前 | 之后 |
|------|------|
|      |      |

## ✅ 自检清单
- [ ] 代码通过所有 Lint 检查
- [ ] 单元测试全部通过
- [ ] 新增代码有对应的测试覆盖
- [ ] 测试覆盖率没有下降
- [ ] UI 变更已附截图
- [ ] API 变更已更新文档

## 🧪 如何测试
<!-- 给 Reviewer 的测试指引 -->
1.
2.
3.
```

### 4.4 自动分配 Reviewer

```bash
# .github/CODEOWNERS
# 语法: <文件路径> <@团队或@用户>

# 构建相关 → 基础架构团队
*.gradle.kts                       @team-infra
gradle.properties                  @team-infra
buildSrc/                          @team-infra

# 核心模块 → 各自负责人
app/core/network/                  @team-backend
app/core/database/                 @team-backend
app/feature/user/                  @team-user
app/feature/payment/               @team-payment

# UI/主题 → 设计系统团队
app/ui/theme/                      @team-design
app/ui/component/                  @team-design

# CI/CD → 基础架构团队
.github/workflows/                 @team-infra
fastlane/                          @team-infra

# 文档 → 全员
*.md                               @team-infra @team-user @team-payment
```

### 4.5 自动化 Issue → 分支流程

```yaml
# .github/workflows/auto-branch.yml
# 当 Issue 被 assign 时自动创建功能分支并关联
name: Auto Create Branch from Issue

on:
  issues:
    types: [assigned]

jobs:
  create-branch:
    runs-on: ubuntu-latest
    if: contains(github.event.issue.labels.*.name, 'feature')
    steps:
      - uses: actions/checkout@v4

      - name: Create feature branch
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          ISSUE_NUM=${{ github.event.issue.number }}
          # 将标题转换为 kebab-case 分支名
          TITLE=$(echo "${{ github.event.issue.title }}" \
            | sed 's/\[Feature\] //' \
            | tr '[:upper:]' '[:lower:]' \
            | sed 's/[^a-z0-9]/-/g' \
            | sed 's/--*/-/g' \
            | sed 's/^-//' | sed 's/-$//')
          BRANCH="feature/${ISSUE_NUM}-${TITLE}"
          git checkout -b "$BRANCH"
          git push origin "$BRANCH"

          # 关联 Issue 到分支
          gh issue develop "$ISSUE_NUM" --name "$BRANCH" --checkout
```

---

## 5. PR 门禁检查

> 目标：**5 分钟内完成**，高频快速反馈。提 PR 即触发，检查通过才能合并。

```yaml
# .github/workflows/pr-check.yml
name: PR Check

on:
  pull_request:
    branches: [main, develop, 'release/**']
  pull_request_review:
    types: [submitted]

concurrency:
  group: pr-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  # ── 阶段 0: PR 标题格式检查 ──
  pr-meta:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check PR title (Conventional Commits)
        uses: amannn/action-semantic-pull-request@v5
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          types: |
            feat fix docs style refactor perf test build ci chore revert
          requireScope: false

      - name: Label by PR size
        uses: codelytv/pr-size-labeler@v1
        with:
          xs_label: 'size/xs'
          xs_max_size: 10
          s_label: 'size/s'
          s_max_size: 100
          m_label: 'size/m'
          m_max_size: 500
          l_label: 'size/l'
          l_max_size: 1000
          xl_label: 'size/xl'
          fail_if_xl: true
          message_if_xl: >
            🚫 PR 超过 1000 行变更，请拆分成多个小 PR 以方便 Review。

  # ── 阶段 1: 代码风格 & 静态分析（并行执行）──
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v3

      - name: ktlint check
        run: ./gradlew ktlintCheck --continue

      - name: Detekt analysis
        run: ./gradlew detekt --continue

      - name: Android Lint
        run: ./gradlew lintDebug --continue

      - name: Spotless check
        run: ./gradlew spotlessCheck --continue

      - name: Upload lint reports (only on failure)
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: lint-reports
          path: |
            **/build/reports/ktlint/
            **/build/reports/detekt/
            **/build/reports/lint-results*.html

  # ── 阶段 2: 单元测试 + 覆盖率 ──
  unit-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v3

      - name: Run unit tests
        run: ./gradlew testDebugUnitTest

      - name: Coverage verification
        run: ./gradlew jacocoTestCoverageVerification --continue

      - name: Publish test report
        if: always()
        uses: dorny/test-reporter@v1
        with:
          name: Unit Tests
          path: '**/build/test-results/**/*.xml'
          reporter: java-junit

  # ── 阶段 3: 构建验证 ──
  build-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v3

      - name: Assemble debug
        run: ./gradlew assembleDebug

  # ── 阶段 4: 依赖安全扫描 ──
  dependency-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: OWASP dependency check
        run: ./gradlew dependencyCheckAnalyze --continue
        continue-on-error: true

      - name: Upload dependency report
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: dependency-check
          path: build/reports/dependency-check-*.html

  # ── 阶段 5: 自动评论汇总结果 ──
  summary:
    needs: [pr-meta, lint, unit-test, build-check, dependency-scan]
    if: always()
    runs-on: ubuntu-latest
    steps:
      - uses: actions/github-script@v7
        with:
          script: |
            const needs = context.payload.workflow_run?.conclusion || {};
            const results = {
              pr_meta: '${{ needs.pr-meta.result }}',
              lint: '${{ needs.lint.result }}',
              unit_test: '${{ needs.unit-test.result }}',
              build: '${{ needs.build-check.result }}',
              deps: '${{ needs.dependency-scan.result }}',
            };

            const emoji = {
              success: '✅',
              failure: '❌',
              skipped: '⏭️',
              cancelled: '⚪',
            };

            const allPassed = Object.values(results).every(r => r === 'success');

            const body = `## 🤖 PR 自动检查结果

| 检查项 | 结果 |
|--------|------|
| PR 标题规范 | ${emoji[results.pr_meta]} ${results.pr_meta} |
| Lint (ktlint/Detekt/Lint) | ${emoji[results.lint]} ${results.lint} |
| 单元测试 + 覆盖率 | ${emoji[results.unit_test]} ${results.unit_test} |
| 构建验证 | ${emoji[results.build]} ${results.build} |
| 依赖安全扫描 | ${emoji[results.deps]} ${results.deps} |

${allPassed
  ? '🎉 **所有检查通过**！请 Review 代码后合并。'
  : '⚠️ **有检查失败**，请点击上方 Actions 链接查看详情并修复。'}`;

            // 找到或创建 "CI Results" 评论
            const { data: comments } = await github.rest.issues.listComments({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
            });

            const botComment = comments.find(c =>
              c.body.includes('🤖 PR 自动检查结果') && c.user.type === 'Bot'
            );

            if (botComment) {
              await github.rest.issues.updateComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                comment_id: botComment.id,
                body,
              });
            } else {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: context.issue.number,
                body,
              });
            }
```

---

## 6. 主 CI 流水线

> 合并到 develop 后触发，做完整检查 + 内部分发。

```yaml
# .github/workflows/ci.yml
name: Main CI

on:
  push:
    branches: [develop]
  workflow_dispatch:     # 允许手动触发
    inputs:
      run_instrumented:
        description: '运行仪器化测试?'
        type: boolean
        default: false
        required: false

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: false   # 不要取消，确保完整执行

jobs:
  # ── 完整 Lint ──
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17' }
      - uses: gradle/actions/setup-gradle@v3
      - run: ./gradlew ktlintCheck detekt lintDebug --continue

  # ── 单元测试矩阵（多版本验证）──
  unit-test-matrix:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        java: ['17', '21']  # 验证 JDK 17 和 21 都通过
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: ${{ matrix.java }}
      - uses: gradle/actions/setup-gradle@v3
      - run: ./gradlew testDebugUnitTest jacocoTestReport
      - uses: codecov/codecov-action@v4
        with:
          files: app/build/reports/jacoco/jacocoTestReport.xml
          token: ${{ secrets.CODECOV_TOKEN }}

  # ── 多风味构建验证 ──
  build-matrix:
    needs: lint
    runs-on: ubuntu-latest
    strategy:
      matrix:
        flavor: [dev, staging, prod]
        build-type: [debug, release]
        exclude:
          # 排除无意义的组合
          - flavor: dev
            build-type: release
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17' }
      - uses: gradle/actions/setup-gradle@v3
      - name: Build ${{ matrix.flavor }}${{ matrix.build-type^ }}
        run: ./gradlew assemble${{ matrix.flavor^ }}${{ matrix.build-type^ }}

  # ── UI 测试（可选，手动触发或夜间）──
  instrumented-test:
    if: ${{ github.event.inputs.run_instrumented == 'true' || github.event_name == 'schedule' }}
    needs: build-matrix
    runs-on: macos-latest
    strategy:
      matrix:
        api-level: [27, 30, 34]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17' }
      - uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: ${{ matrix.api-level }}
          target: google_apis
          arch: x86_64
          emulator-options: -no-window -gpu swiftshader -no-audio
          disable-animations: true
          script: |
            adb wait-for-device
            ./gradlew connectedAndroidTest \
              -Pandroid.testInstrumentationRunnerArguments.package=com.example

  # ── 发布到内部分发 ──
  internal-distribution:
    needs: [build-matrix, unit-test-matrix]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17' }
      - uses: gradle/actions/setup-gradle@v3

      - name: Build staging release APK
        run: ./gradlew assembleStagingRelease

      - name: Upload to Firebase App Distribution
        uses: wzieba/Firebase-Distribution-Github-Action@v1
        with:
          appId: ${{ secrets.FIREBASE_APP_ID }}
          serviceCredentialsFileContent: ${{ secrets.FIREBASE_CREDENTIALS }}
          groups: "qa-team, dev-team"
          file: app/build/outputs/apk/staging/release/app-staging-release.apk
          releaseNotes: |
            📦 Build: ${{ github.run_number }}
            🌿 分支: ${{ github.ref_name }}
            🔖 提交: ${{ github.sha | slice 0 7 }}
```

---

## 7. 自动化测试

### 7.1 测试金字塔与工具选型

```
        ╱    UI Tests (10%)     ╲
       ╱   Compose/Espresso      ╲
      ╱   在模拟器/真机上运行      ╲
     ╱───────────────────────────╲
    ╱   Integration Tests (20%)   ╲
   ╱   跨模块集成 / Repository      ╲
  ╱   使用 Hilt Mock / Fake DI      ╲
 ╱─────────────────────────────────╲
╱      Unit Tests (70%)             ╲
╲    JUnit5 + MockK + Turbine       ╱
 ╲   快速执行 / CI 高频反馈          ╱
  ╲────────────────────────────────╱
```

### 7.2 Gradle 测试配置

```kotlin
// app/build.gradle.kts (测试相关配置)
android {
    testOptions {
        unitTests {
            isIncludeAndroidResources = true  // 使用 Robolectric
            isReturnDefaultValues = true
            all { test ->
                test.systemProperty("robolectric.logging", "stdout")
                // 失败即停止（CI 中节约时间）
                if (System.getenv("CI") == "true") {
                    test.ignoreFailures = false
                }
            }
        }
    }
}

dependencies {
    // ── 单元测试 ──
    testImplementation("junit:junit:4.13.2")
    testImplementation("io.mockk:mockk:1.13.12")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
    testImplementation("app.cash.turbine:turbine:1.1.0")
    testImplementation("com.google.truth:truth:1.4.4")

    // ── 仪器化测试 ──
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4:1.7.0")
    androidTestImplementation("com.google.truth:truth:1.4.4")
    // Hilt 测试
    androidTestImplementation("com.google.dagger:hilt-android-testing:2.52")
    kaptAndroidTest("com.google.dagger:hilt-android-compiler:2.52")
}
```

### 7.3 JaCoCo 覆盖率配置

```kotlin
// 覆盖率门槛：低于 70% CI 失败
tasks.withType<Test> {
    configure<JacocoTaskExtension> {
        isIncludeNoLocationClasses = true
        excludes = listOf("jdk.internal.*")
    }
}

tasks.jacocoTestCoverageVerification {
    violationRules {
        rule {
            limit {
                counter = "LINE"
                value = "COVEREDRATIO"
                minimum = BigDecimal(0.70)
            }
        }
    }
}
```

---

## 8. 依赖管理自动化

### 8.1 Dependabot 配置

```yaml
# .github/dependabot.yml
version: 2
updates:
  # Gradle 依赖
  - package-ecosystem: "gradle"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
      timezone: "Asia/Shanghai"
    labels:
      - "dependencies"
      - "auto-merge"
    reviewers:
      - "team-infra"
    open-pull-requests-limit: 10

  # GitHub Actions 版本
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "monthly"
    labels:
      - "dependencies"
      - "ci"
    reviewers:
      - "team-infra"
```

### 8.2 依赖自动合并（补丁版本）

```yaml
# .github/workflows/auto-merge-deps.yml
name: Auto Merge Dependencies

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  auto-merge:
    # 只对 Dependabot 的小版本更新自动合并
    if: |
      github.actor == 'dependabot[bot]' &&
      (contains(github.event.pull_request.labels.*.name, 'patch') ||
       contains(github.event.pull_request.labels.*.name, 'minor'))
    runs-on: ubuntu-latest
    steps:
      - name: Enable auto-merge
        run: |
          gh pr merge ${{ github.event.pull_request.number }} \
            --auto --squash --delete-branch
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## 9. 代码质量自动化

### 9.1 Git Hook（lefthook 管理）

```yaml
# lefthook.yml
pre-commit:
  parallel: true
  commands:
    ktlint:
      glob: "*.kt"
      run: ./gradlew ktlintFormat {staged_files} && git add {staged_files}
    spotless:
      glob: "*.{kt, kts, xml}"
      run: ./gradlew spotlessApply && git add {staged_files}
    detekt:
      run: ./gradlew detekt --continue

commit-msg:
  commands:
    commitlint:
      run: |
        # 强制 Conventional Commits 格式
        PATTERN='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?: .{1,100}'
        if ! echo "$(head -1 .git/COMMIT_EDITMSG)" | grep -qE "$PATTERN"; then
          echo "❌ 提交信息不符合 Conventional Commits 规范"
          echo "格式: <type>: <description>"
          echo "示例: feat: add login screen"
          echo "      fix: resolve crash on Android 14"
          echo "      ci: add instrumented tests to pipeline"
          exit 1
        fi

pre-push:
  commands:
    ci-local:
      run: ./scripts/ci-local.sh
```

### 9.2 Detekt 配置（关键规则）

```yaml
# detekt-config.yml — 只列出关键配置
complexity:
  TooManyFunctions:
    active: true
    thresholdInFiles: 20
    thresholdInClasses: 15
  LongMethod:
    active: true
    threshold: 80
  LongParameterList:
    active: true
    threshold: 6

style:
  MagicNumber:
    active: true
    ignoreNumbers: ['-1', '0', '1', '2']
  UnusedPrivateMember:
    active: true
  WildcardImport:
    active: false   # Android 项目中常用

naming:
  FunctionNaming:
    active: true
    ignoreAnnotated: ['Composable']  # Compose 函数不限制
```

---

## 10. 构建与签名

### 10.1 Gradle 优化参数

```properties
# gradle.properties — CI 环境优化
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.configuration-cache=true
org.gradle.daemon=false          # CI 中不需要 daemon
org.gradle.jvmargs=-Xmx4g -XX:+UseParallelGC -Dkotlin.daemon.jvm.options=-Xmx2g
kotlin.incremental=true
android.nonTransitiveRClass=true
android.enableJetifier=false     # 如果所有依赖都迁移到了 AndroidX
```

### 10.2 安全签名（不硬编码密钥）

```kotlin
// app/build.gradle.kts — 签名配置
android {
    signingConfigs {
        create("release") {
            // 从 CI Secrets 或环境变量读取，绝不硬编码
            storeFile = project.findProperty("RELEASE_KEYSTORE_PATH")
                ?.let { file(it) }
                ?: file(System.getenv("HOME") + "/.android/debug.keystore")
            storePassword = (findProperty("RELEASE_KEYSTORE_PASSWORD")
                ?: System.getenv("KEYSTORE_PASSWORD")) as? String ?: "android"
            keyAlias = (findProperty("RELEASE_KEY_ALIAS")
                ?: System.getenv("KEY_ALIAS")) as? String ?: "androiddebugkey"
            keyPassword = (findProperty("RELEASE_KEY_PASSWORD")
                ?: System.getenv("KEY_PASSWORD")) as? String ?: "android"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}
```

### 10.3 CI 中解密签名文件

```yaml
# 在 workflow 中解密签名文件
- name: Decrypt keystore
  env:
    KEYSTORE_BASE64: ${{ secrets.KEYSTORE_BASE64 }}
    KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
  run: |
    echo "$KEYSTORE_BASE64" | base64 -d > app/release.keystore

- name: Build signed release
  run: |
    ./gradlew assembleStagingRelease \
      -PRELEASE_KEYSTORE_PATH=app/release.keystore \
      -PRELEASE_KEYSTORE_PASSWORD="$KEYSTORE_PASSWORD" \
      -PRELEASE_KEY_ALIAS="$KEY_ALIAS" \
      -PRELEASE_KEY_PASSWORD="$KEY_PASSWORD"
```

### 10.4 版本号自动化

```kotlin
// build.gradle.kts (root) — 基于 Git 提交数自动计算版本
val gitCommitCount: Int by lazy {
    val process = ProcessBuilder("git", "rev-list", "--count", "HEAD")
        .directory(rootProject.projectDir)
        .start()
    process.inputStream.bufferedReader().use { it.readText().trim().toIntOrNull() ?: 1 }
}

val currentBranch: String by lazy {
    val process = ProcessBuilder("git", "rev-parse", "--abbrev-ref", "HEAD")
        .directory(rootProject.projectDir)
        .start()
    process.inputStream.bufferedReader().use { it.readText().trim() }
}

android {
    defaultConfig {
        versionCode = (System.getenv("GITHUB_RUN_NUMBER")?.toIntOrNull()
            ?: gitCommitCount)
        versionName = "${major}.${minor}.${versionCode}"
        if (currentBranch != "main" && currentBranch != "master") {
            versionNameSuffix = "-${currentBranch.replace("/", "-")}"
        }
    }
}
```

---

## 11. 内部分发（Firebase）

### 11.1 Firebase App Distribution 流水线

```yaml
# .github/workflows/deploy-internal.yml
name: Deploy Internal

on:
  push:
    branches: [develop]
  workflow_dispatch:
    inputs:
      groups:
        description: '发送给哪些测试组（逗号分隔）'
        default: 'qa-team,dev-team'
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # 需要完整 git 历史做版本号

      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - uses: gradle/actions/setup-gradle@v3

      # 解密签名文件
      - name: Decrypt keystore
        env:
          KEYSTORE_BASE64: ${{ secrets.KEYSTORE_BASE64 }}
        run: echo "$KEYSTORE_BASE64" | base64 -d > app/release.keystore

      # 生成 Release Notes
      - name: Generate release notes
        id: notes
        run: |
          LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
          if [ -n "$LAST_TAG" ]; then
            CHANGES=$(git log ${LAST_TAG}..HEAD --pretty=format:"- %s" --no-merges)
          else
            CHANGES=$(git log --since="7 days ago" --pretty=format:"- %s" --no-merges)
          fi
          {
            echo "📦 Build: ${{ github.run_number }}"
            echo "🌿 分支: ${{ github.ref_name }}"
            echo "🔖 提交: $(git rev-parse --short HEAD)"
            echo ""
            echo "📝 变更:"
            echo "$CHANGES"
          } > release_notes.txt
          cat release_notes.txt

      # 构建
      - name: Build staging release
        env:
          KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
        run: |
          ./gradlew assembleStagingRelease \
            -PRELEASE_KEYSTORE_PATH=app/release.keystore \
            -PRELEASE_KEYSTORE_PASSWORD="$KEYSTORE_PASSWORD" \
            -PRELEASE_KEY_ALIAS="$KEY_ALIAS" \
            -PRELEASE_KEY_PASSWORD="$KEY_PASSWORD"

      # 上传 Firebase
      - name: Upload to Firebase
        uses: wzieba/Firebase-Distribution-Github-Action@v1
        with:
          appId: ${{ secrets.FIREBASE_APP_ID }}
          serviceCredentialsFileContent: ${{ secrets.FIREBASE_CREDENTIALS }}
          groups: ${{ github.event.inputs.groups || 'qa-team,dev-team' }}
          file: app/build/outputs/apk/staging/release/app-staging-release.apk
          releaseNotesFile: release_notes.txt

      # 通知 Slack
      - name: Notify Slack
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "📱 新测试版本已就绪\n版本号: ${{ github.run_number }}\n分支: ${{ github.ref_name }}\nFirebase 组: qa-team, dev-team"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

---

## 12. 应用商店上架（Play Store）

### 12.1 fastlane 配置

```ruby
# fastlane/Fastfile
default_platform(:android)
platform :android do

  # ── 内部测试轨道 ──
  lane :internal do
    gradle(task: "bundleRelease")
    upload_to_play_store(
      track: 'internal',
      release_status: 'completed',
      metadata_path: "./fastlane/metadata/android"
    )
    slack(message: "🔵 内部测试版已上线 Play Store (Internal Track)")
  end

  # ── Alpha（封闭测试）──
  lane :alpha do
    gradle(task: "bundleRelease")
    upload_to_play_store(
      track: 'alpha',
      release_status: 'completed'
    )
    slack(message: "🟢 Alpha 版本已上线")
  end

  # ── Beta（公开测试）──
  lane :beta do
    gradle(task: "bundleRelease")
    upload_to_play_store(
      track: 'beta',
      release_status: 'completed'
    )
    slack(message: "🟡 Beta 版本已上线 Play Store")
  end

  # ── 渐进式生产发布（核心自动化）──
  lane :production_staged do |options|
    rollout_percentage = options[:percentage] || 10

    gradle(task: "bundleRelease")

    upload_to_play_store(
      track: 'production',
      release_status: 'inProgress',
      rollout: "#{rollout_percentage}%"
    )

    UI.message "📊 #{rollout_percentage}% 发布已推送，开始监控..."
  end

  # ── 全量发布 ──
  lane :production_full do
    upload_to_play_store(
      track: 'production',
      release_status: 'completed'
    )
    slack(message: "🚀 生产版本已全量发布！")
  end

  # ── 紧急暂停发布 ──
  lane :halt_rollout do
    upload_to_play_store(
      track: 'production',
      release_status: 'halted'
    )
    slack(message: "🛑 生产发布已紧急暂停！请立即排查问题。")
  end
end
```

```ruby
# fastlane/Appfile
json_key_file(ENV["PLAY_STORE_JSON_KEY_FILE"] || "play-store-key.json")
package_name("com.example.yourapp")
```

### 12.2 CI 触发上架

```yaml
# .github/workflows/release-store.yml
name: Release to Play Store

on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'        # v1.2.3 标签触发
  workflow_dispatch:
    inputs:
      track:
        description: '发布轨道'
        required: true
        type: choice
        options:
          - internal
          - alpha
          - beta
          - production_staged
          - production_full
          - halt_rollout
      rollout_percentage:
        description: '渐进发布百分比（仅 production_staged）'
        required: false
        default: '10'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true

      - name: Decrypt keystore
        env:
          KEYSTORE_BASE64: ${{ secrets.KEYSTORE_BASE64 }}
        run: echo "$KEYSTORE_BASE64" | base64 -d > app/release.keystore

      # Google Play 服务账号密钥
      - name: Setup Play Store credentials
        env:
          PLAY_STORE_JSON_BASE64: ${{ secrets.PLAY_STORE_JSON_BASE64 }}
        run: echo "$PLAY_STORE_JSON_BASE64" | base64 -d > play-store-key.json

      - name: Run fastlane
        env:
          KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
          PLAY_STORE_JSON_KEY_FILE: play-store-key.json
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
        run: |
          TRACK="${{ github.event.inputs.track || 'internal' }}"
          PERCENTAGE="${{ github.event.inputs.rollout_percentage || '10' }}"

          if [ "$TRACK" = "production_staged" ]; then
            bundle exec fastlane production_staged percentage:$PERCENTAGE
          else
            bundle exec fastlane $TRACK
          fi
```

---

## 13. 渐进式发布与自动回滚

> 这是生产发布最关键的自动化：先推 10% 用户 → 监控 → OK 就扩大 → 异常就自动暂停。

```ruby
# fastlane/actions/auto_rollout.rb（fastlane 自定义 Action）
module Fastlane
  module Actions
    class AutoRolloutAction < Action
      STAGES = [
        { percentage: 10,  wait_minutes: 30 },
        { percentage: 25,  wait_minutes: 60 },
        { percentage: 50,  wait_minutes: 120 },
        { percentage: 100, wait_minutes: 0 },
      ].freeze

      CRASH_FREE_THRESHOLD = 99.5  # 崩溃率阈值

      def self.run(params)
        STAGES.each_with_index do |stage, index|
          UI.header "📊 阶段 #{index + 1}/#{STAGES.count}: 扩大到 #{stage[:percentage]}%"

          # 1. 扩大到目标百分比
          other_action.upload_to_play_store(
            track: 'production',
            release_status: 'inProgress',
            rollout: "#{stage[:percentage]}%"
          )

          # 2. 等待数据积累
          if stage[:wait_minutes] > 0
            UI.message "⏳ 等待 #{stage[:wait_minutes]} 分钟以积累数据..."
            sleep(stage[:wait_minutes] * 60)
          end

          # 3. 检查崩溃率
          crash_free = fetch_crash_free_rate

          if crash_free < CRASH_FREE_THRESHOLD
            UI.error "🚨 崩溃率异常！Crash-free: #{crash_free}%（阈值: #{CRASH_FREE_THRESHOLD}%）"
            UI.error "紧急暂停发布..."

            other_action.upload_to_play_store(
              track: 'production',
              release_status: 'halted'
            )

            other_action.slack(
              message: "🚨 生产发布已自动暂停！\n当前: #{stage[:percentage]}% 用户\nCrash-free: #{crash_free}%\n阈值: #{CRASH_FREE_THRESHOLD}%\n请立即排查！"
            )

            raise "发布因崩溃率超标而自动中断"
          end

          UI.success "✅ Crash-free: #{crash_free}% — 继续推进"
        end

        UI.success "🎉 全量发布完成！"
      end

      # 通过 Firebase Crashlytics API 获取崩溃率
      def self.fetch_crash_free_rate
        # 调用 Firebase Crashlytics API
        # curl -X POST "https://firebase.googleapis.com/v1beta1/projects/<project>/apps/<appId>/sessions:lookup"
        # 这里简化为伪代码
        # 实际项目中用 Firebase Admin SDK 或 REST API
        begin
          # TODO: 替换为实际的 Crashlytics API 调用
          return 99.8  # 示例
        rescue => e
          UI.important "⚠️ 无法获取崩溃数据: #{e.message}，假定正常"
          return 100.0
        end
      end
    end
  end
end
```

---

## 14. 监控告警闭环

### 14.1 崩溃自动创建 Issue

```yaml
# .github/workflows/auto-issue-from-crash.yml
name: Auto Issue from Crash

on:
  schedule:
    - cron: '0 */6 * * *'   # 每 6 小时检查一次
  workflow_dispatch:

jobs:
  check-crashes:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Fetch new crashes from Firebase
        id: crashes
        run: |
          # 调用 Firebase Crashlytics API（需要服务账号）
          # 这里用脚本文件处理
          ./scripts/fetch-crashes.sh > crash_report.json

      - name: Create issues for new crashes
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          # 解析 crash_report.json，为每个新崩溃创建 Issue
          cat crash_report.json | jq -c '.[]' | while read crash; do
            TITLE=$(echo "$crash" | jq -r '.title')
            COUNT=$(echo "$crash" | jq -r '.count')
            STACK=$(echo "$crash" | jq -r '.stacktrace')

            # 检查是否已存在同名 Issue（去重）
            EXISTS=$(gh issue list -S "$TITLE in:title" --limit 1 --json number -q '.[0].number')

            if [ -z "$EXISTS" ]; then
              gh issue create \
                --title "🔥 Crash: $TITLE" \
                --label "bug,p0,crash" \
                --body "## 崩溃报告

                **影响次数:** $COUNT

                **堆栈跟踪:**
                \`\`\`
                $STACK
                \`\`\`

                **Source:** Firebase Crashlytics
                **创建方式:** 自动 (${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID})"
            fi
          done
```

### 14.2 夜间全面构建（Nighly Build）

```yaml
# .github/workflows/nightly.yml
name: Nightly Full Build

on:
  schedule:
    - cron: '0 2 * * *'      # 每天凌晨 2 点
  workflow_dispatch:

jobs:
  full-build:
    runs-on: macos-latest     # 使用 macOS 跑完整模拟器测试
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 34
          target: google_apis
          arch: x86_64
          disable-animations: true
          emulator-build: 11237101
          script: |
            # 跑所有测试
            ./gradlew clean
            ./gradlew ktlintCheck detekt lint
            ./gradlew testDebugUnitTest
            ./gradlew connectedAndroidTest
            ./gradlew jacocoTestReport

      # 生成性能报告
      - name: Performance report
        run: |
          ./gradlew :benchmark:connectedCheck
          ./gradlew :benchmark:mergeReports

      - name: Notify if failed
        if: failure()
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "⚠️ 夜间构建失败！\nActions: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

---

## 15. 本地开发环境一键初始化

### 15.1 新成员 setup 脚本

```bash
#!/bin/bash
# scripts/setup.sh — 新成员入职/新机器一键就绪
set -e

echo "🚀 Setting up Android development environment..."

# ── 1. 检查必要工具 ──
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ $1 未安装，请先安装: $2"
        exit 1
    fi
}

check_command "java"   "brew install openjdk@17 或从 https://adoptium.net 下载"
check_command "git"    "brew install git 或从 https://git-scm.com 下载"

# ── 2. 设置 JDK 17 ──
JAVA_VER=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
if [ "$JAVA_VER" != "17" ]; then
    echo "⚠️ 需要 JDK 17，当前为 JDK $JAVA_VER"
    echo "请设置 JAVA_HOME 指向 JDK 17"
fi

# ── 3. 安装 Git Hooks ──
echo "📎 安装 Git Hooks..."
./scripts/install-git-hooks.sh

# ── 4. Android SDK 设置 ──
if [ -z "$ANDROID_HOME" ]; then
    echo "⚠️ ANDROID_HOME 未设置"
    echo "请安装 Android Studio 并设置 ANDROID_HOME 环境变量"
fi

# ── 5. Gradle 依赖 ──
echo "📦 下载 Gradle 依赖（首次较慢）..."
./gradlew dependencies --refresh-dependencies --no-daemon -q

# ── 6. 验证 ──
echo "🧪 运行快速验证..."
./gradlew ktlintCheck --no-daemon -q
./gradlew testDebugUnitTest --no-daemon -q

echo ""
echo "✅ 环境初始化完成！可以开始开发了。"
```

### 15.2 本地 CI 模拟脚本

```bash
#!/bin/bash
# scripts/ci-local.sh — 推送前在本地模拟 CI 完整流程
set -e

echo "🧪 本地 CI 检查..."
echo "=============================="

echo "→ Stage 1: Code formatting..."
./gradlew ktlintCheck detekt spotlessCheck --continue
echo "✅ Lint passed"

echo ""
echo "→ Stage 2: Unit tests..."
./gradlew testDebugUnitTest
echo "✅ Tests passed"

echo ""
echo "→ Stage 3: Build check..."
./gradlew assembleDebug
echo "✅ Build passed"

echo ""
echo "→ Stage 4: Coverage check..."
./gradlew jacocoTestCoverageVerification
echo "✅ Coverage passed"

echo ""
echo "=============================="
echo "🎉 本地 CI 全部通过，可以推送！"
```

---

## 16. Secrets 配置清单

在 GitHub 仓库 **Settings → Secrets and variables → Actions** 中添加：

| Secret 名称 | 说明 | 获取方式 |
|-------------|------|---------|
| `KEYSTORE_BASE64` | 签名文件 Base64 编码 | `base64 -i release.keystore \| pbcopy` |
| `KEYSTORE_PASSWORD` | 签名密钥库密码 | 创建签名文件时设置 |
| `KEY_ALIAS` | 签名别名 | 创建签名文件时设置 |
| `KEY_PASSWORD` | 签名密钥密码 | 创建签名文件时设置 |
| `FIREBASE_APP_ID` | Firebase 应用 ID | Firebase Console → 项目设置 |
| `FIREBASE_CREDENTIALS` | Firebase 服务账号 JSON | Firebase Console → 服务账号 → 生成密钥 |
| `PLAY_STORE_JSON_BASE64` | Google Play 服务账号 JSON 的 Base64 | Google Cloud Console → 服务账号 → 生成密钥 |
| `CODECOV_TOKEN` | Codecov 上传 token | codecov.io 项目设置 |
| `SLACK_WEBHOOK_URL` | Slack 通知 Webhook | Slack App → Incoming Webhooks |
| `GH_TOKEN` | GitHub Token (自动提供) | Actions 自动注入，无需手动添加 |

---

## 17. 跨项目复用

### 方案 1：Template Repository（推荐新项目）

```
1. 当前项目全部配置好
2. Settings → Template repository ✅
3. 新项目创建时选择从此模板创建
4. 获得独立拷贝，可自行修改
```

### 方案 2：可复用 Workflow（推荐多项目统一）

```yaml
# 各项目只需写这几行，完整流程在共享仓库定义
# .github/workflows/shared-ci.yml
name: Android CI

jobs:
  call-pr-check:
    uses: your-org/android-shared-workflows/.github/workflows/pr-check.yml@main
    secrets: inherit

  call-ci:
    uses: your-org/android-shared-workflows/.github/workflows/main-ci.yml@main
    secrets: inherit

  call-deploy:
    uses: your-org/android-shared-workflows/.github/workflows/deploy-internal.yml@main
    secrets: inherit
```

### 方案 3：组织级 `.github` 仓库

```
your-org/.github/
├── ISSUE_TEMPLATE/         ← 所有仓库共享的 Issue 模板
├── workflow-templates/     ← 成员创建新 workflow 时可选的模板
└── CODEOWNERS              ← 每个仓库仍需单独配置
```

---

## 18. 实施路线图

### 第一阶段：基础（第 1-2 周）— 立即见效

```
□ 创建 GitHub 仓库，设置分支保护
□ 配置 Issue 模板和 PR 模板
□ 配置 CODEOWNERS
□ 配置 Gradle（CI 优化参数）
□ 搭建 PR Check workflow（Lint + 单元测试 + 构建验证）
□ 配置 Detekt + ktlint + Spotless
□ 本地 Git Hook 安装脚本
```

### 第二阶段：分发（第 3-4 周）— 打通测试链路

```
□ Firebase 项目创建和配置
□ 生成上传用签名文件（独立于发布签名）
□ Deploy Internal workflow（自动上传 Firebase）
□ Slack 通知集成
□ 模拟器 UI 测试（CI 中运行）
□ 测试报告自动发布
```

### 第三阶段：上架（第 5-6 周）— 打通发布链路

```
□ Google Play Console 配置
□ 创建 Google Play 服务账号
□ fastlane 配置（Appfile + Fastfile）
□ Release Store workflow（手动触发 → Play Store）
□ Play Store 元数据自动化
□ Release Notes 自动生成
```

### 第四阶段：高级（第 7-8 周）— 生产就绪

```
□ 渐进式发布配置
□ 崩溃率自动监控 + 自动回滚
□ 夜间全面构建
□ 崩溃自动提 Issue
□ Dependabot 配置 + 自动合并
□ 可复用 Workflow 抽离（如果有多项目）
□ 性能基准测试集成
```

---

## 附录 A：快速命令参考

```bash
# 生成签名文件
keytool -genkey -v -keystore release.keystore \
  -alias upload -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "YOUR_STORE_PASS" -keypass "YOUR_KEY_PASS"

# 将签名文件编码为 Base64（用于 GitHub Secret）
openssl base64 -in release.keystore | tr -d '\n' | pbcopy

# 安装本地 Git Hook
./scripts/install-git-hooks.sh

# 本地运行 CI 检查
./scripts/ci-local.sh

# 手动触发工作流
gh workflow run "Deploy Internal" -f groups="qa-team"

# 查看工作流执行状态
gh run list --workflow="PR Check" --limit=5

# fastlane 本地测试
bundle exec fastlane internal
```

## 附录 B：常用 GitHub Actions 清单

| Action | 用途 | 链接 |
|--------|------|------|
| `actions/setup-java` | 设置 JDK | github.com/actions/setup-java |
| `gradle/actions/setup-gradle` | Gradle 构建优化 | github.com/gradle/actions |
| `reactivecircus/android-emulator-runner` | Android 模拟器 | github.com/ReactiveCircus/android-emulator-runner |
| `wzieba/Firebase-Distribution-Github-Action` | Firebase 分发 | github.com/wzieba/Firebase-Distribution-Github-Action |
| `r0adkll/upload-google-play` | Play Store 上传 | github.com/r0adkll/upload-google-play |
| `dorny/test-reporter` | 测试报告 | github.com/dorny/test-reporter |
| `amannn/action-semantic-pull-request` | PR 标题规范 | github.com/amannn/action-semantic-pull-request |
| `slackapi/slack-github-action` | Slack 通知 | github.com/slackapi/slack-github-action |
| `codecov/codecov-action` | 覆盖率上报 | github.com/codecov/codecov-action |
| `codelytv/pr-size-labeler` | PR 大小标签 | github.com/CodelyTV/pr-size-labeler |
