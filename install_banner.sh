#!/bin/sh

set -eu

# Сброс буфера вывода (для BusyBox)
export POSIXLY_CORRECT=1
exec 2>&1
# Принудительно отключаем буферизацию stdout (если есть stdbuf)
if command -v stdbuf >/dev/null 2>&1; then
    exec stdbuf -oL -eL /bin/sh "$0" "$@"
fi

# Цвета
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

# --- Обработка аргументов ---
FORCE_CONF=0
KEEP_CONF=0

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force) FORCE_CONF=1; shift ;;
        -k|--keep)  FORCE_CONF=0; KEEP_CONF=1; shift ;;
        *)
            echo -e "${RED}Неизвестный аргумент: $1${NC}"
            echo "Использование: $0 [-f|--force] [-k|--keep]"
            exit 1
            ;;
    esac
done

# --- Вспомогательные функции ---
log() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}⚠️ $1${NC}" >&2; }
error() { echo -e "${RED}❌ $1${NC}" >&2; exit 1; }

ask_overwrite() {
    local file="$1"
    printf "${YELLOW}Файл %s уже существует. Перезаписать? [y/N] ${NC}" "$file" >&2
    read answer
    case "$answer" in y|Y|yes|Yes) return 0 ;; *) return 1 ;; esac
}

# --- Проверка сети ---
log "Проверка интернет-соединения..."
if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && ! ping -c 1 -W 3 google.com >/dev/null 2>&1; then
    warn "Нет интернета? Продолжаем, но возможно зависание..."
fi

# --- 1. Установка зависимостей (с таймаутами) ---
log "[1/5] Установка зависимостей..."

# opkg update с таймаутом (30 сек) и повторными попытками
if ! timeout 30 opkg update >/dev/null 2>&1; then
    warn "opkg update занял слишком много времени или не удался, пробуем без таймаута..."
    opkg update >/dev/null 2>&1 || warn "opkg update завершился с ошибкой, но продолжаем"
fi

for pkg in wget-ssl whiptail; do
    if opkg list-installed | grep -q "^$pkg -"; then
        echo "  ✓ $pkg уже установлен"
    else
        echo "  → Установка $pkg ..."
        if timeout 60 opkg install "$pkg" >/dev/null 2>&1; then
            echo "  ✓ $pkg установлен"
        else
            warn "Установка $pkg зависла или не удалась, повторяем без таймаута..."
            opkg install "$pkg" >/dev/null 2>&1 || error "Не удалось установить $pkg"
        fi
    fi
done

# --- 2. Создание каталога ---
mkdir -p /opt/root

# --- 3. Скачивание custom-banner.sh (с таймаутом) ---
BANNER_URL="https://raw.githubusercontent.com/Nosferatus83/Entware-ssh-banner/main/custom-banner.sh"
CONFIG_URL="https://raw.githubusercontent.com/Nosferatus83/Entware-ssh-banner/main/banner.conf"

log "[2/5] Скачивание custom-banner.sh..."
if ! wget -q --timeout=10 --tries=2 -O /opt/root/custom-banner.sh "$BANNER_URL"; then
    warn "Первая попытка wget не удалась, пробуем снова без таймаута..."
    wget -q -O /opt/root/custom-banner.sh "$BANNER_URL" || error "Не удалось скачать custom-banner.sh"
fi
chmod +x /opt/root/custom-banner.sh
echo "  ✓ custom-banner.sh обновлён"

# --- 4. Работа с banner.conf ---
log "[3/5] Настройка banner.conf..."
CONF_FILE="/opt/root/banner.conf"
DOWNLOAD_CONF=0

if [ -f "$CONF_FILE" ]; then
    if [ $FORCE_CONF -eq 1 ]; then
        echo "  → Перезапись конфига (принудительно)"
        DOWNLOAD_CONF=1
    elif [ $KEEP_CONF -eq 1 ]; then
        echo "  → Существующий конфиг оставлен (--keep)"
        DOWNLOAD_CONF=0
    else
        if [ -t 0 ]; then
            if ask_overwrite "$CONF_FILE"; then
                DOWNLOAD_CONF=1
            else
                DOWNLOAD_CONF=0
            fi
        else
            echo "  → Неинтерактивный режим, конфиг оставлен без изменений"
            DOWNLOAD_CONF=0
        fi
    fi
else
    echo "  → Конфиг не существует, будет скачан"
    DOWNLOAD_CONF=1
fi

if [ $DOWNLOAD_CONF -eq 1 ]; then
    wget -q --timeout=10 --tries=2 -O "$CONF_FILE" "$CONFIG_URL" || error "Не удалось скачать banner.conf"
    echo "  ✓ banner.conf скачан"
else
    echo "  ✓ banner.conf не изменён"
fi

# --- 5. Настройка .profile ---
PROFILE_FILE="$HOME/.profile"
log "[4/5] Настройка $PROFILE_FILE..."
if [ -f "$PROFILE_FILE" ]; then
    cp "$PROFILE_FILE" "${PROFILE_FILE}.backup"
    echo "  Создана резервная копия: ${PROFILE_FILE}.backup"
fi

cat > "$PROFILE_FILE" <<'PROFILE_EOF'
#!/bin/sh
. /opt/etc/profile
. /opt/root/custom-banner.sh
PROFILE_EOF
echo "  ✓ $PROFILE_FILE обновлён"

# --- 6. Информация о конфигурации ---
log "[5/5] Информация о конфигурации"
if [ -f "$CONF_FILE" ]; then
    echo "  Файл конфигурации: $CONF_FILE"
    echo "  Текущие параметры:"
    for var in SERVICE_MAP PROC_MAP POSITIVE_KEYWORDS NEGATIVE_KEYWORDS; do
        value=$(grep "^$var=" "$CONF_FILE" | head -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//')
        [ -n "$value" ] && echo "    $var = $value"
    done
else
    echo -e "${RED}  Файл конфигурации не найден!${NC}"
fi

echo -e "\n${YELLOW}📝 Правила изменения настроек:${NC}"
echo "  • Отредактируйте файл: nano $CONF_FILE"
echo "  • SERVICE_MAP      – отображаемые имена сервисов (формат 'имя_скрипта1:Имя1,имя_скрипта2:Имя2,' – В конце списка обязательно ЗАПЯТАЯ)"
echo "  • PROC_MAP         – имя процесса для pidof (формат 'имя_скрипта1:процесс1,имя_скрипта2:процесс2,' – В конце списка обязательно ЗАПЯТАЯ)"
echo "  • POSITIVE_KEYWORDS – слова, означающие 'сервис запущен' (разделитель |)"
echo "  • NEGATIVE_KEYWORDS – слова, означающие 'сервис остановлен' (разделитель |)"
echo "  • После изменений выполните: source ~/.profile  (или перезайдите по SSH)"

echo -e "\n${GREEN}✅ Установка завершена. При следующем входе по SSH появится баннер.${NC}"