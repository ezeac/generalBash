#!/bin/bash

findandcd() {
    if [ -z "$1" ]; then
        echo "Uso: findandcd <nombre_del_url>"
        return 1
    fi

    URL=$1

    # Primero buscar en /etc/nginx/sites-enabled
    FILES=$(grep -rl "$URL" /etc/nginx/sites-enabled/)
    if [ -z "$FILES" ]; then
        # Si no encuentra resultados, buscar en /etc/nginx
        FILES=$(grep -rl "$URL" /etc/nginx/)
        if [ -z "$FILES" ]; then
            echo "No se encontraron archivos que contengan \"$URL\" en /etc/nginx/sites-enabled/ ni en /etc/nginx/"
            return 1
        fi
    fi

    FIRST_FILE=$(echo "$FILES" | head -n 1)

    MAGE_ROOT=$(grep -oP "set \\\$MAGE_ROOT \K[^;]+" "$FIRST_FILE")
    if [ -z "$MAGE_ROOT" ]; then
        echo "No se encontró la ruta del MAGE_ROOT en $FIRST_FILE"
        return 1
    fi
    DOMAIN=$(grep -oP "server_name \K[^;]+" "$FIRST_FILE" | head -n 1)

    echo "Archivo encontrado: $FIRST_FILE"
    echo "Dominio encontrado: $DOMAIN"

    cd "$MAGE_ROOT" || { echo "No se pudo cambiar al directorio $MAGE_ROOT"; return 1; }
}

alias holafindandcd='findandcd'

export VIMINIT=':set mouse-=a'

