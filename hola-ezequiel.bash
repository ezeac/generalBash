#!/bin/bash

findandcd() {
    if [ -z "$1" ]; then
        echo "Uso: findandcd <nombre_del_url>"
        return 1
    fi

    # Obtener solo el dominio de la URL
    URL=$1
    DOMAIN=$(echo "$URL" | sed -E 's~https?://~~' | awk -F[/:] '{print $1}')

    # Primero buscar en /etc/nginx/sites-enabled
    FILES=$(grep -rl "$DOMAIN" /etc/nginx/sites-enabled/*)
    if [ -z "$FILES" ]; then
        # Si no encuentra resultados, buscar en /etc/nginx
        FILES=$(grep -rl "$DOMAIN" /etc/nginx/)
        if [ -z "$FILES" ]; then
            echo "No se encontraron archivos que contengan \"$DOMAIN\" en /etc/nginx/sites-enabled/ ni en /etc/nginx/"
            return 1
        fi
    fi

    # Obtener los primeros 10 archivos
    FILES=$(echo "$FILES" | head -n 10)

    for FILE in $FILES; do
        MAGE_ROOT=$(grep -oP "set \\\$MAGE_ROOT \K[^;]+" "$FILE")
        if [ -n "$MAGE_ROOT" ]; then
            DOMAIN_FOUND=$(grep -oP "server_name \K[^;]+" "$FILE" | head -n 1)
            echo "Archivo encontrado: $FILE"
            echo "Dominio encontrado: $DOMAIN_FOUND"
            cd "$MAGE_ROOT" || { echo "No se pudo cambiar al directorio $MAGE_ROOT"; return 1; }
            return 0
        fi
    done

    echo "No se encontró la ruta del MAGE_ROOT en los primeros 10 archivos"
    return 1
}

alias holafindandcd='findandcd'

export VIMINIT=':set mouse-=a'
