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
    BLUE="\033[0;34m"
    YELLOW="\033[0;33m"
    NC="\033[0m" # Sin color

    # Función para buscar en un directorio específico
    search_in_directory() {
        local DIRECTORY=$1
        grep -rl "server_name.*$DOMAIN" "$DIRECTORY" 2>/dev/null
    }

    # Buscar en directorios de configuración de Nginx
    FILES_ENABLED=$(search_in_directory "/etc/nginx/sites-enabled")
    FILES_CONF_D=$(search_in_directory "/etc/nginx/conf.d")
    FILES_NGINX=$(search_in_directory "/etc/nginx")

    # Combinar los archivos, manteniendo el orden y eliminando duplicados
    FILES=$(printf "%s\n%s\n%s\n" "$FILES_ENABLED" "$FILES_CONF_D" "$FILES_NGINX" | awk '!seen[$0]++' | sed '/^$/d')

    if [ -z "$FILES" ]; then
        echo "No se encontraron archivos de configuración con el dominio \"$DOMAIN\""
        echo "Realizando búsqueda recursiva en /etc/nginx:"
        grep -r --color=auto "$DOMAIN" /etc/nginx
        return 1
    fi

    RESULTS=()
    INDEX=1

    for FILE in $FILES; do
        # Buscar el bloque de servidor que contiene el dominio
        SERVER_BLOCK=$(awk "/server\s*{/,/}/" "$FILE" | grep -E "server_name.*$DOMAIN")
        if [ -n "$SERVER_BLOCK" ]; then
            # Intentar obtener $MAGE_ROOT del mismo bloque de servidor
            MAGE_ROOT=$(awk "/server\s*{/,/}/" "$FILE" | grep -A 50 "server_name.*$DOMAIN" | grep -m1 -oP "set \\\$MAGE_ROOT \K[^;]+")
            PORT=$(awk "/server\s*{/,/}/" "$FILE" | grep -A 50 "server_name.*$DOMAIN" | grep -m1 "proxy_pass" | grep -oP ":[0-9]+" | cut -d: -f2 | head -1)
            DOMAIN_FOUND=$(echo "$SERVER_BLOCK" | grep -oP "server_name \K[^;]+")
            
            if [ -n "$MAGE_ROOT" ]; then
                RESULTS+=("$INDEX")
                RESULTS+=("$DOMAIN_FOUND")
                RESULTS+=("$FILE")
                RESULTS+=("traditional")
                RESULTS+=("$MAGE_ROOT")
                ((INDEX++))
            elif [ -n "$PORT" ]; then
                RESULTS+=("$INDEX")
                RESULTS+=("$DOMAIN_FOUND")
                RESULTS+=("$FILE")
                RESULTS+=("docker")
                RESULTS+=("$PORT")
                ((INDEX++))
            fi
        fi
    done

    if [ ${#RESULTS[@]} -eq 0 ]; then
        echo "No se encontraron configuraciones válidas para el dominio."
        return 1
    else
        # Agrupar resultados tradicionales por directorio (MAGE_ROOT)
        declare -A grouped_traditional
        for ((i=0; i<${#RESULTS[@]}; i+=5)); do
            type="${RESULTS[$i+3]}"
            data="${RESULTS[$i+4]}"
            domain="${RESULTS[$i+1]}"
            if [ "$type" = "traditional" ]; then
                if [ -z "${grouped_traditional[$data]}" ]; then
                    grouped_traditional[$data]=""
                fi
                grouped_traditional[$data]="${grouped_traditional[$data]} $domain"
            fi
        done

        # Crear nuevos resultados agrupados
        GROUPED_RESULTS=()
        index=1

        # Procesar grupos tradicionales
        for key in "${!grouped_traditional[@]}"; do
            domains="${grouped_traditional[$key]}"
            domains=$(echo "$domains" | sed 's/^ //')  # Eliminar espacio inicial
            GROUPED_RESULTS+=("$index")
            GROUPED_RESULTS+=("$domains")
            GROUPED_RESULTS+=("$key")
            GROUPED_RESULTS+=("traditional")
            GROUPED_RESULTS+=("$key")
            ((index++))
        done

        # Procesar entradas docker (sin agrupar)
        for ((i=0; i<${#RESULTS[@]}; i+=5)); do
            type="${RESULTS[$i+3]}"
            if [ "$type" = "docker" ]; then
                domain="${RESULTS[$i+1]}"
                file="${RESULTS[$i+2]}"
                port="${RESULTS[$i+4]}"
                GROUPED_RESULTS+=("$index")
                GROUPED_RESULTS+=("$domain")
                GROUPED_RESULTS+=("$file")
                GROUPED_RESULTS+=("docker")
                GROUPED_RESULTS+=("$port")
                ((index++))
            fi
        done

        # Reemplazar resultados originales con agrupados
        RESULTS=("${GROUPED_RESULTS[@]}")

        echo "Se encontraron los siguientes resultados (priorizando /etc/nginx/sites-enabled):"
        for ((i=0; i<${#RESULTS[@]}; i+=5)); do
            NUM="${RESULTS[$i]}"
            DOM="${RESULTS[$i+1]}"
            FILE="${RESULTS[$i+2]}"
            TYPE="${RESULTS[$i+3]}"
            DATA="${RESULTS[$i+4]}"

            if [ "$TYPE" = "traditional" ]; then
                printf "%s) Directorio: ${GREEN}%s${NC} (traditional)\n" "$NUM" "$DATA"
                printf "   Dominios: %s\n" "$DOM"
            else
                printf "%s) Dominio: ${GREEN}%s${NC} (docker)\n" "$NUM" "$DOM"
                printf "   Archivo: %s\n" "$FILE"
                printf "   Puerto proxy: ${BLUE}%s${NC}\n" "$DATA"
            fi
        done

        # Preguntar al usuario cuál seleccionar si hay múltiples opciones
        if [ "$index" -gt 2 ]; then
            printf "Seleccione el número del sitio al que desea ir: "
            read -r SELECTION

            # Validar la selección del usuario
            if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -ge "$index" ]; then
                echo "Selección inválida."
                return 1
            fi
        else
            SELECTION=1
        fi

        # Obtener los datos seleccionados
        TYPE="${RESULTS[$(( (SELECTION - 1) * 5 + 3 ))]}"
        DATA="${RESULTS[$(( (SELECTION - 1) * 5 + 4 ))]}"

        if [ "$TYPE" = "traditional" ]; then
            cd "$DATA" || { echo "No se pudo cambiar al directorio $DATA"; return 1; }
            return 0
        else
            PORT="$DATA"
            echo "Buscando contenedor Docker con puerto $PORT..."
            
            # Buscar ID del contenedor usando el puerto
            CONTAINER_ID=$(docker ps --format '{{.ID}}' | while read -r ID; do
                if docker port "$ID" | grep -q ":$PORT"; then
                    echo "$ID"
                    break
                fi
            done)

            if [ -z "$CONTAINER_ID" ]; then
                echo "No se encontró ningún contenedor usando el puerto $PORT."
                return 1
            fi

            echo "Contenedor encontrado: ${CONTAINER_ID}"
            echo "Buscando ruta del proyecto..."
            
            # Obtener todos los volúmenes bindeados del contenedor
            VOLUMES=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}:{{.Destination}}{{"\n"}}{{end}}{{end}}' "$CONTAINER_ID")

            if [ -z "$VOLUMES" ]; then
                echo "No se encontraron volúmenes bindeados en el contenedor."
                return 1
            fi

            # Intentar encontrar automáticamente la raíz del proyecto
            HOST_PATH=""
            while IFS= read -r line; do
                IFS=':' read -r SOURCE DEST <<< "$line"
                # Buscar archivos clave que indiquen la raíz del proyecto
                if [[ -f "${SOURCE}/composer.json" || -d "${SOURCE}/app" || -d "${SOURCE}/vendor" ]]; then
                    HOST_PATH="$SOURCE"
                    break
                fi
            done <<< "$VOLUMES"

            if [ -n "$HOST_PATH" ]; then
                echo -e "Ruta del proyecto encontrada automáticamente: ${YELLOW}$HOST_PATH${NC}"
                cd "$HOST_PATH" || { echo "No se pudo cambiar al directorio $HOST_PATH"; return 1; }
                return 0
            fi

            # Si no se encontró automáticamente, buscar archivos clave en los directorios padres
            while IFS= read -r line; do
                IFS=':' read -r SOURCE DEST <<< "$line"
                PARENT_DIR=$(dirname "$SOURCE")
                if [[ -f "${PARENT_DIR}/composer.json" || -d "${PARENT_DIR}/app" || -d "${PARENT_DIR}/vendor" ]]; then
                    HOST_PATH="$PARENT_DIR"
                    break
                fi
            done <<< "$VOLUMES"

            if [ -n "$HOST_PATH" ]; then
                echo -e "Ruta del proyecto encontrada en directorio padre: ${YELLOW}$HOST_PATH${NC}"
                cd "$HOST_PATH" || { echo "No se pudo cambiar al directorio $HOST_PATH"; return 1; }
                return 0
            fi

            # Si aún no se encontró, mostrar todos los volúmenes y preguntar
            VOLUME_PATHS=()
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    VOLUME_PATHS+=("$line")
                fi
            done <<< "$VOLUMES"

            echo "Se encontraron múltiples volúmenes:"
            for i in "${!VOLUME_PATHS[@]}"; do
                IFS=':' read -r SOURCE DEST <<< "${VOLUME_PATHS[$i]}"
                printf "%2d) Origen: ${BLUE}%s${NC}\n" "$((i+1))" "$SOURCE"
                printf "    Destino: %s\n" "$DEST"
            done

            printf "Seleccione el volumen que contiene el proyecto: "
            read -r VOL_SELECTION

            if ! [[ "$VOL_SELECTION" =~ ^[0-9]+$ ]] || [ "$VOL_SELECTION" -lt 1 ] || [ "$VOL_SELECTION" -gt "${#VOLUME_PATHS[@]}" ]; then
                echo "Selección inválida."
                return 1
            fi

            IFS=':' read -r SOURCE DEST <<< "${VOLUME_PATHS[$((VOL_SELECTION-1))]}"
            echo -e "Ruta del proyecto: ${YELLOW}$SOURCE${NC}"
            cd "$SOURCE" || { echo "No se pudo cambiar al directorio $SOURCE"; return 1; }
            return 0
        fi
    fi
}

alias holafindandcd='findandcd'
export VIMINIT=':set mouse-=a | syntax on | set background=dark | colorscheme desert'
