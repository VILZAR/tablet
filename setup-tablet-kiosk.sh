#!/usr/bin/env bash
set -e

# ---------- Настройки: укажи логин и таймзону (или задай через переменные окружения) ----------
LOGIN_USER="${LOGIN_USER:-$USER}"
TZ_NAME="${TZ_NAME:-Asia/Krasnoyarsk}"
REBOOT_TIME="${REBOOT_TIME:-04:00}"

BROWSER="chromium"
AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/browser-at-login.desktop"
KWINRC="$HOME/.config/kwinrc"

echo "=== Настройка планшета: жесты + Chromium (kiosk) + автозапуск + блокировка рабочего стола ==="
echo "Логин (автологин): $LOGIN_USER"
echo "Таймзона: $TZ_NAME"
echo "Браузер: $BROWSER"
echo ""

# ---- 0. Автологин (создаём конфиг из указанного логина) ----
echo "0. Автологин для пользователя $LOGIN_USER..."
sudo mkdir -p /etc/sddm.conf.d
printf '%s\n' '[Autologin]' "User=$LOGIN_USER" 'Session=plasma' | sudo tee /etc/sddm.conf.d/autologin.conf >/dev/null
echo "   Готово: /etc/sddm.conf.d/autologin.conf"
echo ""

# ---- 1. Установка Chromium, если отсутствует ----
echo "1. Проверка Chromium..."
CHROMIUM_CMD=""
for cmd in chromium-browser chromium; do
  if command -v "$cmd" >/dev/null 2>&1; then
    CHROMIUM_CMD="$cmd"
    break
  fi
done
[ -z "$CHROMIUM_CMD" ] && [ -x /usr/bin/chromium-browser ] && CHROMIUM_CMD="/usr/bin/chromium-browser"
[ -z "$CHROMIUM_CMD" ] && [ -x /usr/bin/chromium ] && CHROMIUM_CMD="/usr/bin/chromium"

if [ -n "$CHROMIUM_CMD" ]; then
  echo "   Chromium уже установлен: $CHROMIUM_CMD"
else
  echo "   Chromium не найден, устанавливаю (нужен sudo)..."
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y chromium
  elif command -v xbps-install >/dev/null 2>&1; then
    sudo xbps-install -y chromium
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && (sudo apt-get install -y chromium-browser 2>/dev/null || sudo apt-get install -y chromium)
  else
    echo "   Установи Chromium вручную и снова запусти скрипт."
    exit 1
  fi
  for cmd in chromium-browser chromium; do
    command -v "$cmd" >/dev/null 2>&1 && CHROMIUM_CMD="$cmd" && break
  done
  [ -z "$CHROMIUM_CMD" ] && [ -x /usr/bin/chromium-browser ] && CHROMIUM_CMD="/usr/bin/chromium-browser"
  [ -z "$CHROMIUM_CMD" ] && CHROMIUM_CMD="chromium-browser"
  echo "   Установлено."
fi
echo ""

# ---- 2. Отключение жестов (только тап) ----
echo "2. Отключение жестов (только тап)..."
if [ -f "$KWINRC" ]; then
  cp "$KWINRC" "${KWINRC}.bak"
  echo "   Бэкап: ${KWINRC}.bak"
fi
mkdir -p "$(dirname "$KWINRC")"
touch "$KWINRC" 2>/dev/null || true

if ! grep -q '^\[Desktops\]' "$KWINRC"; then
  echo "" >> "$KWINRC"
  echo "[Desktops]" >> "$KWINRC"
  echo "Number=1" >> "$KWINRC"
  echo "Rows=1" >> "$KWINRC"
else
  sed -i '/^\[Desktops\]/,/^\[/s/^Number=.*/Number=1/' "$KWINRC" 2>/dev/null || true
  grep -q '^Rows=' "$KWINRC" 2>/dev/null && sed -i '/^\[Desktops\]/,/^\[/s/^Rows=.*/Rows=1/' "$KWINRC" 2>/dev/null || sed -i '/^Number=1$/a Rows=1' "$KWINRC"
fi

for effect in desktopgrid presentwindows overview cube flipswitch; do
  key="${effect}Enabled"
  if grep -q "^${key}=" "$KWINRC"; then
    sed -i "s/^${key}=.*/${key}=false/" "$KWINRC"
  else
    grep -q '^\[Plugins\]' "$KWINRC" || echo -e "\n[Plugins]" >> "$KWINRC"
    grep -q "^${key}=" "$KWINRC" || sed -i "0,/^\[Plugins\]/a ${key}=false" "$KWINRC"
  fi
done
echo "   Готово: $KWINRC"
echo ""

# ---- 3. Автозапуск Chromium (kiosk: только браузер, без панели и выхода) ----
echo "3. Автозапуск Chromium в режиме kiosk (полный экран, без других окон)..."
CHROMIUM_EXEC="${CHROMIUM_CMD:-chromium-browser}"
if [ -x /usr/bin/chromium-browser ]; then
  CHROMIUM_EXEC="/usr/bin/chromium-browser"
elif [ -x /usr/sbin/chromium-browser ]; then
  CHROMIUM_EXEC="/usr/sbin/chromium-browser"
elif ! command -v "$CHROMIUM_EXEC" >/dev/null 2>&1; then
  CHROMIUM_EXEC="$(command -v chromium-browser 2>/dev/null)" || CHROMIUM_EXEC="$(command -v chromium 2>/dev/null)" || CHROMIUM_EXEC="chromium-browser"
fi
WRAPPER="$HOME/.local/bin/start-chromium-kiosk.sh"
mkdir -p "$(dirname "$WRAPPER")"
cat > "$WRAPPER" << EOF
#!/bin/sh
sleep 5
exec $CHROMIUM_EXEC --no-sandbox --disable-gpu --disable-software-rasterizer --kiosk --start-fullscreen --disable-pinch --noerrdialogs --disable-infobars --no-first-run --disable-features=OverscrollHistoryNavigation "http://10.1.0.194:3000"
EOF
chmod +x "$WRAPPER"
mkdir -p "$AUTOSTART_DIR"
printf '%s\n' "[Desktop Entry]" "Type=Application" "Name=Browser at login" "Comment=Chromium kiosk at session start" "Exec=$WRAPPER" "X-KDE-AutostartPhase=2" "X-GNOME-Autostart-enabled=true" > "$AUTOSTART_FILE"
echo "   Создан: $WRAPPER и $AUTOSTART_FILE"
echo ""

# ---- 2.1. Блокировка рабочего стола (нет меню «добавить виджеты», панели по зажатию) ----
echo "3.1. Блокировка рабочего стола (lockCorona)..."
LOCK_SCRIPT="$HOME/.local/bin/plasma-lock-desktop.sh"
LOCK_DESKTOP="$AUTOSTART_DIR/plasma-lock-desktop.desktop"
mkdir -p "$(dirname "$LOCK_SCRIPT")"
cat > "$LOCK_SCRIPT" << 'LOCKEOF'
#!/bin/sh
sleep 8
if command -v qdbus6 >/dev/null 2>&1; then
  qdbus6 org.kde.plasmashell /PlasmaShell evaluateScript "lockCorona(true)"
elif command -v qdbus >/dev/null 2>&1; then
  qdbus org.kde.plasmashell /PlasmaShell evaluateScript "lockCorona(true)"
fi
LOCKEOF
chmod +x "$LOCK_SCRIPT"
printf '%s\n' "[Desktop Entry]" "Type=Application" "Name=Lock Plasma desktop" "Comment=Lock widgets, no add panels/widgets menu" "Exec=$LOCK_SCRIPT" "X-KDE-AutostartPhase=2" "X-GNOME-Autostart-enabled=true" > "$LOCK_DESKTOP"
echo "   Создан: $LOCK_SCRIPT и $LOCK_DESKTOP"
echo ""

# ---- 2.2. Вертикальная ориентация (портрет) и фиксация при каждом входе ----
echo "3.2. Вертикальная ориентация экрана (портрет), фиксируется при входе..."
ROTATE_SCRIPT="$HOME/.local/bin/set-portrait-rotation.sh"
ROTATE_DESKTOP="$AUTOSTART_DIR/set-portrait-rotation.desktop"
mkdir -p "$(dirname "$ROTATE_SCRIPT")"
cat > "$ROTATE_SCRIPT" << 'ROTEOF'
#!/bin/sh
sleep 4
# Портрет (вертикаль): rotation.right = 90° по часовой
if command -v kscreen-doctor >/dev/null 2>&1; then
  kscreen-doctor output.1.rotation.right 2>/dev/null || true
  kscreen-doctor output.eDP-1.rotation.right 2>/dev/null || true
  kscreen-doctor output.DSI-1.rotation.right 2>/dev/null || true
fi
ROTEOF
chmod +x "$ROTATE_SCRIPT"
printf '%s\n' "[Desktop Entry]" "Type=Application" "Name=Set portrait rotation" "Comment=Lock display to vertical orientation at login" "Exec=$ROTATE_SCRIPT" "X-KDE-AutostartPhase=2" "X-GNOME-Autostart-enabled=true" > "$ROTATE_DESKTOP"
echo "   Создан: $ROTATE_SCRIPT и $ROTATE_DESKTOP"
echo ""

# ---- 2.3. Экран не блокируется и не гаснет (всегда горит) ----
echo "3.3. Экран не блокируется и не гаснет (всегда горит)..."
mkdir -p "$HOME/.config"
# отключить автоблокировку (kscreenlocker: Secure & Locking → Lock screen automatically)
printf '%s\n' '[Daemon]' 'Autolock=false' 'Timeout=0' > "$HOME/.config/kscreenlockerrc"
# PowerDevil: экран не гаснет, сессия не уходит в сон — таймауты в секундах (2147483647 = по сути «никогда»)
POWERDEVILRC="$HOME/.config/powerdevilrc"
IDLE_NEVER=2147483647
{
  for profile in AC Battery LowBattery; do
    printf '%s\n' "[${profile}][Display]" "DimDisplayIdleTimeoutSec=$IDLE_NEVER" "TurnOffDisplayIdleTimeoutSec=$IDLE_NEVER" ""
    printf '%s\n' "[${profile}][SuspendAndShutdown]" "AutoSuspendIdleTimeoutSec=$IDLE_NEVER" ""
    printf '%s\n' "[${profile}][RunScript]" "RunScriptIdleTimeoutSec=$IDLE_NEVER" ""
  done
} > "$POWERDEVILRC"
echo "   Готово: kscreenlockerrc, powerdevilrc (экран не гаснет, сон отключён)"
echo ""

# ---- 4. Отключение KDE Wallet (без окна «создать кошелёк» при запуске) ----
echo "4. Отключение KDE Wallet..."
KWALLETRC="$HOME/.config/kwalletrc"
mkdir -p "$(dirname "$KWALLETRC")"
if [ -f "$KWALLETRC" ] && grep -q '^\[Wallet\]' "$KWALLETRC"; then
  sed -i '/^\[Wallet\]/,/^\[/s/^Enabled=.*/Enabled=false/' "$KWALLETRC"
  grep -q '^Enabled=' "$KWALLETRC" || sed -i '/^\[Wallet\]/a Enabled=false' "$KWALLETRC"
else
  printf '%s\n' '[Wallet]' 'Enabled=false' > "$KWALLETRC"
fi
echo "   Готово: $KWALLETRC"
echo ""

# ---- 5. Таймзона и ежедневная перезагрузка (всегда включена) ----
echo "5. Таймзона $TZ_NAME и ежедневная перезагрузка в ${REBOOT_TIME}..."
if command -v timedatectl >/dev/null 2>&1; then
  sudo timedatectl set-timezone "$TZ_NAME" 2>/dev/null && echo "   Таймзона: $TZ_NAME" || true
fi
sudo tee /etc/systemd/system/daily-reboot.service >/dev/null << 'SVCEOF'
[Unit]
Description=Daily reboot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/reboot
SVCEOF
printf '%s\n' "[Unit]" "Description=Daily reboot at ${REBOOT_TIME}" "" "[Timer]" "OnCalendar=*-*-* ${REBOOT_TIME}:00" "Persistent=yes" "" "[Install]" "WantedBy=timers.target" | sudo tee /etc/systemd/system/daily-reboot.timer >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable daily-reboot.timer
sudo systemctl start daily-reboot.timer
echo "   Таймер перезагрузки: каждый день в ${REBOOT_TIME} ($TZ_NAME)"
echo ""

echo "=== Готово ==="
echo "Выйди из сессии и зайди снова (или перезагрузка), чтобы применилось всё."