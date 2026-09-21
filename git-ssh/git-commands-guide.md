# Guía de comandos útiles de Git

Colección de comandos frecuentes para trabajar con repositorios Git desde la terminal.

---

## Configuración

```bash
# Ver la configuración actual
git config --list

# Configurar nombre y correo globales
git config --global user.name "Tu Nombre"
git config --global user.email "tu@correo.com"

# Configurar editor por defecto
git config --global core.editor "code --wait"

# Alias útiles
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.ci commit
git config --global alias.st status
git config --global alias.lg "log --oneline --graph --decorate --all"
```

---

## Crear o clonar repositorios

```bash
# Inicializar un repositorio nuevo
git init

# Clonar un repositorio remoto
git clone https://github.com/usuario/repo.git

# Clonar solo una rama específica
git clone --branch nombre-rama --single-branch https://github.com/usuario/repo.git
```

---

## Estado y seguimiento de archivos

```bash
# Ver el estado del repositorio
git status

# Ver cambios en archivos modificados
git diff

# Ver cambios preparados para commit
git diff --staged

# Añadir archivos al área de preparación
git add archivo.txt
git add .

# Quitar archivo del área de preparación
git reset HEAD archivo.txt

# Restaurar un archivo a la última versión confirmada
git checkout -- archivo.txt
```

---

## Commits

```bash
# Crear un commit con mensaje
git commit -m "Mensaje descriptivo del cambio"

# Añadir y confirmar en un solo paso (solo archivos rastreados)
git commit -am "Mensaje"

# Modificar el último commit
git commit --amend -m "Nuevo mensaje"

# Modificar el último commit añadiendo cambios olvidados
git add .
git commit --amend --no-edit
```

---

## Historial

```bash
# Historial en formato compacto
git log --oneline

# Historial con gráfico de ramas
git log --oneline --graph --decorate --all

# Historial de un archivo específico
git log -p archivo.txt

# Ver quién modificó cada línea de un archivo
git blame archivo.txt
```

---

## Ramas

```bash
# Listar ramas locales
git branch

# Listar ramas remotas
git branch -r

# Listar todas las ramas
git branch -a

# Crear una nueva rama
git branch nombre-rama

# Cambiar de rama
git checkout nombre-rama
git switch nombre-rama

# Crear y cambiar a una nueva rama
git checkout -b nombre-rama
git switch -c nombre-rama

# Renombrar la rama actual
git branch -m nuevo-nombre

# Eliminar una rama local
git branch -d nombre-rama

# Forzar eliminación de una rama
git branch -D nombre-rama
```

---

## Fusionar y reorganizar

```bash
# Fusionar otra rama en la actual
git merge nombre-rama

# Continuar merge después de resolver conflictos
git merge --continue

# Cancelar un merge en progreso
git merge --abort

# Reorganizar commits de una rama sobre otra
git rebase nombre-rama

# Continuar rebase tras resolver conflictos
git rebase --continue

# Cancelar un rebase
git rebase --abort
```

---

## Repositorios remotos

```bash
# Ver repositorios remotos configurados
git remote -v

# Agregar un remoto
git remote add origin https://github.com/usuario/repo.git

# Cambiar URL de un remoto
git remote set-url origin https://github.com/usuario/repo.git

# Descargar cambios sin fusionar
git fetch

# Descargar cambios de una rama remota específica
git fetch origin nombre-rama

# Fusionar cambios del remoto en la rama actual
git pull

# Subir cambios al remoto
git push origin nombre-rama

# Subir una rama nueva por primera vez
git push -u origin nombre-rama

# Eliminar una rama remota
git push origin --delete nombre-rama
```

---

## Deshacer cambios

```bash
# Deshacer cambios no confirmados en un archivo
git checkout -- archivo.txt

# Restaurar un archivo a una versión específica
git checkout <commit> -- archivo.txt

# Revertir un commit creando un nuevo commit
git revert <hash>

# Resetear al último commit conservando cambios
git reset --soft HEAD~1

# Resetear al último commit descartando cambios del área de preparación
git reset --mixed HEAD~1

# Resetear al último commit descartando todos los cambios (precaución)
git reset --hard HEAD~1
```

---

## Stash (guardado temporal)

```bash
# Guardar cambios temporalmente
git stash

# Guardar con un mensaje descriptivo
git stash push -m "descripción"

# Listar stash guardados
git stash list

# Recuperar el último stash
git stash pop

# Aplicar un stash sin eliminarlo
git stash apply stash@{0}

# Eliminar un stash específico
git stash drop stash@{0}
```

---

## Tags (etiquetas)

```bash
# Listar etiquetas
git tag

# Crear etiqueta anotada
git tag -a v1.0.0 -m "Versión 1.0.0"

# Subir una etiqueta al remoto
git push origin v1.0.0

# Subir todas las etiquetas
git push origin --tags

# Eliminar una etiqueta local
git tag -d v1.0.0
```

---

## Consejos rápidos

- Usa `git status` frecuentemente para saber en qué estado está tu repositorio.
- Realiza commits pequeños y con mensajes descriptivos.
- Antes de hacer `git push`, verifica que estás en la rama correcta.
- Para flujos de trabajo colaborativos, usa `git pull --rebase` para mantener un historial lineal.
- Guarda cambios temporales con `git stash` cuando necesites cambiar de rama rápidamente.
