#!/bin/bash

# Збираємо образ для збірки
docker build -t proxmox-lxcri-builder -f Dockerfile.build .

# Запускаємо контейнер для збірки
docker run --rm -v $(pwd):/build proxmox-lxcri-builder

# Перевіряємо результат збірки
if [ $? -eq 0 ]; then
    echo "Збірка успішно завершена!"
else
    echo "Помилка під час збірки!"
    exit 1
fi
 