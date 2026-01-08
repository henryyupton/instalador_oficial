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
ARQUIVO_ETAPAS="ETAPA_INSTALACAO"
FFMPEG="$(pwd)/ffmpeg.x"
FFMPEG_DIR="$(pwd)/ffmpeg"
ip_atual=$(curl -s http://checkip.amazonaws.com)
jwt_secret=$(openssl rand -base64 32)
jwt_refresh_secret=$(openssl rand -base64 32)

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

# Carregar variáveis
dummy_carregar_variaveis() {
  INSTALADOR_DIR="/root/instalador_single_oficial"
  ARQUIVO_VARIAVEIS_INSTALADOR="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
  
  # Primeiro tenta carregar do diretório do instalador
  if [ -f "$ARQUIVO_VARIAVEIS_INSTALADOR" ]; then
    source "$ARQUIVO_VARIAVEIS_INSTALADOR"
  # Depois tenta do diretório atual
  elif [ -f $ARQUIVO_VARIAVEIS ]; then
    source $ARQUIVO_VARIAVEIS
  else
    empresa="botmix"
    nome_titulo="BotMix"
  fi
}

# Función para verificar si la instalación fue hecha por el instalador
verificar_instalacao_original() {
  printf "${WHITE} >> Verificando si la instalación fue hecha por el instalador...\n"
  echo
  
  INSTALADOR_DIR="/root/instalador_single_oficial"
  ARQUIVO_VARIAVEIS_INSTALADOR="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
  
  if [ ! -d "$INSTALADOR_DIR" ]; then
    printf "${RED}❌ ERROR: La carpeta ${INSTALADOR_DIR} no fue encontrada.\n"
    printf "${RED}   No es posible continuar la actualización, pues los datos de la instalación original no fueron encontrados.${WHITE}\n"
    echo
    exit 1
  fi
  
  if [ ! -f "$ARQUIVO_VARIAVEIS_INSTALADOR" ]; then
    printf "${RED}❌ ERROR: El archivo ${ARQUIVO_VARIAVEIS_INSTALADOR} no fue encontrado.\n"
    printf "${RED}   No es posible continuar la actualización, pues los datos de la instalación original no fueron encontrados.${WHITE}\n"
    echo
    exit 1
  fi
  
  printf "${GREEN}✅ Verificación concluida: Instalación original encontrada. Continuando con la actualización...${WHITE}\n"
  echo
  sleep 2
}

# Función para verificar si ya está en la versión PRO
verificar_versao_pro() {
  printf "${WHITE} >> Verificando si ya está configurado para la versión PRO...\n"
  echo
  
  # Carregar variáveis para obter o nome da empresa
  dummy_carregar_variaveis
  
  GIT_CONFIG_FILE="/home/deploy/${empresa}/.git/config"
  
  # Verificar si el archivo .git/config existe
  if [ ! -f "$GIT_CONFIG_FILE" ]; then
    printf "${YELLOW}⚠️  AVISO: El archivo ${GIT_CONFIG_FILE} no fue encontrado. Continuando...${WHITE}\n"
    echo
    sleep 2
    return 0
  fi
  
  # Verificar si la URL ya contiene multiflow-pro
  if grep -q "multiflow-pro" "$GIT_CONFIG_FILE"; then
    printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
    printf "${GREEN}✅ ¡La versión PRO ya está configurada!${WHITE}\n"
    echo
    printf "${WHITE}   El repositorio ya está apuntando a ${BLUE}multiflow-pro${WHITE}.\n"
    printf "${WHITE}   La migración para PRO ya fue realizada anteriormente.${WHITE}\n"
    echo
    printf "${YELLOW}   ⚠️  No es necesario ejecutar este actualizador nuevamente.${WHITE}\n"
    echo
    printf "${GREEN}   📌 Para actualizar su instalación, ejecute la ${WHITE}actualización normal por el instalador${GREEN}.${WHITE}\n"
    printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
    echo
    exit 0
  fi
  
  printf "${BLUE} >> Versión PRO no detectada. Continuando con la migración para PRO...${WHITE}\n"
  echo
  sleep 2
}

# Función para recolectar token y actualizar .git/config
atualizar_git_config() {
  printf "${WHITE} >> Recolectando token de autorización y actualizando configuración de Git...\n"
  echo
  
  # Solicitar el token del usuario (fuera del bloque para garantizar alcance global)
  printf "${WHITE} >> Escriba el TOKEN de autorización de GitHub para acceso al repositorio multiflow-pro:${WHITE}\n"
  echo
  read -p "> " TOKEN_AUTH
  
  # Verificar si el token fue informado
  if [ -z "$TOKEN_AUTH" ]; then
    printf "${RED}❌ ERROR: El token de autorización no puede estar vacío.${WHITE}\n"
    exit 1
  fi
  
  printf "${BLUE} >> Token de autorización recibido.${WHITE}\n"
  echo
  
  {
    # Cargar variable empresa si aún no está definida
    if [ -z "$empresa" ]; then
      dummy_carregar_variaveis
    fi
    
    INSTALADOR_DIR="/root/instalador_single_oficial"
    
    # VALIDAR EL TOKEN ANTES DE HACER CUALQUIER CAMBIO
    printf "${WHITE} >> Validando token con prueba de git clone...\n"
    echo
    
    TEST_DIR="${INSTALADOR_DIR}/test_clone_$(date +%s)"
    REPO_URL="https://${TOKEN_AUTH}@github.com/scriptswhitelabel/m.git"
    
    # Intentar hacer clone de prueba
    if git clone --depth 1 "${REPO_URL}" "${TEST_DIR}" >/dev/null 2>&1; then
      # Clone exitoso, remover directorio de prueba
      rm -rf "${TEST_DIR}" >/dev/null 2>&1
      printf "${GREEN}✅ ¡Token validado con éxito! Git clone funcionó correctamente.${WHITE}\n"
      echo
      sleep 2
    else
      # Clone falló, token inválido
      rm -rf "${TEST_DIR}" >/dev/null 2>&1
      printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
      printf "${RED}❌ ERROR: ¡Token de autorización inválido!${WHITE}\n"
      echo
      printf "${RED}   La prueba de git clone falló. El token informado no tiene acceso al repositorio multiflow-pro.${WHITE}\n"
      echo
      printf "${YELLOW}   ⚠️  IMPORTANTE:${WHITE}\n"
      printf "${YELLOW}   MultiFlow PRO es un proyecto privado y requiere autorización especial.${WHITE}\n"
      printf "${YELLOW}   Para solicitar acceso o analizar la disponibilidad de migración,${WHITE}\n"
      printf "${YELLOW}   entre en contacto con el administrador del proyecto:${WHITE}\n"
      echo
      printf "${BLUE}   📱 WhatsApp:${WHITE}\n"
      printf "${WHITE}   • https://wa.me/55${WHITE}\n"
      printf "${WHITE}   • https://wa.me/55${WHITE}\n"
      echo
      printf "${RED}   Actualización interrumpida.${WHITE}\n"
      printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
      echo
      exit 1
    fi
    
    # Cargar el token antiguo del archivo VARIAVEIS_INSTALACAO
    ARQUIVO_VARIAVEIS_INSTALADOR="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
    
    if [ -f "$ARQUIVO_VARIAVEIS_INSTALADOR" ]; then
      source "$ARQUIVO_VARIAVEIS_INSTALADOR"
    else
      printf "${RED}❌ ERROR: No fue posible cargar el archivo de variables del instalador.${WHITE}\n"
      exit 1
    fi
    
    # Verificar si el token antiguo existe
    if [ -z "$github_token" ]; then
      printf "${RED}❌ ERROR: Token de autorización (github_token) no encontrado en el archivo de variables.${WHITE}\n"
      exit 1
    fi
    
    TOKEN_ANTIGO="$github_token"
    printf "${BLUE} >> Token antiguo cargado del archivo VARIAVEIS_INSTALACAO.${WHITE}\n"
    
    GIT_CONFIG_FILE="/home/deploy/${empresa}/.git/config"
    
    # Verificar si el archivo .git/config existe
    if [ ! -f "$GIT_CONFIG_FILE" ]; then
      printf "${RED}❌ ERROR: El archivo ${GIT_CONFIG_FILE} no fue encontrado.${WHITE}\n"
      exit 1
    fi
    
    # Crear copia de seguridad del archivo original
    cp "$GIT_CONFIG_FILE" "${GIT_CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    printf "${BLUE} >> Backup del archivo .git/config creado.${WHITE}\n"
    
    # Actualizar la URL del repositorio usando el token antiguo del archivo VARIAVEIS_INSTALACAO
    # Usar grep -F para búsqueda literal (sin regex) del token
    if grep -Fq "${TOKEN_ANTIGO}@github.com/scriptswhitelabel/multiflow" "$GIT_CONFIG_FILE"; then
      # Escapar caracteres especiales del token para uso en sed
      TOKEN_ANTIGO_ESCAPED=$(printf '%s\n' "$TOKEN_ANTIGO" | sed 's/[[\.*^$()+?{|]/\\&/g')
      sed -i "s|url = https://${TOKEN_ANTIGO_ESCAPED}@github.com/scriptswhitelabel/multiflow|url = https://${TOKEN_AUTH}@github.com/scriptswhitelabel/multiflow-pro|g" "$GIT_CONFIG_FILE"
      printf "${GREEN}✅ URL del repositorio actualizada con éxito.${WHITE}\n"
    else
      # Intentar patrón más genérico caso el token específico no sea encontrado
      if grep -q "url = https://.*@github.com/scriptswhitelabel/multiflow" "$GIT_CONFIG_FILE"; then
        sed -i "s|url = https://.*@github.com/scriptswhitelabel/multiflow|url = https://${TOKEN_AUTH}@github.com/scriptswhitelabel/multiflow-pro|g" "$GIT_CONFIG_FILE"
        printf "${GREEN}✅ URL del repositorio actualizada con éxito (patrón genérico).${WHITE}\n"
      else
        printf "${YELLOW}⚠️  AVISO: Patrón de URL no encontrado en el archivo .git/config. Verificando manualmente...${WHITE}\n"
        # Intentar sustituir cualquier URL que contenga scriptswhitelabel/multiflow
        sed -i "s|\(url = https://\)[^@]*\(@github.com/scriptswhitelabel/multiflow\)|\1${TOKEN_AUTH}\2-pro|g" "$GIT_CONFIG_FILE"
        printf "${GREEN}✅ Intento de actualización realizado.${WHITE}\n"
      fi
    fi
    
    echo
    sleep 2
    
  } || {
    printf "${RED}❌ ERROR: Fallo al actualizar configuración de Git en la etapa atualizar_git_config.${WHITE}\n"
    trata_erro "atualizar_git_config"
  }
}

# Función para actualizar el token en el archivo VARIAVEIS_INSTALACAO
atualizar_token_variaveis() {
  printf "${WHITE} >> Actualizando token en el archivo VARIAVEIS_INSTALACAO...\n"
  echo
  
  {
    INSTALADOR_DIR="/root/instalador_single_oficial"
    ARQUIVO_VARIAVEIS_INSTALADOR="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
    
    # Verificar si el archivo existe
    if [ ! -f "$ARQUIVO_VARIAVEIS_INSTALADOR" ]; then
      printf "${RED}❌ ERROR: El archivo ${ARQUIVO_VARIAVEIS_INSTALADOR} no fue encontrado.${WHITE}\n"
      exit 1
    fi
    
    # Verificar si TOKEN_AUTH fue definido
    if [ -z "$TOKEN_AUTH" ]; then
      printf "${RED}❌ ERROR: TOKEN_AUTH no fue definido.${WHITE}\n"
      exit 1
    fi
    
    # Crear copia de seguridad del archivo original
    cp "$ARQUIVO_VARIAVEIS_INSTALADOR" "${ARQUIVO_VARIAVEIS_INSTALADOR}.backup.$(date +%Y%m%d_%H%M%S)"
    printf "${BLUE} >> Backup del archivo VARIAVEIS_INSTALACAO creado.${WHITE}\n"
    
    # Actualizar la línea github_token en el archivo
    if grep -q "^github_token=" "$ARQUIVO_VARIAVEIS_INSTALADOR"; then
      # Sustituir la línea existente
      sed -i "s|^github_token=.*|github_token=${TOKEN_AUTH}|g" "$ARQUIVO_VARIAVEIS_INSTALADOR"
      printf "${GREEN}✅ Token actualizado en el archivo VARIAVEIS_INSTALACAO con éxito.${WHITE}\n"
    else
      # Si no existe la línea, añadir al final del archivo
      echo "github_token=${TOKEN_AUTH}" >> "$ARQUIVO_VARIAVEIS_INSTALADOR"
      printf "${GREEN}✅ Token añadido al archivo VARIAVEIS_INSTALACAO con éxito.${WHITE}\n"
    fi
    
    echo
    sleep 2
    
  } || {
    printf "${RED}❌ ERROR: Fallo al actualizar token en el archivo VARIAVEIS_INSTALACAO en la etapa atualizar_token_variaveis.${WHITE}\n"
    trata_erro "atualizar_token_variaveis"
  }
}

# Función para verificar e instalar Node.js 20.19.4
verificar_e_instalar_nodejs() {
  printf "${WHITE} >> Verificando versión de Node.js instalada...\n"
  
  # Verificar si Node.js está instalado y qué versión
  if command -v node >/dev/null 2>&1; then
    NODE_VERSION=$(node -v | sed 's/v//')
    printf "${BLUE} >> Versión actual de Node.js: ${NODE_VERSION}\n"
    
    # Verificar si la versión es diferente de 20.19.4
    if [ "$NODE_VERSION" != "20.19.4" ]; then
      printf "${YELLOW} >> Versión de Node.js diferente de 20.19.4. Iniciando actualización...\n"
      
      {
        echo "=== Eliminando Node.js antiguo (apt) ==="
        sudo apt remove -y nodejs npm || true
        sudo apt purge -y nodejs || true
        sudo apt autoremove -y || true

        echo "=== Limpiando enlaces antiguos ==="
        sudo rm -f /usr/bin/node || true
        sudo rm -f /usr/bin/npm || true
        sudo rm -f /usr/bin/npx || true

        echo "=== Eliminando repositorios antiguos de NodeSource ==="
        sudo rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null || true
        sudo rm -f /etc/apt/sources.list.d/nodesource*.list 2>/dev/null || true

        echo "=== Instalando Node.js temporal para tener npm ==="
        # Intenta primero con Node.js 22.x (LTS actual), después 20.x
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>&1 | grep -v "does not have a Release file" || \
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - 2>&1 | grep -v "does not have a Release file" || true
        
        sudo apt-get update -y 2>&1 | grep -v "does not have a Release file" | grep -v "Key is stored in legacy" || true
        sudo apt install -y nodejs

        echo "=== Instalando administrador 'n' ==="
        sudo npm install -g n

        echo "=== Instalando Node.js 20.19.4 ==="
        sudo n 20.19.4

        echo "=== Ajustando enlaces globales para la versión correcta ==="
        if [ -f /usr/local/n/versions/node/20.19.4/bin/node ]; then
          sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/node /usr/bin/node
          sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/npm /usr/bin/npm
          sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/npx /usr/bin/npx 2>/dev/null || true
        fi

        # Actualiza el PATH en el perfil del sistema
        if ! grep -q "/usr/local/n/versions/node" /etc/profile 2>/dev/null; then
          echo 'export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH' | sudo tee -a /etc/profile > /dev/null
        fi

        echo "=== Versiones instaladas ==="
        export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH
        node -v
        npm -v

        printf "${GREEN}✅ ¡Instalación finalizada! Node.js 20.19.4 está activo.\n"
        
      } || trata_erro "verificar_e_instalar_nodejs"
      
    else
      printf "${GREEN} >> Node.js ya está en la versión correcta (20.19.4). Continuando...\n"
    fi
  else
    printf "${YELLOW} >> Node.js no encontrado. Iniciando instalación...\n"
    
    {
      echo "=== Eliminando repositorios antiguos de NodeSource ==="
      sudo rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null || true
      sudo rm -f /etc/apt/sources.list.d/nodesource*.list 2>/dev/null || true

      echo "=== Instalando Node.js temporal para tener npm ==="
      # Tenta primeiro com Node.js 22.x (LTS atual), depois 20.x
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>&1 | grep -v "does not have a Release file" || \
      curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - 2>&1 | grep -v "does not have a Release file" || true
      
      sudo apt-get update -y 2>&1 | grep -v "does not have a Release file" | grep -v "Key is stored in legacy" || true
      sudo apt install -y nodejs

      echo "=== Instalando administrador 'n' ==="
      sudo npm install -g n

      echo "=== Instalando Node.js 20.19.4 ==="
      sudo n 20.19.4

      echo "=== Ajustando enlaces globales para la versión correcta ==="
      if [ -f /usr/local/n/versions/node/20.19.4/bin/node ]; then
        sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/node /usr/bin/node
        sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/npm /usr/bin/npm
        sudo ln -sf /usr/local/n/versions/node/20.19.4/bin/npx /usr/bin/npx 2>/dev/null || true
      fi

      # Actualiza el PATH en el perfil del sistema
      if ! grep -q "/usr/local/n/versions/node" /etc/profile 2>/dev/null; then
        echo 'export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH' | sudo tee -a /etc/profile > /dev/null
      fi

      echo "=== Versiones instaladas ==="
      export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH
      node -v
      npm -v

      printf "${GREEN}✅ ¡Instalación finalizada! Node.js 20.19.4 está activo.\n"
      
    } || trata_erro "verificar_e_instalar_nodejs"
  fi
  
  sleep 2
}

# Funciones de actualización
backup_app_atualizar() {

  dummy_carregar_variaveis
  
  # Verifica si la variable empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERROR: ¡Variable 'empresa' no está definida!\n${WHITE}"
    exit 1
  fi
  
  # Verifica si el archivo .env existe
  ENV_FILE="/home/deploy/${empresa}/backend/.env"
  if [ ! -f "$ENV_FILE" ]; then
    printf "${YELLOW} >> AVISO: Archivo .env no encontrado en $ENV_FILE. Saltando backup.\n${WHITE}"
    return 0
  fi
  
  source "$ENV_FILE"
  {
    printf "${WHITE} >> Haciendo backup de la base de datos de la empresa ${empresa}...\n"
    db_password=$(grep "DB_PASS=" "$ENV_FILE" | cut -d '=' -f2)
    [ ! -d "/home/deploy/backups" ] && mkdir -p "/home/deploy/backups"
    backup_file="/home/deploy/backups/${empresa}_$(date +%d-%m-%Y_%Hh).sql"
    PGPASSWORD="${db_password}" pg_dump -U ${empresa} -h localhost ${empresa} >"${backup_file}"
    printf "${GREEN} >> Backup de la base de datos ${empresa} concluido. Archivo de backup: ${backup_file}\n"
    sleep 2
  } || trata_erro "backup_app_atualizar"

# Dados do Whaticket
TOKEN="u"
QUEUE_ID="15"
USER_ID=""
MENSAGEM="🚨 INICIANDO Atualização do ${nome_titulo} para MULTIFLO"

# Lista de números
NUMEROS=("${numero_suporte}" "44")

# Enviar para cada número
for NUMERO in "${NUMEROS[@]}"; do
  curl -s -X POST https://apiweb \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "number": "'"$NUMERO"'",
      "body": "'"$MENSAGEM"'",
      "userId": "'"$USER_ID"'",
      "queueId": "'"$QUEUE_ID"'",
      "sendSignature": false,
      "closeTicket": true
    }'
done
  
}

otimiza_banco_atualizar() {
  printf "${WHITE} >> Realizando Mantenimiento de la Base de Datos de la empresa ${empresa}... \n"
  
  # Verifica si la variable empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERROR: ¡Variable 'empresa' no está definida!\n${WHITE}"
    exit 1
  fi
  
  # Verifica si el archivo .env existe
  ENV_FILE="/home/deploy/${empresa}/backend/.env"
  if [ ! -f "$ENV_FILE" ]; then
    printf "${YELLOW} >> AVISO: Archivo .env no encontrado en $ENV_FILE. Saltando optimización de la base.\n${WHITE}"
    return 0
  fi
  
  {
    db_password=$(grep "DB_PASS=" "$ENV_FILE" | cut -d '=' -f2)
    if [ -z "$db_password" ]; then
      printf "${YELLOW} >> AVISO: Contraseña de la base no encontrada. Saltando optimización.\n${WHITE}"
      return 0
    fi
    sudo su - root <<EOF
    PGPASSWORD="$db_password" vacuumdb -U "${empresa}" -h localhost -d "${empresa}" --full --analyze
    PGPASSWORD="$db_password" psql -U ${empresa} -h 127.0.0.1 -d ${empresa} -c "REINDEX DATABASE ${empresa};"
    PGPASSWORD="$db_password" psql -U ${empresa} -h 127.0.0.1 -d ${empresa} -c "ANALYZE;"
EOF
    sleep 2
  } || trata_erro "otimiza_banco_atualizar"
}

baixa_codigo_atualizar() {
  # Verifica si la variable empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERROR: ¡Variable 'empresa' no está definida!\n${WHITE}"
    dummy_carregar_variaveis
    if [ -z "${empresa}" ]; then
      printf "${RED} >> ERRO: Não foi possível carregar a variável 'empresa'. Abortando.\n${WHITE}"
      exit 1
    fi
  fi
  
  # Verifica si el directorio existe
  if [ ! -d "/home/deploy/${empresa}" ]; then
    printf "${RED} >> ERROR: Directorio /home/deploy/${empresa} no existe!\n${WHITE}"
    exit 1
  fi
  
  printf "${WHITE} >> Recuperando Permisos de la empresa ${empresa}... \n"
  sleep 2
  chown deploy -R /home/deploy/${empresa}
  chmod 775 -R /home/deploy/${empresa}

  sleep 2

  printf "${WHITE} >> Parando Instancias... \n"
  sleep 2
  sudo su - deploy <<STOPPM2
  # Configura PATH para Node.js e PM2
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  pm2 stop all || true
STOPPM2

  sleep 2

  otimiza_banco_atualizar

  printf "${WHITE} >> Actualizando la Aplicación de la Empresa ${empresa}... \n"
  sleep 2

  # Verifica si la variable empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERROR: ¡Variable 'empresa' no está definida!\n${WHITE}"
    dummy_carregar_variaveis
    if [ -z "${empresa}" ]; then
      printf "${RED} >> ERROR: No fue posible cargar la variable 'empresa'. Abortando.\n${WHITE}"
      exit 1
    fi
  fi

  # Verifica si el directorio existe
  if [ ! -d "/home/deploy/${empresa}" ]; then
    printf "${RED} >> ERROR: Directorio /home/deploy/${empresa} no existe!\n${WHITE}"
    exit 1
  fi

  source /home/deploy/${empresa}/frontend/.env 2>/dev/null || true
  frontend_port=${SERVER_PORT:-3000}
  sudo su - deploy <<UPDATEAPP
  # Configura PATH para Node.js e PM2
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  APP_DIR="/home/deploy/${empresa}"
  BACKEND_DIR="\${APP_DIR}/backend"
  FRONTEND_DIR="\${APP_DIR}/frontend"
  
  # Verifica si los directorios existen
  if [ ! -d "\$APP_DIR" ]; then
    echo "ERROR: Directorio de la aplicación no existe: \$APP_DIR"
    exit 1
  fi
  
  printf "${WHITE} >> Actualizando Backend...\n"
  echo
  cd "\$APP_DIR"
  
  git fetch origin
  git checkout main
  git reset --hard origin/main
  
  if [ ! -d "\$BACKEND_DIR" ]; then
    echo "ERROR: Directorio del backend no existe: \$BACKEND_DIR"
    exit 1
  fi
  
  cd "\$BACKEND_DIR"
  
  if [ ! -f "package.json" ]; then
    echo "ERROR: package.json no encontrado en \$BACKEND_DIR"
    exit 1
  fi
  
  npm prune --force > /dev/null 2>&1
  export PUPPETEER_SKIP_DOWNLOAD=true
  rm -rf node_modules 2>/dev/null || true
  rm -f package-lock.json 2>/dev/null || true
  rm -rf dist 2>/dev/null || true
  npm install --force
  npm install puppeteer-core --force
  npm i glob
  npm run build
  sleep 2
  printf "${WHITE} >> Actualizando Base de Datos de la empresa ${empresa}...\n"
  echo
  sleep 2
  npx sequelize db:migrate
  sleep 2
  printf "${WHITE} >> Actualizando Frontend de la ${empresa}...\n"
  echo
  sleep 2
  
  if [ ! -d "\$FRONTEND_DIR" ]; then
    echo "ERROR: Directorio del frontend no existe: \$FRONTEND_DIR"
    exit 1
  fi
  
  cd "\$FRONTEND_DIR"
  
  if [ ! -f "package.json" ]; then
    echo "ERROR: package.json no encontrado en \$FRONTEND_DIR"
    exit 1
  fi
  
  npm prune --force > /dev/null 2>&1
  rm -rf node_modules 2>/dev/null || true
  rm -f package-lock.json 2>/dev/null || true
  npm install --force
  
  if [ -f "server.js" ]; then
    sed -i 's/3000/'"$frontend_port"'/g' server.js
  fi
  
  NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
  sleep 2
  pm2 flush
  pm2 reset all
  pm2 restart all
  pm2 save
  pm2 startup
UPDATEAPP

  sudo su - root <<EOF
    if systemctl is-active --quiet nginx; then
      sudo systemctl restart nginx
    elif systemctl is-active --quiet traefik; then
      sudo systemctl restart traefik.service
    else
      printf "${GREEN}Ningún servicio de proxy (Nginx o Traefik) está en ejecución.${WHITE}"
    fi
EOF

  echo
  printf "${WHITE} >> Actualización de ${nome_titulo} concluida...\n"
  echo
  sleep 5

# Dados do Whaticket
TOKEN="u"
QUEUE_ID="15"
USER_ID=""
MENSAGEM="🚨 Actualización de ${nome_titulo} FINALIZADA para BOTMIX-PRO"

# Lista de números
NUMEROS=("${numero_suporte}" "444")

# Enviar para cada número
for NUMERO in "${NUMEROS[@]}"; do
  curl -s -X POST https://apiwe\
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "number": "'"$NUMERO"'",
      "body": "'"$MENSAGEM"'",
      "userId": "'"$USER_ID"'",
      "queueId": "'"$QUEUE_ID"'",
      "sendSignature": false,
      "closeTicket": true
    }'
done

}

# Ejecución automática del flujo de actualización
verificar_instalacao_original
verificar_versao_pro
atualizar_git_config
verificar_e_instalar_nodejs
backup_app_atualizar
baixa_codigo_atualizar
atualizar_token_variaveis
