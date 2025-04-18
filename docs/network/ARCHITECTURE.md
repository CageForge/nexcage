# Мережева підсистема Proxmox LXC CRI

## Загальна архітектура

Мережева підсистема Proxmox LXC CRI базується на Container Network Interface (CNI) з Cilium як основним мережевим плагіном. 

### Компоненти системи

1. **CNI Plugin Manager**
   - Відповідає за життєвий цикл CNI плагінів
   - Завантажує та валідує конфігурацію CNI
   - Керує викликами CNI плагінів (ADD, DEL, CHECK)
   - Зберігає стан мережевих інтерфейсів

2. **Cilium Integration**
   - eBPF-based мережева підсистема
   - Забезпечує:
     - Маршрутизацію між контейнерами
     - Мережеві політики (Network Policies)
     - Моніторинг та спостережність
     - Балансування навантаження
     - Шифрування трафіку (WireGuard)

3. **Network Configuration Manager**
   - Управління конфігурацією мережі
   - Генерація CNI конфігурації
   - Валідація мережевих налаштувань
   - Інтеграція з Proxmox networking

4. **Network State Manager**
   - Зберігання стану мережевих інтерфейсів
   - Відстеження IP адрес
   - Управління DNS записами
   - Синхронізація стану з Proxmox

### Взаємодія з Cilium

1. **Конфігурація Cilium**
   ```json
   {
     "cniVersion": "0.3.1",
     "name": "cilium",
     "type": "cilium-cni",
     "enable-endpoint-routes": true,
     "ipam": {
       "type": "cilium-ipam"
     },
     "dns": {
       "servers": ["8.8.8.8", "1.1.1.1"],
       "options": ["ndots:5"]
     },
     "kubernetes": {
       "kubeconfig": "/etc/kubernetes/cni/net.d/cilium-kubeconfig"
     }
   }
   ```

2. **Життєвий цикл мережевого інтерфейсу**
   - Створення мережі:
     1. Валідація конфігурації
     2. Створення namespace
     3. Виклик Cilium CNI ADD
     4. Налаштування маршрутизації
     5. Застосування мережевих політик
   
   - Видалення мережі:
     1. Виклик Cilium CNI DEL
     2. Очищення ресурсів
     3. Видалення namespace

### Інтеграція з Proxmox

1. **Bridge Integration**
   - Створення Linux bridge для кожної мережі
   - Інтеграція з vSwitch
   - VLAN підтримка
   - Bond інтерфейси

2. **IP Management**
   - IPAM через Cilium
   - Підтримка IPv4/IPv6
   - DHCP інтеграція
   - Статичні IP адреси

3. **Security**
   - Мережеві політики через Cilium
   - Firewall правила
   - Encryption (WireGuard)
   - Аудит мережевого трафіку

## Реалізація

### Основні модулі

1. **network/manager.zig**
   - Управління мережевими ресурсами
   - Конфігурація CNI
   - Інтеграція з Proxmox

2. **network/cni.zig**
   - CNI plugin interface
   - Виклики CNI операцій
   - Обробка результатів

3. **network/cilium.zig**
   - Cilium-специфічна конфігурація
   - Управління Cilium ресурсами
   - eBPF maps взаємодія

4. **network/state.zig**
   - Зберігання мережевого стану
   - IP allocation
   - Interface tracking

### Обробка помилок

```zig
pub const NetworkError = error{
    ConfigurationError,
    CNIError,
    IPAMError,
    InterfaceError,
    StateError,
    ProxmoxError,
};
```

### Моніторинг та метрики

1. **Prometheus метрики**
   - Кількість мережевих інтерфейсів
   - Статистика трафіку
   - Помилки конфігурації
   - Латентність операцій

2. **Логування**
   - Детальне логування операцій
   - Трейсинг мережевих викликів
   - Аудит змін конфігурації

## Безпека

1. **Мережеві політики**
   ```yaml
   apiVersion: "cilium.io/v2"
   kind: CiliumNetworkPolicy
   metadata:
     name: "default-deny"
   spec:
     endpointSelector:
       matchLabels:
         type: container
     ingress:
     - fromEndpoints:
       - matchLabels:
           type: container
   ```

2. **Шифрування**
   - WireGuard encryption
   - IPsec підтримка
   - TLS для control plane

## Розширення

1. **Додаткові CNI плагіни**
   - Flannel
   - Calico
   - Multus

2. **Service Mesh**
   - Cilium Service Mesh
   - Istio інтеграція
   - Envoy фільтри 