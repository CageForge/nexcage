# Технічне завдання: Вбудована інтеграція `crun` (C) у `proxmox-lxcri` (Zig)

**Дата**: 26 серпня 2025  
**Статус**: 🚧 **В РОЗРОБЦІ**  
**Пріоритет**: Високий  
**Складність**: Середня  

---

## 1. Мета

Інтегрувати підтримку `crun` в існуючу структуру команди `create` та каталог `src/oci/` через `@cImport`, забезпечивши безпосереднє використання C-API `libcrun` у коді Zig.

---

## 2. Аналіз поточної структури

### 2.1 Існуючі компоненти
- ✅ `src/oci/create.zig` - основна логіка створення контейнерів
- ✅ `src/oci/cli.zig` - парсинг CLI аргументів з підтримкою `--runtime`
- ✅ `src/common/types.zig` - `RuntimeType` enum (runc, crun, lxc, vm)
- ✅ `src/oci/runtime_types.zig` - OCI специфікація типів
- ✅ `src/oci/bundle.zig` - створення OCI bundle
- ✅ `src/oci/validator.zig` - валідація OCI конфігурації

### 2.2 Поточна підтримка runtime
```zig
// src/oci/create.zig:143
runtime_type: oci_types.RuntimeType,

// src/common/types.zig:768
pub const RuntimeType = enum {
    runc,
    crun,        // ✅ Вже є
    lxc,
    vm,
};
```

---

## 3. Завдання інтеграції

### 3.1 Створення модуля `src/oci/crun.zig`
* Імплементувати `CrunManager` struct з методами:
  ```zig
  pub const CrunManager = struct {
      allocator: Allocator,
      logger: *Logger,
      
      pub fn init(allocator: Allocator, logger: *Logger) !*CrunManager
      pub fn deinit(self: *CrunManager) void
      pub fn createContainer(self: *CrunManager, container_id: []const u8, bundle_path: []const u8, config: ?*const OciSpec) !void
      pub fn startContainer(self: *CrunManager, container_id: []const u8) !void
      pub fn deleteContainer(self: *CrunManager, container_id: []const u8) !void
      pub fn runContainer(self: *CrunManager, container_id: []const u8) !void
  };
  ```

### 3.2 Інтеграція через `@cImport`
* Використати `@cImport` для прямих викликів `libcrun`:
  ```zig
  pub const c = @cImport({
      @cInclude("crun.h");
      @cInclude("libcrun/container.h");
  });
  ```

* Імплементувати ключові функції:
  - `libcrun_container_create()`
  - `libcrun_container_start()`
  - `libcrun_container_delete()`
  - `libcrun_container_run()`

### 3.3 Оновлення `src/oci/create.zig`
* Розширити логіку `create()` для підтримки crun:
  ```zig
  .crun => {
      if (self.crun_manager) |crun_mgr| {
          try crun_mgr.createContainer(
              self.options.container_id,
              self.options.bundle_path,
              &self.oci_config,
          );
      } else {
          return CreateError.RuntimeNotAvailable;
      }
  },
  ```

### 3.4 Оновлення `src/oci/cli.zig`
* Розширити `determineRuntimeType()` для кращої підтримки crun:
  ```zig
  if (std.mem.eql(u8, runtime, "crun")) {
      self.use_crun = true;
      self.use_proxmox_lxc = false;
      try self.logger.info("Using crun runtime");
  }
  ```

### 3.5 Оновлення `build.zig`
* Додати залежності для libcrun:
  ```zig
  exe.addIncludePath(.{ .path = "/usr/include" });
  exe.linkSystemLibrary("crun");
  exe.linkSystemLibrary("cap");
  exe.linkSystemLibrary("seccomp");
  exe.linkSystemLibrary("yajl");
  ```

---

## 4. Структура файлів

### 4.1 Новий файл
```
src/oci/crun.zig          # CrunManager та інтеграція з libcrun
```

### 4.2 Оновлені файли
```
src/oci/create.zig         # Інтеграція CrunManager.createContainer()
src/oci/cli.zig           # Покращена підтримка --runtime=crun
src/oci/mod.zig           # Експорт CrunManager
build.zig                 # Залежності libcrun
```

---

## 5. План виконання

### Фаза 1: Створення базового модуля crun
- [ ] Створити `src/oci/crun.zig`
- [ ] Імплементувати `CrunManager` struct
- [ ] Додати `@cImport` для libcrun
- [ ] Створити базові функції (create, start, delete, run)

### Фаза 2: Інтеграція з create.zig
- [ ] Оновити логіку `create()` для crun runtime
- [ ] Інтегрувати `CrunManager.createContainer()`
- [ ] Додати обробку помилок crun

### Фаза 3: Оновлення CLI та build системи
- [ ] Розширити `determineRuntimeType()` для crun
- [ ] Оновити `build.zig` для підключення libcrun
- [ ] Додати валідацію crun runtime

### Фаза 4: Тестування та валідація
- [ ] Створити unit тести для `CrunManager`
- [ ] Протестувати інтеграцію з командою `create`
- [ ] Валідувати роботу з реальними OCI контейнерами

---

## 6. Технічні деталі

### 6.1 API інтерфейс CrunManager
```zig
pub const CrunManager = struct {
    allocator: Allocator,
    logger: *Logger,
    
    // Основні операції
    pub fn createContainer(self: *CrunManager, container_id: []const u8, bundle_path: []const u8, config: ?*const OciSpec) !void
    pub fn startContainer(self: *CrunManager, container_id: []const u8) !void
    pub fn deleteContainer(self: *CrunManager, container_id: []const u8) !void
    pub fn runContainer(self: *CrunManager, container_id: []const u8) !void
    
    // Допоміжні функції
    pub fn containerExists(self: *CrunManager, container_id: []const u8) !bool
    pub fn getContainerState(self: *CrunManager, container_id: []const u8) !ContainerState
};
```

### 6.2 Інтеграція з libcrun
```zig
// Прямі виклики C API
const ret = c.libcrun_container_create(
    &context,
    container,
    0, // flags
    &err,
);
```

### 6.3 Обробка помилок
```zig
pub const CrunError = error{
    ContainerCreateFailed,
    ContainerStartFailed,
    ContainerDeleteFailed,
    ContainerNotFound,
    InvalidConfiguration,
    RuntimeError,
};
```

---

## 7. Приклади використання

### 7.1 Створення контейнера через crun
```bash
proxmox-lxcri create --runtime=crun --bundle /var/lib/containers/test test-123
```

### 7.2 Автоматичне визначення runtime
```bash
# crun для звичайних контейнерів
proxmox-lxcri create test-123

# LXC для спеціальних контейнерів
proxmox-lxcri create lxc-db-123
```

---

## 8. Ризики та мітигація

### 8.1 Ризики
- Несумісність версій libcrun
- Відсутність заголовкових файлів
- Проблеми з компіляцією на різних системах

### 8.2 Мітигація
- Автоматична перевірка залежностей
- Fallback на існуючі runtime-и
- Детальне логування помилок
- Тестування на різних дистрибутивах

---

**Статус**: 🚧 **В РОЗРОБЦІ**  
**Наступний крок**: Інтеграція `CrunManager.createContainer()` з командою `create`
