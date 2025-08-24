<div align="center">
  <img src="logo.png" alt="Córtex Logo" width="200"/>
</div>

# 🧠 Córtex

**Tu propio cerebro para orquestar múltiples modelos de IA al mínimo costo.**

Córtex es un gateway de inferencia y un balanceador de carga inteligente construido sobre **Elixir** y el framework **Phoenix**. Está diseñado para gestionar, enrutar y priorizar peticiones a un pool híbrido de modelos de lenguaje (LLMs), combinando servidores locales auto-alojados (Ollama) con APIs de nube de bajo costo o gratuitas (Gemini, Cohere, Groq, etc.).

El objetivo principal de Córtex es permitir a los desarrolladores y equipos pequeños construir aplicaciones de IA robustas y escalables con un presupuesto cercano a cero.

---

## ## ✨ Características Principales

* **Arquitectura Híbrida:** Prioriza el uso de workers locales para un costo nulo y utiliza workers de nube como respaldo o para picos de tráfico.
* **Failover Automático:** Si un servidor local se cae o está ocupado, Córtex automáticamente redirige el tráfico al siguiente worker disponible, asegurando una alta disponibilidad.
* **Rotación de API Keys:** Gestiona un pool de múltiples API keys gratuitas para sortear los límites de uso (rate limiting) y maximizar la capacidad de peticiones.
* **Tolerancia a Fallos:** Construido sobre los principios de Elixir/OTP, los fallos en un worker no afectan al resto del sistema.
* **Caché Inteligente (Roadmap):** Próximamente, guardará las respuestas a preguntas frecuentes en una caché en memoria (ETS) para respuestas instantáneas y menor carga.
* **Enrutamiento por Tarea (Roadmap):** Futura capacidad para analizar el prompt y enviarlo al modelo más adecuado para la tarea (ej. un modelo pequeño para tareas simples, uno grande para razonamiento complejo).
* **Panel de Monitoreo (Roadmap):** Un dashboard en tiempo real con Phoenix LiveView para observar el estado de todos los workers.

---

## ## 🤔 ¿Por qué Córtex?

El costo de las APIs de IA comerciales puede ser prohibitivo para desarrolladores independientes, startups en etapa temprana y proyectos personales. Córtex resuelve este problema creando un "cerebro" central que gestiona de forma inteligente los recursos de inferencia.

En lugar de depender de un único proveedor de pago, Córtex te permite construir tu propio ecosistema de IA, optimizando para el costo y la resiliencia.

---

## ## 🛠️ Stack Tecnológico

* **Lenguaje:** Elixir
* **Framework:** Phoenix Framework
* **Concurrencia y Supervisión:** Elixir/OTP
* **Caché (próximamente):** Erlang Term Storage (ETS)
* **Dashboard (próximamente):** Phoenix LiveView