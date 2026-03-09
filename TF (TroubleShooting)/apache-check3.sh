# Date: 03-09-2026 
# apachectl -S에서 Main DocumentRoot 파싱하는 스크립트 작성

#!/bin/bash

echo "===== Apache DocumentRoot Detection ====="

# Apache 설치 확인
if ! command -v apache2 >/dev/null 2>&1; then
    echo "[FAIL] Apache not installed"
    exit 1
fi

echo "[OK] Apache installed"

# Apache 실행 여부 확인
if systemctl is-active --quiet apache2; then
    echo "[OK] Apache service running"
else
    echo "[WARN] Apache service not running"
fi

echo ""

# Apache runtime 기준 DocumentRoot 탐지
DOCROOT=$(apache2ctl -S 2>/dev/null | grep "Main DocumentRoot" | awk -F\" '{print $2}')

if [ -z "$DOCROOT" ]; then
    echo "[WARN] Could not detect DocumentRoot from runtime config"
else
    echo "[OK] DocumentRoot detected: $DOCROOT"
fi

# Directory 존재 여부 확인
if [ -d "$DOCROOT" ]; then
    echo "[OK] DocumentRoot directory exists"
else
    echo "[FAIL] DocumentRoot directory not found"
fi

