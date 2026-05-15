# manejoDeSeo-michelJure

Endpoint en Python para recibir datos desde un ESP32 y guardarlos en el VPS.

## 1) Instalacion

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 2) Ejecutar API

```bash
export API_KEY="mi_clave_segura"
export PORT=8000
python app.py
```

La API expone:

- `GET /health` -> estado del servicio
- `POST /api/esp32/data` -> recibe JSON del ESP32

Si defines `API_KEY`, debes enviar el header `X-API-Key`.

## 3) Probar desde terminal

```bash
curl -X POST http://TU_VPS:8000/api/esp32/data \
	-H "Content-Type: application/json" \
	-H "X-API-Key: mi_clave_segura" \
	-d '{"temperature":24.7,"humidity":61,"device_id":"esp32-01"}'
```

Los datos se guardan en `data/telemetry.jsonl`.

## 4) Ejemplo rapido para ESP32 (Arduino)

```cpp
#include <WiFi.h>
#include <HTTPClient.h>

const char* ssid = "TU_WIFI";
const char* password = "TU_PASSWORD";
const char* endpoint = "https://api.tudominio.com/api/esp32/data";
const char* apiKey = "mi_clave_segura";

void setup() {
	Serial.begin(115200);
	WiFi.begin(ssid, password);
	while (WiFi.status() != WL_CONNECTED) {
		delay(500);
	}

	if (WiFi.status() == WL_CONNECTED) {
		HTTPClient http;
		http.begin(endpoint);
		http.addHeader("Content-Type", "application/json");
		http.addHeader("X-API-Key", apiKey);

		String payload = "{\"device_id\":\"esp32-01\",\"temperature\":25.4,\"humidity\":58}";
		int code = http.POST(payload);

		Serial.print("HTTP code: ");
		Serial.println(code);
		http.end();
	}
}

void loop() {
	delay(10000);
}
```

## 5) Dejar corriendo con systemd (VPS)

Los archivos de ejemplo estan en [deploy/systemd/esp32-api.service](deploy/systemd/esp32-api.service) y [deploy/systemd/esp32-api.env.example](deploy/systemd/esp32-api.env.example).

1. Copia tu proyecto al VPS, por ejemplo en `/opt/manejoDeSeo-michelJure`.
2. Crea el entorno virtual e instala dependencias:

```bash
cd /opt/manejoDeSeo-michelJure
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

3. Copia los archivos de systemd:

```bash
sudo cp /opt/manejoDeSeo-michelJure/deploy/systemd/esp32-api.service /etc/systemd/system/esp32-api.service
sudo cp /opt/manejoDeSeo-michelJure/deploy/systemd/esp32-api.env.example /etc/default/esp32-api
```

4. Edita `/etc/default/esp32-api` y cambia `API_KEY`.
5. Si tu ruta no es `/opt/manejoDeSeo-michelJure`, edita `/etc/systemd/system/esp32-api.service` y ajusta `WorkingDirectory` y `ExecStart`.
6. Activa y arranca el servicio:

```bash
sudo systemctl daemon-reload
sudo systemctl enable esp32-api
sudo systemctl start esp32-api
```

7. Verifica estado y logs:

```bash
sudo systemctl status esp32-api
sudo journalctl -u esp32-api -f
```

## 6) Endurecer seguridad (Nginx + HTTPS)

Archivo de ejemplo: [deploy/nginx/esp32-api.conf](deploy/nginx/esp32-api.conf).

1. Instala Nginx + Certbot:

```bash
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx
```

2. Copia el config y cambia tu dominio real:

```bash
sudo cp /opt/manejoDeSeo-michelJure/deploy/nginx/esp32-api.conf /etc/nginx/sites-available/esp32-api.conf
sudo nano /etc/nginx/sites-available/esp32-api.conf
```

Reemplaza `api.tudominio.com` por tu dominio real.

3. Activa el sitio y valida Nginx:

```bash
sudo ln -s /etc/nginx/sites-available/esp32-api.conf /etc/nginx/sites-enabled/esp32-api.conf
sudo nginx -t
sudo systemctl reload nginx
```

4. Emite certificado TLS:

```bash
sudo certbot --nginx -d api.tudominio.com
```

5. Abre firewall solo necesario:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
```

6. Verifica renovacion automatica de certificados:

```bash
sudo systemctl status certbot.timer
```

## 7) Checklist de produccion

- Usa una `API_KEY` larga y aleatoria en `/etc/default/esp32-api`.
- Deja Flask escuchando solo en `127.0.0.1` (ya configurado en ejemplo).
- No expongas el puerto `8000` en el firewall.
- Verifica que el ESP32 envie a `https://api.tudominio.com/api/esp32/data`.
- Revisa logs periodicamente:

```bash
sudo journalctl -u esp32-api --since "1 hour ago"
sudo tail -n 50 /var/log/nginx/access.log
```

## 8) Anti abuso con Fail2ban

Archivos de ejemplo:

- [deploy/fail2ban/filter.d/esp32-api-auth.conf](deploy/fail2ban/filter.d/esp32-api-auth.conf)
- [deploy/fail2ban/jail.d/esp32-api.local](deploy/fail2ban/jail.d/esp32-api.local)

1. Instala Fail2ban:

```bash
sudo apt update
sudo apt install -y fail2ban
```

2. Copia configuraciones:

```bash
sudo cp /opt/manejoDeSeo-michelJure/deploy/fail2ban/filter.d/esp32-api-auth.conf /etc/fail2ban/filter.d/esp32-api-auth.conf
sudo cp /opt/manejoDeSeo-michelJure/deploy/fail2ban/jail.d/esp32-api.local /etc/fail2ban/jail.d/esp32-api.local
```

3. Reinicia y verifica:

```bash
sudo systemctl restart fail2ban
sudo fail2ban-client status
sudo fail2ban-client status esp32-api-auth
```

Con esta regla, multiples respuestas 401/403/429 al endpoint en poco tiempo terminan en bloqueo temporal de IP.

## 9) Rotacion de logs

Archivo de ejemplo: [deploy/logrotate/esp32-api](deploy/logrotate/esp32-api).

1. Copia la regla de logrotate:

```bash
sudo cp /opt/manejoDeSeo-michelJure/deploy/logrotate/esp32-api /etc/logrotate.d/esp32-api
```

2. Prueba la configuracion:

```bash
sudo logrotate -d /etc/logrotate.d/esp32-api
```

3. Forzar una rotacion manual (opcional):

```bash
sudo logrotate -f /etc/logrotate.d/esp32-api
```

## 10) Instalacion automatica (Ubuntu)

Si quieres levantar todo en una sola ejecucion, usa [deploy/install_ubuntu.sh](deploy/install_ubuntu.sh).

Requisitos previos:

- El dominio ya apunta a la IP del VPS.
- El repo esta en `/opt/manejoDeSeo-michelJure` (o define `APP_DIR`).

Comando recomendado:

```bash
cd /opt/manejoDeSeo-michelJure
chmod +x deploy/install_ubuntu.sh
DOMAIN=api.tudominio.com LETSENCRYPT_EMAIL=tu@email.com API_KEY='tu_clave_super_larga' APP_DIR=/opt/manejoDeSeo-michelJure ./deploy/install_ubuntu.sh
```

Si no pasas `API_KEY`, el script genera una automaticamente y la muestra al final.
