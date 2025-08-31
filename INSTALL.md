# 📦 Guía de Instalación de Cortex

## 🚀 Opción 1: Docker (Más Fácil - Recomendado)

### Requisitos
- Docker instalado ([Instalar Docker](https://docs.docker.com/get-docker/))

### Instalación

1. **Clonar el repositorio:**
```bash
git clone https://github.com/tu-usuario/cortex.git
cd cortex
```

2. **Configurar API Keys:**
```bash
cp .env.example .env
nano .env  # Editar y agregar tus API keys
```

3. **Iniciar con Docker Compose:**
```bash
docker-compose up -d
```

¡Listo! Cortex estará corriendo en http://localhost:4000

### Comandos útiles:
```bash
# Ver logs
docker-compose logs -f

# Detener
docker-compose down

# Reiniciar
docker-compose restart

# Actualizar
git pull
docker-compose build
docker-compose up -d
```

---

## 💻 Opción 2: Instalación Local (Para Desarrollo)

### Requisitos
- Ubuntu/Debian o macOS
- Git

### Instalación automática
```bash
# Clonar repositorio
git clone https://github.com/tu-usuario/cortex.git
cd cortex

# Instalar Elixir con asdf (recomendado)
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
echo '. $HOME/.asdf/asdf.sh' >> ~/.bashrc
source ~/.bashrc

# Instalar Erlang y Elixir
asdf plugin add erlang
asdf plugin add elixir

# Instalar dependencias de compilación (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y build-essential autoconf m4 libncurses5-dev libssl-dev

# Instalar versiones
asdf install erlang 26.0
asdf install elixir 1.15.7-otp-26
asdf global erlang 26.0  
asdf global elixir 1.15.7-otp-26

# Configurar Cortex
cp .env.example .env
nano .env  # Agregar tus API keys

# Instalar dependencias del proyecto
mix deps.get
mix compile

# Iniciar
mix phx.server
```

---

## 🎯 Opción 3: Binario Precompilado (Próximamente)

Descarga el binario para tu sistema:
- Linux: `cortex-linux-amd64`
- macOS: `cortex-darwin-amd64`  
- Windows: `cortex-windows-amd64.exe`

```bash
# Linux/macOS
chmod +x cortex-linux-amd64
./cortex-linux-amd64
```

---

## 🔧 Configuración

### API Keys necesarias (al menos una):

1. **Groq** (Gratis, Rápido): https://console.groq.com/
2. **Google Gemini** (Gratis con límites): https://makersuite.google.com/app/apikey
3. **Cohere** (Plan gratuito disponible): https://dashboard.cohere.com/api-keys

### Archivo .env:
```env
GROQ_API_KEYS=gsk_xxxxx,gsk_yyyyy  # Múltiples keys separadas por comas
GEMINI_API_KEYS=AIza_xxxxx
COHERE_API_KEYS=co_xxxxx
```

---

## ✅ Verificar instalación

```bash
# Verificar estado
curl http://localhost:4000/api/health

# Probar chat
curl -N -X POST http://localhost:4000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hola!"}]}'
```

---

## 🐧 Instalación en servidor (Systemd)

```bash
# Crear servicio
sudo nano /etc/systemd/system/cortex.service
```

Contenido:
```ini
[Unit]
Description=Cortex AI Gateway
After=network.target

[Service]
Type=simple
User=tu-usuario
WorkingDirectory=/path/to/cortex
EnvironmentFile=/path/to/cortex/.env
ExecStart=/usr/bin/mix phx.server
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
# Activar servicio
sudo systemctl enable cortex
sudo systemctl start cortex
sudo systemctl status cortex
```

---

## 🆘 Solución de problemas

### Error: "Elixir version too old"
- Solución: Usar asdf para instalar Elixir 1.15+

### Error: "No curses library"
- Solución: `sudo apt-get install libncurses5-dev`

### Error: "Port 4000 already in use"
- Solución: Cambiar puerto en `.env`: `PORT=4001`

### Error: "No workers available"
- Solución: Verificar que al menos una API key esté configurada en `.env`

---

## 📚 Más información

- [README](README.md) - Información general del proyecto
- [CLAUDE.md](CLAUDE.md) - Guía para desarrolladores
- [API Docs](docs/API.md) - Documentación de la API