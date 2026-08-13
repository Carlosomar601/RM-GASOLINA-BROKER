# Octano · App del empleado (handheld, Flutter)

Herramienta de pista para el atendiente: recibe la orden autorizada, atiende la
llegada del cliente en el surtidor, prepara el pedido del minimarket, confirma
identidad por foto, cierra el surtido y liquida.

7 pantallas, iguales a la sección 02 del tablero (`Fuel and Go+ Mockups.dc.html`).

## Instalar

Descomprime en una carpeta hermana de `USER APP`, por ejemplo:

```
D:\PROGRAMACION CARLOS OMAR\RM GASOLINA\EMPLOYEE APP
```

Luego:

```powershell
cd "D:\PROGRAMACION CARLOS OMAR\RM GASOLINA\EMPLOYEE APP"
flutter create . --project-name employee_app --platforms=android
flutter pub get
flutter run
```

Es un proyecto Flutter independiente (no comparte `pubspec.yaml` con la app del
cliente). Comparte, copiado, el mismo `theme/` y `widgets/ui.dart`.

## Pantallas

| Ruta | Pantalla |
|---|---|
| `/` | Dashboard del turno (métricas, alerta, cola) |
| `/turno` | Abrir turno con placa + PIN (sólo en modo broker) |
| `/ordenes` | Cola completa con filtros por estado |
| `/alerta` | «Cliente en estación» · surtidor, foto, pedido |
| `/picking` | Checklist del minimarket + sustituciones |
| `/entrega` | 3 pasos: identidad → surtido → artículos |
| `/roles` | Roles, permisos y apertura/cierre de turno |
| `/integraciones` | POS, controlador de surtidores, nube, cola local |

## Modo demo vs. broker real

Sin URL la app corre con la cola de demostración. Para el broker:

```powershell
flutter run --dart-define=OCTANO_API=http://192.168.100.20:8080
```

Entonces la primera pantalla es `/turno` (placa + PIN) y todo sale del broker:

| Acción en el handheld | Llamada al broker |
|---|---|
| Abrir turno | `POST /v1/auth/employee/login` → token con estación y rol |
| Cola del turno | `GET /v1/tasks` |
| Abrir una tarea | `GET /v1/tasks/:id` (trae los artículos) |
| Aceptar | `POST /v1/tasks/:id/accept` |
| Marcar / sustituir artículo | `POST /v1/tasks/:id/items/:itemId/pick` |
| Identidad coincide / no | `POST /v1/tasks/:id/identity` |
| Completar orden | `POST /v1/tasks/:id/close` → captura la retención y encola la factura a RM |
| Cola en vivo | `ws /v1/stream` suscrito a la estación (`task_incoming`, `task_updated`) |

La cola se refresca sola con cada evento de estación y, como respaldo, cada 20
segundos. El indicador de la barra superior dice `LIVE` (socket), `CLOUD`
(sólo HTTP), `OFF` (broker inalcanzable) o `DEMO`.

El turno se guarda con `shared_preferences`: al reabrir la app vuelve a la cola
sin pedir el PIN, salvo que el token haya vencido.

## Notas de implementación

- `ShiftState` (ChangeNotifier) + `ShiftScope`: cola de tareas, tarea activa, métricas del turno.
- `data/repository.dart`: un contrato, dos implementaciones (demo / broker).
- El ciclo de la tarea (`TaskStatus`) es espejo de `tasks.status` del broker,
  incluyendo `escalada` cuando la identidad no coincide.
- Cada tarea porta su `edge_transaction_uuid` para amarrar surtidor, pago y orden.
- El cierre manual valida contra el techo: el broker responde `over_cap` si el
  monto excede lo autorizado.

## Falta para producción

- Pulso real del surtidor en la pantalla de entrega (hoy el deslizador es el
  respaldo manual; el monto automático lo cierra el `pumpPoller` del broker).
- Cámara para comparar la foto del cliente y capturar evidencia de entrega.
- Escáner de códigos para el picking del minimarket.
- Cola local de eventos cuando el handheld pierde la red (hoy sólo reintenta).
- NFC como alternativa al PIN para abrir turno.
