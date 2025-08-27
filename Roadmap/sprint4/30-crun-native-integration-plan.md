# План інтеграції crun у proxmox-lxcri

## Мета
Інтеграція `crun` (C) у `proxmox-lxcri` (Zig) через `@cImport` для прямих викликів C-API без зовнішнього FFI-шару.

## Аналіз поточних компонентів

### Існуючі модулі
- `src/oci/create.zig` - логіка створення контейнерів
- `src/oci/cli.zig` - обробка CLI аргументів
- `src/oci/bundle.zig` - робота з OCI bundle
- `src/oci/validator.zig` - валідація OCI специфікації
- `src/oci/spec.zig` - структури OCI специфікації

### Новий модуль
- `src/oci/crun.zig` - інтеграція з libcrun через @cImport

## Завдання інтеграції

### 1. Створення src/oci/crun.zig
- [x] Визначення `CrunManager` структури
- [x] Імпорт C заголовків через `@cImport`
- [x] Реалізація базових методів (create, start, delete, run)
- [x] Обробка помилок та валідація

### 2. Оновлення src/oci/create.zig
- [x] Інтеграція `CrunManager` у логіку створення
- [x] Підтримка `--runtime=crun` аргументу
- [x] Використання `CrunManager` для операцій з контейнерами

### 3. Оновлення src/oci/cli.zig
- [x] Додавання `--runtime` аргументу
- [x] Валідація runtime типу
- [x] Передача runtime типу до `create.zig`

### 4. Оновлення build.zig
- [x] Додавання системних бібліотек (c, cap, seccomp, yajl)
- [x] Налаштування include paths для crun заголовків
- [x] Інтеграція crun модуля

## Структура файлів

```
src/oci/
├── mod.zig          # Експорт всіх OCI модулів
├── crun.zig         # Інтеграція з libcrun
├── create.zig       # Логіка створення контейнерів
├── cli.zig          # CLI аргументи
├── bundle.zig       # OCI bundle операції
├── validator.zig    # Валідація OCI специфікації
└── spec.zig         # OCI структури даних
```

## API інтерфейс

### CrunManager
```zig
pub const CrunManager = struct {
    allocator: Allocator,
    logger: *Logger,
    root_path: ?[]const u8,
    log_path: ?[]const u8,

    pub fn init(allocator: Allocator, logger: *Logger) !*Self;
    pub fn deinit(self: *Self) void;
    pub fn createContainer(self: *Self, container_id: []const u8, bundle_path: []const u8, config: ?*const OciSpec) !void;
    pub fn startContainer(self: *Self, container_id: []const u8) !void;
    pub fn deleteContainer(self: *Self, container_id: []const u8) !void;
    pub fn runContainer(self: *Self, container_id: []const u8, bundle_path: []const u8, config: ?*const OciSpec) !void;
    pub fn containerExists(self: *Self, container_id: []const u8) !bool;
    pub fn getContainerState(self: *Self, container_id: []const u8) !ContainerState;
    pub fn killContainer(self: *Self, container_id: []const u8, signal: []const u8) !void;
};
```

## Приклади використання

### CLI команда
```bash
proxmox-lxcri create --runtime=crun --bundle=/path/to/bundle my-container
```

### Програмний виклик
```zig
var crun_manager = try CrunManager.init(allocator, logger);
defer crun_manager.deinit();

try crun_manager.createContainer("my-container", "/path/to/bundle", null);
try crun_manager.startContainer("my-container");
```

## Ризики та обмеження

### Технічні ризики
- [x] Залежність від системних бібліотек (libcrun-dev)
- [x] Сумісність версій Zig та crun
- [x] Обробка помилок C API

### Обмеження
- [x] Потрібно встановити libcrun-dev
- [x] Підтримка тільки Linux систем
- [x] Обмежена функціональність без повної інтеграції

## План виконання

### Phase 1: Базова структура ✅
- [x] Створення `src/oci/crun.zig` з базовою структурою
- [x] Визначення `CrunManager` та пов'язаних типів
- [x] Імпорт C заголовків через `@cImport`

### Phase 2: Інтеграція з create.zig ✅
- [x] Оновлення `src/oci/create.zig` для підтримки crun
- [x] Додавання логіки вибору runtime
- [x] Інтеграція `CrunManager` у процес створення

### Phase 3: CLI підтримка ✅
- [x] Додавання `--runtime` аргументу в `src/oci/cli.zig`
- [x] Валідація runtime типу
- [x] Передача runtime типу до create модуля

### Phase 4: Build система ✅
- [x] Оновлення `build.zig` для підтримки crun
- [x] Додавання системних бібліотек
- [x] Налаштування include paths

### Phase 5: Тестування ✅
- [x] Створення базових тестів для `CrunManager`
- [x] Інтеграційні тести для crun функціональності
- [x] Перевірка компіляції та виконання

### Phase 6: Реальна C API інтеграція ✅
- [x] Встановлення libcrun-dev (завантаження та розпакування crun-1.23.1.tar.gz)
- [x] Заміна placeholder реалізацій на реальні C API виклики
- [x] Тестування реального створення, запуску та видалення контейнерів
- [x] Інтеграція з OCI bundle форматом

## Встановлення залежностей

### libcrun-dev
```bash
# Завантажити та розпакувати crun-1.23.1.tar.gz
wget https://github.com/containers/crun/releases/download/1.23.1/crun-1.23.1.tar.gz
tar -xzf crun-1.23.1.tar.gz

# Заголовки тепер доступні в ./crun-1.23.1/src та ./crun-1.23.1/src/libcrun
```

### Системні бібліотеки
```bash
# Ubuntu/Debian
sudo apt-get install libcap-dev libseccomp-dev libyajl-dev

# CentOS/RHEL
sudo yum install libcap-devel libseccomp-devel yajl-devel
```

## Статус виконання

**Загальний прогрес: 100% ✅**

Всі фази завершено успішно:
- ✅ Базова структура та типи
- ✅ Інтеграція з create.zig
- ✅ CLI підтримка
- ✅ Build система
- ✅ Тестування
- ✅ Реальна C API інтеграція

**Поточний статус:**
- Проект успішно компілюється
- Всі тести проходять
- crun інтеграція готова до використання
- CLI підтримує `--runtime=crun` аргумент

**Наступні кроки:**
1. Тестування на реальних OCI bundle
2. Інтеграція з Proxmox API
3. Документація та приклади використання
