#!/bin/sh

# ----------------------------------------------------------------------
# Загрузка конфигурации (если есть)
# ----------------------------------------------------------------------

CONFIG_FILE="/opt/root/banner.conf"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    echo "Warning: config file $CONFIG_FILE not found" >&2
fi
# Удаляем возможные символы возврата каретки и лишние пробелы
POSITIVE_KEYWORDS=$(echo "${POSITIVE_KEYWORDS}" | tr -d '\r' | xargs)
NEGATIVE_KEYWORDS=$(echo "${NEGATIVE_KEYWORDS}" | tr -d '\r' | xargs)

# Если переменные всё ещё пусты – задаём значения по умолчанию
: "${POSITIVE_KEYWORDS:=запущен|running|alive|started|работает}"
: "${NEGATIVE_KEYWORDS:=не запущен}"

# ----------------------------------------------------------------------
# Цвета (как в оригинале)
# ----------------------------------------------------------------------
blk="\033[1;30m"; red="\033[1;31m"; grn="\033[1;32m"; ylw="\033[1;33m"
blu="\033[1;34m"; pur="\033[1;35m"; cyn="\033[1;36m"; wht="\033[1;37m"
clr="\033[0m"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'; DIM='\033[2m'
RESET='\033[0m'

# Поиск значения по ключу в строке "key:value,key2:value2,..."
map_lookup() {
    _map="$1"
    _key="$2"
    # Ищем "key:" и берём всё до следующей запятой
    _entry=$(echo "$_map" | grep -o "${_key}:[^,]*" | head -1)
    if [ -n "$_entry" ]; then
        echo "$_entry" | cut -d':' -f2-
    fi
}

# ----------------------------------------------------------------------
# Преобразование имени сервиса (из конфига или встроенное)
# ----------------------------------------------------------------------
format_service_name() {
    _raw="$1"
    _name=$(echo "$_raw" | sed 's/^S[0-9]*//')
    _display=$(map_lookup "$SERVICE_MAP" "$_name")
    if [ -n "$_display" ]; then
        echo "$_display"
    else
        echo "$_name"
    fi
}


# ----------------------------------------------------------------------
# Получение имени процесса для pidof (из конфига)
# ----------------------------------------------------------------------
get_proc_name() {
    _raw="$1"
    _name=$(echo "$_raw" | sed 's/^S[0-9]*//')
    _proc=$(map_lookup "$PROC_MAP" "$_name")
    if [ -n "$_proc" ]; then
        echo "$_proc"
    else
        echo "$_name"
    fi
}

# ----------------------------------------------------------------------
# Проверка статуса сервиса (0=running, 1=stopped) + вывод статуса
# ----------------------------------------------------------------------
check_service_status() {
    _script="$1"
    _service_name=$(basename "$_script" | sed 's/^S[0-9]*//')
    _pid=""
    _status_output=""

    # 1. Вызов script status
    if [ -x "$_script" ]; then
        _status_output=$("$_script" status 2>&1)
        _pid=$(echo "$_status_output" | grep -oE 'PID[[:space:]]*[=:]*[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)
    fi

    # 2. Поиск PID в файлах
    if [ -z "$_pid" ]; then
        for _pf in "/opt/var/run/${_service_name}.pid" "/var/run/${_service_name}.pid" "/opt/var/run/${_service_name}/${_service_name}.pid"; do
            if [ -f "$_pf" ] && [ -s "$_pf" ]; then
                _pid=$(cat "$_pf" 2>/dev/null | tr -d ' \n\r')
                [ -n "$_pid" ] && break
            fi
        done
    fi

    # 3. Если PID жив – running
    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
        echo "✅ running (PID: $_pid)"
        return 0
    fi

    # 4. Поиск процесса по имени из PROC_MAP
    _proc_name=$(get_proc_name "$_service_name")
    if [ -n "$_proc_name" ]; then
        _found_pid=$(pidof "$_proc_name" 2>/dev/null | awk '{print $1}')
        if [ -n "$_found_pid" ] && kill -0 "$_found_pid" 2>/dev/null; then
            echo "✅ running (PID: $_found_pid)"
            return 0
        fi
    fi

    # 5. Анализ ключевых слов в выводе status
    if [ -n "$_status_output" ]; then
        _lower=$(echo "$_status_output" | tr '[:upper:]' '[:lower:]')
        # Проверка негативных ключей (явно остановлен)
        if echo "$_lower" | grep -qE "$NEGATIVE_KEYWORDS"; then
            # остановлен
            :
        elif echo "$_lower" | grep -qE "$POSITIVE_KEYWORDS"; then
            echo "✅ running"
            return 0
        fi
    fi

    # 6. По умолчанию – остановлен
    echo "❌ stopped"
    return 1
}

# ----------------------------------------------------------------------
# Получение сырых подробностей сервиса (первая строка вывода status)
# ----------------------------------------------------------------------
get_service_details() {
    _script="$1"
    _status_output=$("$_script" status 2>&1)
    _first_line=$(echo "$_status_output" | head -1)
    _raw=$(echo "$_first_line" | sed 's/^[[:space:]]*//')
    [ -z "$_raw" ] && echo "(no status output)" || echo "$_raw"
}

# ----------------------------------------------------------------------
# Баннер и секции (оригинальное оформление)
# ----------------------------------------------------------------------
print_banner() {
    printf "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
    printf "${WHITE}${BOLD}  🖥️  %s${RESET}\n" "$(hostname)"
    printf "${DIM}     %s  |  Uptime: %s${RESET}\n" "$(uname -o 2>/dev/null || echo "Entware") $(uname -r)" "$(uptime | sed 's/.*up //' | sed 's/,.*//')"
    printf "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
}

print_section() {
    printf "\n${WHITE}${BOLD} ┌── $1${RESET}\n"
}

print_footer() {
    printf "${CYAN}${BOLD} └────────────────────────────────────────────────────────────────────────────────────────────────────────────${RESET}\n"
}

# ----------------------------------------------------------------------
# Информация о системе (расширенная версия print_system_info_new)
# ----------------------------------------------------------------------
print_system_info() {
    print_section "📊  СИСТЕМА"

    # CPU type
    _CPU_TYPE="$(cat /proc/cpuinfo | awk -F: '/(model|system)/{print $2}' | head -1 | sed 's, ,,')"
    if [ "$(uname -m)" = "aarch64" ]; then
        CPU_TYPE="$_CPU_TYPE"
    else
        CPU_TYPE="$_CPU_TYPE$(cat /proc/cpuinfo | awk -F: '/cpu model/{print $2}' | head -1)"
    fi

    # External IP (таймаут 2 сек)
    EXT_IP="$(curl -s --max-time 2 https://ipinfo.io/ip 2>/dev/null || echo 'N/A')"

    # Вывод (сохранён оригинальный формат)
    printf "${WHITE} │  ${wht} %-10s ${ylw} %-30s ${wht} %-10s ${ylw}    %-30s ${clr}\n" \
        "Date:" "📆$(date)" \
        "Uptime:" "🕐 $(uptime -p 2>/dev/null || echo 'unknown')"
    printf "${WHITE} │  ${wht} %-10s ${blu} %-30s ${wht} %-10s ${blu}  %-30s ${clr}\n" \
        "Router:" "$(ndmc -c "show version" 2>/dev/null | awk -F": " '/model/ {print $2}')" \
        "Accessed IP:" "$EXT_IP"
    printf "${WHITE} │  ${wht} %-10s ${grn} %-30s ${wht}   %-10s ${grn}    %-30s ${clr}\n" \
        "OS:" "$(uname -s) 🐧" \
        "CPU:" "$CPU_TYPE"
    printf "${WHITE} │  ${wht} %-10s ${grn} %-30s ${wht} %-10s ${grn} %-30s ${clr}\n" \
        "Kernel:" "$(uname -r)" \
        "Architecture:" "$(uname -m)"
    printf "${WHITE} │  ${wht} %-10s ${red} %-30s ${wht}\n" \
        "CPU Temp:" "$(($(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null) / 1000))°C"
    printf "${WHITE} │  ${wht} %-10s ${pur} %-30s ${clr}\n" \
        "USB Disk:" "$(df -h | grep '/opt' | awk '{print $2" (size) / "$3" (used) / "$4" (free) / "$5" (used %) : 💾 "$6}')"
    printf "${WHITE} │  ${wht} %-10s ${pur} %-30s ${clr}\n" \
        "Memory:" "$(free | awk '/^Mem:/ {printf "%.0f MB (total) / %.0f MB (used) / %.0f MB (free)", $2/1024, $3/1024, $4/1024}')"
    printf "${WHITE} │  ${wht} %-10s ${pur} %-30s ${clr}\n" \
        "Swap:" "$(free | awk '/^Swap:/ {printf "%.0f MB (total) / %.0f MB (used) / %.0f MB (free)", $2/1024, $3/1024, $4/1024}')"
    printf "${WHITE} │  ${wht} %-10s ${pur} %-30s ${clr}\n" \
        "LA:" "$(cat /proc/loadavg | awk '{print $1" (1m) / "$2" (5m) / "$3" (15m)"}')"
    printf "${WHITE} │  ${wht} %-10s ${red} %-30s ${wht}\n" \
        "User:" "🤵 $(echo $USER)"

    # Dist
    if [ -f "/opt/etc/entware_release" ]; then
        printf "${WHITE} │  ${wht} %-10s ${grn} %-30s ${clr}\n" \
            "Dist:" "$(awk -F= '/^PRETTY_NAME/ {gsub(/"/, "", $2); print $2}' /opt/etc/entware_release)"
    else
        printf "${WHITE} │  ${wht} %-10s ${grn} %-30s ${clr}\n" "Dist:" "Entware"
    fi

    # Установленные пакеты
    printf "${WHITE} │  ${wht} %-10s ${cyn} %-30s ${wht}     %-10s ${cyn} %-30s ${clr}\n" \
        "Installed:" "📦📦 $(opkg list-installed 2>/dev/null | wc -l)" \
        "Upgrade:" "📦 $(opkg list-upgradable 2>/dev/null | wc -l)"

    print_footer
}

# ----------------------------------------------------------------------
# Список сервисов (использует check_service_status)
# ----------------------------------------------------------------------
print_services_status() {
    print_section "🔧  СЕРВИСЫ ENTWARE"

    local initd_dir="/opt/etc/init.d"
    local count=0
    local running=0

    printf "${WHITE} │  ${CYAN}%-20s${RESET}  ${GREEN}%-30s${RESET}  %s\n" "SERVICES" "STATUS" "DETAILS"
    printf "${WHITE} │  ${DIM}%-20s  %-30s  %s${RESET}\n" "--------------------" "------------------------------" "--------------------------------------------------"

    for script in $(ls -1 "$initd_dir"/S* 2>/dev/null | sort -V); do
        [ ! -x "$script" ] && continue

        count=$((count + 1))
        raw_name=$(basename "$script")
        display_name=$(format_service_name "$raw_name")

        status_result=$(check_service_status "$script")
        if echo "$status_result" | grep -q "✅"; then
            status_text="$status_result"
            status_color="${GREEN}"
            running=$((running + 1))
        else
            status_text="❌ stopped"
            status_color="${RED}"
        fi

        raw_status=$(get_service_details "$script")

        printf "${WHITE} │  ${CYAN}%-20s${RESET}  ${status_color}%-30s${RESET}  %s\n" "$display_name" "$status_text" "$raw_status"
    done

    if [ $count -eq 0 ]; then
        printf "${WHITE} │  ${YELLOW}⚠️  Нет сервисов в /opt/etc/init.d/${RESET}\n"
    else
        printf "${WHITE} │  \n${WHITE} │  ${DIM}Total: $count, Run: $running${RESET}\n"
    fi

    print_footer
}

# ----------------------------------------------------------------------
# Меню (как в оригинале)
# ----------------------------------------------------------------------
run_menu() {
    printf "\n${WHITE}${BOLD}📋  МЕНЮ УПРАВЛЕНИЯ${RESET}\n"
    printf "${CYAN}  [1]  Обновить список пакетов${RESET}\n"
    printf "${CYAN}  [2]  Обновить все пакеты${RESET}\n"
    printf "${CYAN}  [3]  Показать доступные обновления${RESET}\n"
    printf "${CYAN}  [0]  Выход${RESET}\n"
    printf "\n${WHITE}${BOLD}➜ Выберите действие: ${RESET}"

    read choice
    case $choice in
        1) opkg update ;;
        2) opkg upgrade ;;
        3) opkg list-upgradable ;;
        0) return ;;
        *) printf "${RED}Неверный выбор${RESET}\n" ;;
    esac
    printf "\n${GREEN}Готово. Нажмите Enter...${RESET}\n"
    read
    clear
    print_banner
    print_system_info
    print_services_status
    printf "\n${DIM}💡 Введите ${WHITE}menu${DIM} для управления пакетами.${RESET}\n"
}

# ----------------------------------------------------------------------
# Точка входа
# ----------------------------------------------------------------------
if [ "$1" = "menu" ]; then
    run_menu
    exit 0
fi

clear
#print_banner
print_system_info
print_services_status
#printf "\n${DIM}💡 Введите ${WHITE}menu${DIM} для управления пакетами.${RESET}\n"