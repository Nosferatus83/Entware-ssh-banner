# 🧾 Entware SSH Banner for (Keenetic / other Entware OS)

Универсальный баннер для SSH с отображением состояния системы, пакетов Entware и сервисов с их состоянием.

Объединяет наработки https://github.com/OMchik33/Keenetic-Entware-banner и https://github.com/byrekrut/custom-banner-ssh-Keenetic

## 📸 Preview

<p align="center">
  <img src="https://raw.githubusercontent.com/Nosferatus83/Entware-ssh-banner/main/demo_banner.jpg" width="600"/>
</p>
📦 Репозиторий:https://github.com/Nosferatus83/Entware-ssh-banner

---

## 📁 Состав

В репозитории:

* `custom-banner.sh` — основной баннер
* `setup_opkg_profile.sh` — установочный скрипт

---

## ⚡ Быстрая установка (1 команда)

```bash
cd /opt/root && wget -q https://raw.githubusercontent.com/Nosferatus83/Entware-ssh-banner/main/custom-banner.sh && wget -q https://raw.githubusercontent.com/Nosferatus83/Entware-ssh-banner/main/setup_opkg_profile.sh && sh setup_opkg_profile.sh
```

---

## ⚙️ Что делает установка

Скрипт автоматически:

* обновляет список пакетов (`opkg update`)
* устанавливает зависимости:

  * wget-ssl
  * whiptail
  * nano
* настраивает автозапуск баннера через `~/.profile`

Добавляется:

```bash
. /opt/etc/profile
. /opt/root/custom-banner.sh
```

---

## 🚀 Использование

После установки баннер будет запускаться автоматически при входе по SSH.

---

## ⚠️ Важно

❗ Установщик **перезаписывает файл**:

```bash
~/.profile
```

Если у тебя там были свои настройки — они будут удалены.

---

## ❌ Удаление

```bash
rm -f /opt/root/custom-banner.sh
```

И убрать из `~/.profile` строку:

```bash
. /opt/root/custom-banner.sh
```

---

## 🔧 Настройка

Добавление своего сервиса (в процессе описания):

---

## 📜 Лицензия

Free to use 😄
