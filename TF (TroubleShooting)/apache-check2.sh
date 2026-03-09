#!/bin/bash

echo "===== Apache DocumentRoot Detection ====="

# Apache 설치 확인
if ! command -v apache2 >/dev/null 2>&1 && ! command -v httpd >/dev/null 2>&1; then
    echo "[FAIL] Apache not installed"
    exit 1
fi

echo "[OK] Apache installed"

echo ""
echo "[INFO] Detecting Apache config..."

CONFIG_ROOT=$(apachectl -V 2>/dev/null | grep SERVER_CONFIG_FILE | awk -F\" '{print $2}')

echo "Config file: $CONFIG_ROOT"

echo ""
echo "[INFO] Searching DocumentRoot..."

DOCROOT=$(apachectl -S 2>/dev/null | grep -i documentroot)

if [ -z "$DOCROOT" ]; then
    DOCROOT=$(grep -R "DocumentRoot" /etc/apache2 2>/dev/null)
fi

echo "$DOCROOT"