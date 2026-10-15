# Serverless-Cache-Processor

Servicio serverless de procesamiento de datos en AWS: **API Gateway → Lambda (VPC) →
ElastiCache Redis → S3**, desplegado íntegramente con Terraform.

## Qué hace

Recibe peticiones HTTP, hace un cálculo, guarda el resultado y, si le vuelven a pedir lo
mismo poco después, responde desde la caché en vez de recalcular.

El patrón se llama **cache-aside** (o *lazy loading*): la aplicación consulta primero la
caché y solo calcula cuando no encuentra el dato. Se usa cuando calcular algo es caro o
lento y es habitual que se pida lo mismo varias veces: cotizaciones que consultan varios
proveedores, reportes, miniaturas de imágenes o consultas pesadas a una base de datos.
Las respuestas son más rápidas y se gasta menos cómputo.

## Flujo de una petición

```http
POST /process
{"text": "hola mundo"}
```

**Primera vez — cache MISS**

1. La Lambda calcula una clave a partir del body (un hash): `a1b2c3…`.
2. Consulta Redis con esa clave → no existe.
3. Procesa la petición (por ejemplo, invierte el texto: `"odnum aloh"`).
4. Guarda el resultado en S3 como registro permanente: `results/<fecha>/<id>.json`.
5. Lo guarda en Redis con un vencimiento (TTL) de **60 segundos**.
6. Responde con el resultado y el header **`X-Cache: MISS`**.

**Misma petición antes de 60 s — cache HIT**

1. Misma clave `a1b2c3…`.
2. Redis la tiene → responde de inmediato con **`X-Cache: HIT`**, sin procesar ni escribir
   en S3.

Pasados los 60 segundos, Redis elimina la entrada y la siguiente petición vuelve a ser MISS.

Si algo falla, la Lambda responde **HTTP 500** con un mensaje descriptivo y registra el
error en CloudWatch.

## Analogía: una cocina con mesón

| Componente | En la cocina | Rol |
|---|---|---|
| API Gateway | el mesero | recibe los pedidos y limita cuántos llegan por segundo |
| Lambda | el cocinero | prepara el plato |
| Redis | el mesón caliente | si piden un plato recién hecho, se sirve de ahí sin volver a cocinar; lo que lleva más de 60 s se bota |
| S3 | el libro de registro | anota cada plato preparado, para siempre |
| VPC | la cocina cerrada | el cocinero y el mesón no se ven desde la calle; solo el mesero habla con los clientes |

## Arquitectura

```
Internet
   │  POST /process
   ▼
API Gateway (HTTP API) ── público: throttling, CORS, logs de acceso
   │
   ▼  ┌──────────────────────── VPC ────────────────────────┐
   │  │                                                      │
   └──┼─► Lambda (subnets privadas) ──6379──► Redis          │
      │        │                         (subnets privadas)  │
      │        │ VPC Endpoint Gateway: S3 sin salir a internet
      │        ▼                                             │
      │       S3 privado (results/<fecha>/<id>.json)         │
      │                                                      │
      │   NAT Gateway (subnet pública): salida a internet    │
      │   de la Lambda, p. ej. para leer Secrets Manager     │
      └──────────────────────────────────────────────────────┘
```

Principios de seguridad de red:

- Lambda y Redis viven en **subnets privadas**, sin acceso desde internet.
- Redis **solo acepta conexiones desde la Lambda**, por el puerto 6379
  (security group por referencia, no por rango de IPs).
- S3 es **privado**: Block Public Access completo, acceso solo para el rol de la Lambda y
  a través del **VPC Endpoint**, sin pasar por internet.

## Estructura del repositorio

| Carpeta | Contenido |
|---|---|
| [`bootstrap/`](bootstrap/README.md) | Base de la cuenta, aplicada una sola vez por el administrador: backend remoto del state e identidad de despliegue de mínimo privilegio. |
| `infra/` | El servicio: VPC, Redis, Lambda, API Gateway y S3. *(en construcción)* |
