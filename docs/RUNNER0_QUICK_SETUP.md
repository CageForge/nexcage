# Quick Setup for github-runner0

## На сервері github-runner0.cp.if.ua

### Варіант 1: Автоматичний (рекомендовано)

```bash
# 1. Завантажити скрипт
curl -L https://raw.githubusercontent.com/cageforge/nexcage/feat/optimize-github-actions/scripts/setup_runner0.sh -o setup_runner0.sh

# 2. Зробити виконуваним
chmod +x setup_runner0.sh

# 3. Запустити
./setup_runner0.sh
```

Скрипт автоматично:
- Завантажить GitHub Actions Runner
- Налаштує з label `runner0`
- Встановить як сервіс
- Перевірить та встановить залежності (Zig, build tools)

### Варіант 2: Ручний

```bash
# 1. Створити директорію
mkdir -p ~/actions-runner && cd ~/actions-runner

# 2. Завантажити runner
curl -o actions-runner-linux-x64-2.328.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.328.0/actions-runner-linux-x64-2.328.0.tar.gz

# 3. Розпакувати
tar xzf ./actions-runner-linux-x64-2.328.0.tar.gz

# 4. Налаштувати (використати токен нижче)
./config.sh --url https://github.com/cageforge/nexcage \
  --token ADKGWFVIZG5GUM6RMDTAI7DI5DW6S \
  --name github-runner0 \
  --labels self-hosted,runner0

# 5. Встановити як сервіс
sudo ./svc.sh install
sudo ./svc.sh start

# 6. Перевірити статус
sudo ./svc.sh status
```

### Встановлення залежностей

```bash
# Zig 0.15.1
cd /tmp
curl -L https://ziglang.org/download/0.15.1/zig-linux-x86_64-0.15.1.tar.xz -o zig.tar.xz
tar -xf zig.tar.xz
sudo mv zig-linux-x86_64-0.15.1 /usr/local/zig-0.15.1
sudo ln -sf /usr/local/zig-0.15.1/zig /usr/local/bin/zig

# Build dependencies
sudo apt-get update
sudo apt-get install -y \
  libcap-dev \
  libseccomp-dev \
  libyajl-dev \
  build-essential \
  git \
  curl \
  wget

# Перевірка
zig version  # Має показати 0.15.1
```

## Перевірка

1. **Перевірити runner в GitHub**:
   https://github.com/cageforge/nexcage/settings/actions/runners
   
   Має з'явитися `github-runner0` з labels: `self-hosted`, `runner0`

2. **Перевірити статус сервісу**:
   ```bash
   sudo systemctl status actions.runner.*
   journalctl -u actions.runner.* -f
   ```

3. **Тестовий запуск**:
   Workflows автоматично почнуть виконуватися на runner0

## Що робить runner0

✅ **Виконує** (не потребує Proxmox):
- Build та unit тести
- Security scans (CodeQL, Semgrep, Trivy, Gitleaks)
- Documentation checks
- OCI smoke tests
- Dependency updates

❌ **НЕ виконує** (потребує Proxmox):
- LXC E2E тести (`proxmox_e2e.yml`)
- Crun E2E тести (`crun_e2e.yml`)

## Troubleshooting

**Workflows все ще в черзі?**
- Перевірити: `sudo systemctl status actions.runner.*`
- Перевірити label в GitHub UI
- Перезапустити: `sudo systemctl restart actions.runner.*`

**Build помилки?**
- Перевірити Zig: `zig version` (має бути 0.15.1)
- Перевірити libs: `dpkg -l | grep -E 'libcap|libseccomp|libyajl'`

## Токен

Токен дійсний протягом 1 години: `ADKGWFVIZG5GUM6RMDTAI7DI5DW6S`

Якщо токен застарів, згенерувати новий:
```bash
gh api -X POST repos/cageforge/nexcage/actions/runners/registration-token --jq '.token'
```

