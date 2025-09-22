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
- Docker Engine 24+ и Docker Compose Plugin v2 (устанавливаются ролью `docker`).

## Инсталляция / Ограничения сети

- **Force IPv4 для APT.** Роль `base` автоматически пишет `/etc/apt/apt.conf.d/99force-ipv4` с `Acquire::ForceIPv4 "true";`, чтобы избежать долгих таймаутов IPv6.
- **Fallback после неудачных `apt update`.** При ошибках Ansible выполняет `apt-get clean && rm -rf /var/lib/apt/lists/*` и повторяет `apt-get update -o Acquire::Retries=5`.
- **Установка Docker в оффлайн-/degraded-сетях.**
  - Переменная `use_official_docker_repo` (по умолчанию `true`) выбирает, использовать ли `download.docker.com`. При недоступности зеркала роль автоматически откатывается на пакет `docker.io` из стандартного репозитория.
  - Все URL репозиториев вынесены в `group_vars/all.yml` (`docker_official_repo_base`, `docker_repo_key_url`, `docker_repo_url`) и могут быть переназначены на локальные зеркала.
  - Если пакеты `docker-compose-plugin`/`docker-compose-v2` недоступны, роль ставит `docker-compose` (v1) и разворачивает shim в `/usr/lib/docker/cli-plugins/docker-compose`, перенаправляющий `docker compose` на бинарник v1.
  - При наличии установленного Docker роль можно пропустить флагом `--skip-tags docker`.
- **Предзагрузка образов.** Список образов и их версий хранится в `docker_image_cache` (`group_vars/all.yml`). Разместите заранее выгруженные тарболы в каталоге `images/` — роль загрузит их через `docker load` после копирования на хост.
- **Fail-fast с подсказками.** При сетевых ошибках задачи выводят рекомендации: переключиться на `docker.io`, проверить ForceIPv4 или использовать оффлайн-образы (`make images-cache`).

## RF-friendly install

Короткий чек-лист для развёртывания в ограниченных сетях:

1. Убедитесь, что ForceIPv4 включён (файл `/etc/apt/apt.conf.d/99force-ipv4` создаётся ролью `base`).
2. При необходимости установите Docker заранее (`docker.io`, `docker-compose-v2`) и запускайте `ansible-playbook ... --skip-tags docker`.
3. Переопределите `use_official_docker_repo=false` и/или `docker_official_repo_base` для внутренних зеркал.
4. (Опционально) На машине с доступом к интернету выполните `make images-cache`, перенесите каталог `images/` и убедитесь, что tar-архивы подхватываются автоматически.

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

- `site.yml` — точка входа; импортирует `playbooks/base.yml` и `playbooks/apps.yml`.
- `playbooks/base.yml` — подготовка хоста: снятие apt-lock, установка Docker Engine + compose-plugin (роль `docker`), создание сети `infra_internal` (роль `network`).
- `playbooks/apps.yml` — последовательный деплой сервисов: `private_ca` → `caddy` → `authentik` → `nextcloud` → `onlyoffice`.

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

