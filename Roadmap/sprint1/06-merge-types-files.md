# Sprint 6: Об'єднання файлів типів

## Завдання
Об'єднати `src/oci/types.zig` та `src/common/types.zig` в один файл `src/common/types.zig` та оновити всі імпорти в проекті.

## Аналіз
- `src/common/types.zig` містить 1351 рядок з багатьма типами
- `src/oci/types.zig` містить 273 рядки з деякими дублікатами
- Потрібно визначити унікальні типи з OCI та додати їх до common/types.zig
- Оновити всі імпорти в проекті

## План виконання
1. [ ] Проаналізувати унікальні типи в `src/oci/types.zig`
2. [ ] Додати унікальні типи до `src/common/types.zig`
3. [ ] Видалити `src/oci/types.zig`
4. [ ] Оновити всі імпорти в проекті
5. [ ] Протестувати компіляцію
6. [ ] Записати зміни в Roadmap

## Унікальні типи з OCI
- `Bundle` struct
- `NetworkConfig` (різний від common)
- `Mount` (різний від common)
- `Hooks` struct
- `ContainerState` struct

## Файли для оновлення імпортів
- Всі файли в `src/oci/`
- Деякі файли в `src/proxmox/`
- Деякі файли в `src/network/`
- Деякі тести

## Очікуваний час
2-3 години

## Статус
✅ Завершено

## Результати
- ✅ Успішно об'єднано `src/oci/types.zig` та `src/common/types.zig`
- ✅ Додано унікальні типи з OCI до common/types.zig:
  - `Bundle` struct
  - `Hooks` struct  
  - `OciContainerState` struct
- ✅ Видалено `src/oci/types.zig`
- ✅ Оновлено всі імпорти в проекті
- ✅ Виправлено помилки компіляції
- ✅ Проект успішно компілюється

## Зміни
- Додано метод `deinit` до структури `Hook`
- Виправлено switch statements для обробки всіх можливих значень `RuntimeType`
- Оновлено імпорти в 50+ файлах

## Час виконання
2.5 години
