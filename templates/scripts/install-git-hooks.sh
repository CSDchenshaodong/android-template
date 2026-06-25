#!/bin/bash
# ──────────────────────────────────────────────────
# Git Hooks 安装脚本 — 安装 lefthook 管理的 Git Hooks
# 用法: ./scripts/install-git-hooks.sh
# ──────────────────────────────────────────────────
set -e

echo "📎 安装 Git Hooks (lefthook)..."

# 检查 lefthook 是否安装
if ! command -v lefthook &> /dev/null; then
    echo "🔧 lefthook 未安装，正在安装..."
    if command -v brew &> /dev/null; then
        brew install lefthook
    elif command -v go &> /dev/null; then
        go install github.com/evilmartians/lefthook@latest
    else
        echo "❌ 请先安装 lefthook: https://github.com/evilmartians/lefthook#install"
        echo "   推荐: brew install lefthook"
        exit 1
    fi
fi

# 确保 lefthook.yml 存在
if [ ! -f "lefthook.yml" ]; then
    echo "⚠️ 未找到 lefthook.yml，请确认在项目根目录执行此脚本"
    exit 1
fi

# 安装 hooks
lefthook install

echo "✅ Git Hooks 安装完成"
echo "   pre-commit: ktlint + spotless + detekt"
echo "   commit-msg: Conventional Commits 格式检查"
echo "   pre-push:   本地 CI 完整检查"
lefthook list
