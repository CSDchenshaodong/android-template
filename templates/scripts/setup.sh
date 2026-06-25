#!/bin/bash
# ──────────────────────────────────────────────────
# 新成员环境初始化脚本 — 一键就绪开发环境
# 用法: ./scripts/setup.sh
# ──────────────────────────────────────────────────
set -e

echo "🚀 初始化 Android 开发环境..."
echo "=============================="

# ── 1. 检查必要工具 ──
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ $1 未安装，请先安装: $2"
        MISSING_TOOLS=true
    else
        echo "✅ $1 已安装: $($1 --version 2>&1 | head -1)"
    fi
}

MISSING_TOOLS=false
check_command "java"   "brew install openjdk@17 或从 https://adoptium.net 下载"
check_command "git"    "brew install git 或从 https://git-scm.com 下载"

if [ "$MISSING_TOOLS" = true ]; then
    echo ""
    echo "⚠️ 缺少必要工具，请安装后重新运行此脚本"
    exit 1
fi

# ── 2. 检查 JDK 版本 ──
JAVA_VER=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
if [ "$JAVA_VER" != "17" ]; then
    echo "⚠️ 推荐 JDK 17，当前为 JDK $JAVA_VER"
    echo "   请设置 JAVA_HOME 指向 JDK 17"
fi

# ── 3. Android SDK ──
if [ -z "$ANDROID_HOME" ]; then
    echo "⚠️ ANDROID_HOME 未设置"
    echo "   请安装 Android Studio 并设置 ANDROID_HOME 环境变量"
    if [ -d "$HOME/Library/Android/sdk" ]; then
        echo "   检测到 macOS 默认路径，设置 ANDROID_HOME..."
        export ANDROID_HOME="$HOME/Library/Android/sdk"
    elif [ -d "$HOME/Android/Sdk" ]; then
        echo "   检测到 Linux/Windows 默认路径，设置 ANDROID_HOME..."
        export ANDROID_HOME="$HOME/Android/Sdk"
    fi
fi

# ── 4. 安装 Git Hooks ──
echo ""
echo "📎 安装 Git Hooks..."
if [ -f "lefthook.yml" ]; then
    ./scripts/install-git-hooks.sh
else
    echo "⏭️ 未找到 lefthook.yml，跳过 Git Hook 安装"
fi

# ── 5. 下载 Gradle 依赖 ──
echo ""
echo "📦 下载 Gradle 依赖（首次较慢，后续有缓存）..."
./gradlew dependencies --refresh-dependencies --no-daemon -q 2>/dev/null || true

# ── 6. 验证 ──
echo ""
echo "🧪 运行快速验证..."
echo "   → Lint check..."
./gradlew ktlintCheck --no-daemon -q 2>/dev/null || echo "   ⚠️ ktlint 检查有警告（可后续修复）"
echo "   → Build check..."
./gradlew assembleDebug --no-daemon -q 2>/dev/null || echo "   ⚠️ 构建未通过（请检查环境配置）"
echo "   → Unit test..."
./gradlew testDebugUnitTest --no-daemon -q 2>/dev/null || echo "   ⚠️ 测试未通过（请检查环境配置）"

echo ""
echo "=============================="
echo "✅ 环境初始化完成！可以开始开发了。"
echo ""
echo "💡 提示:"
echo "   - 推送前运行 ./scripts/ci-local.sh 验证"
echo "   - 提交信息请遵循 Conventional Commits 格式"
