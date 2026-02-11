#!/bin/bash

# Git 安全检查脚本
# 在提交前运行此脚本，确保没有敏感文件被误提交

echo "🔍 正在检查 Git 状态..."
echo ""

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 危险文件模式列表
DANGEROUS_PATTERNS=(
  "*.keystore"
  "*.jks"
  "key.properties"
  "local.properties"
  "*.apk"
  "*.aab"
  "upload_to_azure.sh"
  ".env"
  "azure-config.sh"
)

# 检查即将提交的文件
STAGED_FILES=$(git diff --cached --name-only)
UNTRACKED_FILES=$(git ls-files --others --exclude-standard)

FOUND_DANGEROUS=0

echo "📋 检查暂存文件（即将提交）..."
for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$STAGED_FILES" | grep -q "$pattern"; then
    echo -e "${RED}❌ 危险: 发现暂存的敏感文件: $pattern${NC}"
    echo "$STAGED_FILES" | grep "$pattern"
    FOUND_DANGEROUS=1
  fi
done

echo ""
echo "📋 检查未跟踪文件..."
for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$UNTRACKED_FILES" | grep -q "$pattern"; then
    echo -e "${YELLOW}⚠️  警告: 发现未跟踪的敏感文件（应添加到 .gitignore）: $pattern${NC}"
    echo "$UNTRACKED_FILES" | grep "$pattern"
  fi
done

echo ""
echo "🔍 检查脚本中的硬编码密钥..."
if grep -rn "password\|secret\|api[_-]key" build*.sh update*.sh 2>/dev/null | grep -v "AZURE_ACCOUNT\|auth-mode"; then
  echo -e "${RED}❌ 发现可能的硬编码密钥${NC}"
  FOUND_DANGEROUS=1
else
  echo -e "${GREEN}✅ 未发现硬编码密钥${NC}"
fi

echo ""
echo "🔍 检查已跟踪的敏感文件..."
TRACKED_SENSITIVE=$(git ls-files | grep -E "(keystore|\.jks|key\.properties|local\.properties|upload_to_azure)")
if [ -n "$TRACKED_SENSITIVE" ]; then
  echo -e "${RED}❌ 警告: 以下敏感文件已被 Git 跟踪（需要从历史记录中删除）:${NC}"
  echo "$TRACKED_SENSITIVE"
  FOUND_DANGEROUS=1
else
  echo -e "${GREEN}✅ 没有敏感文件被跟踪${NC}"
fi

echo ""
echo "=================================="
if [ $FOUND_DANGEROUS -eq 0 ]; then
  echo -e "${GREEN}✅ 安全检查通过！可以安全提交。${NC}"
  exit 0
else
  echo -e "${RED}❌ 发现安全问题！请修复后再提交。${NC}"
  echo ""
  echo "建议操作："
  echo "1. 取消暂存敏感文件: git reset HEAD <file>"
  echo "2. 添加到 .gitignore: echo '<pattern>' >> .gitignore"
  echo "3. 重新运行此检查: ./git-safety-check.sh"
  exit 1
fi
