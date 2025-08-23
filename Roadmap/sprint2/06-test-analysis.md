# Аналіз тестів проекту

## Дата: $(date)

## Поточний стан тестів

### Тести, які включені в build.zig:
1. **config_test.zig** - тест конфігурації
2. **test_create.zig** - тест створення контейнерів

### Тести, які НЕ включені в build.zig, але імпортуються в tests/main.zig:
1. **test_hooks.zig** - тест хуків (залежить від видаленого src/oci/hooks.zig)
2. **test_api_and_connection.zig** - тест API та з'єднань
3. **test_lxc.zig** - тест LXC функціональності
4. **test_network.zig** - тест мережевої функціональності
5. **test_storage.zig** - тест сховища
6. **test_container.zig** - тест контейнерів
7. **test_container_state.zig** - тест стану контейнерів
8. **test_oci_spec.zig** - тест OCI специфікації
9. **security/test_security.zig** - тест безпеки
10. **integration/test_concurrency.zig** - тест конкурентності
11. **tests/oci/mod.zig** - модуль OCI тестів
12. **tests/network/dns_test.zig** - тест DNS (не існує)
13. **tests/network/port_forward_test.zig** - тест пробросу портів
14. **tests/network/cni_test.zig** - тест CNI
15. **tests/runtime/mod.zig** - модуль runtime тестів (не існує)
16. **tests/cri/runtime/service_test.zig** - тест CRI сервісу

## Проблеми:

### 1. Тести залежать від видалених файлів:
- `test_hooks.zig` → `src/oci/hooks.zig` (видалено)
- `test_create.zig` → `src/container/image_manager.zig` (видалено)
- `test_create.zig` → `src/container/crun.zig` (видалено)
- `test_create.zig` → `src/container/lxc.zig` (видалено)

### 2. Неіснуючі файли в tests/main.zig:
- `tests/network/dns_test.zig` - не існує
- `tests/runtime/mod.zig` - не існує

### 3. Тести, які не можуть запуститися:
- Всі тести, які залежать від видалених модулів
- Тести, які посилаються на неіснуючі файли

## Рекомендації:

### 1. Очистити tests/main.zig:
- Видалити імпорти неіснуючих файлів
- Видалити імпорти тестів, які залежать від видалених модулів
- Залишити тільки робочі тести

### 2. Оновити build.zig:
- Видалити залежності від видалених модулів
- Залишити тільки робочі тести
- Додати нові тести для функціональності, яка залишилася

### 3. Створити нові тести:
- Тести для OCI команд (stop, list, info)
- Тести для Proxmox клієнта
- Тести для мережевої функціональності (якщо потрібно)

## План дій:

1. **Етап 1**: Очистити tests/main.zig від неіснуючих та неробочих тестів
2. **Етап 2**: Оновити build.zig, видаливши залежності від видалених модулів
3. **Етап 3**: Створити нові тести для залишеної функціональності
4. **Етап 4**: Перевірити, що всі тести запускаються успішно

## Файли для видалення:

### Тести, які залежать від видалених модулів:
- `tests/test_hooks.zig`
- `tests/test_create.zig`
- `tests/network/port_forward_test.zig`
- `tests/network/cni_test.zig`
- `tests/oci/create_test.zig`
- `tests/oci/runtime_test.zig`

### Тести, які посилаються на неіснуючі файли:
- `tests/test_storage.zig` (залежить від ZFS)
- `tests/zfs/` (весь каталог)

## Файли для збереження:

### Робочі тести:
- `tests/config_test.zig` - тест конфігурації
- `tests/test_oci_spec.zig` - тест OCI специфікації
- `tests/test_container_state.zig` - тест стану контейнерів
- `tests/test_container.zig` - базовий тест контейнерів
- `tests/test_lxc.zig` - тест LXC функціональності
- `tests/test_network.zig` - тест мережевої функціональності
- `tests/test_api_and_connection.zig` - тест API
- `tests/security/test_security.zig` - тест безпеки
- `tests/integration/test_concurrency.zig` - тест конкурентності
