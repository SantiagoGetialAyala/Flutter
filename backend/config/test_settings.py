"""Isolated fast tests; production remains PostgreSQL."""
from .settings import *  # noqa: F403
DATABASES = {'default': {'ENGINE': 'django.db.backends.sqlite3', 'NAME': ':memory:'}}
PASSWORD_HASHERS = ['django.contrib.auth.hashers.MD5PasswordHasher']
MEDIA_ROOT = __import__('tempfile').mkdtemp(prefix='ritech-test-media-')
