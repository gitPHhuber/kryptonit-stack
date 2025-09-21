# kryptonit-stack

Инфраструктурный плейбук Ansible, который "одной кнопкой" поднимает приватный стек для файлового обмена и совместной работы:

- **Caddy** — единая внешняя точка входа с TLS и безопасными заголовками.
- **Authentik** — центр аутентификации (OIDC/SAML) и единый вход.
- **Nextcloud** — файловое хранилище с шарингом и WebDAV.
- **OnlyOffice DocumentServer** — онлайн-редактор документов из Nextcloud.

Все сервисы работают в Docker и общаются через общую изолированную сеть. Управление и развёртывание выполняются Ansible и Docker Compose v2.

## Requirements

Контролирующая машина:

- Linux/macOS/WSL с Python **3.10+**.
- Ansible **2.15+** (проверено с ansible-core 2.16).
- `ansible-lint`, `yamllint`, `pre-commit` (для локального lint'а, см. ниже).

Управляемые узлы:

- Linux с systemd и доступом по SSH.
- Возможность выполнять `sudo` без пароля (либо настройте become-метод).
- Свободные порты 80/443 для Caddy и порты, которые используют сервисы внутри сети Docker.
- Поддерживается Debian/Ubuntu (роль `docker` устанавливает Docker Engine 24+ и Docker Compose Plugin 2.x).

> **Важно:** модули коллекции [`community.docker`](https://docs.ansible.com/ansible/latest/collections/community/docker/) требуют установленного Docker Engine на целевых хостах и Python-пакета `docker` на контрол-ноде. Роль `docker` ставит движок и Compose, но Python-модуль нужно установить самостоятельно (например, `pip install docker` в виртуальном окружении Ansible).

## Install collections and roles

Сначала установите коллекции и роли, указанные в [`requirements.yml`](requirements.yml):

```bash
make deps
# либо вручную
ansible-galaxy collection install -r requirements.yml
```

При использовании `pre-commit` выполните один раз:

```bash
pipx install pre-commit
pre-commit install
```

## Inventories and variables

Инвентарь разделён по окружениям:

- `inventory/dev/hosts.ini` — localhost-сценарий по умолчанию.
- `inventory/prod/hosts.ini` — пример для реальных хостов, замените FQDN/IP и пользователей.

Запуск по умолчанию использует `inventory/dev/hosts.ini` (см. [`ansible.cfg`](ansible.cfg)). Для переключения окружения передайте путь к инвентарю через переменную `INVENTORY` или флаг `-i`.

Глобальные переменные лежат в [`group_vars/all.yml`](group_vars/all.yml).
Секреты и чувствительные данные разделены по окружениям и должны храниться в Vault-файлах:

- `group_vars/dev/vault.yml` — пример зашифрованного файла (редактировать через `ansible-vault edit`).
- `group_vars/prod/vault.yml` — зашифрованный шаблон с заглушками; перезашифруйте с реальными данными перед деплоем (`ansible-vault edit` или `ansible-vault encrypt --output group_vars/prod/vault.yml …`).

Внутри Vault держите пароли БД, JWT, bootstrap-токены и др. значения. Для единичных секретов можно использовать `ansible-vault encrypt_string` прямо в переменных.

## Repository layout

- `playbooks/base.yml` — базовая подготовка хостов (Docker и общая сеть).
- `playbooks/apps.yml` — прикладные роли (Caddy, Authentik, Nextcloud, OnlyOffice).
- `roles/*` — роли приведены к стандартному skeleton'у (`tasks/`, `defaults/`, `handlers/`, `templates/`, `files/`, `vars/`, `meta/`).
- `site.yml` — точка входа, импортирует playbooks по слоям.

## Run

Dev-окружение (localhost):

```bash
make run
```

Запуск на другом инвентаре:

```bash
make run INVENTORY=inventory/prod/hosts.ini
# или без Makefile
ansible-playbook -i inventory/prod/hosts.ini site.yml
```

Типичный порядок выполнения:

1. Установить Docker Engine и создать сеть `infra_internal`.
2. Развернуть Caddy с подготовленным `Caddyfile` и health-check'ами.
3. Поднять Authentik (Postgres, Redis, server, worker).
4. Поднять Nextcloud (MariaDB, Redis, web, cron) и сгенерировать конфиг Redis.
5. Поднять OnlyOffice DocumentServer.

После успешного запуска сервисы будут доступны по адресам `https://auth.infra.local`, `https://cloud.infra.local` и `https://office.infra.local` (добавьте записи в DNS или `/etc/hosts`).

## Quality checks

Перед пушем прогоняйте линтеры:

```bash
make lint
# или через pre-commit
pre-commit run --all-files
```

CI-пайплайн [.github/workflows/lint.yml](.github/workflows/lint.yml) автоматически запускает `yamllint` и `ansible-lint` на каждом push/PR.

## Troubleshooting

- **Vault:** убедитесь, что используете правильный пароль/файл vault-id. Для разных окружений удобно держать отдельные файлы паролей.
- **SSH:** при `Permission denied` проверьте пользователя и ключи в инвентаре (`ansible_user`, `ansible_ssh_private_key_file`).
- **Become:** если sudo требует пароль, задайте `ansible_become_password` через vault или используйте `--ask-become-pass`.
- **Python facts:** ошибки вида `MODULE FAILURE` могут означать отсутствие Python 3 на целевом хосте — установите `python3` вручную или используйте `ansible_python_interpreter`.
- **Docker collection:** при ошибках `Failed to import docker` установите пакет `docker` на контрол-ноде и убедитесь, что Docker daemon доступен на управляемых хостах.

## Дополнительно

- Для обновления контейнеров отдельного сервиса используйте теги, например: `ansible-playbook -i <inventory> playbooks/apps.yml --tags nextcloud`.
- Шаблоны Jinja в `roles/*/templates/` не должны содержать дефолтных паролей — всё чувствительное храните в Vault.
- Изучите официальную документацию Ansible: [docs.ansible.com](https://docs.ansible.com/) и коллекции [community.docker](https://docs.ansible.com/ansible/latest/collections/community/docker/index.html).
