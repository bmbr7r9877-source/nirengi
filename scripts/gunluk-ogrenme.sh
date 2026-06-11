#!/bin/zsh
# Nirengi günlük öğrenme — launchd her iş günü 18:30'da çalıştırır.
# Robot Yahoo'dan çeker, sicili günceller, GitHub'a push eder.
# (GitHub Actions'taki kopya, Yahoo datacenter IP'lere BIST hissesi vermediği
#  için no-op kalıyor; asıl koşu burada, ev IP'sinden.)

set -e
exec >> /tmp/nirengi-ogrenme.log 2>&1
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="

cd "$HOME/Desktop/yeni-finans-app"

# Hafta sonu koşma (launchd gün filtresi yapamıyor; cumartesi=6 pazar=7).
gun=$(date +%u)
if [ "$gun" -gt 5 ]; then echo "hafta sonu, atlandı"; exit 0; fi

# Uzaktaki olası değişiklikleri al (çakışırsa bugünü atla, yarın toparlanır).
git pull --rebase origin main || { git rebase --abort 2>/dev/null; echo "pull çakıştı, atlandı"; exit 0; }

swift run --package-path Cekirdek -c release ogrenme

git add data/
if git diff --cached --quiet; then
    echo "değişiklik yok"
else
    git commit -m "🤖 Günlük öğrenme (yerel): sicil + ağırlık + kalibrasyon"
    git push origin main
fi
echo "bitti"
