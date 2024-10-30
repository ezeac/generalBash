#!/bin/bash

findandcd() {
    if [ -z "$1" ]; then
        echo "Uso: findandcd <nombre_del_url>"
        return 1
    fi

    # Obtener solo el dominio de la URL
    URL=$1
    DOMAIN=$(echo "$URL" | sed -E 's~https?://~~' | awk -F[/:] '{print $1}')

    # Códigos ANSI para colores
    GREEN="\033[0;32m"
    NC="\033[0m" # Sin color

    # Función para buscar en un directorio específico
    search_in_directory() {
        local DIRECTORY=$1
        grep -rl "server_name.*$DOMAIN" "$DIRECTORY" 2>/dev/null
    }

    # Buscar en directorios de configuración de Nginx
    FILES=$(search_in_directory /etc/nginx/sites-enabled)
    FILES+=" $(search_in_directory /etc/nginx/conf.d)"
    FILES+=" $(search_in_directory /etc/nginx)"

    # Filtrar resultados únicos y eliminar líneas vacías
    FILES=$(echo "$FILES" | tr ' ' '\n' | sort -u | sed '/^$/d')

    if [ -z "$FILES" ]; then
        echo "No se encontraron archivos que contengan \"$DOMAIN\" en las directivas server_name de /etc/nginx/"
        return 1
    fi

    RESULTS=()
    SELECTED_FILES=()
    INDEX=1

    for FILE in $FILES; do
        MAGE_ROOT=$(grep -oP "set \\\$MAGE_ROOT \K[^;]+" "$FILE")
        if [ -n "$MAGE_ROOT" ]; then
            DOMAIN_FOUND=$(grep -oP "server_name \K[^;]+" "$FILE" | head -n 1)
            IFS=' ' read -r -a DOMAIN_ARRAY <<< "$DOMAIN_FOUND"
            FOUND=0
            for DOM in "${DOMAIN_ARRAY[@]}"; do
                if [[ "$DOM" == *"$DOMAIN"* ]]; then
                    FOUND=1
                    break
                fi
            done
            if [ "$FOUND" -eq 1 ]; then
                RESULTS+=("$INDEX")
                RESULTS+=("$DOMAIN_FOUND")
                RESULTS+=("$FILE")
                RESULTS+=("$MAGE_ROOT")
                SELECTED_FILES+=("$FILE")
                ((INDEX++))
            fi
        fi
    done

    if [ ${#RESULTS[@]} -eq 0 ]; then
        echo "No se encontró la ruta del MAGE_ROOT en los archivos encontrados."
        return 1
    else
        echo "Se encontraron múltiples resultados:"
        for ((i=0; i<${#RESULTS[@]}; i+=4)); do
            NUM="${RESULTS[$i]}"
            DOM="${RESULTS[$i+1]}"
            FILE="${RESULTS[$i+2]}"
            MAGE_ROOT="${RESULTS[$i+3]}"

            # Imprimir con colores usando printf
            printf "%s) Dominio: ${GREEN}%s${NC}\n" "$NUM" "$DOM"
            printf "   Archivo: %s\n" "$FILE"
            printf "   MAGE_ROOT: %s\n" "$MAGE_ROOT"
        done

        # Preguntar al usuario cuál seleccionar
        printf "Seleccione el número del sitio al que desea ir: "
        read -r SELECTION

        # Validar la selección del usuario
        if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -ge "$INDEX" ]; then
            echo "Selección inválida."
            return 1
        fi

        # Obtener el MAGE_ROOT seleccionado
        SELECTED_FILE="${SELECTED_FILES[$((SELECTION - 1))]}"
        MAGE_ROOT=$(grep -oP "set \\\$MAGE_ROOT \K[^;]+" "$SELECTED_FILE")

        cd "$MAGE_ROOT" || { echo "No se pudo cambiar al directorio $MAGE_ROOT"; return 1; }
        return 0
    fi
}

alias holafindandcd='findandcd'

export VIMINIT=':set mouse-=a'

