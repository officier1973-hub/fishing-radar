# Полный аудит и технический паспорт проекта: Fishing Radar (FishRadar)

**Дата актуализации:** 20 ноября 2026  
**Версия приложения:** `0.2.0+2` (MVP+, Android)  
**Текущий этап:** Реализованы и доведены до рабочего состояния **Блок 1 (Карты и навигация)**, **Вариант 0 (надёжность в полевых условиях)** и **Блок 2 (UGC и социализация)**.

---

## 1. Концепция и цели (Vision)

* **Название:** Fishing Radar (на рабочем столе Android — `FishRadar`).
* **Тип:** Гиперлокальное мобильное приложение для рыбаков (UGC-карты глубин, точек клёва и комьюнити).
* **Проблема:** Поиск рельефа дна (бровок, ям, коряжников) требует дорогого эхолота или платных карт, а на воде часто пропадает мобильная связь.
* **Решение:** Картографическое приложение с подложками карты и спутника, водными знаками, зонами глубин и линиями свалов между промерами, дифференцированной тепловой картой клёва, записью фоновых GPS-треков, «Кругами доверия» (серверное скрытие точных координат от чужих), фото-отчётами, региональными чатами в реальном времени и офлайн-режимом (30-дневный кеш карт + очередь синхронизации точек).
* **Целевая аудитория:** Спиннингисты (с лодки и с берега), карпятники, зимние рыбаки.
* **Конкуренты:** Dap Drift (платный), Клёвая рыбалка (соцсеть).
* **УТП:** Бесплатность, фокус на UGC-данные о глубинах и перепадах дна, защита секретных мест («Круги доверия»), полноценная работа на воде без интернета.

---

## 2. Рабочий процесс и критичные правила CI/CD (ОБЯЗАТЕЛЬНО К ПРОЧТЕНИЮ!)

Любой разработчик или ИИ, продолжающий этот проект, **обязан учитывать следующие правила**:

1. **Разработка только в браузере на Mac:** весь код редактируется через веб-интерфейс GitHub (`github.com`) или веб-редактор `github.dev` (клавиша `.` в репозитории).
2. **Нет локального SDK:** у владельца нет локально установленных Flutter SDK, Android Studio, терминала сборки и `adb`. **Запрещено предлагать локальные команды** (`flutter pub get`, `flutter run`, `flutter analyze`, `git push` и т.п.).
3. **Единственный контур проверки и сборки — GitHub Actions (`.github/workflows/android.yml`):** при каждом коммите в `main`/`master` CI запускает `flutter analyze --no-fatal-infos` и собирает `FishRadar.apk`.
4. **Формат выдачи кода:** обновления выдаются **строго по 1–2 полных файла за сообщение** с точными путями (`lib/...`) и пошаговой инструкцией (`Cmd+A` → `Backspace` → **Копировать** → `Cmd+V` + проверка последней строки), чтобы ничего не обрезалось при вставке в браузере.
5. **Правило текстов интерфейса:** в UI приложения и публичном `README.md` **не упоминать названия `OSM` и `OpenSeaMap`** — использовать формулировки «Карта», «Спутник», «Водные знаки и фарватер».
6. **Папка `android/` в репозитории не участвует в сборке:**
   * В начале `.github/workflows/android.yml` выполняется `rm -rf android` и заново генерируется чистый проект через `flutter create --platforms=android --org ru.fishingradar --project-name fishing_radar`.
   * Все разрешения (`INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `WAKE_LOCK`, `POST_NOTIFICATIONS`, `CAMERA`), имя `FishRadar`, `EnableImpeller=false` и генерация иконок прописываются **только в `.github/workflows/android.yml`**.
   * Старые файлы внутри `android/` в репозитории — наследие шаблона (игнорируются CI).
7. **Обязательна Java 21 в CI (не понижать до 17!):**
   * Flutter `3.50.0` (канал `stable` на `ubuntu-24.04`) использует Android Gradle Plugin `9.3.x`, анализатор которого (`lintVitalAnalyzeRelease`, в частности на `:image_picker_android`) вызывает `java.util.List.removeLast()` из JDK 21. На JDK 17 сборка падает с `NoSuchMethodError`. В `android.yml` должна стоять **`java-version: '21'`** (`temurin`).
8. **Зеркала Gradle в CI (не удалять и не менять порядок!):**
   * На раннерах `ubuntu-24.04` загрузка Kotlin-артефактов внутри `project ':gradle'` падает на редиректах `plugins.gradle.org` → `repo.maven.apache.org` (403/429).
   * В `android.yml` настроен `~/.gradle/init.d/maven-central-mirror.gradle`.
   * **Критичный порядок в `settingsEvaluated`:** сначала зеркало Google (`maven-central.storage-download.googleapis.com`), затем зеркало JetBrains (`cache-redirector.jetbrains.com/maven-central`), затем `gradlePluginPortal()` и зеркало портала плагинов JetBrains (`cache-redirector.jetbrains.com/plugins.gradle.org/m2`), и **строго последним** `mavenCentralBehindMirror` (`repo.maven.apache.org`).
9. **Генерация иконок и экрана запуска из SVG:**
   * Векторный исходник лежит в `assets/icon/fish_radar_icon.svg` (Вариант 1 «Ночной эхолот»: фон `#041E2B`, бирюзовые кольца `#00E5FF`, золотая рыба `#FFB703`).
   * В CI утилита `rsvg-convert` (`librsvg2-bin`) генерирует `mipmap-*/ic_launcher.png`, адаптивный `ic_launcher_foreground.png` (убирая `<rect id="bg".../>`), цвет фона `colors.xml` и экран запуска `launch_background.xml`.
10. **Защита от белого экрана на Android:**
    * В `AndroidManifest.xml` (через `android.yml`) выставлен `EnableImpeller = false`.
    * В `lib/main.dart` вызов `runApp()` выполняется синхронно, `ApiService.initSupabase()` идёт в фоне с таймаутом 5 сек, а `ErrorWidget.builder` показывает текст ошибки на тёмном фоне вместо пустого белого экрана.

---

## 3. Стек технологий

* **Flutter / Dart SDK:** Flutter `stable` (`3.50.0` в CI), Dart `>=3.6.0 <4.0.0`, Material 3 (`seedColor: #006D77`).
* **CI Java / Android:** Temurin JDK 21, AGP 9.3.x, `ubuntu-24.04`.
* **Карты и геометрия:** `flutter_map: ^8.3.2`, `latlong2: ^0.10.1`.
* **Геолокация:** `geolocator: ^14.1.1` (`AndroidSettings` + `ForegroundNotificationConfig` для фонового трекинга).
* **Фото:** `image_picker: ^1.1.2`.
* **Бэкенд:** `supabase_flutter: ^2.18.3` (Auth, PostgREST, RPC, Realtime Channels, Storage; ключи `SUPABASE_URL`, `SUPABASE_KEY` через `--dart-define`).
* **Локальное хранилище:** `shared_preferences: ^2.3.5`.
* **Даты и линт:** `intl: ^0.20.2`, `flutter_lints: ^5.0.0`.

*(Замечание по Flutter 3.47+: `flutter analyze` выводит `info` о депрекации `package:flutter/material.dart` в пользу `package:material_ui/material_ui.dart` — сборке не мешает благодаря `--no-fatal-infos`.)*

---

## 4. Полная структура проекта и назначение файлов

```text
officier1973-hub-fishing-radar/
├── .github/
│   └── workflows/
│       └── android.yml                 # CI/CD: JDK 21, зеркала Gradle, права, иконки из SVG, FishRadar.apk
├── android/                            # Наследие шаблона (удаляется и пересоздаётся в CI при сборке)
│   ├── gradle.properties               # Не используется в CI
│   ├── local.properties                # Лишний пустой файл (рекомендуется удалить)
│   └── app/src/main/
│       ├── AndroidManifest.xml         # Перезаписывается в CI
│       └── res/values/styles.xml       # Перезаписывается в CI
├── assets/
│   └── icon/
│       └── fish_radar_icon.svg         # Векторный исходник иконки приложения и цвета фона
├── docs/
│   └── AUDIT.md                        # Этот документ (технический паспорт и аудит)
├── supabase/
│   └── schema.sql                      # SQL-схема Supabase: таблицы, RPC со скрытием координат, бакет фото, чат
├── lib/
│   ├── main.dart                       # Точка входа, ErrorWidget, тема, неблокирующий initSupabase
│   ├── models/
│   │   ├── fishing_spot.dart           # Модель точки клёва (точные/публичные координаты, фото, владелец, синк)
│   │   ├── boat_track.dart             # Модель сохранённого GPS-трека лодки
│   │   └── chat_message.dart           # Модель сообщения регионального чата
│   ├── pages/
│   │   ├── map_page.dart               # Главный экран карты: слои, свалы глубин, heatmap, треки, линейка, курс
│   │   ├── report_page.dart            # Экран создания и редактирования точки клёва + выбор фото
│   │   ├── auth_page.dart              # Вход/регистрация по email, быстрый гостевой вход и профиль
│   │   └── chat_page.dart              # Чаты по водоёмам (Realtime + переподключение после сна экрана)
│   ├── services/
│   │   ├── api_service.dart            # Auth, Storage фото, CRUD точек, очередь синка, нормализация URL, чат
│   │   ├── location_service.dart       # Права GPS, текущая позиция, фоновый трекинг Android, настройки
│   │   ├── track_service.dart          # Локальное хранение треков лодки и настроек слоёв/фильтров карты
│   │   └── offline_map_service.dart    # 30-дневный кеш тайлов, подсчёт кеша, 2-фазная загрузка с отчётом ошибок
│   └── widgets/
│       └── map_sheets.dart             # Панели слоёв/фильтров, офлайн-карт (с этапами загрузки) и треков
├── pubspec.yaml                        # Версия 0.2.0+2, зависимости и настройки пакета
└── README.md                           # Публичное описание проекта для GitHub
