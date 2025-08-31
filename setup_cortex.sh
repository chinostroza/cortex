#!/bin/bash

# Script de instalación y configuración de Cortex

echo "🧠 Configuración de Cortex - AI Gateway"
echo "========================================"
echo ""

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para imprimir mensajes
print_step() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# 1. Verificar e instalar Elixir si es necesario
echo "1. Verificando instalación de Elixir..."
if ! command -v elixir &> /dev/null; then
    print_warning "Elixir no está instalado. Por favor instala Elixir primero:"
    echo ""
    echo "   sudo apt-get update"
    echo "   sudo apt-get install -y elixir erlang-dev erlang-xmerl"
    echo ""
    echo "O usando asdf (recomendado):"
    echo "   # Instalar asdf"
    echo "   git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0"
    echo "   echo '. $HOME/.asdf/asdf.sh' >> ~/.bashrc"
    echo "   source ~/.bashrc"
    echo ""
    echo "   # Instalar Erlang y Elixir"
    echo "   asdf plugin add erlang"
    echo "   asdf plugin add elixir"
    echo "   asdf install erlang 26.0"
    echo "   asdf install elixir 1.15.7-otp-26"
    echo "   asdf global erlang 26.0"
    echo "   asdf global elixir 1.15.7-otp-26"
    echo ""
    exit 1
else
    print_step "Elixir está instalado: $(elixir --version | head -1)"
fi

# 2. Configurar el archivo .env
echo ""
echo "2. Configurando archivo .env..."

if [ ! -f .env ]; then
    print_error ".env no existe. Creando desde template..."
    cp .env.example .env 2>/dev/null || print_warning "No se encontró .env.example"
fi

# Verificar si las API keys están configuradas
if grep -q "YOUR_API_KEY_HERE" .env; then
    print_warning "¡IMPORTANTE! Necesitas configurar tus API keys en el archivo .env"
    echo ""
    echo "   Edita el archivo .env y reemplaza:"
    echo "   - GROQ_API_KEYS: Obtén tu key en https://console.groq.com/"
    echo "   - GEMINI_API_KEYS: Obtén tu key en https://makersuite.google.com/app/apikey"
    echo "   - COHERE_API_KEYS: Obtén tu key en https://dashboard.cohere.com/api-keys"
    echo ""
    echo "   Puedes agregar múltiples keys separadas por comas para rotación automática"
    echo ""
    read -p "¿Quieres editar el archivo .env ahora? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        ${EDITOR:-nano} .env
    fi
fi

# 3. Generar SECRET_KEY_BASE si no existe
echo ""
echo "3. Verificando SECRET_KEY_BASE..."
if grep -q "CHANGE_ME_USE_MIX_PHX_GEN_SECRET" .env; then
    print_warning "Generando nuevo SECRET_KEY_BASE..."
    SECRET=$(mix phx.gen.secret 2>/dev/null || openssl rand -base64 48)
    sed -i "s/CHANGE_ME_USE_MIX_PHX_GEN_SECRET/$SECRET/" .env
    print_step "SECRET_KEY_BASE generado"
fi

# 4. Instalar dependencias
echo ""
echo "4. Instalando dependencias del proyecto..."
mix local.hex --force
mix local.rebar --force
mix deps.get
print_step "Dependencias instaladas"

# 5. Compilar el proyecto
echo ""
echo "5. Compilando el proyecto..."
MIX_ENV=prod mix compile
print_step "Proyecto compilado"

# 6. Crear script de inicio
echo ""
echo "6. Creando script de inicio..."
cat > start_cortex.sh << 'EOF'
#!/bin/bash
# Script para iniciar Cortex

# Cargar variables de entorno
source .env

# Exportar todas las variables
export $(grep -v '^#' .env | xargs)

# Iniciar el servidor
echo "🚀 Iniciando Cortex en http://localhost:${PORT:-4000}"
MIX_ENV=${MIX_ENV:-prod} elixir --erl "-detached" -S mix phx.server
EOF

chmod +x start_cortex.sh
print_step "Script de inicio creado: start_cortex.sh"

# 7. Crear script de parada
cat > stop_cortex.sh << 'EOF'
#!/bin/bash
# Script para detener Cortex

PID=$(ps aux | grep "[b]eam.*phx.server" | awk '{print $2}')
if [ -n "$PID" ]; then
    echo "Deteniendo Cortex (PID: $PID)..."
    kill $PID
    echo "✓ Cortex detenido"
else
    echo "Cortex no está en ejecución"
fi
EOF

chmod +x stop_cortex.sh
print_step "Script de parada creado: stop_cortex.sh"

# 8. Crear servicio systemd (opcional)
echo ""
echo "7. Configuración de servicio systemd (opcional)..."
cat > cortex.service << EOF
[Unit]
Description=Cortex AI Gateway
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$(pwd)
Environment="MIX_ENV=prod"
Environment="PORT=4000"
EnvironmentFile=$(pwd)/.env
ExecStart=/usr/bin/mix phx.server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo ""
print_step "Archivo de servicio systemd creado: cortex.service"
echo ""
echo "   Para instalar como servicio systemd:"
echo "   sudo cp cortex.service /etc/systemd/system/"
echo "   sudo systemctl daemon-reload"
echo "   sudo systemctl enable cortex"
echo "   sudo systemctl start cortex"

echo ""
echo "========================================"
echo "✅ Configuración completada!"
echo ""
echo "Para iniciar Cortex:"
echo "  ./start_cortex.sh     # Iniciar en background"
echo "  mix phx.server        # Iniciar en foreground"
echo "  iex -S mix phx.server # Iniciar con consola interactiva"
echo ""
echo "Para detener Cortex:"
echo "  ./stop_cortex.sh"
echo ""
echo "Para verificar el estado:"
echo "  curl http://localhost:4000/api/health"
echo ""
echo "API Endpoints:"
echo "  POST http://localhost:4000/api/chat     # Chat con streaming"
echo "  GET  http://localhost:4000/api/health   # Estado de workers"
echo ""
print_warning "Recuerda configurar tus API keys en .env antes de iniciar"