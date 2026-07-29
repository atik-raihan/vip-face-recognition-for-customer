import os
import sys
import django

# ----------------------------------------------------------
# Setup Django
# ----------------------------------------------------------

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

from face_recognition_app.models import Branch

print("=" * 50)
print("Branch Validation")
print("=" * 50)

total = Branch.objects.count()
active = Branch.objects.filter(is_active=True).count()

print(f"Total Branches : {total}")
print(f"Active         : {active}")
print(f"Inactive       : {total - active}")
print()

failed = False

for branch in Branch.objects.order_by("id"):

    errors = []

    if not branch.name:
        errors.append("Missing name")

    if not branch.code:
        errors.append("Missing code")

    if not branch.address:
        errors.append("Missing address")

    if not branch.phone:
        errors.append("Missing phone")

    if errors:

        failed = True

        print(f"[FAIL] Branch {branch.id}")

        for err in errors:
            print(f"   - {err}")

    else:

        status = "Active" if branch.is_active else "Inactive"

        print(f"[OK] {branch.id} - {branch.name} ({status})")

print()
print("=" * 50)

if total == 0:
    print("[FAIL] No branches found.")
    sys.exit(1)

if failed:
    print("[FAIL] Branch validation failed.")
    sys.exit(1)

print("[OK] All branches verified successfully.")
sys.exit(0)