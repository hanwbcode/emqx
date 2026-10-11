#!/usr/bin/env bash
#
# 一键同步官方 EMQX upstream/release-58 最新代码到本地及个人 GitHub 仓库 (Bash 版)
#
set -euo pipefail

echo "=========================================================="
echo "    EMQX 5.8 官方上游代码一键同步工具 (Upstream Sync)    "
echo "=========================================================="

CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "release-58" ]; then
    echo "[!] 当前分支是 [$CURRENT_BRANCH]，正在切换到 [release-58]..."
    git checkout release-58
fi

if ! git remote | grep -q "^upstream$"; then
    echo "[*] 添加官方上游远程地址 upstream..."
    git remote add upstream https://github.com/emqx/emqx.git
fi

echo "[*] 正在从官方上游 (upstream/release-58) 获取最新提交..."
git fetch upstream release-58

NEW_COMMITS=$(git log HEAD..upstream/release-58 --oneline || true)
if [ -z "$NEW_COMMITS" ]; then
    echo "[✔] 当前本地及远程仓库已经是最新！官方上游没有新的提交。"
    exit 0
fi

echo "[★] 检测到官方上游有新的更新提交："
echo "$NEW_COMMITS" | head -n 10
TOTAL_COMMITS=$(echo "$NEW_COMMITS" | wc -l)
echo "共 $TOTAL_COMMITS 个新提交。"

echo "[*] 正在合并上游更新到本地分支..."
git merge upstream/release-58 --no-edit || true

echo "[*] 维护流水线清洁（确保只保留社区版镜像构建流）..."
find .github/workflows/ -type f -name "*.yaml" ! -name "build-community-58.yaml" -exec git rm -f {} + 2>/dev/null || true

if [ -n "$(git status --porcelain .github/workflows/)" ]; then
    git add .github/workflows/
    git commit -m "chore: prune upstream QA workflows after sync" || true
fi

TRIGGER_BUILD=false
if [ "${1:-}" = "-BuildDocker" ] || [ "${1:-}" = "--build-docker" ]; then
    TRIGGER_BUILD=true
else
    read -p "是否同时触发 GitHub Actions 编译发布最新 Docker 镜像？(Y/N，默认 Y): " answer || true
    answer=${answer:-Y}
    if [ "$answer" = "Y" ] || [ "$answer" = "y" ]; then
        TRIGGER_BUILD=true
    fi
fi

if [ "$TRIGGER_BUILD" = true ]; then
    DATE_STR=$(date +'%Y%m%d')
    echo "[*] 正在提交构建触发标记 (pushdocker)..."
    git commit --allow-empty -m "pushdocker: sync upstream update ($DATE_STR)"
fi

echo "[*] 正在推送到您的远程仓库 (origin/release-58)..."
git push origin release-58

echo "=========================================================="
echo " [✔] 同步并推送成功！"
if [ "$TRIGGER_BUILD" = true ]; then
    echo " 已触发 GitHub Actions 构建任务，新镜像将推送到："
    echo "   ghcr.io/hanwbcode/emqx:5.8-latest"
    echo "   ghcr.io/hanwbcode/emqx:5.8-$(date +'%Y%m%d')"
fi
echo "=========================================================="
