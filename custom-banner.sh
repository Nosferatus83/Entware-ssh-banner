#!/bin/sh

# Цвета
blk="\033[1;30m"   # Black
red="\033[1;31m"   # Red
grn="\033[1;32m"   # Green
ylw="\033[1;33m"   # Yellow
blu="\033[1;34m"   # Blue
pur="\033[1;35m"   # Purple
cyn="\033[1;36m"   # Cyan
wht="\033[1;37m"   # White
clr="\033[0m"      # Reset

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# --- Баннер -------------------------------------------------------------------
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

# --- Преобразование имени сервиса -----------------------------------------------
format_service_name() {
    local raw="$1"
    local name=$(echo "$raw" | sed 's/^S[0-9]*//')
    case "$name" in
        crond)       echo "Cron" ;;
        dropbear)    echo "Dropbear (SSH)" ;;
        awg-manager) echo "AWG Manager" ;;
        b4)          echo "B4" ;;
        xkeen)       echo "Xkeen (Xray)" ;;
        xkeen-ui)    echo "Xkeen Web UI" ;;
        ascn)        echo "ASCN" ;;
        *)           echo "$name" ;;
    esac
}

# --- Проверка статуса сервиса по PID/процессу/ключам ---------------------------
# Возвращает: статусную строку и код выхода (0=running, 1=stopped)
check_service_status() {
    local script="$1"
    local service_name=$(basename "$script" | sed 's/^S[0-9]*//')
    local pid=""
    local status_output=""
    
    # 1. Пробуем получить вывод через вызов "status"
    if [ -x "$script" ]; then
        status_output=$("$script" status 2>&1)
        pid=$(echo "$status_output" | grep -oE 'PID[[:space:]]*[=:]*[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)
    fi
    
    # 2. Если PID не нашли — ищем в PID-файлах
    if [ -z "$pid" ]; then
        for pf in "/opt/var/run/${service_name}.pid" "/var/run/${service_name}.pid" "/opt/var/run/${service_name}/${service_name}.pid"; do
            if [ -f "$pf" ] && [ -s "$pf" ]; then
                pid=$(cat "$pf" 2>/dev/null | tr -d ' \n\r')
                [ -n "$pid" ] && break
            fi
        done
    fi
    
    # 3. Если PID есть и процесс жив → running
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "✅ running (PID: $pid)"
        return 0
    fi
    
    # 4. PID нет — ищем процесс по имени сервиса (отбросив S##)
    local proc_name=""
    case "$service_name" in
        crond)      proc_name="crond" ;;
        dropbear)   proc_name="dropbear" ;;
        awg-manager) proc_name="awg_manager" ;;
        b4)         proc_name="b4" ;;
        xkeen)      proc_name="xray" ;;
        xkeen-ui)   proc_name="xkeen" ;;
        ascn)       proc_name="ascn" ;;
        *)          proc_name="$service_name" ;;
    esac
    
    local found_pid=$(pidof "$proc_name" 2>/dev/null | awk '{print $1}')
    if [ -n "$found_pid" ] && kill -0 "$found_pid" 2>/dev/null; then
        echo "✅ running (PID: $found_pid)"
        return 0
    fi
    
    # 5. Процесс по имени не нашли — проверяем ключевые слова в тексте статуса
    if [ -n "$status_output" ]; then
        local lower_text=$(echo "$status_output" | tr '[:upper:]' '[:lower:]')
        
        # Исключаем отрицания
        if echo "$lower_text" | grep -q "не запущен"; then
            # явно остановлен
            :
        elif echo "$lower_text" | grep -qE "запущен|running|alive|started|работает"; then
            echo "✅ running"
            return 0
        fi
    fi
    
    # 6. Ключевых слов нет → stopped
    echo "❌ stopped"
    return 1
}

# --- Получение подробностей сервиса (сырой вывод) ------------------------------
get_service_details() {
    local script="$1"
    local status_output=$("$script" status 2>&1)
    local first_line=$(echo "$status_output" | head -1)
    local raw_status=$(echo "$first_line" | sed 's/^[[:space:]]*//')
    
    if [ -z "$raw_status" ]; then
        echo "(no status output)"
    else
        echo "$raw_status"
    fi
}

# --- Системная информация ------------------------------------------------------
print_system_info_new() {
    print_section "📊  СИСТЕМА"
# Определение типа процессора
_CPU_TYPE="$(cat /proc/cpuinfo | awk -F: '/(model|system)/{print $2}' | head -1 | sed 's, ,,')"

if [ "$(uname -m)" = "aarch64" ]; then
    CPU_TYPE="$_CPU_TYPE"
else
    CPU_TYPE="$_CPU_TYPE$(cat /proc/cpuinfo | awk -F: '/cpu model/{print $2}' | head -1)"
fi

# Получение внешнего IP
EXT_IP="$(curl -s https://ipinfo.io/ip 2>/dev/null || echo 'N/A')"

# Вывод информации
printf "${WHITE} │  ${wht} %-10s ${ylw} %-30s ${wht} %-10s ${ylw}    %-30s ${clr}\n" \
    "Date:" "📆$(date)" \
    "Uptime:" "🕐 $(uptime -p)"
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
    "CPU Temp:" "$(($(cat /sys/class/thermal/thermal_zone0/temp)/1000))°C"
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

# Версия Entware
if [ -f "/opt/etc/entware_release" ]; then
    printf "${WHITE} │  ${wht} %-10s ${grn} %-30s ${clr}\n" \
        "Dist:" "$(awk -F= '/^PRETTY_NAME/ {gsub(/"/, "", $2); print $2}' /opt/etc/entware_release)"
else
    printf "${WHITE} │  ${wht} %-10s ${grn} %-30s ${clr}\n" \
        "Dist:" "Entware"
fi

# Установленные и доступные обновления
printf "${WHITE} │  ${wht} %-10s ${cyn} %-30s ${wht}     %-10s ${cyn} %-30s ${clr}\n" \
    "Installed:" "📦📦 $(opkg list-installed | wc -l)" \
    "Upgrade:" "📦 $(opkg list-upgradable | wc -l)"
    
    print_footer
}
print_system_info() {
    print_section "📊  СИСТЕМА"
    
    load=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs)
    printf "${WHITE} │  ${CYAN}%-20s${RESET} : ${GREEN}%s${RESET}\n" "Загрузка CPU" "$load"
    
    if [ -r /sys/class/thermal/thermal_zone0/temp ]; then
        temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        if [ -n "$temp_raw" ] && [ "$temp_raw" -gt 0 ] 2>/dev/null; then
            temp=$(awk "BEGIN {printf \"%.1f\", $temp_raw/1000}")
            printf "${WHITE} │  ${CYAN}%-20s${RESET} : ${GREEN}%s${RESET}\n" "Температура" "${temp}°C"
        else
            printf "${WHITE} │  ${CYAN}%-20s${RESET} : ${GREEN}%s${RESET}\n" "Температура" "N/A"
        fi
    else
        printf "${WHITE} │  ${CYAN}%-20s${RESET} : ${GREEN}%s${RESET}\n" "Температура" "N/A"
    fi
    
    mem_total=$(awk '/MemTotal/ {printf "%.1f MB", $2/1024}' /proc/meminfo)
    mem_free=$(awk '/MemAvailable/ {printf "%.1f MB", $2/1024}' /proc/meminfo)
    printf "${WHITE} │  ${CYAN}%-20s${RESET} : ${GREEN}%s${RESET}\n" "Память" "$mem_free / $mem_total"
    
    print_footer
}

# --- Пакеты Entware ------------------------------------------------------------
print_packages_info() {
    print_section "📦  ПАКЕТЫ ENTWARE"
    
    total=$(opkg list-installed 2>/dev/null | wc -l)
    printf "${WHITE} │  ${CYAN}%-20s${RESET} : ${GREEN}%s${RESET}\n" "Установлено" "$total"
    
    upgradable=$(opkg list-upgradable 2>/dev/null | wc -l)
    if [ "$upgradable" -gt 0 ]; then
        printf "${WHITE} │  ${CYAN}%-20s${RESET} : ${YELLOW}⚠️  %s${RESET}\n" "Доступно обновлений" "$upgradable"
    else
        printf "${WHITE} │  ${CYAN}%-20s${RESET} : ${GREEN}%s${RESET}\n" "Доступно обновлений" "0"
    fi
    
    print_footer
}

# --- Вывод списка сервисов (использует check_service_status) -------------------
print_services_status() {
    print_section "🔧  СЕРВИСЫ ENTWARE"
    
    local initd_dir="/opt/etc/init.d"
    local count=0
    local running=0
    
    # Заголовок таблицы
    printf "${WHITE} │  ${CYAN}%-20s${RESET}  ${GREEN}%-30s${RESET}  %s\n" "SERVICES" "STATUS" "DETAILS"
    printf "${WHITE} │  ${DIM}%-20s  %-30s  %s${RESET}\n" "--------------------" "------------------------------" "--------------------------------------------------"
    
    for script in $(ls -1 "$initd_dir"/S* 2>/dev/null | sort -V); do
        [ ! -x "$script" ] && continue
        
        count=$((count + 1))
        local raw_name=$(basename "$script")
        local display_name=$(format_service_name "$raw_name")
        
        # Используем унифицированную функцию для статуса
        local status_result=$(check_service_status "$script")
        local status_text=""
        local status_color=""
        
        if echo "$status_result" | grep -q "✅"; then
            status_text="$status_result"
            status_color="${GREEN}"
            running=$((running + 1))
        else
            status_text="❌ stopped"
            status_color="${RED}"
        fi
        
        # Получаем подробности (сырой вывод скрипта)
        local raw_status=$(get_service_details "$script")
        
        # Вывод в три колонки
        printf "${WHITE} │  ${CYAN}%-20s${RESET}  ${status_color}%-30s${RESET}  %s\n" "$display_name" "$status_text" "$raw_status"
    done
    
    if [ $count -eq 0 ]; then
        printf "${WHITE} │  ${YELLOW}⚠️  Нет сервисов в /opt/etc/init.d/${RESET}\n"
    else
        printf "${WHITE} │  \n${WHITE} │  ${DIM}Total: $count, Run: $running${RESET}\n"
    fi
    
    print_footer
}

# --- Меню ---------------------------------------------------------------------
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
    print_banner
    print_system_info
    print_packages_info
    print_services_status
}

# --- Основной запуск ----------------------------------------------------------
if [ "$1" = "menu" ]; then
    run_menu
    exit 0
fi

clear
print_system_info_new
#print_banner
#print_system_info
#print_packages_info
print_services_status
#printf "\n${DIM}💡 Введите ${WHITE}menu${DIM} для управления пакетами.${RESET}\n"
