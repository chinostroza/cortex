<div align="center">
  <img src="logo.png" alt="Córtex Logo" width="200"/>
</div>

# 🧠 Córtex

**Tu propio cerebro para orquestar múltiples modelos de IA al mínimo costo.**

Córtex es un gateway de inferencia y un balanceador de carga inteligente construido sobre **Elixir** y el framework **Phoenix**. Su objetivo es permitir a los desarrolladores construir aplicaciones de IA robustas y escalables con un presupuesto cercano a cero, combinando servidores locales (Ollama) con APIs de nube gratuitas.

---

## ✨ Características Principales

* **Arquitectura Híbrida:** Prioriza el uso de workers locales y utiliza workers de nube como respaldo.
* **Failover Automático:** Redirige el tráfico automáticamente si un servidor local se cae o está ocupado.
* **Rotación de API Keys:** Gestiona un pool de múltiples API keys para sortear los límites de uso.
* **Tolerancia a Fallos:** Construido sobre Elixir/OTP para máxima resiliencia.
* **Caché Inteligente (Roadmap):** Próximamente, usará ETS para respuestas instantáneas.
* **Enrutamiento por Tarea (Roadmap):** Futura capacidad para enrutar prompts al modelo más adecuado.
* **Panel de Monitoreo (Roadmap):** Un dashboard en tiempo real con Phoenix LiveView.

---

## 🚀 Cómo Empezar (Desarrollo Local)

Sigue estos pasos para levantar el entorno de Córtex en tu máquina.

1. **Instala las dependencias:**
   ```bash
   mix deps.get
````

2.  **Inicia el servidor de Phoenix:**
    ```bash
    mix phx.server
    ```

Ahora puedes visitar [`localhost:4000`](https://www.google.com/search?q=http://localhost:4000) desde tu navegador y el endpoint de la API estará disponible para recibir peticiones.

-----

## 🤔 ¿Por qué Córtex?

El costo de las APIs de IA comerciales puede ser prohibitivo para desarrolladores y MVPs. Córtex resuelve este problema creando un "cerebro" central que gestiona de forma inteligente los recursos de inferencia, optimizando para el costo y la resiliencia.

-----

## 🛠️ Stack Tecnológico

  * **Lenguaje:** Elixir
  * **Framework:** Phoenix Framework
  * **Concurrencia y Supervisión:** Elixir/OTP
  * **HTTP Client:** Finch
  * **JSON Parsing:** Jason

-----

## Para Aprender Más sobre Phoenix

  * **Sitio Oficial:** https://www.phoenixframework.org/
  * **Guías:** https://hexdocs.pm/phoenix/overview.html
  * **Documentación:** https://hexdocs.pm/phoenix
  * **Foro:** https://elixirforum.com/c/phoenix-forum
  * **Código Fuente:** https://github.com/phoenixframework/phoenix