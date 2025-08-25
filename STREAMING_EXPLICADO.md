# 🎭 La Explicación Épica del Streaming Real en Córtex 🚀

## 📖 Introducción

Este documento explica de forma divertida y visual cómo funciona el streaming en tiempo real implementado en Córtex usando Elixir, Phoenix y Finch.

## 🏗️ El Constructor de Peticiones

```elixir
request = Finch.build(
  :post,
  @ollama_url <> "/api/chat",
  [{"content-type", "application/json"}],
  Jason.encode!(payload)
)
```

🎨 **¿Qué hace?** ¡Es como armar un cohete 🚀 antes de lanzarlo! Le decimos a Finch:
- 📮 "Vas a hacer un POST"
- 📍 "A esta dirección de Ollama"
- 🏷️ "Con esta etiqueta que dice que es JSON"
- 📦 "Y lleva este paquete (el payload)"

## 🌊 La Fábrica de Streams Mágica

```elixir
stream = Stream.unfold(:init, fn
  :init ->
    parent = self()
    ref = make_ref()
```

🎪 **¿Qué hace?** ¡`Stream.unfold` es como una máquina de palomitas infinita! 🍿
- 🎬 Empieza con `:init` (como prender la máquina)
- 👨‍👩‍👧 `parent = self()` - "Yo soy el papá proceso"
- 🎫 `ref = make_ref()` - "Este es mi ticket único"

## 👶 El Proceso Hijo Trabajador

```elixir
spawn(fn ->
  Finch.stream(request, Req.Finch, "", fn
    {:status, _status}, acc -> acc
    {:headers, _headers}, acc -> acc
    {:data, data}, acc ->
      data
      |> String.split("\n", trim: true)
      |> Enum.each(fn line ->
        send(parent, {ref, {:chunk, line}})
      end)
      acc
  end)
  send(parent, {ref, :done})
end)
```

🏃‍♂️ **¿Qué hace?** ¡Nace un proceso bebé que corre a buscar los datos!
- 🙈 Ignora el status HTTP (no le importa)
- 🙉 Ignora los headers (tampoco le interesan)
- 🎁 Cuando llega data: "¡REGALOS!" 
  - ✂️ Corta por líneas nuevas
  - 📬 Envía cada línea al papá: "¡Papá, te llegó carta!"
- 🏁 Al final dice: "¡Ya terminé, papá!"

## 📮 El Buzón del Proceso Padre

```elixir
{ref, :streaming} = state ->
  receive do
    {^ref, :done} -> 
      nil
    {^ref, {:chunk, chunk}} -> 
      {chunk, state}
  after
    30_000 -> nil
  end
```

📪 **¿Qué hace?** ¡El papá revisa su buzón constantemente!
- 💌 Si llega `{ref, :done}`: "¡Se acabó el show!" 🎭
- 📦 Si llega `{ref, {:chunk, chunk}}`: "¡Un paquetito más!" 📦
- ⏰ Si pasan 30 segundos sin nada: "Me aburrí, me voy" 😴

## 🧹 El Filtro Anti-Basura

```elixir
|> Stream.reject(&is_nil/1)
```

🗑️ **¿Qué hace?** ¡Es el portero del stream!
- 🚫 Si ve un `nil`: "¡Tú no pasas!"
- ✅ Si es data real: "¡Adelante, campeón!"

## 🎨 El Flujo Completo Ilustrado

```
Cliente: "Quiero un cuento" 🙋
    ↓
Phoenix: "¡Marchando!" 🏃
    ↓
Dispatcher: "¡Activo el modo streaming!" 🌊
    ↓
Proceso Hijo: "¡Voy por los datos!" 🏃‍♂️
    ↓
Ollama: "Era... una... vez..." 🤖
    ↓
Proceso Hijo: "¡Papá, llegó 'Era'!" 📬
    ↓
Proceso Padre: "¡Al cliente!" 📤
    ↓
Cliente: "Era" 👀
    ↓
[Repite hasta que termine el cuento]
    ↓
Proceso Hijo: "¡Terminé! 🏁"
    ↓
Stream: "¡Show terminado!" 🎭
```

## 🎯 ¿Por qué es genial?

1. **🚀 Real-time**: No espera a tener todo el cuento, envía palabra por palabra
2. **🧵 Concurrente**: Usa procesos de Elixir (¡como tener múltiples empleados!)
3. **💪 Resiliente**: Si algo falla, tiene timeout de 30 segundos
4. **🌊 Lazy**: Solo procesa lo que necesita, cuando lo necesita

¡Es como tener un mensajero súper rápido 🏃‍♂️ que en lugar de esperar a tener todas las cartas, te las va entregando una por una mientras las recibe! 📬✨

## 🛠️ Cómo probarlo

### Prueba básica con curl (verás el texto aparecer gradualmente):
```bash
curl -N -X POST http://localhost:4000/api/chat \
-H "Content-Type: application/json" \
-d '{
  "messages": [
    {
      "role": "user",
      "content": "Escribe un cuento corto para mi hija sobre un unicornio"
    }
  ]
}'
```

### Para ver mejor el efecto del streaming, pide algo más largo:
```bash
curl -N -X POST http://localhost:4000/api/chat \
-H "Content-Type: application/json" \
-d '{
  "messages": [
    {
      "role": "user",
      "content": "Explica paso a paso cómo hacer una tortilla española"
    }
  ]
}'
```

### Para ver las estadísticas de velocidad:
```bash
curl -N -X POST http://localhost:4000/api/chat \
-H "Content-Type: application/json" \
-H "Accept: text/event-stream" \
-w "\n\nTiempo total: %{time_total}s\n" \
-d '{
  "messages": [
    {
      "role": "user",
      "content": "Cuenta una historia larga sobre piratas"
    }
  ]
}'
```

**Nota importante:** La opción `-N` es crucial - desactiva el buffering de curl para que veas el streaming en tiempo real. Sin ella, curl esperará a tener toda la respuesta antes de mostrarla.

## 🎉 Conclusión

Este sistema de streaming permite que Córtex entregue respuestas de IA de manera fluida y en tiempo real, mejorando significativamente la experiencia del usuario. En lugar de esperar varios segundos para ver una respuesta completa, los usuarios ven el texto aparecer palabra por palabra, tal como lo haría un humano escribiendo.

¡La magia de Elixir y OTP en acción! 🪄✨