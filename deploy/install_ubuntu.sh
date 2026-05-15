#!/usr/bin/env bash
set -euo pipefail

# Instalador automatizado para Ubuntu.
# Configura: systemd, nginx + TLS, ufw, fail2ban y logrotate.

if [[ "${EUID}" -eq 0 ]]; then
  echo "Ejecuta este script como usuario normal (no root). Usa sudo cuando sea necesario."
  exit 1
fi

if [[ ! -f /etc/os-release ]]; then
  echo "No se pudo detectar el sistema operativo."
  exit 1
fi

source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "Este script esta preparado para Ubuntu. Sistema detectado: ${ID:-desconocido}"
  exit 1
fi

APP_NAME="esp32-api"
DEFAULT_APP_DIR="/opt/manejoDeSeo-michelJure"
APP_DIR="${APP_DIR:-$DEFAULT_APP_DIR}"
DOMAIN="${DOMAIN:-}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
API_KEY_VALUE="${API_KEY:-}"

if [[ -z "${DOMAIN}" ]]; then
  echo "Falta DOMAIN. Ejemplo: DOMAIN=api.tudominio.com"
  exit 1
fi

if [[ -z "${LETSENCRYPT_EMAIL}" ]]; then
  echo "Falta LETSENCRYPT_EMAIL. Ejemplo: LETSENCRYPT_EMAIL=tu@email.com"
  exit 1
fi

if [[ -z "${API_KEY_VALUE}" ]]; then
  API_KEY_VALUE="$(openssl rand -hex 32)"
  echo "API_KEY no definida. Se genero una automaticamente."
fi

if [[ ! -d "${APP_DIR}" ]]; then
  echo "No existe APP_DIR: ${APP_DIR}"
  echo "Clona primero el repo en esa ruta o define APP_DIR correctamente."
  exit 1
fi

if [[ ! -f "${APP_DIR}/app.py" ]]; then
  echo "No se encontro app.py en ${APP_DIR}."
  exit 1
fi

echo "==> Instalando paquetes del sistema"
sudo apt update
sudo apt install -y python3 python3-venv nginx certbot python3-certbot-nginx fail2ban openssl

echo "==> Preparando entorno Python"
cd "${APP_DIR}"
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
deactivate

echo "==> Configurando archivo de entorno del servicio"
sudo cp "${APP_DIR}/deploy/systemd/esp32-api.env.example" /etc/default/esp32-api
sudo sed -i "s|^API_KEY=.*|API_KEY=${API_KEY_VALUE}|" /etc/default/esp32-api
sudo sed -i "s|^HOST=.*|HOST=127.0.0.1|" /etc/default/esp32-api
sudo sed -i "s|^PORT=.*|PORT=8000|" /etc/default/esp32-api
sudo sed -i "s|^DATA_DIR=.*|DATA_DIR=${APP_DIR}/data|" /etc/default/esp32-api

echo "==> Configurando systemd"
sudo cp "${APP_DIR}/deploy/systemd/esp32-api.service" /etc/systemd/system/esp32-api.service
sudo sed -i "s|^WorkingDirectory=.*|WorkingDirectory=${APP_DIR}|" /etc/systemd/system/esp32-api.service
sudo sed -i "s|^ExecStart=.*|ExecStart=${APP_DIR}/.venv/bin/python ${APP_DIR}/app.py|" /etc/systemd/system/esp32-api.service
sudo mkdir -p "${APP_DIR}/data"
sudo chown -R www-data:www-data "${APP_DIR}/data"
sudo systemctl daemon-reload
sudo systemctl enable esp32-api
sudo systemctl restart esp32-api

echo "==> Configurando Nginx"
sudo cp "${APP_DIR}/deploy/nginx/esp32-api.conf" /etc/nginx/sites-available/esp32-api.conf
sudo sed -i "s|api.tudominio.com|${DOMAIN}|g" /etc/nginx/sites-available/esp32-api.conf
if [[ ! -e /etc/nginx/sites-enabled/esp32-api.conf ]]; then
  sudo ln -s /etc/nginx/sites-available/esp32-api.conf /etc/nginx/sites-enabled/esp32-api.conf
fi
if [[ -e /etc/nginx/sites-enabled/default ]]; then
  sudo rm -f /etc/nginx/sites-enabled/default
fi
sudo nginx -t
sudo systemctl reload nginx

echo "==> Emision de certificado TLS"
sudo certbot --nginx --non-interactive --agree-tos -m "${LETSENCRYPT_EMAIL}" -d "${DOMAIN}" --redirect

echo "==> Configurando firewall (UFW)"
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

echo "==> Configurando Fail2ban"
sudo cp "${APP_DIR}/deploy/fail2ban/filter.d/esp32-api-auth.conf" /etc/fail2ban/filter.d/esp32-api-auth.conf
sudo cp "${APP_DIR}/deploy/fail2ban/jail.d/esp32-api.local" /etc/fail2ban/jail.d/esp32-api.local
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban

echo "==> Configurando logrotate"
sudo cp "${APP_DIR}/deploy/logrotate/esp32-api" /etc/logrotate.d/esp32-api

echo
echo "Instalacion finalizada."
echo "Dominio: https://${DOMAIN}"
echo "Endpoint: https://${DOMAIN}/api/esp32/data"
echo "API_KEY: ${API_KEY_VALUE}"
echo
echo "Verificaciones sugeridas:"
echo "  sudo systemctl status esp32-api"
echo "  sudo nginx -t"
echo "  sudo fail2ban-client status esp32-api-auth"
