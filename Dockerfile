# Dockerfile para Cortex - AI Gateway
# Build stage
FROM elixir:1.15-alpine AS builder

# Instalar dependencias de build
RUN apk add --no-cache build-base git

WORKDIR /app

# Copiar archivos de configuración
COPY mix.exs mix.lock ./
COPY config config

# Instalar Hex y Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Configurar entorno de producción
ENV MIX_ENV=prod

# Instalar y compilar dependencias
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && \
    mix deps.compile

# Copiar código fuente
COPY lib lib
COPY priv priv

# Compilar aplicación
RUN mix compile

# Generar release
RUN mix release

# Runtime stage
FROM alpine:3.18

RUN apk add --no-cache openssl ncurses-libs libstdc++ libgcc bash

WORKDIR /app

# Copiar release desde builder
COPY --from=builder /app/_build/prod/rel/cortex ./

# Copiar archivo de configuración de ejemplo
COPY .env.example /app/.env.example

# Crear script de inicio mejorado
RUN cat > /app/docker-entrypoint.sh << 'EOF'
#!/bin/bash
set -e

echo "🧠 Cortex AI Gateway - Docker Edition"
echo "======================================"

# Función para verificar API keys
check_api_keys() {
    local has_keys=false
    
    if [ -n "$GROQ_API_KEYS" ] || [ -n "$GEMINI_API_KEYS" ] || [ -n "$COHERE_API_KEYS" ]; then
        has_keys=true
    fi
    
    if [ "$has_keys" = false ]; then
        echo "⚠️  WARNING: No API keys configured!"
        echo ""
        echo "Configure at least one of:"
        echo "  - GROQ_API_KEYS"
        echo "  - GEMINI_API_KEYS"
        echo "  - COHERE_API_KEYS"
        echo ""
        echo "Example:"
        echo "  docker run -e GROQ_API_KEYS=your_key -p 4000:4000 cortex"
        echo ""
        echo "Or mount a .env file:"
        echo "  docker run --env-file .env -p 4000:4000 cortex"
        echo ""
        exit 1
    fi
}

# Si hay un archivo .env montado, cargarlo
if [ -f /app/.env ]; then
    echo "✓ Loading configuration from .env file"
    export $(grep -v '^#' /app/.env | xargs)
fi

# Verificar que hay al menos una API key configurada
check_api_keys

# Configurar valores por defecto si no están definidos
export PORT=${PORT:-4000}
export MIX_ENV=${MIX_ENV:-prod}
export WORKER_POOL_STRATEGY=${WORKER_POOL_STRATEGY:-local_first}
export API_KEY_ROTATION_STRATEGY=${API_KEY_ROTATION_STRATEGY:-round_robin}
export HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-60}
export RATE_LIMIT_BLOCK_MINUTES=${RATE_LIMIT_BLOCK_MINUTES:-15}

# Mostrar configuración activa
echo ""
echo "Configuration:"
echo "  Port: $PORT"
echo "  Workers configured:"
[ -n "$GROQ_API_KEYS" ] && echo "    ✓ Groq"
[ -n "$GEMINI_API_KEYS" ] && echo "    ✓ Gemini"
[ -n "$COHERE_API_KEYS" ] && echo "    ✓ Cohere"
[ -n "$OLLAMA_URLS" ] && echo "    ✓ Ollama ($OLLAMA_URLS)"
echo ""
echo "Starting Cortex on port $PORT..."
echo "======================================"
echo ""

# Iniciar la aplicación
exec /app/bin/cortex start
EOF

RUN chmod +x /app/docker-entrypoint.sh

# Exponer puerto
EXPOSE 4000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:4000/api/health || exit 1

ENTRYPOINT ["/app/docker-entrypoint.sh"]