# Módulo `network`

Red del servicio. Se construye pieza por pieza; esta página documenta cada una.

---

## VPC

### Qué es

**VPC = Virtual Private Cloud.** Es una red privada propia dentro de AWS, aislada de las
redes de los demás clientes. Todo lo que tiene que "vivir en una red" va dentro de ella:
Lambda, Redis y el NAT Gateway. Por defecto **nada entra ni sale** de una VPC: las puertas
(Internet Gateway, NAT, endpoints) se agregan después, una por una y a propósito.

**Analogía:** es el terreno cercado de un edificio. Todavía no hay pisos, ni puertas, ni
calles internas; solo el terreno con su cerca y su rango de direcciones.

### Configuración

| Opción | Valor | Por qué |
|---|---|---|
| IPv4 CIDR | `10.0.0.0/16` | Ver abajo. Variable `vpc_cidr` |
| IPv6 | sin IPv6 | La arquitectura no lo necesita; agregarlo solo suma complejidad |
| Tenancy | `default` | `dedicated` reserva hardware físico exclusivo: muy caro, solo para regulaciones o licencias especiales |
| DNS resolution | activado | Permite traducir nombres a IPs dentro de la VPC |
| DNS hostnames | activado | Los recursos reciben nombre DNS. La Lambda se conecta a Redis por nombre (`…cache.amazonaws.com`), no por IP, y el VPC Endpoint de S3 también depende del DNS |
| Encryption control | `None` | Ver abajo |

#### IPv4 CIDR `10.0.0.0/16`

- `10.0.0.0` es un rango **privado**: esas IPs no existen en internet, solo dentro de la VPC.
- `/16` indica cuántas direcciones: los primeros 16 bits quedan fijos (`10.0`) y el resto es
  libre. Va de `10.0.0.0` a `10.0.255.255`, unas **65.536 direcciones**.
- Se divide en subnets más pequeñas de `/24` (256 direcciones cada una).
- *Analogía:* `10.0.x.x` es el código postal del terreno; cada subnet será una calle
  (`10.0.0.x`, `10.0.1.x`, …).

#### Encryption control

*VPC Encryption Controls* permite auditar y exigir que el tráfico **dentro** de la VPC viaje
cifrado. Tiene tres opciones:

| Modo | Qué hace |
|---|---|
| **None** | Desactivado. El cifrado del tráfico depende de cada aplicación. |
| **Monitor** | Solo observa: agrega a los VPC Flow Logs el campo `encryption-status` (cifrado / no cifrado) y lista los recursos que permiten tráfico sin cifrar. No bloquea nada. |
| **Enforce** | Bloquea: impide crear o conectar recursos que permitan tráfico sin cifrar. Los recursos que salen de la red de AWS (Internet Gateway, NAT Gateway) y las Lambdas en la VPC solo se permiten como **exclusiones** explícitas. En una VPC existente hay que pasar primero por Monitor. |

**Elegido: `None`.**

- **Enforce** exigiría exclusiones justo para tres piezas centrales de esta arquitectura:
  el Internet Gateway, el NAT Gateway y la Lambda. Quedaría casi todo exceptuado.
- El cifrado en tránsito se garantiza **en la capa de aplicación**, en cada conexión:
  Lambda → Redis con TLS (cifrado en tránsito de ElastiCache), Lambda → S3 y
  Lambda → Secrets Manager por HTTPS.
- **Monitor** sirve para auditar cumplimiento (HIPAA, PCI DSS); requiere VPC Flow Logs y
  tiene costo (ver [precios de Amazon VPC](https://aws.amazon.com/vpc/pricing/)). Es una
  mejora posible si hubiera requisitos de cumplimiento.

Referencia: [VPC Encryption Controls](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-encryption-controls.html).

### Lo que AWS crea solo junto con la VPC

| Recurso por defecto | Qué es | Uso en este proyecto |
|---|---|---|
| Main route table | El "GPS" que usa cualquier subnet sin route table propia | Ninguno: cada subnet tendrá su route table explícita |
| Default network ACL | Firewall a nivel de subnet; por defecto permite todo | Se deja así; el control fino lo hacen los security groups |
| Default security group | Firewall a nivel de recurso | No se usa: Lambda y Redis tienen security groups propios |

### Terraform

- Recurso: `aws_vpc.this` en [`main.tf`](main.tf).
- Salidas: `vpc_id`, `vpc_cidr_block`.

---

## Subnets

### Qué es

Una **subnet** es un pedazo del rango de la VPC ubicado en una **zona de disponibilidad**
concreta. Los recursos (Lambda, Redis, NAT) no se ponen "en la VPC" en general, sino en
una subnet.

**Analogía:** si la VPC es el terreno cercado, las subnets son las calles dentro de él, y
cada calle está en un barrio distinto.

### Diseño

| Subnet | AZ | CIDR | Rango | Qué va ahí |
|---|---|---|---|---|
| `public-a` | us-east-2a | `10.0.0.0/24` | 10.0.0.0 – 10.0.0.255 | NAT Gateway |
| `public-b` | us-east-2b | `10.0.1.0/24` | 10.0.1.0 – 10.0.1.255 | (reserva / NAT por AZ) |
| `private-a` | us-east-2a | `10.0.10.0/24` | 10.0.10.0 – 10.0.10.255 | Lambda, Redis |
| `private-b` | us-east-2b | `10.0.11.0/24` | 10.0.11.0 – 10.0.11.255 | Lambda, Redis |

- **Dos zonas de disponibilidad.** Una región tiene varios datacenters físicamente
  separados (AZs). La Lambda corre en ambas: si `us-east-2a` falla, sigue en `us-east-2b`.
- **`/24` por subnet:** 256 direcciones, de las que AWS reserva 5 en cada subnet (red,
  router, DNS, uso futuro y broadcast). Quedan 251 utilizables.
- **Las privadas empiezan en `10.0.10.x`** para reconocerlas a simple vista (0–9
  públicas, 10+ privadas) y dejar espacio para más subnets públicas.

### Pública vs. privada

Al crear una subnet no existe una opción "pública" o "privada": todas nacen iguales. Lo que
las diferencia es su **route table**:

- **Pública:** su route table tiene una ruta `0.0.0.0/0` hacia el Internet Gateway.
- **Privada:** sin ruta directa a internet. Lambda y Redis viven aquí, como exige el
  enunciado.

Hasta que existan las route tables propias, las cuatro usan la *main route table* de la VPC.

### El tag `Tier`

Un **tag** es una etiqueta `clave = valor` pegada a un recurso. Es metadata: **no cambia
nada** del funcionamiento. Una subnet con `Tier = private` se comporta igual que sin él.
`Tier` ("capa") indica en qué capa de la arquitectura está la subnet: `public` o `private`.

Para qué sirve:

1. **Deja clara la intención.** Una subnet no es pública o privada por sí misma, sino por su
   route table. El tag dice para qué es cada una y permite auditar: una subnet
   `Tier = private` cuya route table vaya al Internet Gateway es un error.
2. **Buscar y filtrar** en la consola o la CLI:
   ```powershell
   aws ec2 describe-subnets --profile deployer-role --filters "Name=tag:Tier,Values=private" --query "Subnets[].SubnetId"
   ```
3. **Que otros stacks encuentren las subnets sin escribir IDs**, un patrón habitual cuando
   un equipo administra la red y otros la consumen:
   ```hcl
   data "aws_subnets" "private" {
     filter {
       name   = "tag:Tier"
       values = ["private"]
     }
   }
   ```

**Analogía:** es el letrero de una puerta. "Solo personal autorizado" no cierra la puerta
(eso lo hace la cerradura, aquí la route table), pero dice para qué es y ayuda a encontrarla.

Los tags `Project`, `Stack` y `ManagedBy` cumplen la misma función, pero los agrega
automáticamente el `default_tags` del provider a todos los recursos: identifican el
proyecto, permiten separar costos y avisan que el recurso lo administra Terraform y no se
debe modificar a mano.

### Sin IPs públicas automáticas

`map_public_ip_on_launch = false` en las cuatro subnets. Esa opción le da una IP pública a
cada recurso que se cree en la subnet (sobre todo servidores EC2), y nada en esta
arquitectura la necesita:

| Componente | IP pública |
|---|---|
| NAT Gateway | Sí: una **Elastic IP** asignada explícitamente. Es la única de la arquitectura |
| Internet Gateway | No: es una puerta, no tiene dirección |
| Lambda | No: sale a internet a través del NAT, usando la IP del NAT |
| Redis | No: no sale a internet |

El camino de salida de la Lambda es:
`Lambda (10.0.10.x) → NAT (cambia la IP privada por su Elastic IP) → Internet Gateway → internet`.

### Cómo se generan en Terraform

Un solo bloque de código crea una subnet por zona. El flujo tiene cuatro etapas:

```
variables (3 listas)  →  locals (mapa por zona)  →  for_each (1 subnet por zona)  →  outputs (IDs)
      entrada               transformación              fábrica                       salida
```

**1. Variables — la entrada** ([`variables.tf`](variables.tf)). Tres listas que se leen por
columnas: la posición 0 de cada una corresponde a la zona `a` y la posición 1 a la `b`.

```
                        posición 0       posición 1
availability_zones   = ["us-east-2a",   "us-east-2b"]
public_subnet_cidrs  = ["10.0.0.0/24",  "10.0.1.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
```

Se valida que haya al menos dos zonas, que los CIDR sean válidos y que haya exactamente uno
por zona.

**2. Locals — la transformación** ([`locals.tf`](locals.tf)). Valores calculados dentro del
módulo, que no vienen de afuera:

- `az_keys` toma la última letra de cada zona: `["us-east-2a", "us-east-2b"]` → `["a", "b"]`
  (`substr(texto, desde, cuántos)`).
- `public_subnets` y `private_subnets` juntan las listas en un mapa con la letra como clave,
  una ficha por subnet:
  ```hcl
  {
    a = { az = "us-east-2a", cidr = "10.0.10.0/24" }
    b = { az = "us-east-2b", cidr = "10.0.11.0/24" }
  }
  ```

**3. `for_each` — la fábrica** ([`main.tf`](main.tf)). Crea una copia del recurso por cada
elemento del mapa. `each.key` es la letra y `each.value` la ficha:

```hcl
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id     # conexión con la VPC, sin escribir su ID
  availability_zone = each.value.az       # "us-east-2a"
  cidr_block        = each.value.cidr     # "10.0.10.0/24"
  tags = { Name = "${var.name_prefix}-private-${each.key}" }   # "sre-assessment-private-a"
}
```

Resultado: `aws_subnet.private["a"]` y `aws_subnet.private["b"]` (ídem para `public`).

**¿Por qué la letra como clave y no un número?** La alternativa, `count`, numera las copias
`[0]`, `[1]`. Si se quita la primera zona, la que era `[1]` pasa a ser `[0]` y Terraform la
destruye y la recrea. Con letras, quitar la zona `a` solo borra `["a"]`; `["b"]` no se toca.

**4. Outputs — la salida** ([`outputs.tf`](outputs.tf)). `public_subnet_ids` y
`private_subnet_ids` devuelven los IDs como lista ordenada por zona. Redis, la Lambda y el
NAT los usan para saber dónde ubicarse.

**Agregar una tercera zona** solo requiere sumar un elemento a cada lista en
`terraform.tfvars` (por ejemplo `us-east-2c`, `10.0.2.0/24`, `10.0.12.0/24`); el módulo no
cambia.
