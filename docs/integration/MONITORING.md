# Monitoring and Observability Integration

This guide explains how to set up monitoring and observability for NexCage using industry-standard tools.

## Overview

NexCage can be integrated with various monitoring and observability platforms:

- **Prometheus** - Metrics collection
- **Grafana** - Visualization and dashboards
- **Loki** - Log aggregation
- **ELK Stack** - Centralized logging
- **Jaeger/Tempo** - Distributed tracing (future)

## Prometheus Integration

### Exporting Metrics

NexCage doesn't yet have a built-in metrics endpoint, but you can export metrics using custom scripts.

#### Metrics Exporter Script

```bash
#!/bin/bash
# nexcage-exporter.sh - Export metrics to Prometheus text format

METRICS_FILE="/var/lib/prometheus/node-exporter/nexcage.prom"
mkdir -p "$(dirname "$METRICS_FILE")"

# Collect metrics
TOTAL_CONTAINERS=$(nexcage list 2>/dev/null | tail -n +2 | wc -l || echo 0)
RUNNING_CONTAINERS=$(nexcage list 2>/dev/null | tail -n +2 | grep -c "running" || echo 0)
STOPPED_CONTAINERS=$(nexcage list 2>/dev/null | tail -n +2 | grep -c "stopped" || echo 0)

# Write Prometheus metrics
cat > "$METRICS_FILE" <<EOF
# HELP nexcage_containers_total Total number of containers
# TYPE nexcage_containers_total gauge
nexcage_containers_total $TOTAL_CONTAINERS

# HELP nexcage_containers_running Number of running containers
# TYPE nexcage_containers_running gauge
nexcage_containers_running $RUNNING_CONTAINERS

# HELP nexcage_containers_stopped Number of stopped containers
# TYPE nexcage_containers_stopped gauge
nexcage_containers_stopped $STOPPED_CONTAINERS

# HELP nexcage_exporter_last_run_timestamp Last successful metrics collection timestamp
# TYPE nexcage_exporter_last_run_timestamp gauge
nexcage_exporter_last_run_timestamp $(date +%s)
EOF
```

#### Systemd Timer for Regular Export

```ini
# /etc/systemd/system/nexcage-exporter.service
[Unit]
Description=NexCage Metrics Exporter
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nexcage-exporter.sh
User=root
```

```ini
# /etc/systemd/system/nexcage-exporter.timer
[Unit]
Description=Run NexCage Metrics Exporter every minute
Requires=nexcage-exporter.service

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=nexcage-exporter.service

[Install]
WantedBy=timers.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now nexcage-exporter.timer
```

### Prometheus Configuration

```yaml
# /etc/prometheus/prometheus.yml
scrape_configs:
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          instance: 'proxmox-host'
    
  - job_name: 'nexcage'
    file_sd_configs:
      - files:
        - '/var/lib/prometheus/node-exporter/nexcage.prom'
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'nexcage_.*'
        action: keep
```

## Grafana Dashboards

### Import NexCage Dashboard

Create a custom dashboard JSON:

```json
{
  "dashboard": {
    "title": "NexCage Monitoring",
    "panels": [
      {
        "title": "Total Containers",
        "targets": [
          {
            "expr": "nexcage_containers_total"
          }
        ],
        "type": "stat"
      },
      {
        "title": "Container Status",
        "targets": [
          {
            "expr": "nexcage_containers_running",
            "legendFormat": "Running"
          },
          {
            "expr": "nexcage_containers_stopped",
            "legendFormat": "Stopped"
          }
        ],
        "type": "timeseries"
      }
    ]
  }
}
```

### Creating Dashboard via UI

1. Login to Grafana (usually http://localhost:3000)
2. Create → Dashboard → Add visualization
3. Select Prometheus as data source
4. Add queries:
   - `nexcage_containers_total`
   - `nexcage_containers_running`
   - `nexcage_containers_stopped`
5. Configure visualizations
6. Save dashboard

## Loki Integration (Log Aggregation)

### Promtail Configuration

```yaml
# /etc/promtail/config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: nexcage
    static_configs:
      - targets:
          - localhost
        labels:
          job: nexcage
          __path__: /var/log/nexcage/*.log
```

### Querying Logs in Grafana

LogQL queries:

```logql
# All NexCage logs
{job="nexcage"}

# Error logs only
{job="nexcage"} |= "error" or "Error" or "ERROR"

# Container creation logs
{job="nexcage"} |= "create" |= "container"

# Recent logs with context
{job="nexcage"} | json | line_format "{{.timestamp}} [{{.level}}] {{.message}}"
```

## ELK Stack Integration

### Filebeat Configuration

```yaml
# /etc/filebeat/filebeat.yml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/nexcage/*.log
    fields:
      app: nexcage
      env: production
    multiline:
      pattern: '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
      negate: true
      match: after

output.elasticsearch:
  hosts: ["localhost:9200"]
  index: "nexcage-%{+yyyy.MM.dd}"

setup.kibana:
  host: "localhost:5601"
```

### Logstash Pipeline

```ruby
# /etc/logstash/conf.d/nexcage.conf
input {
  beats {
    port => 5044
  }
}

filter {
  if [fields][app] == "nexcage" {
    grok {
      match => {
        "message" => "%{TIMESTAMP_ISO8601:timestamp} \[%{LOGLEVEL:level}\] %{GREEDYDATA:message}"
      }
    }
    
    date {
      match => [ "timestamp", "ISO8601" ]
    }
  }
}

output {
  if [fields][app] == "nexcage" {
    elasticsearch {
      hosts => ["localhost:9200"]
      index => "nexcage-%{+YYYY.MM.dd}"
    }
  }
}
```

## Alerting

### Prometheus Alertmanager Rules

```yaml
# /etc/prometheus/rules/nexcage.yml
groups:
  - name: nexcage_alerts
    interval: 1m
    rules:
      - alert: NexCageTooManyContainers
        expr: nexcage_containers_total > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Too many containers on {{ $labels.instance }}"
          description: "NexCage has {{ $value }} containers, may need scaling."
      
      - alert: NexCageNoContainersRunning
        expr: nexcage_containers_running == 0 and nexcage_containers_total > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "No containers running on {{ $labels.instance }}"
          description: "All containers are stopped, potential outage."
      
      - alert: NexCageExporterDown
        expr: up{job="nexcage"} == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "NexCage exporter is down"
          description: "Cannot collect metrics from NexCage."
```

### Alertmanager Configuration

```yaml
# /etc/alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m

route:
  receiver: 'default'
  group_by: ['alertname', 'cluster', 'service']
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty'
    - match:
        severity: warning
      receiver: 'slack'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:5001/webhook'
  
  - name: 'slack'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK'
        channel: '#alerts'
        title: 'NexCage Alert'
  
  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_KEY'
```

## Health Checks

### Container Health Script

```bash
#!/bin/bash
# container-health-check.sh

EXIT_CODE=0

echo "=== NexCage Health Check ==="
echo "Timestamp: $(date -Iseconds)"

# Check NexCage binary
if ! command -v nexcage &> /dev/null; then
    echo "ERROR: nexcage command not found"
    EXIT_CODE=1
fi

# Check configuration
if [ ! -f /etc/nexcage/config.json ]; then
    echo "ERROR: Configuration file not found"
    EXIT_CODE=1
fi

# Check if we can list containers
if ! nexcage list &> /dev/null; then
    echo "ERROR: Cannot list containers"
    EXIT_CODE=1
fi

# Check for stuck containers
STUCK=$(nexcage list 2>/dev/null | grep -i "unknown" | wc -l)
if [ "$STUCK" -gt 0 ]; then
    echo "WARNING: $STUCK containers in unknown state"
    EXIT_CODE=1
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo "OK: All checks passed"
fi

exit $EXIT_CODE
```

### Integration with Monitoring

```bash
# Add to metrics exporter
HEALTH_STATUS=$(bash /usr/local/bin/container-health-check.sh > /dev/null 2>&1; echo $?)

cat >> "$METRICS_FILE" <<EOF
# HELP nexcage_health_status Health check status (0=healthy, 1=unhealthy)
# TYPE nexcage_health_status gauge
nexcage_health_status $HEALTH_STATUS
EOF
```

## Performance Metrics

### Advanced Metrics Collection

```bash
#!/bin/bash
# advanced-metrics.sh

METRICS_FILE="/var/lib/prometheus/node-exporter/nexcage-advanced.prom"

# Container state distribution
for state in running stopped; do
  COUNT=$(nexcage list 2>/dev/null | grep -c "$state" || echo 0)
  echo "nexcage_containers_by_state{state=\"$state\"} $COUNT"
done > "$METRICS_FILE"

# Backend distribution
for runtime in lxc crun runc; do
  COUNT=$(nexcage list 2>/dev/null | grep -c "$runtime" || echo 0)
  echo "nexcage_containers_by_runtime{runtime=\"$runtime\"} $COUNT"
done >> "$METRICS_FILE"

# System resources (if available)
if command -v pct &> /dev/null; then
  TOTAL_MEM=0
  TOTAL_CPU=0
  
  pct list | tail -n +2 | while read line; do
    VMID=$(echo $line | awk '{print $1}')
    # Get memory and CPU usage
    MEM=$(pct config $VMID | grep 'memory:' | awk '{print $2}')
    CPU=$(pct config $VMID | grep 'cores:' | awk '{print $2}')
    
    TOTAL_MEM=$((TOTAL_MEM + MEM))
    TOTAL_CPU=$((TOTAL_CPU + CPU))
    
    echo "nexcage_container_memory_mb{vmid=\"$VMID\"} $MEM"
    echo "nexcage_container_cpu_cores{vmid=\"$VMID\"} $CPU"
  done >> "$METRICS_FILE"
fi
```

## Visualization Examples

### Grafana Panel Queries

**Container Overview:**
```promql
# Total containers
sum(nexcage_containers_total)

# Running containers percentage
(nexcage_containers_running / nexcage_containers_total) * 100
```

**Resource Usage:**
```promql
# Total memory allocated
sum(nexcage_container_memory_mb)

# Total CPU cores allocated
sum(nexcage_container_cpu_cores)
```

**Trends:**
```promql
# Growth rate
rate(nexcage_containers_total[5m])

# Container churn
rate(nexcage_containers_total[1h])
```

## Related Documentation

- [CLI Reference](../CLI_REFERENCE.md)
- [User Guide](../user_guide.md)
- [Troubleshooting](../TROUBLESHOOTING_GUIDE.md)
- [Performance Tuning](../PERFORMANCE_TUNING.md)
