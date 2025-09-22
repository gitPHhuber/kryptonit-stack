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

- **Apt-bootstrap под деградировавшие сети.** Роль `bootstrap_apt` временно останавливает `packagekit`/`apt-daily*`, включает `Acquire::ForceIPv4 "true";` при `force_ipv4_for_apt: true`, очищает кэш и выполняет `apt-get update` с таймаутом `apt_timeout_sec` и ретраями `apt_retries`.
- **Установка Docker с fallback.**
  - `use_official_docker_repo: false` (значение по умолчанию в `group_vars/all.yml`) переключает установку на системный пакет `docker.io`.
  - При `use_official_docker_repo: true` используется `download.docker.com` (URL и канал `docker_repo_channel` можно переопределить).
  - Docker Compose v2 берётся из пакета `docker-compose-v2`; если его нет, роль автоматически ставит `python3-pip`, `pip install docker-compose` и создаёт shim `/usr/lib/docker/cli-plugins/docker-compose`, перенаправляющий на бинарник v1.
  - Для пропуска роли используйте `--skip-tags docker`.
- **Предзагрузка образов.** Включите `use_offline_images: true`, положите сохранённые `docker save` тарболы в локальный каталог `images/` и скопируйте их на таргет `/opt/kryptonit/images`. Роль `offline_images` выполнит `docker load -i` для каждого архива.
- **Префлайт перед сервисами.** Роль `preflight` проверяет доступность Docker/Compose, свободные порты 80/443, объём свободного места на `/` и сообщает об отключённом swap.

## RF-friendly install

Короткий чек-лист для развёртывания в ограниченных сетях:

1. Оставьте `force_ipv4_for_apt: true`, чтобы APT всегда ходил по IPv4.
2. Используйте `use_official_docker_repo: false`, чтобы ставить Docker из `docker.io`. При наличии локального зеркала можно включить официальный репозиторий и заменить `docker_official_repo_base`/`docker_repo_channel`.
3. Docker Compose v2 ставится автоматически; если пакет недоступен, shim создастся сам и будет вызывать `pip`-версию `docker-compose`.
4. При полностью закрытом интернете сохраните нужные образы через `docker save -o images/<name>.tar` и установите `use_offline_images: true`.
5. Если Docker уже установлен вручную, запускайте Ansible с `--skip-tags docker`.

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

- `site.yml` — единый плей, который выполняет роли в порядке: `bootstrap_apt` → `docker` → `offline_images` → `preflight` → сервисные роли (`network`, `private_ca`, `caddy`, `authentik`, `nextcloud`, `onlyoffice`) → `bootstrap_apt_teardown`.
- При необходимости можно ограничить запуск отдельных ролей через теги (например, `--skip-tags docker`).

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

