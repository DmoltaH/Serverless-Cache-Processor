# bootstrap/

Un bootstrap aplicado una sola vez por el administrador crea el backend remoto y una
identidad de despliegue de mínimo privilegio: un usuario sin permisos que asume un rol
con credenciales temporales, acotado por prefijo, región y un permissions boundary.
Todo lo demás lo despliega Terraform con ese rol.

## Identidad de despliegue

```
terraform-deployer (usuario IAM)          sin permisos propios; solo sts:AssumeRole
        │
        │ sts:AssumeRole → credenciales de 1 hora
        ▼
sre-assessment-terraform-deployer (rol)   permisos de mínimo privilegio para el stack infra/
```

Si se filtra la access key del usuario, solo sirve para pedir credenciales temporales del
rol; desactivarla en IAM corta el acceso de inmediato.

## Permisos del rol: acotados por prefijo, región y cuenta

El rol solo puede gestionar recursos cuyo nombre empiece con el prefijo del proyecto
(`sre-assessment`, variable `project_name`), en la región del proyecto (`us-east-2`) y en
esta cuenta. Cualquier otro recurso devuelve `AccessDenied`.

| Servicio | Alcance permitido |
|---|---|
| Lambda | funciones `sre-assessment-*` |
| S3 | buckets `sre-assessment-*` (+ solo la carpeta `infra/` del bucket de state) |
| ElastiCache | replication groups, clusters, subnet y parameter groups `sre-assessment-*` |
| Secrets Manager | secretos `sre-assessment/*` |
| CloudWatch Logs | log groups `/aws/lambda/sre-assessment-*` y `/aws/apigateway/sre-assessment-*` |
| IAM | solo roles bajo el path `/sre-assessment/`, y únicamente con el boundary adjunto |
| EC2/VPC y API Gateway | sus IDs son aleatorios (`vpc-0a1b…`), así que se acotan por cuenta + región |

Además:
- Una denegación explícita bloquea cualquier acción fuera de la región del proyecto.
- El rol no puede modificar nada bajo el path IAM `/bootstrap/`, donde viven él mismo, sus
  políticas y el boundary: no puede ampliarse sus propios permisos.

## Permissions boundary

El rol necesita crear el rol de ejecución de la Lambda y escribirle permisos. Sin control,
podría crear un rol con permisos de administrador, asignarlo a una Lambda y, a través de
ella, obtener más poder del que tiene: una **escalada de privilegios**.

El boundary (`sre-assessment-workload-boundary`) es un **techo**. El rol deployer solo puede
crear o editar roles si llevan ese boundary adjunto, y los permisos efectivos de esos roles
son la **intersección** entre su propia política y el boundary:

```
Política del rol de la Lambda:  "puede hacer todo"
Boundary:                       S3 sre-assessment-*/*, logs del proyecto, ENIs de VPC,
                                leer secretos sre-assessment/*, X-Ray
────────────────────────────────────────────────────────────────────────────────
Permisos efectivos:             solo lo que permite el boundary
```

Aunque la política de un rol de la aplicación se escriba mal (o con mala intención),
nunca puede superar ese techo. Y el deployer no puede quitar el boundary ni modificarlo.

---

## Cómo se aplicó

El bootstrap se aplicó desde un PC con Windows y PowerShell, en cinco pasos.

### 1. Credenciales temporales del administrador

**Técnico.** El bootstrap crea identidades IAM, así que necesita permisos de administrador.
En vez de crear access keys para el dueño de la cuenta (permanentes y con poder total),
se usó `aws login`, que abre el navegador, pasa por el login con MFA y entrega
**credenciales temporales**. Terraform todavía no entiende ese tipo de sesión, así que se
exportaron como variables de entorno para esa terminal:

```powershell
aws login --profile owner
aws configure export-credentials --profile owner --format powershell | Invoke-Expression
```

**Analogía.** En vez de hacerle una copia permanente de la llave maestra del edificio al
contratista, el dueño va en persona a recepción, muestra su cédula y recibe un pase que se
vence solo en unas horas.

### 2. Primer apply con el state local

**Técnico.** Este stack crea el bucket donde Terraform guarda su state. En el primer
`apply` ese bucket todavía no existe, así que Terraform no puede guardar ahí su propio
state: el primer apply se hace con **state local** (`terraform.tfstate` en el PC), sin
`backend.tf`.

```powershell
Rename-Item backend.tf backend.tf.off      # solo si se aplica desde cero
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

**Analogía.** Es como construir el archivador de la oficina: mientras lo arman, los
papeles del proyecto se guardan en el escritorio. No se pueden guardar dentro de un
archivador que todavía no existe.

### 3. Migración del state al bucket

**Técnico.** Con el bucket ya creado, se activa el backend S3 y Terraform copia el state
local al bucket (`bootstrap/terraform.tfstate`). Desde ese momento el state queda
versionado, cifrado y con bloqueo de escrituras simultáneas (`use_lockfile`); el archivo
local queda vacío.

```powershell
Rename-Item backend.tf.off backend.tf
terraform init -migrate-state              # responder "yes" a la copia del state
```

**Analogía.** Ya armado el archivador, se pasan los papeles del escritorio a su cajón
con llave. Si mañana se pierde el escritorio, los papeles siguen a salvo.

### 4. De `backend.hcl` a `backend.tf`

**Técnico.** La primera versión usaba **configuración parcial del backend**: `backend.tf`
solo decía `backend "s3" {}` y los valores (bucket, key, región, `use_lockfile`) vivían en
un archivo aparte, `backend.hcl`, que se pasaba con
`terraform init -backend-config=backend.hcl`. Es un patrón útil cuando el mismo código se
despliega en varias cuentas, pero aquí hay una sola, y como `backend.hcl` no se versiona,
el repositorio no mostraba dónde vive el state.

Se movieron los valores directamente a `backend.tf` y se le indicó a Terraform la nueva
configuración. El state no se movió: ya estaba en el bucket.

```powershell
terraform init -reconfigure
terraform plan                             # resultado esperado: sin cambios en recursos
```

`backend.hcl` ya no se usa y puede borrarse. `backend.tf` tiene el nombre del bucket
escrito a mano (incluye el ID de la cuenta) porque el bloque `backend` no admite
variables; si el stack se desplegara en otra cuenta, habría que cambiarlo ahí.

**Analogía.** Antes, la dirección del archivador estaba en una nota suelta que solo tenía
quien instaló la oficina. Ahora está escrita en el manual de la oficina, a la vista de
cualquiera que lo lea. El archivador no se movió: solo cambió dónde está anotada su
dirección.

### 5. Credenciales del deployer en el PC

**Técnico.** Se creó la access key del usuario `terraform-deployer` en la consola de IAM.
Se hizo a mano a propósito: si la creara Terraform, el secreto quedaría guardado en el
state. Luego se configuraron dos perfiles de la AWS CLI, que son solo etiquetas locales
del PC (AWS no las conoce):

| Perfil | Qué contiene | Uso |
|---|---|---|
| `deployer-user` | la access key de `terraform-deployer` (en `~/.aws/credentials`) | nunca directo: solo sirve para pedir el rol |
| `deployer-role` | `role_arn` del rol + `source_profile = deployer-user` | **el que usan la CLI y Terraform** |

```powershell
aws configure --profile deployer-user      # access key, secret, us-east-2, json
# + bloque [profile deployer-role] en ~/.aws/config (output aws_cli_config)
aws sts get-caller-identity --profile deployer-role
# → arn:aws:sts::<cuenta>:assumed-role/sre-assessment-terraform-deployer/terraform-sre-assessment
```

**Analogía.** `deployer-user` es la cédula guardada en la billetera; `deployer-role` es la
instrucción "cuando necesite entrar, muestra la cédula en recepción y pide el pase de
contratista". Cada vez que se usa `--profile deployer-role`, eso pasa solo y en un
segundo.

### Ajustes por las restricciones de la cuenta

La cuenta usa la nueva experiencia de AWS, que aplica políticas de organización (SCP)
administradas por AWS. El primer apply falló por dos de ellas y el código se adaptó:

- **Grupos IAM prohibidos** (`iam:CreateGroup`): el permiso de asumir el rol se puso como
  política directa del usuario en vez de un grupo. El resultado es el mismo.
- **`us-east-1` solo para servicios globales**: todo lo regional se crea en la región del
  proyecto, `us-east-2`.
