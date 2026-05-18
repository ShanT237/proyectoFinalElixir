# 🚖 UrbanFleet

> Sistema de simulación de flota de taxis multijugador en tiempo real, construido sobre Elixir y OTP. Clientes solicitan viajes, conductores los aceptan, todo corre de forma concurrente y distribuida.

---

## 📋 Tabla de Contenidos

- [Descripción](#descripción)
- [Características](#características)
- [Tecnologías](#tecnologías)
- [Arquitectura](#arquitectura)
- [Estructura del Proyecto](#estructura-del-proyecto)
- [Instalación](#instalación)
- [Ejecución](#ejecución)
- [Comandos del Sistema](#comandos-del-sistema)
- [Sistema de Puntuación](#sistema-de-puntuación)
- [Persistencia](#persistencia)
- [Flujo de un Viaje](#flujo-de-un-viaje)
- [Autores](#autores)

---

## 📖 Descripción

**UrbanFleet** es una aplicación de simulación de despacho de taxis que corre sobre la plataforma **Elixir/OTP**. Permite que múltiples clientes y conductores interactúen simultáneamente a través de una interfaz de línea de comandos (CLI), conectándose a un nodo servidor mediante Erlang Distribution (RPC entre nodos).

Cada viaje es gestionado por su propio proceso `GenServer`, supervisado dinámicamente, con temporizadores de expiración y notificaciones en tiempo real enviadas a los usuarios involucrados.

---

## ✨ Características

### Para Clientes
- 📝 Registro automático o inicio de sesión con contraseña hasheada (SHA-256)
- 🗺️ Solicitud de viajes especificando origen y destino
- ❌ Cancelación de viajes antes de que un conductor los acepte
- ⭐ Consulta de puntuación personal
- 🏆 Visualización de rankings globales y por rol

### Para Conductores
- 🚗 Listado de viajes disponibles en tiempo real
- ✅ Aceptación de viajes con completación automática tras 60 segundos
- 🛑 Cancelación de viajes en progreso (con penalización de puntos)
- ⭐ Consulta de puntuación personal y ranking de conductores

### Para el Administrador (Servidor)
- ➕ Agregar nuevas zonas al sistema
- 📋 Listar zonas válidas
- 👥 Ver todos los usuarios registrados y sus puntuaciones
- 📊 Ver estadísticas del sistema (viajes completados, expirados, tasa de completación)

### General
- 🔔 Notificaciones en tiempo real vía RPC entre nodos Erlang
- 💾 Persistencia en archivos planos (`users.dat`, `results.log`, `locations.dat`)
- ⏱️ Expiración automática de viajes sin conductor tras 60 segundos
- 🔀 Concurrencia total: cada viaje es un proceso independiente

---

## 🛠️ Tecnologías

| Tecnología | Versión | Uso |
|---|---|---|
| **Elixir** | 1.15+ | Lenguaje principal |
| **OTP** | Incluido | GenServer, DynamicSupervisor, Registry |
| **Erlang Distribution** | Incluido | Comunicación entre nodos (RPC) |
| **Mix** | Incluido | Build y gestión del proyecto |
| **:crypto** | Incluido (Erlang) | Hash SHA-256 de contraseñas |

No se requieren dependencias externas. El sistema corre únicamente con la plataforma Elixir/OTP estándar.

---

## 🏛️ Arquitectura

### Árbol de Supervisión

```
UrbanFleet.Supervisor (one_for_one)
├── Registry (UrbanFleet.TripRegistry)   # Localización de procesos de viaje
├── UrbanFleet.UserManager               # GenServer: usuarios y puntuaciones
├── UrbanFleet.TripSupervisor            # DynamicSupervisor: viajes activos
│   ├── UrbanFleet.Trip (T00001)         # GenServer por viaje
│   ├── UrbanFleet.Trip (T00002)
│   └── ...
└── UrbanFleet.Server                    # GenServer: CLI y manejo de comandos
```

### Comunicación entre Nodos

```
┌──────────────────────┐         ┌──────────────────────┐
│   NODO CLIENTE       │         │   NODO SERVIDOR      │
│  (run_client.exs)    │         │  (run_server.exs)    │
│                      │         │                      │
│  UrbanFleet.Client   │◄───────►│  UrbanFleet.Server   │
│                      │  RPC /  │  UrbanFleet.Trip     │
│  :notification_      │  Erlang │  UrbanFleet.UserMgr  │
│   listener           │  Dist.  │  UrbanFleet.TripSup  │
└──────────────────────┘         └──────────────────────┘
```

### Flujo de mensajes de un viaje

```
Cliente                 TripSupervisor         Trip (GenServer)       UserManager
  │                          │                       │                     │
  │── request_trip ─────────►│                       │                     │
  │                          │── start_child ────────►│                     │
  │◄─ {:ok, trip_id} ────────│◄─ {:ok, pid} ─────────│                     │
  │                          │                       │── send_after(60s) ──►│ (timer expira)
  │                                                  │                     │
  │  (Conductor conectado)                           │                     │
  │── accept_trip ──────────────────────────────────►│                     │
  │◄─ {:ok, trip} ─────────────────────────────────  │                     │
  │                                                  │── send_after(60s) ──►│ (completar)
  │                                                  │                     │
  │                                                  │── :complete_trip ───►│
  │                                                  │── trip_completed ───►│── +10 cliente
  │◄─ notificación RPC ──────────────────────────────│                     │── +15 conductor
```

---

## 📁 Estructura del Proyecto

```
urban_fleet/
├── lib/
│   ├── urban_fleet.ex                  # Módulo principal: API pública, stats, info
│   └── urban_fleet/
│       ├── application.ex              # Inicio de la aplicación OTP
│       ├── server.ex                   # GenServer principal: CLI + comandos RPC
│       ├── trip.ex                     # GenServer de viaje individual
│       ├── trip_supervisor.ex          # DynamicSupervisor de viajes
│       ├── user_manager.ex             # GenServer: autenticación y puntuaciones
│       ├── location.ex                 # Carga y validación de zonas
│       └── persistence.ex             # Registro de resultados en results.log
├── test/
│   └── urban_fleet/
│       ├── location_test.exs
│       ├── server_test.exs
│       ├── trip_test.exs
│       └── user_manager_test.exs
├── data/                               # Generado en tiempo de ejecución
│   ├── users.dat                       # Usuarios registrados (texto plano)
│   ├── results.log                     # Log de resultados de viajes
│   └── locations.dat                   # Zonas válidas del sistema
├── run_server.exs                      # Script de inicio del servidor
├── run_client.exs                      # Script de inicio del cliente
└── mix.exs                             # Configuración del proyecto
```

---

## ⚙️ Instalación

### Prerrequisitos

- **Elixir 1.15+** (incluye Erlang/OTP 26+)
- Verificar instalación:

```bash
elixir --version
# Elixir 1.15.x (compiled with Erlang/OTP 26)
```

### Clonar el repositorio

```bash
git clone https://github.com/tu-usuario/urban_fleet.git
cd urban_fleet
```

### Instalar dependencias

```bash
mix deps.get
```

---

## 🚀 Ejecución

El sistema requiere **dos terminales**: una para el servidor y otra (o más) para cada cliente.

### Terminal 1 — Servidor

```bash
elixir --name server@localhost --cookie urbanfleet run_server.exs
```

Verás el banner del servidor y el prompt de administrador:

```
╔════════════════════════════════════════╗
║        🖥️  MODO SERVIDOR URBANFLEET     ║
╚════════════════════════════════════════╝
[servidor-admin] >
```

### Terminal 2 — Cliente / Conductor

```bash
elixir --name client1@localhost --cookie urbanfleet run_client.exs
```

```
╔════════════════════════════════════════╗
║       🚗 SISTEMA CLIENTE URBANFLEET     ║
╚════════════════════════════════════════╝
✅ Conectado al Servidor UrbanFleet.
[Invitado] >
```

> ⚠️ El `--cookie` debe ser el mismo en todos los nodos para permitir la comunicación distribuida.

> Para conectar múltiples clientes, abre terminales adicionales con nombres distintos: `--name client2@localhost`, `--name driver1@localhost`, etc.

---

## 💻 Comandos del Sistema

### Comandos de Conexión (todos los roles)

| Comando | Descripción |
|---|---|
| `connect <usuario> <contraseña> <client\|driver>` | Registrarse o iniciar sesión |
| `disconnect` | Cerrar sesión |
| `exit` | Salir de la aplicación |
| `help` | Mostrar ayuda contextual |

### Comandos para Clientes

| Comando | Descripción |
|---|---|
| `request <origen> <destino>` | Solicitar un viaje (forma corta) |
| `request_trip origen=<loc> destino=<loc>` | Solicitar un viaje (forma larga) |
| `cancel <trip_id>` | Cancelar viaje sin conductor asignado |
| `my_score` / `score` | Ver puntuación personal |
| `ranking` / `rank` | Ver ranking global |
| `list_zones` / `zones` | Ver zonas disponibles |

### Comandos para Conductores

| Comando | Descripción |
|---|---|
| `list_trips` / `trips` | Listar viajes disponibles |
| `accept_trip <id>` / `accept <id>` | Aceptar un viaje |
| `cancel <trip_id>` | Cancelar viaje en progreso (penalización) |
| `my_score` / `score` | Ver puntuación personal |
| `ranking driver` / `rank driver` | Ver ranking de conductores |
| `list_zones` / `zones` | Ver zonas disponibles |

### Comandos del Administrador (servidor)

| Comando | Descripción |
|---|---|
| `add_zone <nombre>` | Agregar una nueva zona |
| `list_zones` | Listar zonas actuales |
| `show_stats` | Ver estadísticas del sistema |
| `show_users` | Ver usuarios registrados |
| `exit` | Cerrar el servidor |

---

## 🏆 Sistema de Puntuación

| Evento | Efecto |
|---|---|
| ✅ Cliente completa un viaje | **+10 puntos** |
| ✅ Conductor completa un viaje | **+15 puntos** |
| 🛑 Conductor cancela un viaje | **-10 puntos** |
| ⏱️ Viaje expira sin conductor | Sin penalización al cliente |

Los rankings pueden filtrarse por rol (`ranking client` / `ranking driver`) o verse de forma global (`ranking`). Se muestran los top 10 usuarios por puntuación.

---

## 💾 Persistencia

El sistema guarda datos en la carpeta `data/` mediante archivos de texto plano:

### `data/users.dat`
Un usuario por línea con el formato:
```
username|role|password_hash_base64|score
```

Ejemplo:
```
juan|client|47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=|30
maria|driver|LzTG6pVZ3d0m...=|75
```

### `data/results.log`
Un viaje por línea con el formato:
```
YYYY-MM-DD HH:MM:SS; cliente=<name>; conductor=<name>; origen=<loc>; destino=<loc>; status=<status>
```

Ejemplo:
```
2024-03-15 14:32:10; cliente=juan; conductor=maria; origen=Centro; destino=Aeropuerto; status=Completado
2024-03-15 14:35:00; cliente=pedro; conductor=ninguno; origen=Plaza; destino=Hospital; status=Expirado
```

### `data/locations.dat`
Una zona por línea (se puede editar manualmente o vía `add_zone`):
```
Aeropuerto
Biblioteca
Centro
Estadio
Hospital
Mercado
Parque
Plaza
Terminal
Universidad
```

---

## 🔄 Flujo de un Viaje

```
1. Cliente ejecuta: request Centro Aeropuerto
   └── TripSupervisor crea proceso Trip (ID: T12345)
       └── Temporizador: 60s para expirar si no hay conductor

2. Conductor ejecuta: list_trips
   └── Se muestran todos los Trip con status :available

3. Conductor ejecuta: accept_trip T12345
   └── Trip cambia status a :in_progress
       └── Nuevo temporizador: 60s hasta completar

4a. [Éxito] Pasan 60s
    └── Trip envía :complete_trip
        ├── UserManager: +10 al cliente, +15 al conductor
        ├── Persistence: registra en results.log
        └── Server: notifica a cliente y conductor vía RPC
            └── Proceso Trip se detiene (:stop, :normal)

4b. [Conductor cancela] cancel T12345
    └── Trip cambia status a :cancelled
        ├── UserManager: -10 al conductor
        ├── Persistence: registra en results.log
        └── Server: notifica a cliente y conductor
            └── Proceso Trip se detiene

4c. [Expira] 60s sin conductor
    └── Trip recibe :check_expiration
        ├── Persistence: registra como Expirado
        └── Server: notifica al cliente
            └── Proceso Trip se detiene
```

---

## 🧪 Pruebas

Los archivos de test están en `test/urban_fleet/`. Para ejecutarlos:

```bash
mix test
```

---

## 📝 Notas de Seguridad

- Las contraseñas se almacenan como hash SHA-256 en Base64. Para un entorno de producción se recomienda usar **Argon2** o **bcrypt** (disponibles como dependencias Hex).
- El cookie de Erlang (`--cookie urbanfleet`) debe mantenerse secreto en despliegues reales.
- Los archivos en `data/` no deben subirse al repositorio si contienen datos sensibles. Considera añadirlos al `.gitignore`.

```gitignore
# .gitignore sugerido
data/users.dat
data/results.log
/_build/
/deps/
```

---

## 👨‍💻 Autores

Desarrollado como proyecto de programación concurrente y distribuida con Elixir/OTP.

---

## 📄 Licencia

Proyecto con fines académicos y educativos.

---

<p align="center">
  Hecho con 💜 y Elixir · Powered by OTP
</p>
