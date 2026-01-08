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
  echo "║                    ACTUALIZADOR API OFICIAL                  ║"
  echo "║                                                              ║"
  echo "║                    BotMix System                          ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  printf "${WHITE}"
  echo
}

# Carregar variáveis
carregar_variaveis() {
  if [ -f $ARQUIVO_VARIAVEIS ]; then
    source $ARQUIVO_VARIAVEIS
  else
    empresa="botmix"
    nome_titulo="BotMix"
  fi
}

# Verificar si la API Oficial ya está instalada
verificar_instalacao_apioficial() {
  banner
  printf "${WHITE} >> Verificando si la API Oficial ya está instalada...\n"
  echo
  
  # Verificar si el directorio de la API Oficial existe
  if [ ! -d "/home/deploy/${empresa}/api_oficial" ]; then
    printf "${RED} >> ERROR: ¡La API Oficial no está instalada!${WHITE}\n"
    printf "${RED} >> Directorio /home/deploy/${empresa}/api_oficial no encontrado.${WHITE}\n"
    echo
    printf "${YELLOW} >> Ejecute primero el script de instalación de la API Oficial.${WHITE}\n"
    echo
    sleep 5
    exit 1
  fi
  
  # Verificar si el proceso PM2 está rodando (como usuario deploy)
  pm2_status=$(sudo su - deploy -c "pm2 list | grep -q 'api_oficial' && echo 'running' || echo 'not_running'")
  
  if [ "$pm2_status" = "not_running" ]; then
    printf "${RED} >> AVISO: ¡La API Oficial no se está ejecutando en PM2!${WHITE}\n"
    printf "${YELLOW} >> Intentando iniciar la API Oficial...${WHITE}\n"
    echo
  else
    printf "${GREEN} >> ¡API Oficial encontrada y ejecutándose en PM2!${WHITE}\n"
    echo
  fi
  
  sleep 2
}

# Actualizar código de la API Oficial
atualizar_codigo_apioficial() {
  banner
  printf "${WHITE} >> Actualizando código de la API Oficial...\n"
  echo
  {
    sudo su - deploy <<EOF
cd /home/deploy/${empresa}

printf "${WHITE} >> Haciendo pull de las actualizaciones...\n"
git reset --hard
git pull

cd /home/deploy/${empresa}/api_oficial

printf "${WHITE} >> Instalando dependencias actualizadas...\n"
npm install

printf "${WHITE} >> Generando Prisma...\n"
npx prisma generate

printf "${WHITE} >> Compilando aplicación...\n"
npm run build

printf "${WHITE} >> Ejecutando migraciones...\n"
npx prisma migrate deploy

printf "${WHITE} >> Generando cliente Prisma...\n"
npx prisma generate client

printf "${GREEN} >> ¡Código de la API Oficial actualizado con éxito!${WHITE}\n"
sleep 2
EOF
  } || trata_erro "atualizar_codigo_apioficial"
}

# Reiniciar API Oficial en PM2
reiniciar_apioficial() {
  banner
  printf "${WHITE} >> Reiniciando API Oficial en PM2...\n"
  echo
  {
    sudo su - deploy <<EOF
    # Parar la API Oficial si se está ejecutando
    pm2 stop api_oficial 2>/dev/null || true
    
    # Iniciar la API Oficial
    pm2 restart api_oficial
    
    # Guardar configuración de PM2
    pm2 save
    
    printf "${GREEN} >> ¡API Oficial reiniciada con éxito!${WHITE}\n"
    sleep 2
EOF
  } || trata_erro "reiniciar_apioficial"
}

# Función principal
main() {
  carregar_variaveis
  verificar_instalacao_apioficial
  atualizar_codigo_apioficial
  reiniciar_apioficial
  
  banner
  printf "${GREEN} >> ¡Actualización de la API Oficial concluida con éxito!${WHITE}\n"
  echo
  printf "${WHITE} >> API Oficial actualizada y ejecutándose en el puerto: ${YELLOW}${default_apioficial_port}${WHITE}\n"
  echo
  sleep 5
}

# Executar função principal
main
