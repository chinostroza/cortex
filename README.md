<div align="center">
  <img src="logo.png" alt="Córtex Logo" width="200"/>
</div>

# 🧠 Córtex

**Tu propio cerebro para orquestar múltiples modelos de IA al mínimo costo.**

Córtex es un gateway de inferencia y un balanceador de carga inteligente construido sobre **Elixir** y **Phoenix**. Su misión es permitir a los desarrolladores construir aplicaciones de IA robustas con un presupuesto cercano a cero, ofreciendo un modelo de doble licencia para dar soporte tanto a la comunidad open-source como a las necesidades comerciales.

---

## 🤔 ¿Por qué existe Córtex?

Las APIs de IA son increíbles, ¡pero pueden costar un ojo de la cara 💸! Córtex resuelve este problema creando un "cerebro" central que gestiona de forma inteligente tus recursos de IA, priorizando siempre las opciones gratuitas o locales. ¡Construye sin miedo a la factura!

---

## ✨ Características Principales

* **Arquitectura Híbrida 🏡+☁️:** Usa tus servidores locales primero y solo recurre a las APIs de nube como respaldo.
* **A Prueba de Fallos 🛡️:** Si un servidor local se toma un descanso (se cae), Córtex redirige el tráfico automáticamente. ¡El show debe continuar!
* **Rotación de API Keys 🔑:** Maneja múltiples API keys gratuitas para exprimir hasta la última gota de sus límites de uso.
* **Tolerancia a Fallos Nivel DIOS 💪:** Construido sobre Elixir/OTP, si un "worker" falla, el resto del sistema ni se inmuta.
* **Caché Mágica 🧠 (Roadmap):** Próximamente, usará ETS para respuestas instantáneas.
* **Enrutamiento Inteligente 🗺️ (Roadmap):** Futura capacidad para enrutar prompts al modelo más adecuado para la tarea.
* **Panel de Monitoreo (Roadmap):** Un dashboard en tiempo real con Phoenix LiveView para observar a nuestros workers en acción.

---

## 📮 ¿Cómo Funciona? ¡La Oficina de Correo Mágico!

Imagina que Córtex es una oficina de correo mágico para tus peticiones de IA:

1.  **El Recepcionista (`Router`) 🧑‍💼:** Recibe tu carta (`POST /api/chat`) y, sin leerla, la pone en el buzón del Gerente.
2.  **El Gerente (`Controller`) 👨‍💼:** Abre la carta, prepara la conexión para enviar la respuesta en trocitos (¡streaming!) y le pasa la orden al Mensajero.
3.  **El Mensajero Mágico (`Dispatcher`) 🚀:** Toma la orden, viaja a la velocidad del rayo ⚡ hasta el Oráculo (`Ollama`), le entrega tu pregunta y vuelve con la respuesta.
4.  **El Gerente de nuevo 👨‍💼:** Recibe la respuesta del mensajero y la va enviando por la ventanilla al cliente, trocito a trocito.

---

## 🛠️ Instalación y Primeros Pasos

¡Manos a la obra! Para tener Córtex funcionando en tu máquina.

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

3.  **Configura tus Servidores:**
    * Crea tu archivo de configuración personal copiando el ejemplo:
        ```bash
        cp .env.example .env
        ```
    * Abre el archivo `.env` y edítalo con las URLs de tus workers y tus API keys (más info abajo).

4.  **¡Lanzamiento! 🚀**
    * **En una terminal**, inicia tu servidor de IA:
        ```bash
        ollama serve
        ```
    * **En otra terminal**, inicia Córtex:
        ```bash
        mix phx.server
        ```

¡Listo! Tu gateway Córtex está ahora escuchando en `http://localhost:4000`.

---

## ⚙️ Configuración

Toda la configuración de Córtex se maneja en el archivo `.env`.

* `ROUTING_STRATEGY`: Cómo se seleccionan los workers. Por ahora, `local_first`.
* `LOCAL_OLLAMA_URLS`: Una lista de las URLs de tus servidores Ollama locales, separadas por comas.
* `GEMINI_API_KEYS`: Tus API keys de Google Gemini, separadas por comas.
* `COHERE_API_KEYS`: Tus API keys de Cohere, separadas por comas.
* ...¡y más workers que añadiremos en el futuro!

---

## 🎮 Modo de Uso

Para probar que todo funciona, envía una petición `POST` a la API con `curl`. La opción `-N` es para ver el streaming en tiempo real.

```bash
curl -N -X POST http://localhost:4000/api/chat \
-H "Content-Type: application/json" \
-d '{
  "messages": [
    {
      "role": "user",
      "content": "Escribe un poema corto sobre Elixir y la concurrencia."
    }
  ]
}'
````

Deberías ver la respuesta del poema escribiéndose palabra por palabra en tu terminal. ¡Magia\! ✨

-----

## 🗺️ Roadmap (Nuestros Próximos Hechizos)

  * [ ] 🧠 **Caché Inteligente:** Implementar caché con ETS para respuestas instantáneas.
  * [ ] 🗺️ **Enrutamiento por Tarea:** Enseñar al Dispatcher a elegir el mejor modelo para cada tipo de pregunta.
  * [ ] 📊 **Panel de Monitoreo:** Un dashboard con LiveView para ver a nuestros workers en acción en tiempo real.
  * [ ] 🔌 **Más Workers:** Añadir soporte nativo para más APIs de IA.

-----

## 🤝 ¿Quieres Ayudar? ¡Únete a la Magia\!

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