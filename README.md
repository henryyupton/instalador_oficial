# BotMix Installer

## Instalación Limpia
Ejecute el siguiente comando para descargar e instalar BotMix:

```bash
sudo apt install -y git && git clone https://github.com/henryyupton/instalador_oficial && sudo chmod -R 777 instalador_oficial && cd instalador_oficial && sudo chmod +x *.sh && sudo ./instalador_single.sh
```
Nota: El instalador se encargará de configurar los permisos necesarios.

## Ejecutar Nuevamente / Actualizar Instalador
Si necesita ejecutar el instalador nuevamente o descargar correcciones recientes del script:

```bash
cd /root/instalador_oficial && git reset --hard && git pull && sudo chmod +x *.sh && sudo ./instalador_single.sh
```

© BotMix System. Todos los derechos reservados.