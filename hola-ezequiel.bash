#!/bin/bash

# Define la función findandcd
findandcd() {
    # Verifica si se pasó el parámetro "URL"
    if [ -z "$1" ]; then
        echo "Uso: findandcd <nombre_del_url>"
        return 1
    fi

    URL=$1

    # Busca archivos que contengan "$URL" en /etc/nginx/
    FILES=$(grep -rl "$URL" /etc/nginx/)

    # Verifica si se encontraron archivos
    if [ -z "$FILES" ]; then
        echo "No se encontraron archivos que contengan \"$URL\" en /etc/nginx/"
        return 1
    fi

    # Obtén el primer archivo encontrado
    FIRST_FILE=$(echo "$FILES" | head -n 1)

    # Busca la ruta del MAGE_ROOT en el primer archivo encontrado
    MAGE_ROOT=$(grep -oP "set \\\$MAGE_ROOT \K[^;]+" "$FIRST_FILE")

    # Verifica si se encontró la ruta del MAGE_ROOT
    if [ -z "$MAGE_ROOT" ]; then
        echo "No se encontró la ruta del MAGE_ROOT en $FIRST_FILE"
        return 1
    fi

    # Busca el dominio completo en el archivo
    DOMAIN=$(grep -oP "server_name \K[^;]+" "$FIRST_FILE")

    # Muestra el archivo y el dominio encontrado
    echo "Archivo encontrado: $FIRST_FILE"
    echo "Dominio encontrado: $DOMAIN"

    # Cambia el directorio a la ruta del MAGE_ROOT
    cd "$MAGE_ROOT" || { echo "No se pudo cambiar al directorio $MAGE_ROOT"; return 1; }
}

# Define el alias en la sesión actual del shell
alias findandcd='findandcd'
