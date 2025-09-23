# kryptonit-stack

Инфраструктурный репозиторий для офлайн-первого развёртывания приватного стека сервисов (private-ca, Caddy, Authentik, Nextcloud, OnlyOffice) с помощью Ansible и Docker Compose v2.

## Состав стека

| Сервис | Назначение | Особенности |
| --- | --- | --- |
| **smallstep/step-ca** | Внутренний центр сертификации с ACME-эндпоинтом `https://private-ca:9000/acme/acme/directory`. | Генерирует корневой сертификат, сохраняет его на хосте и публикует в `branding/assets/root_ca.crt`. |
| **Caddy** | Реверс-прокси и единая точка входа. | Выдаёт TLS-сертификаты через private-ca, слушает 80/443. |
| **Authentik** | IdP и SSO. | Контейнеры server/worker + PostgreSQL и Redis. |
| **Nextcloud** | Файловое хранилище. | Контейнеры web/cron + MariaDB и Redis. |
| **OnlyOffice DocumentServer** | Совместное редактирование документов из Nextcloud. | JWT-секрет хранится в Vault. |

Все контейнеры подключены к общей Docker-сети `infra_internal` и запускаются с политикой `restart: unless-stopped`.

## Требования

### Контролирующая машина

- Python 3.10+, ansible-core 2.15+ (проверено с ansible-core 2.16).
- Коллекции Ansible: `community.docker`, `ansible.posix`, `community.general` (устанавливаются через `make deps`).
- Docker CLI с доступом в интернет для режима `fetch`.

### Управляемый хост

- Debian/Ubuntu с systemd.
- Root-доступ (passwordless sudo или `--ask-become-pass`).
- Установленные Docker Engine 24+ и Docker Compose Plugin v2 **вручную** до запуска плейбуков.
- Свободные порты 80, 443 и 9000.
- Доступ по SSH от контроллера.

Проект **не** выполняет установку пакетов, не управляет репозиториями и не пытается ставить Docker. Все системные зависимости должны быть подготовлены заранее.

## Конфигурация

- `group_vars/all.yml` — базовые параметры стека: домены, имена сервисов, переменные для Docker Compose и каталог `offline_images_catalog` с перечнем образов и имён архивов.
- `group_vars/dev/vault.yml` (или собственный Vault-файл) — секреты: пароли БД, JWT, bootstrap-данные Authentik. Редактируются через `make vault`.
- `offline_images_cache_dir` — локальный каталог кэша (по умолчанию `./images` относительно плейбука). Здесь появляются `.tar`, `manifest.json` и `.sha256`.
- `offline_images_target_dir` — директория на управляемом хосте, куда копируются тарболы перед загрузкой (`/opt/kryptonit-stack/images`).
- `offline_images_manifest_filename` — имя manifest-файла (по умолчанию `manifest.json`).
- `preflight_enable_disk_checks` — включает/отключает дополнительные проверки диска и swap (по умолчанию `false`).

## Работа с Docker-образами

Роль `offline_images` поддерживает два режима работы, выбираемые переменной `mode` (значение по умолчанию — `fetch`). Управляющий плейбук `playbooks/images.yml` запускает соответствующие задачи:

- `mode=fetch` — выполняет `docker pull` для каждого элемента каталога, сохраняет архивы (`*.tar`) в кэш, формирует `manifest.json` с полями `{image, archive, checksum}` и создаёт `.sha256`-файлы. Повторный запуск пропускает уже существующие архивы, если не установлен флаг `offline_images_force_fetch`.
- `mode=offline` — проверяет наличие `manifest.json` и всех объявленных архивов, сверяет контрольные суммы, копирует тарболы на управляемый хост, выполняет `docker load` и ретегирует образы согласно каталогу. Никаких сетевых запросов к реестрам не выполняется.

Плейбуки и роли не выполняют установку пакетов, работают только с уже доступным Docker/Compose и выводят сводки по количеству обработанных образов.

## Сценарии запуска

### 1. Подготовка кэша образов (mode=fetch)

```bash
make fetch-images
```

- Проверяет доступность Docker на контролирующей машине.
- Выполняет `docker pull` для каждого элемента `offline_images_catalog`.
- Сохраняет образы в `offline_images_cache_dir` в виде `*.tar`, обновляет `manifest.json` и создаёт `*.sha256`.
- В выводе отображается сводка «Images in catalog / Saved / Skipped».

Передайте `offline_images_force_fetch=true`, чтобы принудительно обновить существующие архивы.

### 2. Доставка кэша на изолированную машину (mode=offline)

Перенесите каталог кэша (по умолчанию `images/`) на контроллер, который управляет изолированной средой, затем выполните:

```bash
make load-images
```

- Проверяет доступность Docker на целевом хосте.
- Подтверждает наличие `manifest.json`, всех `.tar` и корректность их контрольных сумм.
- Копирует архивы в `offline_images_target_dir` и загружает их локально через `docker load` без обращения в реестры.
- Выводит сводку «Images prepared / Loaded / Skipped».

### 3. Запуск стека из локальных образов

```bash
make stack-up   # или make run
```

Плейбук `playbooks/stack-up.yml` выполняет:

1. Префлайт-проверки (`roles/preflight`): наличие Docker/Compose, свободные порты `80`, `443`, `9000`, при необходимости — дисковое пространство и swap.
2. Создание общей сети Docker (`roles/network`).
3. Развёртывание сервисов (private-ca, Caddy, Authentik, Nextcloud, OnlyOffice). Каждая роль использует только локальные образы и не запускает `docker pull`.

### 4. Остановка и диагностика

- Остановить сервисы: `docker compose -p <project> down` (например, `docker compose -p caddy down`) либо `docker stop <container>` для единичных контейнеров.
- Просмотреть логи: `docker compose -p <project> logs -f <service>` или `docker logs <container>`.
- Удалить образы при необходимости: `docker image rm <tag>`.

## Быстрый старт

1. Склонируйте репозиторий и установите зависимости коллекций:
   ```bash
   make deps
   ```
2. (Опционально) Подготовьте secrets в `group_vars/dev/vault.yml` или зашифруйте свои значения через `ansible-vault`.
3. В режиме онлайн выполните `make fetch-images` и убедитесь, что в каталоге `images/` появились `.tar`, `manifest.json` и файлы `*.sha256`.
4. Настройте SSH-доступ к целевому хосту и при необходимости добавьте записи в `/etc/hosts` на рабочей станции:
   ```text
   127.0.0.1 auth.infra.local cloud.infra.local office.infra.local private-ca
   ```
5. Загрузите образы и запустите стек:
   ```bash
   make load-images
   make stack-up        # эквивалентно make run
   ```

После успешного выполнения будут доступны сервисы:
- https://auth.infra.local — Authentik
- https://cloud.infra.local — Nextcloud
- https://office.infra.local — OnlyOffice (через Caddy)

Корневой сертификат приватного ЦС сохраняется на хосте (`/opt/private-ca/config/certs/root_ca.crt`) и автоматически копируется на управляющую машину в `branding/assets/root_ca.crt`. Установите его в доверенные корневые сертификаты пользователей.

## Структура репозитория

```
kryptonit-stack/
├─ inventory/
│  └─ local.ini
├─ group_vars/
│  └─ all.yml
├─ roles/
│  ├─ offline_images/
│  │  ├─ defaults/main.yml
│  │  └─ tasks/
│  │     ├─ fetch.yml
│  │     └─ load.yml
│  ├─ network/
│  ├─ private_ca/
│  ├─ caddy/
│  ├─ authentik/
│  ├─ nextcloud/
│  └─ onlyoffice/
├─ playbooks/
│  ├─ images.yml
│  ├─ images-fetch.yml
│  ├─ images-load.yml
│  └─ stack-up.yml
├─ branding/
├─ images/
├─ Makefile
└─ README.md
```

## Плейбуки

- `playbooks/images.yml` — единая точка входа для работы с образом; переменная `mode` переключает сценарий (`fetch` или `offline`).
- `playbooks/images-fetch.yml` и `playbooks/images-load.yml` — обёртки над ролью `offline_images`, оставлены для совместимости и запускают соответствующие задачи напрямую.
- `playbooks/stack-up.yml` — запуск всего стека (префлайт → сеть → сервисы) без доступа к интернету.

## Makefile

- `make deps` — установка требуемых коллекций Ansible.
- `make lint` — запуск `yamllint` и `ansible-lint`.
- `make fetch-images` — режим `fetch` (`ansible-playbook playbooks/images.yml -e mode=fetch`).
- `make load-images` — режим `offline` (`ansible-playbook playbooks/images.yml -e mode=offline`).
- `make stack-up` / `make run` — запуск стека.
- `make vault` — редактирование Vault-файла с секретами.

## Примечания

- Роль `preflight` проверяет наличие Docker/Compose и свободные порты, но не устанавливает пакеты.
- Роли сервисов используют только офлайн-предзагруженные образы и `community.docker.docker_compose_v2`.
- Для обновления версий образов измените значения в `group_vars/all.yml`, перезапустите `make fetch-images`, затем `make load-images` и `make stack-up`.

## FAQ

- **Нужно ли делать `sudo -K` перед запуском?** Не требуется, достаточно иметь доступ с `sudo` (или настроить безпарольный sudo). При выполнении плейбуков используется `become`, поэтому Ansible сам запросит пароль, если необходимо.
- **Где хранится пароль от Vault?** Файл `group_vars/dev/vault.yml` зашифрован Ansible Vault. Используйте `make vault` или `ansible-vault view/edit` с вашим паролем. Пароль Vault не хранится в репозитории.
- **Нужно ли прописывать домены в `/etc/hosts`?** Для локального тестирования добавьте записи `auth.infra.local`, `cloud.infra.local`, `office.infra.local`, `private-ca` на рабочей станции. В боевой среде настройте DNS соответствующим образом.
- **Как доверять приватному ЦС?** После запуска роль `private_ca` копирует корневой сертификат в `branding/assets/root_ca.crt`. Распространите его пользователям и импортируйте в доверенные корневые хранилища ОС/браузеров.
- **Можно ли отключить дополнительные проверки (диск, swap)?** Да, установите `preflight_enable_disk_checks=false` (значение по умолчанию). При включении роли выполняют idempotent-проверки и выводят понятные ошибки.
