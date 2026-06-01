#!/bin/bash
# ============================================
#  INSTALADOR API - DEBIAN 13 
#  sudo bash infra_pro.sh
# chmod +x infra_pro.sh
# ============================================

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Ejecuta con: sudo bash setup_api.sh"
  exit 1
fi

USUARIO="${SUDO_USER:-}"
if [ -z "$USUARIO" ] || [ "$USUARIO" = "root" ]; then
  USUARIO="www-data"
fi

PROYECTO="/var/www/html/api"
DB_PASS="231190031"

# ── 1. Actualizar sistema ──────────────────────────────────────────────────────
echo "======================================"
echo " Actualizando sistema..."
echo "======================================"
apt update && apt upgrade -y

# ── 2. Instalar paquetes ───────────────────────────────────────────────────────
echo "======================================"
echo " Instalando paquetes..."
echo "======================================"
apt install -y \
  apache2 mariadb-server \
  php php-cli php-mysql php-mbstring \
  php-xml php-curl php-zip php-bcmath \
  libapache2-mod-php \
  git curl wget gpg unzip ufw

# ── 3. Configurar Apache ───────────────────────────────────────────────────────
echo "======================================"
echo " Configurando Apache..."
echo "======================================"
a2enmod rewrite
systemctl enable apache2
systemctl restart apache2

# ── 4. Configurar MariaDB ──────────────────────────────────────────────────────
echo "======================================"
echo " Configurando MariaDB..."
echo "======================================"
systemctl enable mariadb
systemctl start mariadb

mysql <<SQL
CREATE DATABASE IF NOT EXISTS api
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'lizbeth'@'localhost'
  IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON api.* TO 'lizbeth'@'localhost';
FLUSH PRIVILEGES;
SQL

# ── 5. Instalar Composer ───────────────────────────────────────────────────────
echo "======================================"
echo " Instalando Composer..."
echo "======================================"
COMPOSER_TMP="$(mktemp)"
curl -sS https://getcomposer.org/installer -o "$COMPOSER_TMP"
php "$COMPOSER_TMP"
rm -f "$COMPOSER_TMP"
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer

# ── 6. VS Code (solo si hay entorno grafico) ───────────────────────────────────
echo "======================================"
echo " Instalando VS Code..."
echo "======================================"
if [ -n "${DISPLAY:-}" ]; then
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor > /usr/share/keyrings/microsoft.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
https://packages.microsoft.com/repos/code stable main" \
    > /etc/apt/sources.list.d/vscode.list
  apt update
  apt install -y code || true

  if command -v code >/dev/null 2>&1; then
    echo "--- Instalando Thunder Client ---"
    sudo -u "$USUARIO" code \
      --install-extension rangav.vscode-thunder-client --force || true
  fi
else
  echo "AVISO: Sin entorno grafico - VS Code omitido."
  echo "       Usa Remote SSH desde tu maquina local."
fi

# ── 7. Firewall ────────────────────────────────────────────────────────────────
echo "======================================"
echo " Configurando Firewall..."
echo "======================================"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# ── 8. SSH ─────────────────────────────────────────────────────────────────────
echo "======================================"
echo " Verificando SSH..."
echo "======================================"
systemctl enable ssh || true
systemctl restart ssh || true

# ── 9. Clonar repositorio ──────────────────────────────────────────────────────
echo "======================================"
echo " Clonando repositorio..."
echo "======================================"
if [ -d "$PROYECTO/.git" ]; then
  echo "Repositorio encontrado, actualizando..."
  git -C "$PROYECTO" pull
else
  git clone https://github.com/km3236833-netizen/api.git "$PROYECTO"
fi

chown -R www-data:www-data "$PROYECTO"
chmod -R 755 "$PROYECTO"

# ── 10. Dependencias Composer ──────────────────────────────────────────────────
echo "======================================"
echo " Instalando dependencias Composer..."
echo "======================================"
if [ -f "$PROYECTO/composer.json" ]; then
  sudo -u www-data composer install \
    --no-interaction \
    --working-dir="$PROYECTO"
fi

# ── Resumen ────────────────────────────────────────────────────────────────────
echo ""
echo "======================================"
echo " INSTALACION COMPLETADA"
echo "======================================"
echo " Base de datos : api"
echo " Usuario DB    : lizbeth"
echo " Contrasena    : ${DB_PASS}"
echo " Proyecto      : $PROYECTO"
echo ""
echo " Puertos abiertos:"
echo "   22  -> SSH"
echo "   80  -> HTTP"
echo "   443 -> HTTPS"
echo ""
echo " Para VS Code Remote SSH:"
echo "   Host    : IP_DEL_DROPLET"
echo "   Usuario : root"
echo "   Puerto  : 22"
echo "======================================"

# Abrir VS Code si hay display
if [ -n "${DISPLAY:-}" ] && command -v code >/dev/null 2>&1; then
  sudo -u "$USUARIO" code "$PROYECTO" >/dev/null 2>&1 &
fi
