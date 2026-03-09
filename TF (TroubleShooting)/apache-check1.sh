#!/bin/bash

echo "===== Apache Troubleshooting Check ====="

# Apache 설치 확인
if ! command -v apache2 >/dev/null 2>&1; then
    echo "[FAIL] Apache not installed"
    exit 1
else
    echo "[OK] Apache installed"
fi

# Apache 서비스 상태
if systemctl is-active --quiet apache2; then
    echo "[OK] Apache running"
else
    echo "[FAIL] Apache not running"
fi

# Port check
if ss -ntlp | grep -q ":80"; then
    echo "[OK] Port 80 LISTEN"
else
    echo "[FAIL] Port 80 not open"
fi

# DocumentRoot 확인
DOCROOT=$(grep -R "DocumentRoot" /etc/apache2/sites-enabled 2>/dev/null | awk '{print $2}')

echo "[INFO] DocumentRoot: $DOCROOT"

# Directory 확인
for dir in $DOCROOT
do
    if [ -d "$dir" ]; then
        echo "[OK] $dir exists"
    else
        echo "[WARN] $dir not found"
    fi
done