# Tablet Kiosk Setup

Настройка планшета на базе Linux (Fedora/Plasma или аналог) в режим киоска: автологин, один полноэкранный браузер (Chromium), скрытие панелей, блокировка рабочего стола, портретная ориентация, экран не гаснет, **ежедневная перезагрузка**. Логин и таймзону задаёт пользователь.

---

## Файлы в проекте

| Файл | Назначение |
|------|------------|
| **setup-tablet-kiosk.sh** | Основной скрипт: автологин (по указанному логину), установка Chromium, жесты KWin, автозапуск браузера в kiosk, блокировка рабочего стола, портрет, экран не гаснет, KDE Wallet, таймзона и **ежедневная перезагрузка в 04:00**. |
| **plasma-hide-panels.sh** | Скрывает верхнюю и нижнюю панели Plasma Mobile. |
| **plasma-hide-panels.service** | Юнит systemd пользователя: при входе запускает `plasma-hide-panels.sh`. |
| **autologin.conf** | Шаблон автологина (опционально). Скрипт сам создаёт `/etc/sddm.conf.d/autologin.conf` по переменной `LOGIN_USER`. |

---

## Требования

- Linux с **KDE Plasma Mobile**.
- Дисплей-менеджер **SDDM** (для автологина).
- На устройстве: **SSH-сервер** (чтобы подключаться и копировать файлы), **sudo**.

---

## 1. Установка SSH на устройстве (планшете)

Чтобы подключаться к планшету и перекидывать файлы, на **самом устройстве** (локально или по консоли) нужно установить и включить SSH-сервер.

### Fedora / RHEL

```bash
sudo dnf install -y openssh-server
sudo systemctl enable sshd
sudo systemctl start sshd
hostname -I
```

Проверка: с другого компьютера выполни `ssh ПОЛЬЗОВАТЕЛЬ@IP_ПЛАНШЕТА`. Если подключается — можно перекидывать файлы через `scp`.

---

## 2. Копирование файлов на устройство (перекидывание)

С **компьютера**, где лежит папка `tablet-setup`, в той же папке выполни (подставь свой логин и IP планшета):

```bash
scp setup-tablet-kiosk.sh plasma-hide-panels.sh plasma-hide-panels.service autologin.conf ПОЛЬЗОВАТЕЛЬ@IP_ПЛАНШЕТА:~/
```

**Пример** (пользователь `void`, IP планшета `10.1.0.192`):

```bash
scp setup-tablet-kiosk.sh plasma-hide-panels.sh plasma-hide-panels.service autologin.conf void@10.1.0.192:~/
```

В Windows (PowerShell) укажи полный путь к файлам, например:

```powershell
scp C:\Users\ИМЯ\Desktop\tablet-setup\setup-tablet-kiosk.sh C:\Users\ИМЯ\Desktop\tablet-setup\plasma-hide-panels.sh C:\Users\ИМЯ\Desktop\tablet-setup\plasma-hide-panels.service C:\Users\ИМЯ\Desktop\tablet-setup\autologin.conf void@10.1.0.192:~/
```

После копирования зайди по SSH:

```bash
ssh void@10.1.0.192
```

---

## 3. Указание логина и таймзоны

Перед запуском скрипта задай **логин** (для автологина) и **таймзону**.

**Способ 1 — переменные окружения (удобно для одной команды):**

```bash
export LOGIN_USER="void"
export TZ_NAME="Asia/Krasnoyarsk"
```

Можно и время перезагрузки (по умолчанию 04:00):

```bash
export REBOOT_TIME="04:00"
```

**Способ 2 — правка скрипта:** открой `setup-tablet-kiosk.sh` и в начале файла измени строки:

```bash
LOGIN_USER="${LOGIN_USER:-$USER}"
TZ_NAME="${TZ_NAME:-Asia/Krasnoyarsk}"
REBOOT_TIME="${REBOOT_TIME:-04:00}"
```

Подставь нужные значения по умолчанию (например другой город для таймзоны: `Europe/Moscow`, `Asia/Bangkok` и т.д.).

---

## 4. Быстрый старт: одна команда на устройстве

После копирования файлов зайди по SSH на устройство и выполни **одну** команду ниже (подставь свой логин и таймзону). Скрипт сам создаст автологин; в конце устройство перезагрузится.

```bash
export LOGIN_USER="void" TZ_NAME="Asia/Krasnoyarsk" && \
mkdir -p ~/.local/bin ~/.config/systemd/user && \
cp ~/plasma-hide-panels.sh ~/.local/bin/ && chmod +x ~/.local/bin/plasma-hide-panels.sh && \
cp ~/plasma-hide-panels.service ~/.config/systemd/user/ && \
systemctl --user daemon-reload && systemctl --user enable plasma-hide-panels.service && systemctl --user start plasma-hide-panels.service && \
chmod +x ~/setup-tablet-kiosk.sh && ~/setup-tablet-kiosk.sh && \
echo "Готово. Перезагрузка через 10 сек..." && sleep 10 && sudo reboot
```

Если логин и таймзону задал в самом скрипте, переменные `LOGIN_USER` и `TZ_NAME` в команде можно не писать.

---

## Пошаговые команды (если нужны по отдельности)

| Шаг | Действие | Команда |
|-----|----------|---------|
| 1 | Логин и таймзона | `export LOGIN_USER="void" TZ_NAME="Asia/Krasnoyarsk"` |
| 2 | Панели: скрипт и сервис | `mkdir -p ~/.local/bin ~/.config/systemd/user && cp ~/plasma-hide-panels.sh ~/.local/bin/ && chmod +x ~/.local/bin/plasma-hide-panels.sh && cp ~/plasma-hide-panels.service ~/.config/systemd/user/` |
| 3 | Включить сервис панелей | `systemctl --user daemon-reload && systemctl --user enable plasma-hide-panels.service && systemctl --user start plasma-hide-panels.service` |
| 4 | Основная настройка (автологин, Chromium, перезагрузка и т.д.) | `chmod +x ~/setup-tablet-kiosk.sh && ~/setup-tablet-kiosk.sh` |
| 5 | Перезагрузка | `sudo reboot` |

Автологин создаётся **внутри** `setup-tablet-kiosk.sh` по переменной `LOGIN_USER`, отдельно копировать `autologin.conf` в `/etc` не нужно.

---

## Что делает setup-tablet-kiosk.sh

- **0** — создаёт автологин в `/etc/sddm.conf.d/autologin.conf` для пользователя из `LOGIN_USER`.
- **1** — устанавливает Chromium (dnf/apt/xbps), если его нет.
- **2** — один рабочий стол, отключает жесты в KWin.
- **3** — автозапуск Chromium в kiosk (полный экран, URL из скрипта).
- **3.1** — блокировка рабочего стола (lockCorona).
- **3.2** — портретная ориентация при входе.
- **3.3** — экран не блокируется и не гаснет.
- **4** — отключение KDE Wallet.
- **5** — таймзона из `TZ_NAME`, **ежедневная перезагрузка в `REBOOT_TIME` (всегда включена)**.

Часть шагов требует **sudo** (автологин, пакеты, таймер перезагрузки).

---

## Настройка под себя

- **Логин:** переменная `LOGIN_USER` или правка в начале скрипта.
- **Таймзона:** переменная `TZ_NAME` (например `Europe/Moscow`, `Asia/Bangkok`). Список: `timedatectl list-timezones`.
- **Время перезагрузки:** переменная `REBOOT_TIME` (по умолчанию `04:00`).
---

## Проверка после перезагрузки

- Вход без пароля (автологин под выбранным логином).
- Скрытые панели, Chromium в полноэкранном режиме с заданным URL.
- Портретная ориентация, экран не гаснет.
- **Каждый день в заданное время (по выбранной таймзоне) устройство перезагружается.**

## Сброс данных браузера

```bash
rm -rf ~/.config/chromium
sudo reboot
```