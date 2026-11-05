# RiTech SAS — Gestión de exportaciones

Aplicación Flutter con API Django REST, JWT y PostgreSQL para origen de café/cacao, exportaciones, cumplimiento documental, logística, finanzas y acceso por roles.

El rediseño visual y el alta de empresas están explicados en [Diseño y organizaciones](documentacion/diseno-y-organizaciones.md).

La implementación, los límites de cada perfil y el recorrido para probar las operaciones están en [Roles y flujos de negocio](documentacion/roles-y-flujos.md).

## Iniciar el backend

Requiere Python 3.12 o superior y PostgreSQL iniciado con base `ritech_db`, usuario `ritech_user` y contraseña configurada en `backend/.env` (`POSTGRES_PASSWORD`).

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver 127.0.0.1:8000
```

En una instalación nueva, genera la empresa y las cuentas de prueba con:

```bash
python manage.py seed_role_demo
```

El comando guarda las credenciales aleatorias en `backend/.demo-credentials.txt`, excluido de versiones. No restablece contraseñas existentes. Incluye diez perfiles: los ocho del requerimiento y los perfiles compatibles comercial y gerencia.

## Iniciar Flutter

En otra terminal, desde la raíz del proyecto:

```bash
cd frontend
flutter pub get
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

Para un emulador Android, identifica el dispositivo con `flutter devices` y ejecuta:

```bash
flutter run -d ID_DEL_EMULADOR --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

## Verificaciones

Backend con PostgreSQL de pruebas:

```bash
cd backend
python manage.py check
python manage.py makemigrations --check --dry-run
python manage.py test --keepdb --noinput
```

Alternativa aislada y rápida:

```bash
python manage.py test --settings=config.test_settings
```

Frontend:

```bash
cd frontend
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

Los archivos de negocio están en `backend/private_media/` y solo se sirven mediante descargas autenticadas. No se debe publicar esa carpeta como contenido estático.
