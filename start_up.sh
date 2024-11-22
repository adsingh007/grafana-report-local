############Install node-exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar xzf node_exporter-1.8.2.linux-amd64.tar.gz
#Remove node_exporter-1.7.0.linux-amd64.tar.gz
rm -rf node_exporter-1.8.2.linux-amd64.tar.gz

mv node_exporter-1.8.2.linux-amd64 /etc/node_exporter

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/etc/node_exporter/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl restart node_exporter

sudo systemctl status node_exporter

#############

mkdir -p grafana/data
mkdir -p prometheus/data
mkdir -p prometheus/config
HOST=$(hostname -I |awk '{print $1}')
tee prometheus/config/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s

scrape_configs:
- job_name: node
  static_configs:
  - targets: ['$HOST:9100']
EOF


chmod -R 777 prometheus grafana

##############Start grafana-stack
podman load -q -i grafana-report.tar 
podman  pod create --name grafana-stack -p 3000:3000 -p 8686:8686 -p 8081:8081
podman run -d --name=grafana --pod grafana-stack -v $(pwd)/grafana/data:/var/lib/grafana  grafana/grafana
podman run -d --name=grafana-image-renderer --pod grafana-stack -e GF_RENDERING_SERVER_URL: http://$HOST:8081/render -e GF_RENDERING_CALLBACK_URL: http://$HOST:3000/ grafana/grafana-image-renderer:latest
podman run -d --name=grafana-report --pod grafana-stack localhost/grafana-report:v1 -ip $HOST:3000 -templates /opt/TinyTeX/templates

#############Start Prometheus

podman run -d --name=prometheus \
  -p 9090:9090 \
  -v $(pwd)/prometheus/data:/prometheus \
  -v $(pwd)/prometheus/config/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus
