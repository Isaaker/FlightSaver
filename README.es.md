# FlightSaver

Un salvapantallas nativo para macOS que representa el tráfico ADS-B cercano sobre un mapa oscuro, con una interfaz de inspiración aeronáutica y una ficha ampliada de la aeronave seleccionada.

FlightSaver está desarrollado con Swift, AppKit y `ScreenSaver.framework`. No utiliza navegador integrado, WebView ni JavaScript.

> **Aviso:** es un proyecto comunitario. No es una herramienta de control de tráfico aéreo, ayuda a la navegación ni un producto aeronáutico certificado. No debe utilizarse en operaciones de vuelo reales.

## Funciones

- Posiciones de aeronaves en tiempo real mediante fuentes ADS-B públicas y respaldo automático entre proveedores.
- Mapa oscuro basado en OpenStreetMap sin clave por defecto; CARTO Dark Matter como alternativa opcional con clave propia.
- Símbolos de aeronaves, indicativos, altitud, velocidad, tipo, indicadores militares / emergencia y estelas.
- Anillos de distancia en millas náuticas, punto central configurable y resumen del tráfico.
- Tarjeta ampliada con matrícula, tipo, altitud, velocidad, régimen vertical, rumbo, distancia y marcación.
- Fotografías de Planespotters.net cuando existe una coincidencia: primero por matrícula y después por hex ICAO de 24 bits. Se muestra el crédito del fotógrafo y un enlace a la página original.
- Sin reloj ni fecha superpuestos: macOS ya muestra la hora del sistema en el salvapantallas.
- Caché local para teselas del mapa y metadatos de búsqueda de fotografías.

## Requisitos

- macOS 12 Monterey o posterior.
- Mac Apple Silicon (`arm64`) o Intel (`x86_64`).
- Xcode Command Line Tools, que incluyen `swiftc`, `codesign` y el SDK de macOS.
- Conexión a Internet para tráfico, mapas y fotografías.

No hay dependencias de paquetes Swift de terceros.

## Compilar e instalar

```bash
git clone https://github.com/Isaaker/FlightSaver.git
cd FlightSaver
xcode-select --install   # solo si aún no tienes las Command Line Tools
./build.sh
```

El bundle compilado se crea en `build/FlightSaver.saver`. Para instalarlo en el usuario actual:

```bash
./build.sh --install
```

Después, abre **Ajustes del Sistema → Fondo de pantalla → Salvapantallas** (el nombre puede variar según macOS), selecciona **FlightSaver** y abre **Opciones**.

El script genera un bundle firmado ad hoc para uso local; no está firmado con Developer ID ni notarizado.

## Fuentes de datos

### Tráfico ADS-B

- `adsb.fi` se consulta primero cuando no se configura una clave de `adsb.lol`.
- `adsb.lol` se consulta primero cuando se configura su clave; sin ella queda como proveedor de respaldo de menor frecuencia.

Los proveedores controlan la cobertura, los límites y la disponibilidad. Respeta sus condiciones de uso vigentes.

### Fotografías de aeronaves

FlightSaver consulta la API pública de Planespotters.net sin clave:

1. `https://api.planespotters.net/pub/photos/reg/{registration}` por matrícula.
2. Si no hay una fotografía utilizable, `https://api.planespotters.net/pub/photos/hex/{hex}` por dirección ICAO de 24 bits.
3. Descarga la miniatura del CDN, muestra el crédito del fotógrafo y enlaza a la fotografía original.

El User-Agent identifica la aplicación y proporciona la URL pública de contacto del proyecto:

```http
User-Agent: FlightSaver/1.1.1 (+https://github.com/Isaaker/FlightSaver)
```

Los metadatos se conservan en memoria hasta 24 horas, incluidas las búsquedas sin resultado. La miniatura no se guarda en la caché de disco de FlightSaver. No todos los aviones tienen fotografías disponibles. Respeta las reglas, límites, atribución y derechos de imagen de Planespotters.net.

### Mapas

- OpenStreetMap es el mapa gratuito predeterminado. Las teselas se transforman localmente a una apariencia oscura y la atribución permanece visible.
- CARTO Dark Matter es opcional y requiere una clave propia. Si falla, FlightSaver vuelve a OpenStreetMap.

Las teselas se guardan en la caché de macOS durante un máximo de siete días. Consulta [PRIVACY.md](PRIVACY.md) para conocer los datos transmitidos a cada proveedor.

## Privacidad

FlightSaver no incorpora cuentas, analítica ni telemetría. Para funcionar, envía a los proveedores correspondientes el centro y radio de búsqueda ADS-B, las coordenadas de las teselas solicitadas, y la matrícula o hex de la aeronave para consultar una fotografía. La clave de CARTO solo se envía a CARTO cuando ese mapa está seleccionado. Las claves se guardan en las preferencias locales del salvapantallas.

## Desarrollo y soporte

Consulta [CONTRIBUTING.md](CONTRIBUTING.md) para compilar, ejecutar las comprobaciones y preparar contribuciones. Para incidencias, utiliza GitHub Issues. Para vulnerabilidades, sigue [SECURITY.md](SECURITY.md) y no publiques detalles sensibles en una incidencia pública.

## Licencia y marcas

FlightSaver se distribuye bajo licencia MIT; consulta [LICENSE](LICENSE). Es un proyecto independiente, sin afiliación ni respaldo de Apple, OpenStreetMap, CARTO, Planespotters.net, adsb.fi o adsb.lol. Los datos pueden estar retrasados, incompletos, no disponibles o ser inexactos.
