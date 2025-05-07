# Proxmox LXC Runtime Interface

Інтерфейс для управління LXC контейнерами в Proxmox VE з підтримкою OCI образів.

## Вимоги

- Proxmox VE 7.0 або новіше
- Zig 0.11.0 або новіше
- ZFS (опціонально)
- LXC 4.0 або новіше

## Встановлення

1. Клонуйте репозиторій:
```bash
git clone https://github.com/yourusername/proxmox-lxcri.git
cd proxmox-lxcri
```

2. Встановіть залежності:
```bash
sudo apt-get update
sudo apt-get install -y build-essential git zfsutils-linux lxc
```

3. Зберіть проект:
```bash
zig build -Doptimize=ReleaseFast
```

4. Налаштуйте конфігурацію:
```bash
cp proxmox-config.json.example proxmox-config.json
# Відредагуйте proxmox-config.json з вашими налаштуваннями
```

## Використання

### Створення контейнера

```bash
./zig-out/bin/proxmox-lxcri create \
    --name my-container \
    --image debian:bullseye \
    --memory 512 \
    --cores 1 \
    --storage zfs
```

### Управління контейнером

```bash
# Запуск контейнера
./zig-out/bin/proxmox-lxcri start my-container

# Зупинка контейнера
./zig-out/bin/proxmox-lxcri stop my-container

# Видалення контейнера
./zig-out/bin/proxmox-lxcri delete my-container
```

### Робота з образами

```bash
# Завантаження образу з реєстру
./zig-out/bin/proxmox-lxcri image pull debian:bullseye

# Створення образу з локального файлу
./zig-out/bin/proxmox-lxcri image import my-image.raw

# Видалення образу
./zig-out/bin/proxmox-lxcri image delete my-image
```

## Розробка

### Запуск тестів

```bash
zig build test
```

### Лінтер

```bash
zig build lint
```

## Ліцензія

MIT License

## Автори

- Ваше ім'я <your.email@example.com>

## Внесок

1. Форкніть репозиторій
2. Створіть гілку для ваших змін
3. Зробіть коміт з вашими змінами
4. Відправте Pull Request 