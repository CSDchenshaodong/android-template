# Changelog

## v1 (2026-06-25) — 初始版本

### 可复用 Workflow

- `pr-check.yml` — PR 门禁检查（PR 标题规范、Lint、单元测试、构建验证、依赖扫描、自动评论）
- `ci.yml` — 主 CI 流水线（多 JDK 矩阵、多风味构建、UI 测试、内部分发）
- `deploy-internal.yml` — Firebase App Distribution 内部分发
- `release-store.yml` — Google Play Store 上架（支持 internal/alpha/beta/渐进发布/紧急暂停）
- `nightly.yml` — 夜间全面构建

### 模板文件

- Issue 模板（Feature Request / Bug Report）
- PR 模板
- CODEOWNERS
- Dependabot 配置
- lefthook Git Hook 配置
- Detekt 规则配置
- fastlane Fastfile + Appfile
- Gradle CI 优化参数
- 本地开发脚本（setup / ci-local / install-git-hooks）
- 消费项目 Workflow 包装示例
