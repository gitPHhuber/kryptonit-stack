# kryptonit-stack

Инфраструктурный репозиторий для автоматического развёртывания приватного стека сервисов (private-ca, Caddy, Authentik, Nextcloud, OnlyOffice) с помощью Ansible и Docker Compose v2.

## Состав стека

| Сервис | Назначение | Особенности |
| --- | --- | --- |
| **smallstep/step-ca** | Внутренний центр сертификации с ACME-эндпоинтом `https://private-ca:9000/acme/acme/directory`. | Генерирует корневой сертификат, хранит его на хосте и выгружает в `branding/assets/root_ca.crt`. |
| **Caddy** | Единая точка входа, выдаёт TLS-сертификаты через private-ca. | Работает в сети `infra_internal`, может отключать автоматический HTTPS (dev). |
| **Authentik** | IdP и единый вход. | Контейнеры server/worker + PostgreSQL и Redis. |
| **Nextcloud** | Файловое хранилище. | Контейнеры web/cron + MariaDB и Redis. |
| **OnlyOffice DocumentServer** | Совместное редактирование документов из Nextcloud. | JWT секрет для интеграции хранится в Vault. |

Все контейнеры подключены к общей docker-сети `infra_internal` и настроены с `restart: unless-stopped`.

## Требования

### Контролирующая машина

- Python 3.10+ и Ansible 2.15+ (проверено с ansible-core 2.16).
- Установленные `ansible-lint`, `yamllint`, `docker` (Python-библиотека) для коллекции `community.docker`.
- Доступ в интернет для загрузки Docker образов.

### Управляемый хост

- Ubuntu/Debian с systemd.
- root-доступ (passwordless sudo или `--ask-become-pass`).
- Порты 80, 443 и 9000 свободны.
- Docker Engine 24+ и Docker Compose Plugin v2 (должны быть установлены вручную до запуска плейбуков).

## Инсталляция / Ограничения сети

- **Docker и Compose — внешний предусловие.** Плейбуки не управляют пакетами хоста. Убедитесь, что на целевой машине уже установлены совместимые версии Docker Engine и Docker Compose Plugin, и сервис Docker запущен.
- **Предзагрузка образов.** Включите `use_offline_images: true`, положите сохранённые `docker save` тарболы в локальный каталог `images/` и скопируйте их на таргет `/opt/kryptonit/images`. Роль `offline_images` выполнит `docker load -i` для каждого архива.
- **Префлайт перед сервисами.** Роль `preflight` проверяет доступность Docker/Compose, свободные порты 80/443, объём свободного места на `/` и сообщает об отключённом swap.

## RF-friendly install

Короткий чек-лист для развёртывания в ограниченных сетях:

1. Установите Docker Engine и Compose Plugin из доступного источника (заранее, вручную или через собственный playbook/скрипт).
2. Убедитесь, что требуемые Docker-образы доступны: либо в публичном реестре, либо подготовлены архивы для `use_offline_images: true`.
3. При полностью закрытом интернете сохраните нужные образы через `docker save -o images/<name>.tar`, перенесите их в каталог `images/` и включите `use_offline_images: true`.

## Быстрый старт

1. Склонируйте репозиторий и установите зависимости коллекций:
   ```bash
   make deps
   ```
2. Настройте секреты в `group_vars/dev/vault.yml` (для локальной проверки уже есть заглушки; в production зашифруйте файл `ansible-vault` и обновите значения в `group_vars/prod/vault.yml`).
3. (Локально) Добавьте записи в `/etc/hosts`:
   ```text
   127.0.0.1 auth.infra.local cloud.infra.local office.infra.local private-ca
   ```
4. Запустите развёртывание:
   ```bash
   make run
   ```
   По умолчанию используется `inventory/local.ini`. Для другого окружения задайте переменную `INVENTORY`, например `make run INVENTORY=inventory/prod/hosts.ini`.

После успешного выполнения будут доступны:
- https://auth.infra.local — Authentik
- https://cloud.infra.local — Nextcloud
- https://office.infra.local — OnlyOffice (через Caddy)

Корневой сертификат внутреннего ЦС сохраняется на хосте (`/opt/private-ca/config/certs/root_ca.crt`) и автоматически копируется на управляющую машину в `branding/assets/root_ca.crt`. Раздайте этот файл пользователям и установите в доверенные корневые сертификаты ОС/браузеров.

## Структура плейбуков

- `site.yml` — единый плей, который выполняет роли в порядке: `offline_images` → `preflight` → сервисные роли (`network`, `private_ca`, `caddy`, `authentik`, `nextcloud`, `onlyoffice`).
- При необходимости можно ограничить запуск отдельных ролей через теги.

## Переменные и секреты

- Общие параметры (домены, URL ACME, имена контейнеров) — в `group_vars/all.yml`.
- Секреты (пароли БД, Redis, JWT, ключи Authentik) — только в Vault-файлах `group_vars/<env>/vault.yml`.
  - `group_vars/dev/vault.yml` содержит примерные значения для локального запуска и отключает автоматический HTTPS в Caddy.
  - `group_vars/prod/vault.yml` — шаблон; перед использованием зашифруйте `ansible-vault` и замените значения.

## Makefile

- `make deps` — установка необходимых коллекций (`community.docker`, `ansible.posix`, `community.general`).
- `make run` — запуск `ansible-playbook` с выбранным инвентарём (по умолчанию `inventory/local.ini`).
- `make lint` — локальный запуск `yamllint` и `ansible-lint`.
- `make images-cache` — выгрузка Docker-образов из `docker_image_cache` в каталог `images/` (требуется Docker на контролирующей машине).

## Примечания по эксплуатации

- Роль `private_ca` инициализирует step-ca только при первом запуске; последующие прогоны idempotent.
- `caddy` ожидает доступности ACME-эндпоинта перед стартом (если включён автоматический HTTPS).
- Все роли используют `community.docker.docker_compose_v2` и внешнюю сеть `infra_internal`.
- Корневой сертификат публикуется в `branding/assets/root_ca.crt` автоматически; храните его в системе контроля версий **только** для демонстрации. Для production рекомендуется хранить артефакт вне репозитория.

## Полезные команды

```bash
make lint                      # прогнать yamllint + ansible-lint
ansible-playbook site.yml -vvv # отладочный запуск
ansible-vault edit group_vars/dev/vault.yml
```

## CI

`.github/workflows/lint.yml` запускает `yamllint` и `ansible-lint` на каждый push/PR. Убедитесь, что локальные линтеры проходят перед коммитом.

