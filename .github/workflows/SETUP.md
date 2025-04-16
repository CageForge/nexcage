# Налаштування репозиторію для GitHub Actions

## Крок 1: Перевірка налаштувань репозиторію

1. Перейдіть в налаштування репозиторію:
   - Settings > Actions > General
   - Перевірте наступні налаштування:
     - "Allow all actions and reusable workflows"
     - "Allow GitHub Actions to create and approve pull requests"
     - "Allow GitHub Actions to create and approve pull requests from forks"

2. Перевірте налаштування безпеки:
   - Settings > Security > Code security and analysis
   - Увімкніть:
     - Dependabot alerts
     - Dependabot security updates
     - Code scanning

## Крок 2: Налаштування токенів

1. Перейдіть в налаштування токенів:
   - Settings > Secrets and variables > Actions
   - Натисніть "New repository secret"

2. Додайте наступні токени:
   - GITHUB_TOKEN (автоматично створюється)
   - DOCKERHUB_TOKEN (якщо потрібно)
   - PROXMOX_TOKEN (якщо потрібно)

## Крок 3: Налаштування permissions

1. Перейдіть в налаштування permissions:
   - Settings > Actions > General > Workflow permissions
   - Виберіть "Read and write permissions"

2. Якщо опція недоступна:
   - Перевірте, чи ви є власником репозиторію
   - Перевірте, чи маєте права адміністратора
   - Зв'яжіться з адміністратором організації

## Крок 4: Перевірка доступу

1. Перевірте налаштування доступу:
   - Settings > Collaborators and teams
   - Переконайтеся, що маєте необхідні права

2. Перевірте налаштування організації:
   - Organization settings > Actions > General
   - Переконайтеся, що GitHub Actions увімкнено

## Вирішення проблем

Якщо виникли проблеми з налаштуванням permissions:

1. Перевірте права доступу:
   - Ви повинні бути власником або адміністратором репозиторію
   - Організація повинна дозволяти налаштування permissions

2. Перевірте налаштування організації:
   - Organization settings > Actions > General
   - Переконайтеся, що GitHub Actions увімкнено
   - Перевірте налаштування permissions на рівні організації

3. Зв'яжіться з підтримкою:
   - Якщо проблема не вирішується, зв'яжіться з підтримкою GitHub
   - Надайте інформацію про помилки та налаштування 