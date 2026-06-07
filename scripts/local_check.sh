#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  FirstProAccounting — Local Pre-Push Check Script
#  يحاكي فحص GitHub Actions محلياً قبل الدفع
#  يشتغل بـ: bash scripts/local_check.sh [--quick|--full]
# ═══════════════════════════════════════════════════════════════════

set -e

# ── Setup Paths ────────────────────────────────────────────────
export PATH="/home/z/my-project/tools/flutter/bin:/home/z/my-project/tools/dart-sdk/bin:$PATH"
PROJECT_DIR="/home/z/my-project/FirstProAccounting"
cd "$PROJECT_DIR"

# ── Colors ─────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MODE="${1:---full}"
ERRORS=0
WARNINGS=0

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  FirstProAccounting — فحص محلي قبل الدفع${NC}"
echo -e "${BLUE}  الوضع: $MODE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# ── Step 1: Flutter Version ────────────────────────────────────
echo -e "${YELLOW}[1/6] فحص بيئة Flutter...${NC}"
flutter --version 2>&1 | head -3
echo ""

# ── Step 2: Dependencies ──────────────────────────────────────
echo -e "${YELLOW}[2/6] تحديث الاعتماديات...${NC}"
flutter pub get 2>&1 | tail -3
echo ""

# ── Step 3: Static Analysis ───────────────────────────────────
echo -e "${YELLOW}[3/6] تحليل الكود الثابت (dart analyze)...${NC}"
ANALYSIS_OUTPUT=$(dart analyze lib/ 2>&1)
ERROR_COUNT=$(echo "$ANALYSIS_OUTPUT" | grep -c "error -" || true)
WARNING_COUNT=$(echo "$ANALYSIS_OUTPUT" | grep -c "warning -" || true)
INFO_COUNT=$(echo "$ANALYSIS_OUTPUT" | grep -c "info -" || true)

if [ "$ERROR_COUNT" -gt 0 ]; then
    echo -e "${RED}  ❌ أخطاء: $ERROR_COUNT${NC}"
    echo "$ANALYSIS_OUTPUT" | grep "error -"
    ERRORS=$((ERRORS + ERROR_COUNT))
else
    echo -e "${GREEN}  ✅ لا أخطاء${NC}"
fi

if [ "$WARNING_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}  ⚠️ تحذيرات: $WARNING_COUNT${NC}"
    echo "$ANALYSIS_OUTPUT" | grep "warning -" | head -10
    WARNINGS=$((WARNINGS + WARNING_COUNT))
fi

echo -e "  ℹ️ معلومات: $INFO_COUNT (deprecation وغيرها)"
echo ""

# ── Step 4: Format Check ──────────────────────────────────────
echo -e "${YELLOW}[4/6] فحص التنسيق (dart format)...${NC}"
FORMAT_OUTPUT=$(dart format --output=none --set-exit-if-changed lib/ 2>&1 || true)
if [ -n "$FORMAT_OUTPUT" ]; then
    UNFORMATTED=$(echo "$FORMAT_OUTPUT" | wc -l)
    echo -e "${YELLOW}  ⚠️ $UNFORMATTED ملف يحتاج تنسيق${NC}"
    if [ "$MODE" = "--full" ]; then
        echo "$FORMAT_OUTPUT" | head -20
    fi
else
    echo -e "${GREEN}  ✅ كل الملفات منسقة${NC}"
fi
echo ""

# ── Step 5: Pub Outdated ──────────────────────────────────────
if [ "$MODE" = "--full" ]; then
    echo -e "${YELLOW}[5/6] فحص الحزم القديمة...${NC}"
    flutter pub outdated 2>&1 | head -20 || true
    echo ""
else
    echo -e "${YELLOW}[5/6] تخطي فحص الحزم (--quick)${NC}"
    echo ""
fi

# ── Step 6: Custom Anti-Pattern Checks ────────────────────────
echo -e "${YELLOW}[6/6] فحوصات مخصصة...${NC}"

SHRINKWRAP_COUNT=$(grep -r "shrinkWrap: true" lib/ --include="*.dart" | wc -l || true)
echo "  shrinkWrap: true → $SHRINKWRAP_COUNT استخدام"

SETSTATE_COUNT=$(grep -r "setState(" lib/ --include="*.dart" | wc -l || true)
echo "  setState() → $SETSTATE_COUNT استدعاء"

GOD_CLASS_LINES=$(wc -l < lib/data/datasources/database_helper.dart)
echo "  DatabaseHelper → $GOD_CLASS_LINES سطر"

echo ""

# ── Summary ────────────────────────────────────────────────────
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ملخص الفحص${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

if [ "$ERRORS" -gt 0 ]; then
    echo -e "${RED}  ❌ أخطاء: $ERRORS — لا تدفع حتى تُصلح!${NC}"
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    echo -e "${YELLOW}  ⚠️ تحذيرات: $WARNINGS — يُفضل إصلاحها قبل الدفع${NC}"
    exit 0
else
    echo -e "${GREEN}  ✅ الكود جاهز للدفع!${NC}"
    exit 0
fi
