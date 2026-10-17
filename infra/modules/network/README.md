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
