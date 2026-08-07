# TestFlight автозалив

Собирает и заливает новый билд в TestFlight одной командой — без Xcode
Organizer и без ручного логина в GUI. Подпись и загрузка идут headless через
App Store Connect API-ключ.

## Разовая настройка

### 1. Получить App Store Connect API-ключ

Ключ создаётся в App Store Connect, а не в Xcode:

1. Зайти на [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
   под аккаунтом с ролью **Admin** (или Account Holder).
2. **Users and Access** → вкладка **Integrations** → **App Store Connect API**.
3. Раздел **Team Keys** → **+** (Generate API Key).
   - Name: например `soma-ci`.
   - Access: **App Manager** (достаточно для сборок/TestFlight).
4. Скачать `.p8`-файл — **Apple даёт скачать его только один раз**. Сохранить в:
   ```
   ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
   ```
5. Записать два значения со страницы:
   - **Key ID** — рядом с ключом в списке (например `ABC123DEFG`).
   - **Issuer ID** — UUID вверху страницы, один на всю команду.

### 2. Прописать креды локально

```
cp scripts/asc-api.env.example scripts/asc-api.env
```
Заполнить `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` в `scripts/asc-api.env`.
Файл и `.p8` — в `.gitignore`, в публичный репозиторий не попадут.

## Использование

```
scripts/testflight.sh              # bump build +1, archive, upload в TestFlight
scripts/testflight.sh --no-bump    # не менять номер билда
scripts/testflight.sh --archive-only   # только собрать архив, без заливки
```

Скрипт бампает `CFBundleVersion` в `project.yml` (единственный источник
правды — из него XcodeGen генерит `Info.plist`), регенерит проект, архивит
Release и заливает. Обработка на стороне Apple — от пары минут до ~1 часа,
затем билд появляется во вкладке TestFlight.

Коммит бампа версии скрипт не делает — команду он печатает в конце.

## Автозалив при мерже в main (GitHub Actions, self-hosted)

`.github/workflows/testflight.yml` при каждом push/merge в `main` собирает
архив, заливает в TestFlight и коммитит новый build-номер обратно в `main`
(с `[skip ci]`, чтобы не зациклиться). Сборка идёт на **self-hosted раннере на
этом Mac** — здесь уже есть Xcode 26 и keychain с сертификатом подписи.

### Разовая настройка раннера

1. Установить и зарегистрировать self-hosted runner (нужны права на репо):
   GitHub → репозиторий **Settings → Actions → Runners → New self-hosted
   runner → macOS** и выполнить показанные команды (`./config.sh ...`,
   затем `./run.sh` или установить как сервис через `./svc.sh install`).
   Дефолтные метки раннера — `self-hosted`, `macOS` — совпадают с
   `runs-on: [self-hosted, macOS]` в workflow.
2. Сложить локальные секреты в стеш `~/.soma-ci` (свежий checkout раннера их
   не содержит — они в `.gitignore`):
   ```
   scripts/ci-stash-secrets.sh
   ```
   Копирует `Config-Debug.xcconfig`, `Config-Release.xcconfig`,
   `GoogleService-Info.plist`, `scripts/asc-api.env`. `.p8` не копируется —
   он читается по абсолютному пути из `asc-api.env`
   (`~/.appstoreconnect/private_keys/`).
3. Держать Mac включённым, залогиненным и с разблокированным keychain в
   момент мержа — иначе шаг подписи не пройдёт.

### Как это работает

- `DEVELOPER_DIR` в workflow принудительно указывает на Xcode 26 (без
  `sudo xcode-select`).
- Build-номер монотонно растёт: скрипт бампает `CFBundleVersion` в
  `project.yml`, а workflow коммитит это в `main` — так следующий запуск
  стартует уже с актуального числа.
- `concurrency` сериализует запуски, чтобы номера билдов не гонялись.

При смене любого секрета — перезапустить `scripts/ci-stash-secrets.sh`.
