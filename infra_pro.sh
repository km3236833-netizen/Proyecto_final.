#!/bin/bash
# ============================================
#  INSTALADOR LAMP + LARAVEL API - DEBIAN/UBUNTU
#  Uso: sudo bash instalador.sh
#  Compatible con: DigitalOcean Droplet / Máquinas Virtuales
# ============================================

if [ "$EUID" -ne 0 ]; then
    echo "Ejecuta con: sudo bash instalador.sh"
    exit 1
fi

USUARIO="${SUDO_USER:-$USER}"
PROYECTO="/var/www/html/api/API/api-practica"
PUBLIC_DIR="$PROYECTO/public"

apt_safe() {
    apt-get -o DPkg::Lock::Timeout=120 "$@" || {
        echo "Apt bloqueado, forzando liberación..."
        killall -9 apt apt-get dpkg 2>/dev/null
        rm -f /var/lib/apt/lists/lock
        rm -f /var/cache/apt/archives/lock
        rm -f /var/lib/dpkg/lock-frontend
        rm -f /var/lib/dpkg/lock
        dpkg --configure -a 2>/dev/null
        apt-get -o DPkg::Lock::Timeout=120 "$@"
    }
}

# 0. Reparar instalaciones rotas anteriores (Especialmente MariaDB)
echo "--- Verificando y reparando dependencias rotas ---"
mkdir -p /etc/mysql
touch /etc/mysql/mariadb.cnf
dpkg --configure -a --force-confmiss 2>/dev/null
apt-get install -f -y -o Dpkg::Options::="--force-confmiss" 2>/dev/null
apt-get purge -y libapache2-mod-php8.4 2>/dev/null

# 1. Actualizar paquetes del sistema
echo "--- Actualizando sistema ---"
apt_safe update -y
apt_safe upgrade -y

# 2. Instalar Servidor Web y PHP (con SQLite)
echo "--- Instalando Servidor Web y PHP ---"
apt_safe install -y apache2 sqlite3 \
    php8.4 php8.4-cli php8.4-sqlite3 php8.4-mbstring \
    php8.4-xml php8.4-curl php8.4-zip php8.4-bcmath \
    libapache2-mod-php8.4

a2enmod rewrite
phpenmod xml mbstring curl zip bcmath sqlite3 2>/dev/null
systemctl enable apache2
systemctl start apache2

# 3. Quitar MariaDB que ya no ocupamos
echo "--- Eliminando rastros rotos de MariaDB ---"
apt-get purge -y mariadb-common mariadb-server mariadb-client mysql-common 2>/dev/null
apt-get autoremove -y 2>/dev/null

# 4. Instalar Git
echo "--- Instalando Git ---"
apt_safe install -y git

# 5. Instalar Composer
echo "--- Instalando Composer ---"
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer

# 6. Clonar o actualizar el repositorio
echo "--- Clonando/Actualizando repositorio ---"
REPO_DIR="/var/www/html/api"
if [ -d "$REPO_DIR/.git" ]; then
    echo "Repositorio ya existe, actualizando..."
    git -C "$REPO_DIR" pull
else
    git clone https://github.com/km3236833-netizen/api.git "$REPO_DIR"
fi

# 7. Instalar dependencias de Laravel
echo "--- Instalando dependencias PHP (Composer) ---"
cd "$PROYECTO"
composer install --no-interaction --prefer-dist --optimize-autoloader --ignore-platform-reqs

# 8. Configurar .env si no existe
if [ ! -f "$PROYECTO/.env" ]; then
    cp "$PROYECTO/.env.example" "$PROYECTO/.env"
fi

# Asegurar valores correctos en .env para SQLite
sed -i "s|APP_URL=.*|APP_URL=http://$(hostname -I | awk '{print $1}')|g" "$PROYECTO/.env"
sed -i "s|DB_CONNECTION=.*|DB_CONNECTION=sqlite|g" "$PROYECTO/.env"
sed -i "s|DB_HOST=.*|#DB_HOST=127.0.0.1|g" "$PROYECTO/.env"
sed -i "s|DB_PORT=.*|#DB_PORT=3306|g" "$PROYECTO/.env"
sed -i "s|DB_DATABASE=.*|#DB_DATABASE=api|g" "$PROYECTO/.env"
sed -i "s|DB_USERNAME=.*|#DB_USERNAME=lizbeth|g" "$PROYECTO/.env"
sed -i "s|DB_PASSWORD=.*|#DB_PASSWORD=231190031|g" "$PROYECTO/.env"

# Crear archivo de la base de datos sqlite y dar permisos
touch "$PROYECTO/database/database.sqlite"
chown -R www-data:www-data "$PROYECTO/database"

# 9. Generar clave de la app si no existe
php "$PROYECTO/artisan" key:generate --no-interaction

# 10. Ejecutar migraciones
echo "--- Ejecutando migraciones ---"
php "$PROYECTO/artisan" migrate --force

# 11. Permisos de storage y cache (CRÍTICO en servidor)
echo "--- Configurando permisos ---"
chown -R www-data:www-data "$PROYECTO/storage" "$PROYECTO/bootstrap/cache"
chmod -R 775 "$PROYECTO/storage" "$PROYECTO/bootstrap/cache"

# 12. Configurar VirtualHost de Apache para la API Laravel
echo "--- Configurando Apache VirtualHost ---"
cat > /etc/apache2/sites-available/api-laravel.conf <<VHOST
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $PUBLIC_DIR

    <Directory $PUBLIC_DIR>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/api_error.log
    CustomLog \${APACHE_LOG_DIR}/api_access.log combined
</VirtualHost>
VHOST

# Activar el nuevo sitio y desactivar el default
a2ensite api-laravel.conf
a2dissite 000-default.conf
systemctl reload apache2

# 13. Optimizar Laravel para producción
echo "--- Optimizando Laravel ---"
php "$PROYECTO/artisan" config:cache
php "$PROYECTO/artisan" route:cache

IP_PUBLICA=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================"
echo "  LISTO! API desplegada"
echo "  IP de acceso: http://$IP_PUBLICA"
echo "  Endpoint:     http://$IP_PUBLICA/api/libros"
echo "  DB: api | Usuario: lizbeth"
echo "  Proyecto en: $PROYECTO"
echo "============================================"
echo ""
