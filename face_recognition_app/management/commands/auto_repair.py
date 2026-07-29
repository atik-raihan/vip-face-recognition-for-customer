import os
import sys
import subprocess
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

print("=" * 60)
print("Automatic Repair")
print("=" * 60)

errors = 0

def run(command, description):
    global errors

    print(f"\n[RUN] {description}")

    result = subprocess.run(command, shell=True)

    if result.returncode == 0:
        print("[OK]")
    else:
        print("[FAIL]")
        errors += 1

# --------------------------------------------------
# Django System Check
# --------------------------------------------------

run(
    "python manage.py check",
    "Django System Check"
)

# --------------------------------------------------
# Database Migrations
# --------------------------------------------------

run(
    "python manage.py makemigrations",
    "Create Migrations"
)

run(
    "python manage.py migrate",
    "Apply Migrations"
)

# --------------------------------------------------
# Customer Faces
# --------------------------------------------------

run(
    "python manage.py build_faces",
    "Build Customer Faces"
)

# --------------------------------------------------
# Employee Faces
# --------------------------------------------------

run(
    "python manage.py build_employee_faces",
    "Build Employee Faces"
)

# --------------------------------------------------
# Collect Static (if used)
# --------------------------------------------------

run(
    "python manage.py collectstatic --noinput",
    "Collect Static Files"
)

# --------------------------------------------------

print("\n" + "=" * 60)

if errors == 0:
    print("[OK] Automatic repair completed successfully.")
    sys.exit(0)

print(f"[FAIL] {errors} repair task(s) failed.")
sys.exit(1)