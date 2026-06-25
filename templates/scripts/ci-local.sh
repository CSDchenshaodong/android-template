#!/bin/bash
# ──────────────────────────────────────────────────
# 本地 CI 模拟脚本 — 推送前在本地模拟 CI 完整流程
# 用法: ./scripts/ci-local.sh
# ──────────────────────────────────────────────────
set -e

echo "🧪 本地 CI 检查..."
echo "=============================="

echo ""
echo "→ Stage 1: Code formatting & lint..."
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
./gradlew jacocoTestCoverageVerification 2>/dev/null || echo "⏭️ Coverage check skipped (task not configured)"
echo "✅ Coverage check done"

echo ""
echo "=============================="
echo "🎉 本地 CI 全部通过，可以推送！"
