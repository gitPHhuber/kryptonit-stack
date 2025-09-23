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

## Работа с Docker-образами

Стек разворачивается в два этапа:

1. **Режим `fetch` (онлайн).** На машине с доступом в реестры выполните `make fetch-images`. Плейбук `playbooks/images-fetch.yml` подтянет требуемые образы и сохранит их в локальный кэш `images/*.tar`.
2. **Режим `offline`.** Перенесите каталог `images/` на контроллер в закрытом сегменте (если требуется). Выполните `make load-images` — плейбук `playbooks/images-load.yml` загрузит тарболы на целевой хост и выполнит `docker load` для каждого образа.
3. **Запуск стека.** После загрузки образов запустите `make stack-up` (или `make run`). Плейбук `playbooks/stack-up.yml` выполнит префлайт и стартует все сервисы, не обращаясь к реестрам.

Перечень образов и имена тарболов задаются в `group_vars/all.yml` в переменной `offline_images_catalog`. При необходимости можно добавить собственные сервисы, дополнив список и роли.

## Быстрый старт

1. Склонируйте репозиторий и установите зависимости коллекций:
   ```bash
   make deps
   ```
2. (Опционально) Подготовьте secrets в `group_vars/dev/vault.yml` или зашифруйте свои значения через `ansible-vault`.
3. В режиме онлайн выполните `make fetch-images` и убедитесь, что в каталоге `images/` появились тарболы.
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
│  ├─ images-fetch.yml
│  ├─ images-load.yml
│  └─ stack-up.yml
├─ branding/
├─ images/
├─ Makefile
└─ README.md
```

## Плейбуки

- `playbooks/images-fetch.yml` — режим `fetch`, подтягивает образы и сохраняет их в `images/*.tar`.
- `playbooks/images-load.yml` — режим `offline`, копирует тарболы на целевой хост и выполняет `docker load`.
- `playbooks/stack-up.yml` — запуск всего стека (префлайт → сеть → сервисы) без доступа к интернету.

## Makefile

- `make deps` — установка требуемых коллекций Ansible.
- `make lint` — запуск `yamllint` и `ansible-lint`.
- `make fetch-images` — режим fetch.
- `make load-images` — загрузка образов на хост.
- `make stack-up` / `make run` — запуск стека.
- `make vault` — редактирование Vault-файла с секретами.

## Примечания

- Роль `preflight` проверяет наличие Docker/Compose и свободные порты, но не устанавливает пакеты.
- Роли сервисов используют только офлайн-предзагруженные образы и `community.docker.docker_compose_v2`.
- Для обновления версий образов измените значения в `group_vars/all.yml`, перезапустите `make fetch-images`, затем `make load-images` и `make stack-up`.
