# Guía de comandos útiles de SSH

Colección de comandos para conectarse y administrar servidores mediante SSH de forma segura.

---

## Conexiones básicas

```bash
# Conectarse a un servidor remoto
ssh usuario@servidor

# Conectarse usando un puerto diferente
ssh -p 2222 usuario@servidor

# Conectarse con una clave privada específica
ssh -i ~/.ssh/mi_clave usuario@servidor

# Conectarse y ejecutar un comando remoto
ssh usuario@servidor "ls -la /var/log"
```

---

## Gestión de claves

```bash
# Generar un par de claves SSH (ed25519 recomendado)
ssh-keygen -t ed25519 -C "tu@correo.com"

# Generar claves RSA de 4096 bits
ssh-keygen -t rsa -b 4096 -C "tu@correo.com"

# Generar clave con nombre personalizado
ssh-keygen -t ed25519 -f ~/.ssh/mi_clave -C "tu@correo.com"

# Cambiar la frase de paso de una clave privada
ssh-keygen -p -f ~/.ssh/id_ed25519

# Mostrar la clave pública
ssh-keygen -y -f ~/.ssh/id_ed25519

# Copiar la clave pública a un servidor remoto
ssh-copy-id usuario@servidor

# Copiar la clave pública usando un puerto diferente
ssh-copy-id -p 2222 usuario@servidor
```

---

## Agente SSH

```bash
# Iniciar el agente SSH
eval "$(ssh-agent -s)"

# Añadir una clave privada al agente
ssh-add ~/.ssh/id_ed25519

# Listar claves cargadas en el agente
ssh-add -l

# Eliminar todas las claves del agente
ssh-add -D

# Añadir clave con passphrase usando Keychain (macOS)
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

---

## Configuración del cliente (~/.ssh/config)

Ejemplo de archivo de configuración para accesos rápidos:

```ssh-config
Host mi-servidor
    HostName 192.168.1.100
    User admin
    Port 2222
    IdentityFile ~/.ssh/mi_clave
    ServerAliveInterval 60

Host github
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_key
```

Con esta configuración puedes conectarte simplemente con:

```bash
ssh mi-servidor
```

### Opciones comunes

| Opción            | Descripción                                      |
|-------------------|--------------------------------------------------|
| HostName          | Dirección IP o nombre de dominio del servidor    |
| User              | Nombre de usuario para la conexión               |
| Port              | Puerto del servidor SSH                          |
| IdentityFile      | Ruta a la clave privada                          |
| ServerAliveInterval | Segundos entre mensajes keep-alive               |
| StrictHostKeyChecking | Aceptar o rechazar nuevas claves de host         |
| ProxyJump         | Saltar a través de otro host                     |

---

## Transferencia de archivos

```bash
# Copiar un archivo local al servidor remoto
scp archivo.txt usuario@servidor:/ruta/destino/

# Copiar un archivo del servidor remoto al equipo local
scp usuario@servidor:/ruta/archivo.txt ./

# Copiar un directorio completo
scp -r ./carpeta usuario@servidor:/ruta/destino/

# Usar un puerto diferente con scp
scp -P 2222 archivo.txt usuario@servidor:/ruta/destino/

# Sincronizar carpetas con rsync por SSH
rsync -avz --progress ./carpeta usuario@servidor:/ruta/destino/
```

---

## Túneles y redirección de puertos

```bash
# Túnel local: puerto local → puerto remoto
ssh -L 8080:localhost:80 usuario@servidor

# Túnel remoto: puerto remoto → puerto local
ssh -R 9090:localhost:3000 usuario@servidor

# Proxy SOCKS dinámico
ssh -D 1080 usuario@servidor

# Saltar a través de un host (bastión)
ssh -J usuario@bastion usuario@servidor-interno
```

---

## Verificación y diagnóstico

```bash
# Probar la conexión SSH
ssh -v usuario@servidor

# Modo verbose extendido
ssh -vvv usuario@servidor

# Mostger la huella digital de un servidor
ssh-keyscan -t ed25519 servidor

# Verificar claves conocidas
ssh-keygen -F servidor

# Eliminar una clave de host conocida
ssh-keygen -R servidor

# Verificar permisos de la carpeta SSH
ls -la ~/.ssh
```

---

## Consejos rápidos

- Usa siempre claves SSH en lugar de contraseñas cuando sea posible.
- Protege tus claves privadas con una frase de paso segura.
- Mantén los permisos correctos en `~/.ssh`: carpeta `700`, archivos `600`.
- Desactiva el inicio de sesión por contraseña en servidores propios.
- Usa `~/.ssh/config` para no tener que recordar IPs, puertos y claves.
- Para mayor seguridad, considera usar autenticación de dos factores.
