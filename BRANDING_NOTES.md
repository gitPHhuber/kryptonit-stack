# Брендинг "НПК КРИПТОНИТ"

## Nextcloud
1. Включить **Theming** → задать имя/цвет/логотип.
2. Apps: `onlyoffice`, `files_fulltextsearch`, `talk` (по необходимости).
3. ONLYOFFICE URL: `https://{{ onlyoffice_fqdn }}`; Secret = `onlyoffice_jwt_secret`.

## Authentik
- Appearance: заголовок, логотип, favicon, цветовая схема.
- Создать OAuth2 Provider + Application для Nextcloud (SSO), затем включить Social Login в Nextcloud.

## OnlyOffice
- При необходимости подменить логотип через bind-mount и свой `local.json`.
