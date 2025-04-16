# Налаштування токенів безпеки

## GITHUB_TOKEN

GITHUB_TOKEN - це автоматично створений токен, який використовується для автентифікації в GitHub Actions. Він автоматично створюється для кожного запуску workflow.

### Як налаштувати GITHUB_TOKEN:

1. Перейдіть в налаштування репозиторію:
   - Settings > Actions > General
   - Увімкніть "Read and write permissions" для GITHUB_TOKEN

2. Перевірте налаштування токенів:
   - Settings > Secrets and variables > Actions
   - Переконайтеся, що GITHUB_TOKEN доступний

3. Налаштуйте permissions для workflow:
   ```yaml
   permissions:
     contents: read
     pull-requests: write
     actions: read
     checks: write
     statuses: write
     security-events: write
     packages: read
     deployments: write
     pages: write
     issues: write
     discussions: write
     repository-projects: write
     workflows: write
   ```

## Інші токени

Якщо потрібні додаткові токени (наприклад, для доступу до Docker Hub або інших сервісів), їх можна додати в:
- Settings > Secrets and variables > Actions > New repository secret

### Приклад додавання токена:
1. Натисніть "New repository secret"
2. Введіть ім'я токена (наприклад, DOCKERHUB_TOKEN)
3. Введіть значення токена
4. Натисніть "Add secret"

## Безпека токенів

- Ніколи не зберігайте токени в коді
- Використовуйте тільки необхідні permissions
- Регулярно оновлюйте токени
- Видаляйте невикористані токени 