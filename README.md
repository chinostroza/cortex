<div align="center"\>
<img src="logo.png" alt="Córtex Logo" width="200"/\>
</div\>

# 🧠 Córtex: Tu AI Gateway de Producción

**Un gateway de inferencia inteligente y resiliente para tus aplicaciones de IA. Construido para ofrecer fiabilidad, control de costos y alto rendimiento a escala.**

Córtex es un **AI Gateway** de código abierto construido sobre **Elixir** y **Phoenix**. Su misión es actuar como una capa de enrutamiento robusta entre tu aplicación y múltiples proveedores de modelos de IA, garantizando que tus servicios se mantengan disponibles, rápidos y rentables.

-----

## 🤔 ¿Por qué un AI Gateway?

Construir una aplicación de IA puede llevar minutos. Sin embargo, llevarla a producción requiere **fiabilidad y estabilidad a escala**. Conectar una aplicación directamente a un único proveedor de LLM crea una dependencia frágil: si ese proveedor sufre una caída o alcanzas sus límites de tasa, tu aplicación también lo hará.

Córtex resuelve este problema al proporcionar una capa unificada que garantiza la disponibilidad cuando un proveedor falla, evita los bajos límites de tasa y ofrece una fiabilidad constante para las cargas de trabajo de IA.

-----

## ✨ Características Principales

  * **Resiliencia Multi-Proveedor 🌐:** Soporte nativo para **Ollama**, **Groq**, **Gemini** y **Cohere**. Si un proveedor falla, Córtex redirige el tráfico al siguiente disponible de forma automática.
  * **Balanceo de Carga y Worker Pools Inteligentes 🏊:** Gestiona un pool de workers con chequeos de salud (health checks), priorización y tolerancia a fallos para garantizar que siempre se utilice el recurso más óptimo.
  * **Gestión y Rotación Automática de API Keys 🔑:** Administra múltiples API keys por proveedor con estrategias de rotación (round-robin, least-used) para maximizar el uso de las cuotas gratuitas y evitar bloqueos.
  * **Manejo Dinámico de Límites de Tasa (Rate Limiting) ⏱️:** Detecta automáticamente los errores de límite de tasa, bloquea temporalmente la API key afectada y rota a la siguiente, manteniendo la aplicación en funcionamiento.
  * **Streaming de Baja Latencia 🌊:** Implementación completa de Server-Sent Events (SSE) para entregar respuestas en tiempo real desde cualquier proveedor, mejorando la experiencia del usuario.
  * **Tolerancia a Fallos Superior 💪:** Construido sobre la plataforma Elixir/OTP, Córtex aprovecha la supervisión jerárquica y la recuperación automática para una estabilidad a nivel de producción.
  * **Arquitectura Limpia y Extensible 🏗️:** Diseñado siguiendo los principios SOLID, lo que facilita la adición de nuevos proveedores de IA sin modificar el código existente.

-----

## 📮 Arquitectura y Flujo de Peticiones

Córtex actúa como un director de orquesta inteligente para tus peticiones de IA:

1.  **Entrada (`Phoenix Router`) 🧑‍💼:** Recibe la petición (`POST /api/chat`) de tu aplicación cliente.
2.  **Controlador (`Controller`) 🎭:** Prepara la conexión de streaming y solicita un worker disponible al `Worker Pool`.
3.  **Selección de Worker (`Pool`) 🏊:** El pool manager evalúa la salud y prioridad de todos los workers registrados y selecciona el mejor candidato para procesar la petición.
      * **Worker Ollama** (Prioridad 10): Tu modelo local, siempre la primera opción para costo cero 🏠.
      * **Worker Groq** (Prioridad 20): El especialista en velocidad con LPUs ⚡.
      * **Worker Gemini** (Prioridad 30): El potente y equilibrado modelo de Google 🧠.
      * **Worker Cohere** (Prioridad 40): El especialista en conversaciones de nivel empresarial 💬.
4.  **Ejecución y Gestión de API Keys (`API Key Manager`)** 🔑: El worker seleccionado solicita una API key válida al gestor, que la proporciona según la estrategia de rotación configurada.
5.  **Respuesta en Tiempo Real (`Streaming`)** 🎼: El resultado se transmite de vuelta al cliente en tiempo real, token por token.

### 🎯 **Lógica de Failover en Cascada**

El sistema está diseñado para que el show siempre continúe:

  * Si tu servidor **Ollama** está caído o sobrecargado → Córtex utiliza **Groq** automáticamente.
  * Si **Groq** alcanza sus límites de tasa → Córtex rota a otra API key de Groq o salta a **Gemini**.
  * Si todos los proveedores primarios fallan → **Cohere** actúa como respaldo final.

-----

## 🛠️ Instalación y Primeros Pasos

¡Manos a la obra\! Para tener Córtex funcionando en tu máquina.

#### **Requisitos Previos**

Asegúrate de tener:

  * [Elixir](https://elixir-lang.org/install.html) instalado.
  * [Ollama](https://ollama.com/) instalado y funcionando.
  * Git para clonar el proyecto.

#### **Pasos**

1.  **Clona el Repositorio:**

    ```bash
    git clone [https://github.com/tu-usuario/cortex.git](https://github.com/tu-usuario/cortex.git)
    cd cortex
    ```

2.  **Instala las Dependencias de Elixir:**

    ```bash
    mix deps.get
    ```

3.  **Configura tus Variables de Entorno:**

      * Crea tu archivo de configuración personal copiando el ejemplo:
        ```bash
        cp .env.example .env
        ```
      * Abre el archivo `.env` y configúralo con tus API keys reales.
      * **⚠️ Importante:** El archivo `.env` está incluido en `.gitignore` para proteger tus credenciales.

4.  **¡Lanzamiento\!** 🚀

      * **En una terminal**, inicia tu servidor de Ollama:
        ```bash
        ollama serve
        ```
      * **En otra terminal**, inicia el gateway Córtex:
        ```bash
        mix phx.server
        ```

¡Listo\! Tu AI Gateway Córtex está ahora escuchando en `http://localhost:4000`.

-----

## ⚙️ Configuración Multi-Provider

Configura tus proveedores y estrategias a través de variables de entorno.

```bash
# === PROVEEDORES DE IA ===
# Separa múltiples claves con comas para habilitar la rotación
GROQ_API_KEYS=gsk_key1,gsk_key2
GEMINI_API_KEYS=AIza_key1,AIza_key2
COHERE_API_KEYS=co_key1

# Modelos a usar (opcional, usa los predeterminados si no se especifica)
GROQ_MODEL=llama-3.1-8b-instant
GEMINI_MODEL=gemini-1.5-flash
COHERE_MODEL=command-r

# === OLLAMA (LOCAL) ===
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=llama3

# === CONFIGURACIÓN AVANZADA DEL GATEWAY ===
API_KEY_ROTATION_STRATEGY=round_robin  # Opciones: round_robin, least_used, random
RATE_LIMIT_BLOCK_MINUTES=15           # Tiempo que una key bloqueada por rate limit permanece inactiva
HEALTH_CHECK_INTERVAL=60              # Intervalo en segundos para los chequeos de salud de los workers
```

### 🎯 **Estrategias de Rotación de API Keys**

  - **`round_robin`**: Rota las claves en orden secuencial. Ideal para una distribución uniforme.
  - **`least_used`**: Selecciona la clave que ha procesado menos peticiones.
  - **`random`**: Selección aleatoria para evitar patrones predecibles.

-----

## 🎮 Modo de Uso

Interactúa con Córtex como lo harías con una API de OpenAI, pero apuntando a tu endpoint local.

### 🚀 **Prueba Rápida con cURL**

```bash
curl -N -X POST http://localhost:4000/api/chat \
-H "Content-Type: application/json" \
-d '{
  "messages": [
    {
      "role": "user",
      "content": "Explica qué es un AI Gateway en una frase"
    }
  ]
}'
```

Deberías ver la respuesta generándose en tiempo real. Si Ollama no responde, Córtex cambiará automáticamente a Groq o al siguiente proveedor disponible.

### 📊 **Endpoints de Monitoreo**

Córtex proporciona endpoints para observar el estado del sistema en tiempo real:

```bash
# Ver el estado de salud de todos los workers
curl http://localhost:4000/api/health

# Ver estadísticas de uso de las API keys
curl http://localhost:4000/api/stats

# Ver la lista de workers disponibles y su prioridad
curl http://localhost:4000/api/workers
```

-----

## 🗺️ Roadmap

### ✅ **Completado**

  - [x] 🌐 **Arquitectura Multi-Proveedor:** Soporte para Ollama, Groq, Gemini y Cohere.
  - [x] 🔑 **Gestor de API Keys:** Rotación inteligente con múltiples estrategias.
  - [x] 🏊 **Worker Pool Resiliente:** Sistema robusto con health checks y failover.
  - [x] 🌊 **Streaming Unificado:** Server-Sent Events para todos los proveedores.
  - [x] ⚡ **Manejo de Rate Limits:** Detección automática y rotación de claves.
  - [x] 🧪 **Cobertura de Pruebas:** Más de 70 pruebas automatizadas para garantizar la calidad.

### 🔮 **Próximas Mejoras**

  - [ ] 🧠 **Caché Inteligente:** Implementar caché en ETS para respuestas comunes y reducir la latencia.
  - [ ] 📊 **Dashboard LiveView:** Un panel de control en tiempo real para monitorear el tráfico y el estado de los workers.
  - [ ] 🗺️ **Enrutamiento por Contenido:** Un "router de IA" que seleccione el mejor modelo según la tarea (ej. codificación, escritura creativa).
  - [ ] 🔌 **Soporte para más Proveedores:** Añadir OpenAI, Anthropic, y Mistral.
  - [ ] 📈 **Métricas Avanzadas:** Integración con Prometheus y Grafana para observabilidad a nivel de producción.

-----

## 🏗️ Arquitectura Técnica Detallada

El diseño de Córtex se basa en los principios de software robusto para garantizar la mantenibilidad y escalabilidad.

### 🧬 **Principios SOLID Implementados**

  - **Single Responsibility**: Cada worker se especializa en un único proveedor de IA.
  - **Open/Closed**: Es posible añadir nuevos proveedores (workers) sin modificar el código del `Pool` o del `Controller`.
  - **Liskov Substitution**: Todos los workers adhieren a un comportamiento común (`APIWorker`), permitiendo que el `Pool` los trate de forma intercambiable.
  - **Interface Segregation**: Se definen comportamientos específicos para tareas como el formateo de mensajes y la gestión de streaming.
  - **Dependency Inversion**: Los módulos de alto nivel (como el `Pool`) dependen de abstracciones (el `behaviour` de los workers), no de implementaciones concretas.

*(El resto de las secciones de Arquitectura, Testing, Contribuciones y Licencia de tu README original son excelentes y no necesitan cambios significativos).*

-----

## 🤝 Contribuciones

¡Las contribuciones son bienvenidas\! Si tienes una idea o quieres arreglar un bug:

1.  Abre un "Issue" para discutir tu idea.
2.  Haz un "Fork" del repositorio.
3.  Crea una nueva rama (`git checkout -b mi-nueva-feature`).
4.  Haz tus cambios y envía un "Pull Request".

-----

## 📜 Licencia

Córtex se distribuye bajo la licencia **GNU Affero General Public License v3.0 (AGPLv3)**. Esto significa que puedes usarlo, modificarlo y distribuirlo libremente. Si lo utilizas para potenciar un servicio accesible a través de una red, la licencia requiere que el código fuente completo de tu servicio también sea público.

Puedes leer la licencia completa [aquí](https://www.gnu.org/licenses/agpl-3.0.html).

-----

## 💼 Licencia Comercial

Si las condiciones de la licencia AGPLv3 no son compatibles con tu modelo de negocio (por ejemplo, si deseas ofrecer Córtex como un servicio de código cerrado), es posible adquirir una licencia comercial.

Para más detalles, por favor contacta a **Carlos Hinostroza** en **c@zea.cl**.