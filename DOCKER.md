# 🐳 Cortex con Docker

## 🚀 Inicio Rápido

### Opción 1: Docker Run (Simple)

```bash
# Con tus API keys directamente
docker run -d \
  --name cortex \
  -p 4000:4000 \
  -e GROQ_API_KEYS=tu_key_aqui \
  -e GEMINI_API_KEYS=tu_key_aqui \
  cortex:latest

# Con archivo .env
docker run -d \
  --name cortex \
  -p 4000:4000 \
  --env-file .env \
  cortex:latest
```

### Opción 2: Docker Compose (Recomendado)

1. **Configurar tus API keys en `.env`:**
```bash
cp .env.example .env
nano .env  # Editar y agregar tus keys
```

2. **Iniciar con Docker Compose:**
```bash
docker-compose up -d
```

3. **Verificar que está funcionando:**
```bash
curl http://localhost:4000/api/health
```

## 📦 Construir la Imagen

### Construcción Simple
```bash
docker build -t cortex:latest .
```

### Con Script Automatizado
```bash
# Solo construir
./docker-build.sh --build

# Construir y probar
./docker-build.sh --test

# Construir, probar y publicar
DOCKER_HUB_USER=tu-usuario ./docker-build.sh --publish
```

## 🔧 Configuración

### Variables de Entorno Requeridas

Al menos una de estas API keys debe estar configurada:

```env
# Groq (Gratis, Rápido)
GROQ_API_KEYS=gsk_xxxxx,gsk_yyyyy

# Google Gemini
GEMINI_API_KEYS=AIza_xxxxx

# Cohere
COHERE_API_KEYS=co_xxxxx
```

### Variables Opcionales

```env
# Configuración del servidor
PORT=4000

# Modelos por defecto
GROQ_MODEL=llama-3.1-8b-instant
GEMINI_MODEL=gemini-2.0-flash-exp
COHERE_MODEL=command

# Estrategias
WORKER_POOL_STRATEGY=local_first
API_KEY_ROTATION_STRATEGY=round_robin
HEALTH_CHECK_INTERVAL=60
RATE_LIMIT_BLOCK_MINUTES=15

# Ollama (si tienes un servidor local/remoto)
OLLAMA_URLS=http://host.docker.internal:11434
OLLAMA_MODEL=llama3:8b
```

## 🎯 Uso con Docker

### Verificar Estado
```bash
# Health check
curl http://localhost:4000/api/health

# Ver logs
docker logs cortex

# En tiempo real
docker logs -f cortex
```

### Hacer Peticiones

```bash
# Chat simple
curl -N -X POST http://localhost:4000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hola!"}]}'

# Forzar provider específico
curl -N -X POST http://localhost:4000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hola!"}], "provider": "groq"}'
```

## 🔄 Docker Compose Avanzado

### Con Ollama Local

Descomenta la sección de Ollama en `docker-compose.yml`:

```yaml
services:
  cortex:
    # ... configuración de cortex ...
    
  ollama:
    image: ollama/ollama:latest
    container_name: ollama-local
    ports:
      - "11434:11434"
    volumes:
      - ollama-data:/root/.ollama
    networks:
      - cortex-network
    restart: unless-stopped

volumes:
  ollama-data:
```

Luego:
```bash
# Iniciar ambos servicios
docker-compose up -d

# Descargar un modelo en Ollama
docker exec ollama-local ollama pull llama3:8b

# Actualizar Cortex para usar Ollama
docker-compose exec cortex sh -c 'export OLLAMA_URLS=http://ollama:11434'
docker-compose restart cortex
```

## 🚢 Despliegue en Producción

### En un VPS

```bash
# 1. Clonar repositorio
git clone https://github.com/tu-usuario/cortex.git
cd cortex

# 2. Configurar .env con keys reales
cp .env.example .env
nano .env

# 3. Construir y ejecutar
docker-compose up -d

# 4. Configurar nginx (opcional)
sudo nano /etc/nginx/sites-available/cortex
```

Configuración nginx ejemplo:
```nginx
server {
    listen 80;
    server_name api.tu-dominio.com;

    location / {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        
        # Para streaming
        proxy_buffering off;
        proxy_cache off;
    }
}
```

### En Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cortex
spec:
  replicas: 3
  selector:
    matchLabels:
      app: cortex
  template:
    metadata:
      labels:
        app: cortex
    spec:
      containers:
      - name: cortex
        image: tu-usuario/cortex:latest
        ports:
        - containerPort: 4000
        env:
        - name: GROQ_API_KEYS
          valueFrom:
            secretKeyRef:
              name: cortex-secrets
              key: groq-keys
        - name: GEMINI_API_KEYS
          valueFrom:
            secretKeyRef:
              name: cortex-secrets
              key: gemini-keys
---
apiVersion: v1
kind: Service
metadata:
  name: cortex-service
spec:
  selector:
    app: cortex
  ports:
  - port: 80
    targetPort: 4000
  type: LoadBalancer
```

## 🐛 Troubleshooting

### Container no inicia
```bash
# Ver logs detallados
docker logs cortex

# Verificar que las API keys están configuradas
docker exec cortex env | grep API_KEYS
```

### No hay workers disponibles
```bash
# Verificar health de workers
curl http://localhost:4000/api/health

# Reiniciar container
docker restart cortex
```

### Problemas de red
```bash
# Si usas Ollama local desde Docker
# En Linux, usa: host.docker.internal o la IP real
OLLAMA_URLS=http://host.docker.internal:11434

# En macOS/Windows Docker Desktop
OLLAMA_URLS=http://host.docker.internal:11434
```

## 🔐 Seguridad

### Mejores Prácticas

1. **Nunca hardcodees API keys en el Dockerfile**
2. **Usa Docker secrets en producción**
3. **Limita los puertos expuestos**
4. **Usa HTTPS con un reverse proxy**
5. **Actualiza regularmente la imagen base**

### Ejemplo con Docker Secrets

```bash
# Crear secrets
echo "tu_groq_key" | docker secret create groq_key -
echo "tu_gemini_key" | docker secret create gemini_key -

# Usar en docker-compose
services:
  cortex:
    image: cortex:latest
    secrets:
      - groq_key
      - gemini_key
    environment:
      - GROQ_API_KEYS_FILE=/run/secrets/groq_key
      - GEMINI_API_KEYS_FILE=/run/secrets/gemini_key

secrets:
  groq_key:
    external: true
  gemini_key:
    external: true
```

## 📊 Monitoreo

### Con Prometheus

Agregar a `docker-compose.yml`:

```yaml
services:
  prometheus:
    image: prom/prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
    
  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
```

## 🆘 Soporte

Si encuentras problemas:

1. Revisa los logs: `docker logs cortex`
2. Verifica la configuración: `docker exec cortex env`
3. Prueba el health check: `curl http://localhost:4000/api/health`
4. Abre un issue en GitHub con los detalles