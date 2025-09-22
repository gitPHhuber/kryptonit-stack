# kryptonit-stack

Инфраструктурный плейбук Ansible, который "одной кнопкой" поднимает приватный стек для файлового обмена и совместной работы:

- **private-ca (step-ca)** — внутренний центр сертификации (ACME) для выпуска доверенных сертификатов.
- **Caddy** — единая внешняя точка входа с TLS и безопасными заголовками, автоматически запрашивает сертификаты у частного ЦС.
- **Authentik** — центр аутентификации (OIDC/SAML) и единый вход.
- **Nextcloud** — файловое хранилище с шарингом и WebDAV.
- **OnlyOffice DocumentServer** — онлайн-редактор документов из Nextcloud.

Все сервисы работают в Docker и общаются через общую изолированную сеть. Управление и развёртывание выполняются Ansible и Docker Compose v2.

## Requirements


### Контролирующая машина

- Linux/macOS/WSL с Python **3.10+**.
- Ansible **2.15+** (проверено с ansible-core 2.16).
- Установленные `ansible-lint`, `yamllint`, `pre-commit` (для локального lint'а, см. ниже).
- Python-библиотека [`docker`](https://pypi.org/project/docker/) (клиент для коллекции `community.docker`). Рекомендуется установить в виртуальное окружение: `python3 -m venv .venv && source .venv/bin/activate`, затем `pip install --upgrade pip docker`.

### Управляемые узлы

- Linux с systemd. Для локального сценария достаточно одной машины с Docker.
- Доступ root (через `sudo` без пароля или заранее настроенный `become`-метод).
- Свободные порты 80/443/9000 и ресурсы для контейнеров (CPU/RAM/диск).
- Docker Engine 24+ и Docker Compose Plugin 2.x (роль `docker` устанавливает при необходимости).

> **Важно:** роли управляют контейнерами через CLI `docker compose`. Убедитесь, что установлен [Docker Compose Plugin v2](https://docs.docker.com/compose/install/linux/) и бинарь `docker` доступен в `PATH`.

Порт `9000` используется контейнером private-ca. Откройте его только для доверенной внутренней сети — весь TLS-трафик пользователей по-прежнему идёт через 443 порт Caddy.

## Install collections and roles

Все команды ниже выполняйте из корня репозитория:

```bash
make deps
# команда оставлена для совместимости и просто подтвердит,
# что внешние коллекции не требуются
ansible-galaxy collection install -r requirements.yml
```

Все роли используют только модули из `ansible.builtin`. Файл `requirements.yml`
оставлен пустым, чтобы `ansible-galaxy` мог отработать без доступа в интернет.

При использовании `pre-commit` выполните один раз:

```bash
pipx install pre-commit
pre-commit install
```

## Inventories and variables

- `inventory/local.ini` — одиночная машина (`ansible_connection=local`). Это значение используется по умолчанию (см. [`ansible.cfg`](ansible.cfg)).
- `inventory/prod/hosts.ini` — пример для удалённых хостов. Замените FQDN/IP и пользователей под свою инфраструктуру.

Переключить инвентарь можно переменной `INVENTORY` (`make run INVENTORY=inventory/prod/hosts.ini`) или флагом `-i` Ansible.

Глобальные переменные заданы в [`group_vars/all.yml`](group_vars/all.yml).
Ключевые параметры для приватного ЦС и прокси:

- `private_ca_hostname` — доменное имя центра сертификации (используется при инициализации step-ca).
- `internal_ca_url` — ACME-директория, к которой обращается Caddy.
- `private_ca_root_cert_path` — путь к корневому сертификату на прокси-хосте.

Для локальной разработки подготовлены несекретные значения по умолчанию:

- [`group_vars/dev/vars.yml`](group_vars/dev/vars.yml) содержит заглушки для паролей Authentik/Nextcloud/OnlyOffice и `private_ca_password`,
  а также отключает автоматический HTTPS в Caddy (`caddy_proxy_auto_https: false`).
- [`group_vars/dev/vault.yml`](group_vars/dev/vault.yml) — пример зашифрованного файла для тех случаев, когда хочется использовать Vault и на dev.

Секреты вынесены по окружениям и должны храниться в Vault-файлах:

- `group_vars/dev/vault.yml` — пример зашифрованного файла для локального сценария.
- `group_vars/prod/vault.yml` — зашифрованный шаблон с заглушками.

## Vault secrets

Для работы с зашифрованными переменными используйте один из способов:

- интерактивно: `ansible-playbook ... --ask-vault-pass`;
- файл пароля: создайте `~/.vault_pass.txt` с содержимым пароля и передавайте `--vault-password-file ~/.vault_pass.txt`.

Все Vault-файлы должны начинаться с заголовка `$ANSIBLE_VAULT;`. Держите в них только секреты (пароли БД, токены и т.п.), а публичные значения оставляйте в обычных YAML.

## Repository layout

- `site.yml` — точка входа, импортирует playbooks по слоям.
- `playbooks/base.yml` — базовая подготовка хостов (Docker и общая сеть).
- `playbooks/apps.yml` — прикладные роли (private-ca, Caddy, Authentik, Nextcloud, OnlyOffice).
- `roles/*` — роли приведены к стандартному skeleton'у (`tasks/`, `defaults/`, `handlers/`, `templates/`, `files/`, `vars/`, `meta/`).

## Run

Запуск локального окружения (одна машина):

```bash
make run
# или напрямую
ansible-playbook site.yml
```

> Если целевой пользователь не имеет passwordless sudo, добавьте `--ask-become-pass`
> или задайте `ansible_become_password` через Vault/переменные окружения.

Запуск на другом инвентаре:

```bash
INVENTORY=inventory/prod/hosts.ini make run
INVENTORY=inventory/prod/hosts.ini ansible-playbook -i "$INVENTORY" site.yml
```

> Если вы запускаете команды из подкаталога (например, `playbooks/`), используйте относительные пути: `ansible-playbook -i ../inventory/local.ini ../site.yml`.

Типичный порядок выполнения:

1. Установить Docker Engine и создать сеть `infra_internal`.
2. Развернуть private-ca — он сгенерирует корневой сертификат и поднимет ACME-эндпоинт `https://private-ca:9000/acme/acme/directory`.
3. Развернуть Caddy, который автоматически получит TLS-сертификаты у private-ca.
4. Поднять Authentik (Postgres, Redis, server, worker).
5. Поднять Nextcloud (MariaDB, Redis, web, cron).
6. Поднять OnlyOffice DocumentServer.

После успешного запуска сервисы будут доступны по адресам `https://auth.infra.local`, `https://cloud.infra.local` и `https://office.infra.local` (добавьте записи в DNS или `/etc/hosts`). Корневой сертификат внутреннего ЦС сохраняется на прокси-хосте в `/opt/private-ca/config/certs/root_ca.crt` и автоматически скачивается на управляющую машину в `branding/assets/root_ca.crt`. Передайте этот файл администраторам рабочих станций и установите в доверенные корневые хранилища.

## Private CA и доверенные сертификаты

Роль `private_ca` разворачивает [smallstep step-ca](https://smallstep.com/docs/step-ca) в Docker и публикует ACME-эндпоинт для Caddy. Основные настройки (домены, пути, URL ACME) находятся в `group_vars/all.yml`, а секрет `private_ca_password` обязательно задаётся через Vault для каждого окружения.

### Алгоритм внедрения

1. **Задайте пароль ЦС.** Добавьте переменную `private_ca_password` (не короче 12 символов) в `group_vars/<env>/vault.yml` и зашифруйте файл.
2. **Разверните плейбук.** После первого запуска private-ca сформирует каталоги `/opt/private-ca/…`, запустит контейнер и выгрузит корневой сертификат в `branding/assets/root_ca.crt` на управляющей машине.
3. **Распространите доверие.** Используйте `branding/assets/root_ca.crt`, чтобы централизованно установить сертификат в доверенные корневые центры сертификации (GPO/MDM/Ansible).
4. **Настройте внутренний DNS.** Все сервисные домены (`auth.infra.local`, `cloud.infra.local`, `office.infra.local`, `ca.infra.local`) должны указывать на IP reverse-прокси, а запись `private-ca` — на тот же хост для выдачи сертификатов по ACME.

После этого браузеры будут без предупреждений принимать сертификаты, выпущенные Caddy через внутренний ACME. Дополнительную копию корня всегда можно получить с прокси-хоста: `scp proxyhost:/opt/private-ca/config/certs/root_ca.crt branding/assets/root_ca.crt`.

## Quality checks

Перед пушем прогоняйте линтеры:

```bash
make lint
# или через pre-commit
pre-commit run --all-files
```

CI-пайплайн [.github/workflows/lint.yml](.github/workflows/lint.yml) автоматически запускает `yamllint` и `ansible-lint` на каждом push/PR.

## Troubleshooting

- **option `inventory` already exists:** Ansible читает несколько источников инвентаря одновременно. Убедитесь, что в `ansible.cfg` указан только один `inventory`, и не передавайте такой же путь флагом `-i`. Для дефолтного окружения запускайте `ansible-playbook site.yml` или `make run` без дополнительных параметров.
- **Failed to lock apt /var/lib/apt/lists:** автоматические обновления могут удерживать блокировки APT. В `playbooks/base.yml` добавлены `pre_tasks`, которые мягко ждут освобождение блокировок и переподнимают `dpkg`. Если пишете собственные роли, используйте аналогичный приём.
- **`community.docker` требует python docker:** клиент Docker для Python должен быть установлен на контроллере. Создайте виртуальное окружение и поставьте зависимости: `python3 -m venv .venv && source .venv/bin/activate`, затем `pip install --upgrade pip docker` и `make deps`.
- **Vault:** проверьте пароль (`--ask-vault-pass` или файл). Для разных окружений удобно держать отдельные файлы паролей.
- **SSH/локальный режим:** в `inventory/local.ini` используется `ansible_connection=local`, поэтому SSH не требуется. Для удалённых хостов настройте ключи и пользователя (`ansible_user`).
- **Become:** если sudo требует пароль, задайте `ansible_become_password` через vault или используйте `--ask-become-pass`.
- **Python facts:** ошибки вида `MODULE FAILURE` могут означать отсутствие Python 3 на целевом хосте — установите `python3` вручную или задайте `ansible_python_interpreter`.
- **Docker compose:** при ошибках вида `docker: 'compose' is not a docker command` установите плагин Docker Compose v2 и убедитесь, что бинарь `docker` доступен в `PATH`.

Дополнительную информацию ищите в официальной документации Ansible: [docs.ansible.com](https://docs.ansible.com/) и Docker Compose: [docs.docker.com/compose](https://docs.docker.com/compose/).

