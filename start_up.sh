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
mkdir -p grafana/config
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
podman run -d --name=grafana --pod grafana-stack -v $(pwd)/grafana/config:/etc/grafana -v $(pwd)/grafana/data:/var/lib/grafana -e "GF_INSTALL_PLUGINS=grafana-image-renderer" -e "GF_RENDERING_SERVER_URL=http://$HOST:8081/render" -e "GF_RENDERING_CALLBACK_URL=http://$HOST:3000/"  -e "GF_SERVER_ROOT_URL=http://$HOST:3000" grafana/grafana
podman run -d --name=grafana-image-renderer --pod grafana-stack  grafana/grafana-image-renderer:latest
podman run -d --name=grafana-report --pod grafana-stack localhost/grafana-report:v1 -ip $HOST:8080 -templates /opt/TinyTeX/templates

#############Start Prometheus

podman run -d --name=prometheus \
  -p 9090:9090 \
  -v $(pwd)/prometheus/data:/prometheus \
  -v $(pwd)/prometheus/config/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus





##############Start Nginx
mkdir -p nginx/config
chmod -R 777 nginx

tee nginx/config/default.conf > /dev/null <<EOF
server {
    listen       80;
    listen  [::]:80;
    server_name  localhost;

    #access_log  /var/log/nginx/host.access.log  main;

    location / {
        proxy_pass http://$HOST:3000;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
#        rewrite ^/grafana/?(.*) /$1 break;
    }

    location /grafana-report {
        proxy_pass http://$HOST:8686;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        rewrite ^/grafana-report/?(.*) /$1 break;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
EOF

podman run -d -p 8080:80 -v $(pwd)/nginx/config/default.conf:/etc/nginx/conf.d/default.conf --name nginx nginx:latest
