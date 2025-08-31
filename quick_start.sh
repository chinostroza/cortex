#!/bin/bash

echo "🧠 Cortex AI Gateway - Quick Start"
echo "==================================="

# Verificar Elixir
if ! command -v elixir &> /dev/null; then
    echo "❌ Elixir no está instalado!"
    echo ""
    echo "Instálalo con:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y elixir erlang-dev erlang-xmerl"
    echo ""
    echo "Luego ejecuta este script nuevamente."
    exit 1
fi

echo "✓ Elixir instalado"

# Cargar variables de entorno
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
    echo "✓ Configuración cargada desde .env"
fi

# Instalar hex y rebar si no están
echo "📦 Preparando herramientas..."
mix local.hex --force 2>/dev/null
mix local.rebar --force 2>/dev/null

# Instalar dependencias
if [ ! -d "deps" ] || [ ! -d "_build" ]; then
    echo "📦 Instalando dependencias (primera vez)..."
    mix deps.get
    mix deps.compile
fi

# Compilar
echo "🔨 Compilando proyecto..."
MIX_ENV=prod mix compile

echo ""
echo "==================================="
echo "✅ Listo para iniciar!"
echo ""
echo "🚀 Iniciando Cortex en http://localhost:4000"
echo "   Presiona Ctrl+C dos veces para detener"
echo ""

# Iniciar servidor
MIX_ENV=prod mix phx.server