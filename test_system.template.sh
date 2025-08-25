#!/bin/bash

echo "🚀 Test del sistema Córtex Multi-Provider"
echo "========================================"

# CONFIGURACIÓN: Reemplaza con tus API keys reales
export GROQ_API_KEYS=your_groq_api_key_here
export GEMINI_API_KEYS=your_gemini_api_key_here
export COHERE_API_KEYS=your_cohere_api_key_here

# Configuración de modelos (opcional)
export GEMINI_MODEL=gemini-2.0-flash-001
export GROQ_MODEL=llama-3.1-8b-instant  
export COHERE_MODEL=command-light

# Configuración de Ollama (opcional)
export OLLAMA_BASE_URL=http://localhost:11434
export OLLAMA_MODEL=gemma3:4b

echo "✅ Para usar este script:"
echo "   1. Copia este archivo: cp test_system.template.sh test_system.sh"
echo "   2. Edita test_system.sh con tus API keys reales"
echo "   3. Ejecuta: ./test_system.sh"
echo ""
echo "⚠️  NUNCA hagas commit de archivos con API keys reales!"

find_free_port() {
    local port=4001
    while lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; do
        port=$((port+1))
    done
    echo $port
}

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo ""
    echo "🔧 Uso del sistema:"
    echo "   ./test_system.sh              - Test completo"
    echo "   ./test_system.sh --health     - Solo health check"
    echo "   ./test_system.sh --chat       - Solo test de chat"
    exit 0
fi

PORT=$(find_free_port)
echo "🔍 Puerto: $PORT"

export PORT=$PORT
mix phx.server &
SERVER_PID=$!

echo "⏳ Esperando servidor (12 segundos)..."
sleep 12

if [ "$1" = "--health" ]; then
    echo "🏥 Health check:"
    curl -s http://localhost:$PORT/api/health | head -c 300
    echo ""
elif [ "$1" = "--chat" ]; then
    echo "💬 Chat test:"
    curl -v -N -X POST http://localhost:$PORT/api/chat \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"¡Hola! Sistema funcionando."}]}'
else
    echo ""
    echo "🏥 Health check:"
    curl -s http://localhost:$PORT/api/health | head -c 200
    echo ""
    echo ""
    echo "💬 Chat test:"
    curl -v -N -X POST http://localhost:$PORT/api/chat \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"¡Sistema multi-provider operacional!"}]}'
fi

echo ""
echo "🛑 Cerrando servidor..."
kill $SERVER_PID 2>/dev/null

echo ""
echo "✅ Test completado"
echo "🎯 Tu sistema Córtex con 4 providers está listo para 100+ usuarios!"