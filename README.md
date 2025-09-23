# kryptonit-stack

Инфраструктурный проект для офлайн-первого развёртывания приватного стека
сервисов (step-ca, Caddy, Authentik, Nextcloud и OnlyOffice) с помощью
Ansible и Docker Compose v2. Основная идея — подготовить весь набор Docker-
образов заранее, а затем запускать стек в полностью изолированном сегменте
без обращения к реестрам и пакетным менеджерам.

## Требования

### Контролирующая машина

- Python 3.10+, ansible-core 2.15+ (проверено с ansible-core 2.16).
- Коллекции Ansible: `community.docker`, `ansible.posix`, `community.general`
  (устанавливаются через `make deps`).
- Docker CLI с доступом в интернет для режима `fetch`.
- Возможность запускать `ansible-playbook` без установки системных пакетов —
  проект не выполняет `apt`, `dnf` и аналогичные команды.

### Управляемый хост

- Подготовленный вручную Docker Engine 24+ и Docker Compose Plugin v2.
- Доступ по SSH от контроллера с правами `root` (passwordless sudo или
  `--ask-become-pass`).
- Свободные порты 80, 443 и 9000.
- Достаточно дискового пространства для образов и данных сервисов.

Проект **не** устанавливает и не обновляет системные пакеты, не добавляет
репозитории и не пытается развернуть Docker — все зависимости должны быть
готовы до запуска Ansible.

## Конфигурация

Основные переменные заданы в `group_vars/all.yml`:

- `offline_images_cache_dir` — каталог с .tar на машине контроллера (по
  умолчанию `./images`).
- `offline_images_target_dir` — путь на управляемом хосте
  (`/opt/kryptonit-stack/images`).
- `offline_images_catalog` — список словарей `{image, archive_name}` для
  каждого контейнера стека.
- `offline_images_force_fetch` — перезаписывать ли кэш при повторном запуске
  режима `fetch`.
- `kryptonit_mode` — текущий режим (`fetch` или `offline`), по умолчанию
  `offline`.

Пример описания каталога образов:

```yaml
offline_images_catalog:
  - image: "smallstep/step-ca:0.27.3"
    archive_name: step-ca_0.27.3.tar
  - image: "caddy:2.7"
    archive_name: caddy_2.7.tar
```

Команда `make fetch-images` создаёт файл `manifest.json` и набор
`*.sha256` в каталоге кэша. Manifest представляет собой список записей вида
`{"image": "repo:tag", "archive": "name.tar", "checksum": "sha256"}` и
используется в офлайн-режиме для проверки целостности.

Секреты (пароли БД, JWT и т.п.) храните в `group_vars/<env>/vault.yml`,
шифруя их через `ansible-vault` (`make vault`).

## Офлайн-первый процесс

1. **Установка зависимостей (один раз на контроллере).**
   ```bash
   make deps
   ```
2. **Подготовка кэша образов (режим `fetch`, требуется интернет).**
   ```bash
   make fetch-images
   ```
   Плейбук `playbooks/images-fetch.yml` проверит доступность Docker, скачает
   образы из реестров, сохранит их в `offline_images_cache_dir`, сформирует
   `manifest.json`, `manifest.json.sha256` и отдельные файлы с чек-суммами
   `*.tar.sha256`. При повторном запуске существующие архивы не
   перезаписываются, если не установлен флаг `offline_images_force_fetch`.
3. **Перенос кэша.** Скопируйте каталог `images/` (или указанный в
   `offline_images_cache_dir`) на машину с ограниченным доступом.
4. **Загрузка образов на управляемый хост (режим `offline`).**
   ```bash
   make load-images
   ```
   Плейбук `playbooks/images-load.yml` проверит наличие manifest и каждого
   tar-архива, сверит контрольные суммы, скопирует файлы в
   `offline_images_target_dir` и выполнит `docker load` для всех образов.
   При отсутствии файла или несоответствии checksum выполнение завершится
   понятной ошибкой.
5. **Запуск стека из локальных образов.**
   ```bash
   make stack-up        # эквивалентно make run
   ```
   Плейбук `playbooks/stack-up.yml` запускает роль `preflight`: проверяет
   режим `kryptonit_mode`, версии Docker/Compose, состояние демона, доступность
   портов и наличие всех требуемых образов локально. Затем создаётся общая
   сеть и разворачиваются сервисы. Все `docker compose` определения используют
   `pull_policy: never`, поэтому сетевые обращения к реестрам исключены.

После успешного запуска будут доступны:

- https://auth.infra.local — Authentik
- https://cloud.infra.local — Nextcloud
- https://office.infra.local — OnlyOffice (через Caddy)

Корневой сертификат step-ca сохраняется в
`/opt/private-ca/config/certs/root_ca.crt` и копируется на контроллер в
`branding/assets/root_ca.crt` для последующего распространения.

## Управление сервисами

- Остановить или удалить конкретный сервис можно стандартными командами
  Docker Compose, например `docker compose -p caddy down`.
- Для просмотра логов используйте `docker compose -p <project> logs -f` или
  `docker logs <container>`.

## Makefile

- `make deps` — установка необходимых коллекций Ansible.
- `make lint` — `yamllint` + `ansible-lint --offline`.
- `make fetch-images` — режим fetch, подготовка кэша образов и manifest.
- `make load-images` — копирование и загрузка образов на управляемый хост.
- `make stack-up` / `make run` — полный запуск стека в офлайн-режиме.
- `make vault` — редактирование Vault-файла с секретами.

## FAQ

**Нужно ли вводить пароль от sudo?**
: По умолчанию в `inventory/local.ini` включён `ansible_become=true`. Если на
  целевом хосте требуется пароль, запускайте playbook с `--ask-become-pass`.
  Для сброса кэша sudo-пароля можно предварительно выполнить `sudo -K`.

**Где взять пароль от Vault?**
: Храните его отдельно и передавайте в `ansible-playbook` через
  `--vault-password-file` или `--ask-vault-pass`. Команда `make vault`
  автоматически откроет `group_vars/dev/vault.yml` для редактирования.

**Нужно ли править `/etc/hosts`?**
: Для локального тестирования добавьте записи вида
  `127.0.0.1 auth.infra.local cloud.infra.local office.infra.local private-ca`
  на машину, с которой обращаетесь к сервисам.

**Как доверять приватному центру сертификации?**
: Импортируйте файл `branding/assets/root_ca.crt` в доверенные корневые
  сертификаты ОС и браузеров пользователей.

**Можно ли отключить проверки диска и swap?**
: Да. Переменная `preflight_enable_disk_checks` в `group_vars/all.yml`
  управляет запуском дополнительных проверок. По умолчанию они отключены.

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
│  │  └─ tasks/{fetch.yml,load.yml}
│  ├─ preflight/
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
