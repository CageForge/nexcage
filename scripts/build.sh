#!/bin/bash

# Перевіряємо наявність Docker
if ! command -v docker &> /dev/null; then
    echo "Помилка: Docker не встановлено"
    exit 1
fi

# Перевіряємо наявність Dockerfile
if [ ! -f "Dockerfile.build" ]; then
    echo "Помилка: Dockerfile.build не знайдено"
    exit 1
fi

# Збираємо образ для збірки
echo "Збірка образу для збірки..."
docker build -t proxmox-lxcri-builder -f Dockerfile.build .

# Запускаємо контейнер для збірки
echo "Запуск збірки проекту..."
docker run --rm -v $(pwd):/build proxmox-lxcri-builder

# Перевіряємо результат збірки
if [ $? -eq 0 ]; then
    echo "Збірка успішно завершена!"
else
    echo "Помилка під час збірки!"
    exit 1
fi
 