# 📋 TODO - Córtex Development Roadmap

## 🎯 Objetivo
Completar el desarrollo de Córtex como un gateway de inferencia inteligente que permita usar múltiples LLMs con costo cercano a cero.

## 🚨 Prioridad Alta

### 1. 🏊 Pool de Workers Locales
- [ ] Soportar múltiples instancias de Ollama
- [ ] Configurar URLs de múltiples servidores locales
- [ ] Implementar health checks para cada worker

### 2. 🛡️ Failover Automático
- [ ] Detectar cuando un worker falla o está ocupado
- [ ] Redirigir automáticamente al siguiente worker disponible
- [ ] Implementar circuit breaker pattern

### 3. 🌐 APIs Gratuitas/Baratas
- [ ] Integrar Google Gemini API
- [ ] Integrar Cohere API
- [ ] Integrar Groq API
- [ ] Crear adaptadores unificados para cada API

### 4. 🔑 Rotación de API Keys
- [ ] Pool de API keys por proveedor
- [ ] Rotar automáticamente cuando se alcancen límites
- [ ] Tracking de uso por key

### 5. 🎪 Supervisión OTP
- [ ] Crear supervisor tree para workers
- [ ] Implementar GenServers para cada tipo de worker
- [ ] Auto-recuperación ante fallos

## 📊 Prioridad Media

### 6. 🗺️ Estrategias de Routing
- [ ] `local_first`: Priorizar workers locales
- [ ] `round_robin`: Distribuir carga equitativamente
- [ ] `least_loaded`: Enviar al worker menos ocupado
- [ ] `cost_optimized`: Minimizar costo

### 7. ⚙️ Configuración Externa
- [ ] Leer configuración desde `.env`
- [ ] Variables para URLs de workers
- [ ] Variables para API keys
- [ ] Hot-reload de configuración

### 8. 💾 Caché Inteligente
- [ ] Implementar caché con ETS
- [ ] Hash de prompts para keys de caché
- [ ] TTL configurable
- [ ] Métricas de hit/miss ratio

### 12. 🧪 Testing
- [ ] Tests unitarios para dispatcher
- [ ] Tests de integración para failover
- [ ] Tests de carga
- [ ] Property-based testing

## 🎨 Prioridad Baja (Futuro)

### 9. 🧠 Routing Inteligente
- [ ] Analizar complejidad del prompt
- [ ] Detectar tipo de tarea (código, escritura, etc.)
- [ ] Asignar modelo óptimo por tarea
- [ ] ML para mejorar routing con el tiempo

### 10. 📊 Dashboard LiveView
- [ ] Vista en tiempo real de workers
- [ ] Métricas de uso y rendimiento
- [ ] Gestión de API keys
- [ ] Logs y debugging

### 11. 📈 Telemetría
- [ ] Integrar Telemetry
- [ ] Métricas de latencia por worker
- [ ] Contadores de requests/errores
- [ ] Exportar a Prometheus/Grafana

## 🏗️ Arquitectura Propuesta

```
┌─────────────┐
│   Cliente   │
└──────┬──────┘
       │
┌──────▼──────┐
│   Router    │
└──────┬──────┘
       │
┌──────▼──────┐
│ Supervisor  │
└──────┬──────┘
       │
┌──────┴───────────────┬────────────┬─────────────┐
│                      │            │             │
▼                      ▼            ▼             ▼
Worker Pool         API Pool    Cache (ETS)   Telemetry
├─ Ollama 1        ├─ Gemini                    
├─ Ollama 2        ├─ Cohere                    
└─ Ollama N        └─ Groq                      
```

## 📝 Notas de Implementación

1. **Empezar simple**: Primero pool local, luego APIs externas
2. **Fail fast**: Timeouts agresivos para detectar fallos rápido
3. **Observabilidad**: Logs detallados desde el día 1
4. **Configuración flexible**: Todo configurable sin recompilar

## 🎉 Resultado Final

Un sistema que permite:
- 💰 Costo $0 para la mayoría de requests (usando local)
- 🚀 Alta disponibilidad (failover automático)
- 📈 Escalable (agregar workers es trivial)
- 🧠 Inteligente (routing optimizado)
- 🔍 Observable (dashboard y métricas)