# kryptonit-stack

Инфраструктурный плейбук Ansible, который "одной кнопкой" поднимает приватный стек для файлового обмена и совместной работы:

- **Caddy** — единая внешняя точка входа с TLS и безопасными заголовками.
- **Authentik** — центр аутентификации (OIDC/SAML) и единый вход.
- **Nextcloud** — файловое хранилище с шарингом и WebDAV.
- **OnlyOffice DocumentServer** — онлайн-редактор документов из Nextcloud.

Все сервисы работают в Docker и общаются через общую изолированную сеть. Управление и развёртывание выполняются Ansible и Docker Compose v2.

## Требования

- Linux-хост с системd, доступный по SSH.
- Установленный Docker не требуется — роль `docker` сама установит движок и создаст общую сеть.
- Ansible 9+ на рабочей станции (установится автоматически через `make bootstrap`).

Подтяните коллекции перед запуском:

```bash
make deps
```

## Секреты

Все чувствительные значения хранятся в `group_vars/secrets.vault.yml`. Файл уже зашифрован через Ansible Vault. Структура переменных следующая (пример в открытом виде):

```yaml
ak_db_password: "supersecret"
ak_secret_key: "django-secret-key"
ak_bootstrap:
  email: "admin@example.com"
  password: "change-me"
  token: ""
authentik_redis_password: "redis-pass"

nc_db_root_password: "rootpass"
nc_db_password: "nextcloudpass"
# при необходимости можно переопределить nc_db_user и nc_db_name

onlyoffice_jwt_secret: "jwt-secret"
```

Отредактируйте файл через `ansible-vault edit group_vars/secrets.vault.yml`.

Если хотите сначала обойтись без Vault, плейбук сам сгенерирует временные секреты и сложит их на управляющей машине в каталоге `~/.cache/kryptonit-stack`. Удалите файлы внутри, чтобы выпустить новые значения, либо перенесите их в Vault для постоянного использования.

## Инвентарь и домены

По умолчанию все сервисы ставятся на localhost (см. `ansible/inventory.ini`).
В `group_vars/all.yml` задаются FQDN и имя общей docker-сети (`docker_infra_network`).
Caddy слушает 80/443 и проксирует к внутренним контейнерам по их именам.
Для каталогов Nextcloud используется пользователь `www-data`; при необходимости переопределите `nextcloud_fs_owner` и `nextcloud_fs_group` в инвентаре.

## Запуск

```bash
make run
```

Плейбук выполнит следующие шаги:

1. Установит Docker Engine и создаст сеть `infra_internal`.
2. Развернёт Caddy с подготовленным `Caddyfile` и health-check'ами.
3. Поднимет Authentik (Postgres, Redis, server, worker).
4. Поднимет Nextcloud (MariaDB, Redis, web, cron) и подготовит конфиг Redis.
5. Поднимет OnlyOffice DocumentServer.

После успешного запуска сервисы будут доступны по адресам `https://auth.infra.local`, `https://nextcloud.infra.local` и `https://office.infra.local` (добавьте записи в DNS/`/etc/hosts`).

## Полезные команды

- Обновить контейнеры конкретного сервиса: `make run PLAYBOOK_OPTS="--tags nextcloud"`.
- Посмотреть логи Caddy: `docker logs caddy`.
- Проверить состояние сети: `docker network inspect infra_internal`.

> **Важно:** убедитесь, что DNS имена указывают на хост, где запущен Caddy, иначе браузер не сможет найти сервисы.
