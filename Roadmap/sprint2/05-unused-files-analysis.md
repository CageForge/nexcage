# Sprint 2: Аналіз невикористаних файлів

## Опис завдання
Аналіз проекту для виявлення файлів, які не використовуються в основному коді та можуть бути видалені або рефакторовані.

## Методологія аналізу
1. Перевірка `build.zig` - які модулі дійсно імпортуються
2. Аналіз `src/main.zig` - які модулі використовуються в основному коді
3. Перевірка тестів - які модулі використовуються тільки в тестах
4. Визначення файлів, які можна видалити або рефакторити

## Аналіз build.zig

### Використовувані модулі:
- ✅ `types` - src/common/types.zig
- ✅ `error` - src/common/error.zig  
- ✅ `logger` - src/common/logger.zig
- ✅ `config` - src/common/config.zig
- ✅ `zfs` - src/zfs/mod.zig
- ✅ `network` - src/network/network.zig
- ✅ `proxmox` - src/proxmox/proxmox.zig
- ✅ `json_helpers` - src/common/custom_json_parser.zig
- ✅ `cli_args` - src/common/cli_args.zig
- ✅ `image` - src/container/image_manager.zig
- ✅ `lxc` - src/container/lxc.zig
- ✅ `crun` - src/container/crun.zig
- ✅ `registry` - src/registry/mod.zig
- ✅ `raw` - src/raw/mod.zig
- ✅ `oci` - src/oci/mod.zig

## Аналіз src/main.zig

### Використовувані модулі:
- ✅ `types` - для типів
- ✅ `error` - для обробки помилок
- ✅ `logger` - для логування
- ✅ `config` - для конфігурації
- ✅ `proxmox` - для роботи з Proxmox API
- ✅ `oci` - для OCI команд

### НЕ використовувані модулі:
- ❌ `network` - мережеві функції
- ❌ `zfs` - ZFS управління
- ❌ `cli_args` - CLI аргументи
- ❌ `image` - управління образами
- ❌ `lxc` - LXC контейнери
- ❌ `crun` - CRUN runtime
- ❌ `registry` - реєстр образів
- ❌ `raw` - raw образи

## Детальний аналіз невикористаних файлів

### 1. src/container/ (повністю не використовується)
- ❌ `routing.zig` - маршрутизація контейнерів
- ❌ `lxc.zig` - LXC менеджер
- ❌ `crun.zig` - CRUN runtime
- ❌ `image_manager.zig` - управління образами

**Причина**: Ці модулі створені для майбутнього використання, але зараз не інтегровані в основний код.

### 2. src/pause/ (повністю не використовується)
- ❌ `pause.zig` - призупинення контейнерів
- ❌ `config.zig` - конфігурація паузи

**Причина**: Функціональність паузи ще не реалізована в основному коді.

### 3. src/network/ (частково не використовується)
- ❌ `port_forward.zig` - проброс портів
- ❌ `flannel.zig` - Flannel мережа
- ❌ `kube_ovn.zig` - Kube-OVN мережа
- ❌ `cilium.zig` - Cilium мережа
- ❌ `lxc_network.zig` - LXC мережа
- ❌ `manager.zig` - менеджер мереж
- ❌ `state.zig` - стан мереж
- ❌ `validator.zig` - валідація мереж
- ❌ `plugin.zig` - плагіни мереж
- ❌ `cni.zig` - CNI інтеграція

**Причина**: Мережева функціональність ще не інтегрована в основний код.

### 4. src/oci/ (частково не використовується)
- ❌ `hooks.zig` - OCI hooks
- ❌ `overlay/` - overlay файлова система
- ❌ `runtime/` - runtime функції
- ❌ `image.zig` - OCI образи
- ❌ `registry.zig` - реєстр образів

**Причина**: Деякі OCI функції ще не реалізовані.

### 5. src/zfs/ (не використовується)
- ❌ `manager.zig` - ZFS менеджер

**Причина**: ZFS функціональність ще не інтегрована.

### 6. src/registry/ (не використовується)
- ❌ `registry.zig` - реєстр образів

**Причина**: Реєстр образів ще не використовується.

## Рекомендації

### 1. Файли для видалення (повністю не використовуються)
```
src/container/routing.zig
src/container/lxc.zig  
src/container/crun.zig
src/container/image_manager.zig
src/pause/pause.zig
src/pause/config.zig
src/network/port_forward.zig
src/network/flannel.zig
src/network/kube_ovn.zig
src/network/cilium.zig
src/network/lxc_network.zig
src/network/manager.zig
src/network/state.zig
src/network/validator.zig
src/network/plugin.zig
src/network/cni.zig
src/zfs/manager.zig
src/registry/registry.zig
```

### 2. Файли для рефакторингу (використовуються тільки в тестах)
```
src/oci/hooks.zig
src/oci/overlay/
src/oci/runtime/
src/oci/image.zig
```

### 3. Файли для майбутньої інтеграції
```
src/network/network.zig (базовий модуль)
src/oci/spec.zig (OCI специфікація)
```

## Вплив на проект

### Позитивні аспекти:
- Зменшення розміру проекту
- Краща читабельність коду
- Легше підтримувати
- Менше конфузії для розробників

### Ризики:
- Втрата функціональності, яка може знадобитися в майбутньому
- Потрібно буде перестворювати файли при необхідності

## План дій

### Фаза 1: Видалення невикористаних файлів
- [ ] Видалити файли з `src/container/`
- [ ] Видалити файли з `src/pause/`
- [ ] Видалити файли з `src/network/` (крім network.zig)
- [ ] Видалити файли з `src/zfs/`
- [ ] Видалити файли з `src/registry/`

### Фаза 2: Очищення build.zig
- [ ] Видалити невикористані модулі
- [ ] Оновити залежності
- [ ] Перевірити компіляцію

### Фаза 3: Оновлення документації
- [ ] Видалити посилання на неіснуючі модулі
- [ ] Оновити README.md
- [ ] Оновити DEPENDENCIES.md

## Висновок

Проект має значну кількість невикористаних файлів, які можна безпечно видалити. Це покращить структуру проекту та зробить його легшим для розуміння та підтримки.

Рекомендується поетапне видалення з перевіркою компіляції на кожному кроці.
