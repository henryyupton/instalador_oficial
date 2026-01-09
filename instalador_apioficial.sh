#!/bin/bash

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

# Variaveis Padrão
ARCH=$(uname -m)
UBUNTU_VERSION=$(lsb_release -sr)
ARQUIVO_VARIAVEIS="VARIAVEIS_INSTALACAO"
ip_atual=$(curl -s http://checkip.amazonaws.com)
default_apioficial_port=6000

if [ "$EUID" -ne 0 ]; then
echo
printf "${WHITE} >> Este script necesita ser ejecutado como root ${RED}o con privilegios de superusuario${WHITE}.\n"
echo
sleep 2
exit 1
fi

# Función para manejar errores y cerrar el script
trata_erro() {
printf "${RED}Error encontrado en la etapa $1. Cerrando el script.${WHITE}\n"
exit 1
}

# Banner
banner() {
clear
printf "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    INSTALADOR API OFICIAL                    ║"
echo "║                                                              ║"
echo "║                       BotMix System                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
printf "${WHITE}"
echo
}

# Función de Reparación Crítica de Nginx (Limpia la línea include rota y enlaces huérfanos)
reparo_nginx_critico() {
    banner
    printf "${YELLOW} >> Ejecutando Reparación Crítica de Configuración de Nginx...${WHITE}\n"
    
    # 1. Limpia enlaces y archivos huérfanos (como el -oficial)
    printf "${WHITE} >> Eliminando enlaces simbólicos rotos (e.g., -oficial)...${WHITE}\n"
    sudo rm -f /etc/nginx/sites-enabled/-oficial
    printf "${WHITE} >> Eliminando archivos de configuración huérfanos (e.g., -oficial) en sites-available...${WHITE}\n"
    sudo rm -f /etc/nginx/sites-available/-oficial

    # 2. Elimina la línea "include /etc/nginx/sites-enabled/-oficial;" de nginx.conf
    printf "${WHITE} >> Eliminando la línea de inclusión rota de /etc/nginx/nginx.conf...${WHITE}\n"
    # Este comando es crucial para remover la línea de que Nginx estaba reclamando
    sudo sed -i '/include \/etc\/nginx\/sites-enabled\/-oficial;/d' /etc/nginx/nginx.conf
    
    printf "${GREEN} >> Reparación concluida. Probando la configuración de Nginx...${WHITE}\n"
    sudo nginx -t
    if [ $? -ne 0 ]; then
        printf "${RED} >> ERROR: Nginx aún no pasó la prueba de configuración tras la reparación. Interrumpiendo la instalación.${WHITE}\n"
        printf "${YELLOW} >> Si este error persiste, verifique el permiso del directorio /etc/nginx/sites-enabled.${WHITE}\n"
        exit 1
    fi
    printf "${GREEN} >> Nginx listo. Continuando...${WHITE}\n"
    sleep 2
}

# Cargar variables (Sintaxis Corregida: SIN espacios antes de 'if' y 'fi')
carregar_variaveis() {
if [ -f "$ARQUIVO_VARIAVEIS" ]; then
    source "$ARQUIVO_VARIAVEIS"
else
    empresa="botmix"
    nome_titulo="BotMix"
    printf "${RED} >> ERROR: Archivo VARIAVEIS_INSTALACAO no encontrado. Este script debe ser ejecutado por el instalador principal.${WHITE}\n"
    exit 1
fi
}

# Función auxiliar para garantizar subdominio_backend está cargado
carregar_subdominio_backend() {
if [ -z "${subdominio_backend}" ]; then
    local backend_env_path="/home/deploy/${empresa}/backend/.env"
    if [ -f "${backend_env_path}" ]; then
        local subdominio_backend_full=$(grep "^BACKEND_URL=" "${backend_env_path}" 2>/dev/null | cut -d '=' -f2-)
        subdominio_backend=$(echo "${subdominio_backend_full}" | sed 's|https://||g' | sed 's|http://||g' | cut -d'/' -f1)
        # Salva para futuras execuções se carregado
        echo "subdominio_backend=${subdominio_backend}" >>$ARQUIVO_VARIAVEIS
    else
        printf "${RED} >> ERROR: No fue posible encontrar el archivo .env del backend para cargar el subdominio principal.${WHITE}\n"
        exit 1
    fi
fi
}

# Solicitar datos del subdominio de la API Oficial
solicitar_dados_apioficial() {
local temp_subdominio_oficial
banner
printf "${WHITE} >> Ingrese el subdominio de la API Oficial (Ej: api.susistema.com.br): \n"
echo
read -p "> " temp_subdominio_oficial
echo

# Limpiar y salvar subdominio (sin protocolo)
subdominio_oficial=$(echo "${temp_subdominio_oficial}" | sed 's|https://||g' | sed 's|http://||g' | cut -d'/' -f1)

printf "   ${WHITE}Subdominio API Oficial: ---->> ${YELLOW}${subdominio_oficial}\n"
# Salvar la nueva variable en el archivo de variables principal
echo "subdominio_oficial=${subdominio_oficial}" >>$ARQUIVO_VARIAVEIS
}

# Validación de DNS
verificar_dns_apioficial() {
banner
printf "${WHITE} >> Verificando el DNS del subdominio de la API Oficial...\n"
echo
sleep 2

if ! command -v dig &> /dev/null; then
    sudo apt-get update >/dev/null 2>&1
    sudo apt-get install dnsutils -y >/dev/null 2>&1
fi

local domain=${subdominio_oficial}
local resolved_ip

if [ -z "${domain}" ]; then
    printf "${RED} >> ERROR: El subdominio de la API Oficial está vacío. Revise el paso anterior.${WHITE}\n"
    exit 1
fi

# Consulta DNS (A record)
resolved_ip=$(dig +short ${domain} @8.8.8.8)

if [[ "${resolved_ip}" != "${ip_atual}"* ]] || [ -z "${resolved_ip}" ]; then
    echo "El dominio ${domain} (resuelto a ${resolved_ip}) no está apuntando a la IP pública actual (${ip_atual})."
    echo
    printf "${RED} >> ERROR: Verifique la configuración DNS del subdominio: ${subdominio_oficial}${WHITE}\n"
    sleep 5
    exit 1
else
    echo "Subdominio ${domain} está apuntando correctamente a la IP pública del VPS."
    sleep 2
fi
echo
printf "${WHITE} >> Continuando...\n"
sleep 2
echo
}

# Configurar Nginx para API Oficial
configurar_nginx_apioficial() {
banner
printf "${WHITE} >> Configurando Nginx para API Oficial...\n"
echo

# --- PROTECCIÓN CONTRA DUPLICACIÓN DE NGINX ---
local sites_available_path="/etc/nginx/sites-available/${empresa}-oficial"
local sites_enabled_link="/etc/nginx/sites-enabled/${empresa}-oficial"

# 1. Eliminar enlace simbólico anterior
if [ -L "${sites_enabled_link}" ]; then
    printf "${YELLOW} >> Eliminando enlace simbólico antiguo en ${sites_enabled_link}...${WHITE}\n"
    sudo rm -f "${sites_enabled_link}"
fi

# 2. Eliminar archivo de configuración anterior
if [ -f "${sites_available_path}" ]; then
    printf "${YELLOW} >> Eliminando archivo de configuración antiguo en ${sites_available_path}...${WHITE}\n"
    sudo rm -f "${sites_available_path}"
fi
# --- FINAL DE LA PROTECCIÓN ---


{
    local oficial_hostname=${subdominio_oficial} 
    
    # Creación del archivo de configuración de Nginx (LIMPIO, sin \xa0)
    sudo su - root <<EOF
cat > ${sites_available_path} << 'END'
upstream oficial {
    server 127.0.0.1:${default_apioficial_port};
    keepalive 32;
}
server {
    server_name ${oficial_hostname};
    location / {
        proxy_pass http://oficial;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
        proxy_buffering on;
    }
}
END
ln -sf ${sites_available_path} ${sites_enabled_link}
EOF

    sleep 2
    # Recarga Nginx antes de emitir Certbot para que la nueva config sea leída
    sudo systemctl reload nginx 

    banner
    printf "${WHITE} >> Emitiendo SSL de https://${subdominio_oficial}...\n"
    echo
    local oficial_domain=${subdominio_oficial}
    
    # Ejecuta Certbot
    if [ -z "${email_deploy}" ]; then
        printf "${RED} >> ERROR: El correo para Certbot (email_deploy) no fue encontrado.${WHITE}\n"
        exit 1
    fi

    printf "${WHITE} >> Ejecutando: certbot -m ${email_deploy} --nginx --agree-tos -n -d ${oficial_domain}\n"
    sudo certbot -m "${email_deploy}" \
                --nginx \
                --agree-tos \
                -n \
                -d "${oficial_domain}"
    
    if [ $? -ne 0 ]; then
        printf "${RED} >> ERROR: Fallo al emitir el certificado SSL/TLS con Certbot para ${oficial_domain}.${WHITE}\n"
        printf "${YELLOW} >> Verifique si el DNS está totalmente propagado, si el email es válido y si Nginx está funcionando correctamente.${WHITE}\n"
        exit 1
    fi

    sleep 2
} || trata_erro "configurar_nginx_apioficial"
}

# Crear base de datos para API Oficial
criar_banco_apioficial() {
banner
printf "${WHITE} >> Creando base de datos 'oficialseparado' para API Oficial...\n"
echo
{
    if [ -z "${empresa}" ] || [ -z "${senha_deploy}" ]; then
        printf "${RED} >> ERROR: ¡Variables 'empresa' o 'senha_deploy' no están definidas! Necesarias para la base de datos.${WHITE}\n"
        exit 1
    fi
    
    sudo -u postgres psql <<EOF
CREATE DATABASE oficialseparado WITH OWNER ${empresa};
\q
EOF
    printf "${GREEN} >> ¡Base de datos 'oficialseparado' creada y asociada al usuario '${empresa}' con éxito!${WHITE}\n"
    sleep 2
} || trata_erro "criar_banco_apioficial"
}

# Configurar archivo .env de la API Oficial
configurar_env_apioficial() {
banner
printf "${WHITE} >> Configurando archivo .env de la API Oficial...\n"
echo
{
    local backend_env_path="/home/deploy/${empresa}/backend/.env"
    local jwt_refresh_secret_backend=$(grep "^JWT_REFRESH_SECRET=" "${backend_env_path}" 2>/dev/null | cut -d '=' -f2-)
    local backend_url_full=$(grep "^BACKEND_URL=" "${backend_env_path}" 2>/dev/null | cut -d '=' -f2-)
    
    if [ -z "${jwt_refresh_secret_backend}" ] || [ -z "${backend_url_full}" ]; then
    	printf "${RED} >> ERROR: No fue posible obtener JWT_REFRESH_SECRET o BACKEND_URL del backend principal.${WHITE}\n"
    	exit 1
    fi

    local api_oficial_dir="/home/deploy/${empresa}/api_oficial"
    
    # Ajusta permisos del directorio antes de crear el .env
    mkdir -p "${api_oficial_dir}"
    chown -R deploy:deploy "${api_oficial_dir}"
    
    # Crea el archivo .env
    sudo -u deploy cat > "${api_oficial_dir}/.env" <<EOF
# Configuraciones de acceso a la Base de Datos (Postgres)
DATABASE_LINK=postgresql://${empresa}:${senha_deploy}@localhost:5432/oficialseparado?schema=public
DATABASE_URL=localhost
DATABASE_PORT=5432
DATABASE_USER=${empresa}
DATABASE_PASSWORD=${senha_deploy}
DATABASE_NAME=oficialseparado

# Configuraciones del BotMix Backend (URL Completa con https://)
TOKEN_ADMIN=adminxpert
URL_BACKEND_MULT100=${backend_url_full}
JWT_REFRESH_SECRET=${jwt_refresh_secret_backend}

# Configuraciones de la API Oficial
REDIS_URI=redis://:${senha_deploy}@127.0.0.1:6379
PORT=${default_apioficial_port}
# URL_API_OFICIAL debe ser la URL limpia (sin https://)
URL_API_OFICIAL=${subdominio_oficial}

# Configuraciones de Usuario Inicial
NAME_ADMIN=Admin
EMAIL_ADMIN=admin@botmix.com
PASSWORD_ADMIN=${senha_deploy}
EOF

    printf "${GREEN} >> ¡Archivo .env de la API Oficial configurado con éxito!${WHITE}\n"
    sleep 2
} || trata_erro "configurar_env_apioficial"
}

# Instalar y configurar API Oficial
instalar_apioficial() {
banner
printf "${WHITE} >> Instalando y configurando API Oficial...\n"
echo
{
    local api_oficial_dir="/home/deploy/${empresa}/api_oficial"
    
    # Asumimos que el código fuente ya fue clonado
    chown -R deploy:deploy "${api_oficial_dir}"

    sudo su - deploy <<INSTALL_API
# Configura PATH para Node.js (PM2, npm, npx)
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi

cd ${api_oficial_dir}

printf "${WHITE} >> Instalando dependencias (npm install)...\n"
npm install --force

printf "${WHITE} >> Generando Prisma (npx prisma generate)...\n"
npx prisma generate

printf "${WHITE} >> Compilando aplicación (npm run build)...\n"
npm run build

printf "${WHITE} >> Ejecutando migraciones (npx prisma migrate deploy)...\n"
npx prisma migrate deploy

printf "${WHITE} >> Generando cliente Prisma (npx prisma generate client)...\n"
npx prisma generate client

printf "${WHITE} >> Iniciando aplicación con PM2...\n"
pm2 start dist/main.js --name=api_oficial
pm2 save

printf "${GREEN} >> ¡API Oficial instalada y configurada con éxito!${WHITE}\n"
sleep 2
INSTALL_API
} || trata_erro "instalar_apioficial"
}

# Actualizar .env del backend con URL de la API Oficial
atualizar_env_backend() {
banner
printf "${WHITE} >> Actualizando .env del backend con URL de la API Oficial...\n"
echo
{
    local backend_env_path="/home/deploy/${empresa}/backend/.env"
    
    # Adicionar URL_API_OFICIAL (con https://)
    local new_url="URL_API_OFICIAL=https://${subdominio_oficial}"
    
    # 1. Activa USE_WHATSAPP_OFICIAL
    if ! grep -q "^USE_WHATSAPP_OFICIAL=true" "${backend_env_path}"; then
        sudo sed -i 's|^USE_WHATSAPP_OFICIAL=.*|USE_WHATSAPP_OFICIAL=true|' "${backend_env_path}" || echo "USE_WHATSAPP_OFICIAL=true" | sudo tee -a "${backend_env_path}" >/dev/null
    fi

    # 2. Sustituye o adiciona URL_API_OFICIAL
    if grep -q "^URL_API_OFICIAL=" "${backend_env_path}"; then
        sudo sed -i "s|^URL_API_OFICIAL=.*|${new_url}|" "${backend_env_path}"
    else
        echo "${new_url}" | sudo tee -a "${backend_env_path}" >/dev/null
    fi
    
    # 3. Reiniciar el Backend para cargar la nueva variable
    sudo su - deploy <<RESTART_BACKEND
# Configura PATH para Node.js y PM2
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi
pm2 reload ${empresa}-backend
RESTART_BACKEND

    printf "${GREEN} >> ¡.env del backend actualizado y backend reiniciado con éxito!${WHITE}\n"
    sleep 2
} || trata_erro "atualizar_env_backend"
}

# Reiniciar servicios de Proxy
reiniciar_servicos() {
banner
printf "${WHITE} >> Reiniciando servicios de Proxy (Nginx/Traefik)...\n"
echo
{
    sudo su - root <<EOF
    if systemctl is-active --quiet nginx; then
      sudo systemctl restart nginx
      printf "${GREEN}Nginx reiniciado.${WHITE}\n"
    elif systemctl is-active --quiet traefik; then
      sudo systemctl restart traefik.service
      printf "${GREEN}Traefik reiniciado.${WHITE}\n"
    else
      printf "${YELLOW}Ningún servicio de proxy (Nginx o Traefik) está en ejecución.${WHITE}\n"
    fi
EOF
    printf "${GREEN} >> Servicios de Proxy concluidos.${WHITE}\n"
    sleep 2
} || trata_erro "reiniciar_servicos"
}

# Función principal
main() {
# 1. Reparación Crítica en Nginx (Elimina enlaces e includes rotos)
reparo_nginx_critico
    
# 2. Cargar variables del instalador principal (incluye empresa, email_deploy, senha_deploy)
carregar_variaveis
# 3. Garantiza que el subdominio principal está cargado para configurar el .env de la API Oficial
carregar_subdominio_backend
    
# 4. Recolectar datos de la nueva API
solicitar_dados_apioficial
    
# 5. Verificar DNS
verificar_dns_apioficial
    
# 6. Configurar Proxy y SSL
configurar_nginx_apioficial 
    
# 7. Crear base de datos
criar_banco_apioficial
    
# 8. Configurar variables de entorno de la API Oficial
configurar_env_apioficial
    
# 9. Instalar dependencias e iniciar 
instalar_apioficial
    
# 10. Actualizar el backend principal para usar la nueva API
atualizar_env_backend
    
# 11. Reiniciar servicios
reiniciar_servicos
    
banner
printf "${GREEN} >> ¡Instalación de la API Oficial concluida con éxito!${WHITE}\n"
echo
printf "${WHITE} >> API Oficial disponible en: ${YELLOW}https://${subdominio_oficial}${WHITE}\n"
printf "${WHITE} >> Puerto de la API Oficial: ${YELLOW}${default_apioficial_port}${WHITE}\n"
echo
sleep 5
}

# Ejecutar función principal
main