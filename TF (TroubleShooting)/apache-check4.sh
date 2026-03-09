## Date: 03-09-2026

#!/bin/bash

echo "========== Apache Troubleshooting Checker =========="

# 1. Apache 설치 확인
if ! command -v apache2 >/dev/null 2>&1; then
    echo "[FAIL] Apache is not installed"
    exit 1
fi

echo "[OK] Apache installed"

# 2. Apache 서비스 상태 확인
if systemctl is-active --quiet apache2; then
    echo "[OK] Apache service running"
else
    echo "[WARN] Apache service not running"
fi

echo ""

# 3. Apache 설정 파일 위치 확인
echo "[INFO] Apache Config Root"
apache2ctl -V 2>/dev/null | grep SERVER_CONFIG_FILE

echo ""

# 4. VirtualHost 설정 확인
echo "[INFO] Active VirtualHost Config"
apache2ctl -S 2>/dev/null | grep sites-enabled

echo ""

# 5. DocumentRoot 탐지
echo "[INFO] Searching DocumentRoot..."

DOCROOTS=$(grep -R "DocumentRoot" /etc/apache2 2>/dev/null | awk '{print $2}')

if [ -z "$DOCROOTS" ]; then
    echo "[WARN] No DocumentRoot found"
else
    for dir in $DOCROOTS
    do
        echo "Detected DocumentRoot: $dir"

        if [ -d "$dir" ]; then
            echo "[OK] Directory exists"
        else
            echo "[FAIL] Directory not found"
        fi

        echo ""
    done
fi

# 6. Apache Port 확인
echo "[INFO] Apache Listening Port"
ss -ntlp | grep apache2

echo ""

echo "========== Apache Troubleshooting Checker Fin. =========="