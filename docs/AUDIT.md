# Полный аудит и технический паспорт проекта: Fishing Radar (FishRadar)

**Дата актуализации:** 19 ноября 2026  
**Версия приложения:** `0.1.0+1` (MVP, Android)  
**Статус:** Блок 1 (Карты и навигация) реализован, собран в Release APK и проверен на устройстве.

---

## 1. Концепция и цели (Vision)

* **Название:** Fishing Radar (на рабочем столе Android — `FishRadar`).
* **Тип:** Гиперлокальное мобильное приложение для рыбаков (UGC-карты глубин и точек клёва с офлайн-режимом).
* **Проблема:** Поиск рельефа дна (бровок, ям, коряжников) требует дорогого эхолота или платных карт. В местах рыбалки часто нет мобильного интернета.
* **Решение:** Краудсорсинговая (UGC) карта на базе OpenStreetMap + спутниковых снимков + OpenSeaMap, где пользователи отмечают глубины, структуру дна и уловы, записывают треки лодки, пользуются кольцами расстояний и могут заранее скачать участок карты в офлайн.
* **Целевая аудитория:** Спиннингисты (с лодки и с берега), карпятники, зимние рыбаки.
* **Конкуренты:** Dap Drift (платный), Клёвая рыбалка (соцсеть).
* **УТП:** Бесплатность, фокус на UGC-данные о глубинах и структуре дна, «Круги доверия» для защиты секретных мест, работа на воде без интернета.

---

## 2. Рабочий процесс разработки (КРИТИЧНО ДЛЯ ПРОДОЛЖЕНИЯ!)

Любой разработчик или ИИ, продолжающий этот проект, **обязан учитывать особенности рабочего процесса владельца**:

1. **Среда разработки:** всё редактирование кода ведётся **на Mac исключительно в браузере** — через веб-интерфейс GitHub (`github.com`) или веб-редактор `github.dev` (открывается клавишей `.` в репозитории).
2. **Отсутствие локального SDK:** у владельца нет локально настроенного Flutter SDK, Android Studio, терминала сборки и `adb logcat`. **Нельзя предлагать локальные CLI-команды** (`flutter pub get`, `flutter run`, `flutter analyze`, `git push` и т.д.).
3. **Проверка и сборка:** единственный контур проверки и сборки — **GitHub Actions** (`.github/workflows/android.yml`), который при каждом коммите в `main`/`master` запускает `flutter analyze --no-fatal-infos` и собирает `FishRadar.apk`.
4. **Формат выдачи изменений:** изменения нужно выдавать **полными готовыми файлами** с точным путём (`lib/...`), чтобы их можно было вставить через `Cmd+A` → `Cmd+V` в `github.dev` одним коммитом.
5. **Папка `android/` в репозитории не используется напрямую при сборке:**
   * В начале работы `.github/workflows/android.yml` выполняет `rm -rf android` и заново генерирует чистый проект через `flutter create --platforms=android --org ru.fishingradar --project-name fishing_radar`.
   * Поэтому любые разрешения в `AndroidManifest.xml`, название приложения, настройки движка и генерация иконок **должны прописываться в `.github/workflows/android.yml`**, а не в файлах внутри `android/`.
   * Наличие старых файлов в `android/` (`gradle.properties`, `local.properties`, `AndroidManifest.xml`, `styles.xml`) в репозитории — наследие ранних этапов; они игнорируются в CI.
6. **Обход блокировок/лимитов Maven Central в GitHub Actions:**
   * На раннерах `ubuntu-24.04` сборка Flutter Gradle (`project ':gradle'`) падала на загрузке Kotlin (`kotlin-stdlib`, `kotlin-gradle-plugins-bom`) через `plugins.gradle.org/m2` из-за ограничений `repo.maven.apache.org`.
   * Проблема решена в `android.yml` созданием `~/.gradle/init.d/maven-central-mirror.gradle` (перенаправляет Maven Central и `settingsEvaluated` на зеркало Google `https://maven-central.storage-download.googleapis.com/maven2/`). **Не удалять этот шаг из `android.yml`!**
7. **Генерация иконок и экрана запуска (Splash Screen):**
   * В репозитории хранится векторный исходник `assets/icon/fish_radar_icon.svg` (текстовый XML, легко меняется в браузере).
   * CI устанавливает `librsvg2-bin` (`rsvg-convert`) и на каждой сборке нарезает из этого SVG все `mipmap-*/ic_launcher.png`, адаптивную иконку (`mipmap-anydpi-v26/ic_launcher.xml` + `ic_launcher_foreground.png`), цвет фона из `<rect id="bg" ... fill="..."/>` и экран запуска `launch_background.xml`.
8. **Защита от белого экрана на Android:**
   * В `AndroidManifest.xml` (через `android.yml`) добавлен `<meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false" />`.
   * В `lib/main.dart` запуск `runApp()` сделан синхронным и неблокирующим (Supabase инициализируется асинхронно в фоне с таймаутом 4 сек), а также задан `ErrorWidget.builder`, чтобы ошибки в Release APK отображались текстом на тёмном фоне вместо пустого белого экрана.

---

## 3. Стек технологий

* **Flutter / Dart SDK:** `>=3.6.0 <4.0.0`, Material 3 (основной цвет `#006D77`).
* **Карты и геометрия:** `flutter_map: ^8.3.2`, `latlong2: ^0.10.1`.
* **Геолокация:** `geolocator: ^14.1.1`.
* **Бэкенд:** `supabase_flutter: ^2.18.3` (секреты `SUPABASE_URL`, `SUPABASE_KEY` передаются через `--dart-define`).
* **Локальное хранилище:** `shared_preferences: ^2.3.5`.
* **Форматирование дат:** `intl: ^0.20.2`.
* **Линтер:** `flutter_lints: ^5.0.0`.

*(Замечание по Flutter 3.47+: в логах `flutter analyze` могут появляться `info`-подсказки о грядущем переезде с `package:flutter/material.dart` на `package:material_ui/material_ui.dart`. На сборку они не влияют благодаря `--no-fatal-infos`, менять импорты сейчас не нужно.)*

---

## 4. Полная структура проекта и назначение файлов

```text
officier1973-hub-fishing-radar/
├── .github/
│   └── workflows/
│       └── android.yml                 # CI/CD: зеркало Gradle, иконки из SVG, сборка FishRadar.apk
├── android/                            # Наследие шаблона (удаляется и пересоздаётся в CI!)
│   ├── gradle.properties               # Не используется в CI
│   ├── local.properties                # Лишний пустой файл (рекомендуется удалить)
│   └── app/src/main/
│       ├── AndroidManifest.xml         # Перезаписывается в CI
│       └── res/values/styles.xml       # Перезаписывается в CI
├── assets/
│   └── icon/
│       └── fish_radar_icon.svg         # Векторный исходник иконки «Рыба на радаре» и цвета фона
├── docs/
│   └── AUDIT.md                        # Этот документ (полный технический паспорт и аудит)
├── lib/
│   ├── main.dart                       # Точка входа, ErrorWidget, тема, фоновый initSupabase
│   ├── models/
│   │   ├── fishing_spot.dart           # Модель рыболовной точки (глубина, дно, рыба, вес, приватность)
│   │   └── boat_track.dart             # Модель сохранённого GPS-трека лодки
│   ├── pages/
│   │   ├── map_page.dart               # Главный экран: карты, слои, треки, кольца, линейка, навигация
│   │   └── report_page.dart            # Экран добавления точки клёва / отчёта
│   ├── services/
│   │   ├── api_service.dart            # Работа с Supabase (RPC/INSERT) + офлайн-кеш точек
│   │   ├── location_service.dart       # Разрешения GPS, текущая позиция и поток координат
│   │   ├── track_service.dart          # Хранение истории треков и настроек слоёв карты
│   │   └── offline_map_service.dart    # 30-дневный дисковый кеш и скачивание тайлов района
│   └── widgets/
│       └── map_sheets.dart             # Нижние панели: слои/фильтры, офлайн-карты, треки + форматтеры
├── pubspec.yaml                        # Версия пакета, SDK, зависимости
└── README.md                           # Публичное описание проекта для главной страницы GitHub
