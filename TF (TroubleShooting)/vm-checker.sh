#!/bin/bash

echo "===== Apache Check ====="

# Apache 설치 확인
if ! command -v apache2 >/dev/null 2>&1; then
    echo "Apache is not installed."
    exit 1
fi

echo "Apache installed."

# DocumentRoot 확인
DOCROOT=$(grep -R "DocumentRoot" /etc/apache2/sites-enabled 2>/dev/null | awk '{print $2}')

echo "DocumentRoot:"
echo "$DOCROOT"

# Directory 확인
for dir in $DOCROOT
do
    if [ -d "$dir" ]; then
        echo "[OK] $dir exists"
    else
        echo "[WARN] $dir not found"
    fi
done