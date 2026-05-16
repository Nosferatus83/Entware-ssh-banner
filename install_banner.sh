#!/bin/sh

set -eu

# Цвета для вывода
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

# --- Обработка аргументов командной строки ---
FORCE_CONF=0   # 0 - не перезаписывать, 1 - перезаписывать, 2 - спрашивать
KEEP_CONF=0

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)
            FORCE_CONF=1
            shift
            ;;
        -k|--keep)
            FORCE_CONF=0
            KEEP_CONF=1
            shift
            ;;
        *)
            echo -e "${RED}Неизвестный аргумент: $1${NC}"
            echo "Использование: $0 [-f|--force] [-k|--keep]"
            exit 1
            ;;
    esac
done

# --- Функция для запроса подтверждения ---
ask_overwrite() {
    local file="$1"
    printf "${YELLOW}Файл %s уже существует. Перезаписать? [y/N] ${NC}" "$file"
    read answer
    case "$answer" in
        y|Y|yes|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

echo -e "${GREEN}==> Установка SSH-баннера для Entware${NC}"

# 1. Установка зависимостей
echo -e "\n${YELLOW}[1/5] Установка зависимостей...${NC}"
opkg update >/dev/null 2>&1

for pkg in wget-ssl whiptail; do
    if opkg list-installed | grep -q "^$pkg -"; then
        echo "  ✓ $pkg уже установлен"
    else
        echo "  → Установка $pkg ..."
        opkg install $pkg >/dev/null 2>&1
        echo "  ✓ $pkg установлен"
    fi
done

# 2. Создание каталога /opt/root
mkdir -p /opt/root

# 3. Скачивание custom-banner.sh (всегда перезаписываем)
BANNER_URL="https://raw.githubusercontent.com/Nosferatus83/Entware-ssh-banner/main/custom-banner.sh"
CONFIG_URL="https://raw.githubusercontent.com/Nosferatus83/Entware-ssh-banner/main/banner.conf"

echo -e "\n${YELLOW}[2/5] Скачивание custom-banner.sh...${NC}"
wget -q -O /opt/root/custom-banner.sh "$BANNER_URL"
chmod +x /opt/root/custom-banner.sh
echo "  ✓ custom-banner.sh обновлён"

# 4. Работа с banner.conf
echo -e "\n${YELLOW}[3/5] Настройка banner.conf...${NC}"
CONF_FILE="/opt/root/banner.conf"
DOWNLOAD_CONF=0

if [ -f "$CONF_FILE" ]; then
    # Файл существует
    if [ $FORCE_CONF -eq 1 ]; then
        echo "  → Перезапись конфига (принудительно)"
        DOWNLOAD_CONF=1
    elif [ $KEEP_CONF -eq 1 ]; then
        echo "  → Существующий конфиг оставлен (--keep)"
        DOWNLOAD_CONF=0
    else
        # Спрашиваем, если интерактивный режим
        if [ -t 0 ]; then
            if ask_overwrite "$CONF_FILE"; then
                DOWNLOAD_CONF=1
            else
                DOWNLOAD_CONF=0
            fi
        else
            # Неинтерактивный режим — не перезаписываем
            echo "  → Неинтерактивный режим, конфиг оставлен без изменений"
            DOWNLOAD_CONF=0
        fi
    fi
else
    echo "  → Конфиг не существует, будет скачан"
    DOWNLOAD_CONF=1
fi

if [ $DOWNLOAD_CONF -eq 1 ]; then
    wget -q -O "$CONF_FILE" "$CONFIG_URL"
    echo "  ✓ banner.conf скачан"
else
    echo "  ✓ banner.conf не изменён"
fi

# 5. Настройка .profile
PROFILE_FILE="$HOME/.profile"
echo -e "\n${YELLOW}[4/5] Настройка $PROFILE_FILE...${NC}"
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

# 6. Вывод информации о конфигурации
echo -e "\n${YELLOW}[5/5] Информация о конфигурации${NC}"
if [ -f "$CONF_FILE" ]; then
    echo "  Файл конфигурации: $CONF_FILE"
    echo "  Текущие параметры:"
    for var in SERVICE_MAP PROC_MAP POSITIVE_KEYWORDS NEGATIVE_KEYWORDS; do
        value=$(grep "^$var=" "$CONF_FILE" | head -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//')
        if [ -n "$value" ]; then
            echo "    $var = $value"
        fi
    done
else
    echo -e "${RED}  Файл конфигурации не найден!${NC}"
fi

echo -e "\n${YELLOW}📝 Правила изменения настроек:${NC}"
echo "  • Отредактируйте файл: nano $CONF_FILE"
echo "  • SERVICE_MAP      – отображаемые имена сервисов (формат 'имя_скрипта1:отображаемоеИмя1,имя_скрипта2:отображаемоеИмя2,' В конце списка обязательно ЗАПЯТАЯ)"
echo "  • PROC_MAP         – имя процесса для pidof (соответствие 'имя_скрипта1:процесс1:имя_скрипта2:процесс2,' В конце списка обязательно ЗАПЯТАЯ)"
echo "  • POSITIVE_KEYWORDS – слова, отвечающие за определение статуса 'сервис запущен' (разделитель |)"
echo "  • NEGATIVE_KEYWORDS – слова, отвечающие за определение статуса 'сервис остановлен' (разделитель |)"
echo "  • После изменений выполните: source ~/.profile  (или перезайдите по SSH)"

echo -e "\n${GREEN}✅ Установка завершена. При следующем входе по SSH появится баннер.${NC}"