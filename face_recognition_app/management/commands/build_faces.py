"""
face_recognition_app/management/commands/build_faces.py

Rebuilds customer_embeddings.pkl using real InsightFace embeddings
instead of just storing customer info + image paths.

Usage:
    python manage.py build_faces
    python manage.py build_faces --customer-id 42       # rebuild a single customer
"""

from django.core.management.base import BaseCommand, CommandError

from customers.models import Customer
from face_recognition_app.services.face_service import FaceService


class Command(BaseCommand):

    help = "Build customer face database with real InsightFace embeddings"

    def add_arguments(self, parser):
        parser.add_argument(
            "--customer-id",
            type=int,
            default=None,
            help="Only (re)build the embedding for a single customer ID.",
        )

    def handle(self, *args, **options):
        customer_id = options["customer_id"]

        face_service = FaceService.get_instance()

        # Merge with existing records so rebuilding one customer doesn't
        # wipe out everyone else's embedding.
        existing_records = {}
        face_service.reload_database()
        for record in face_service._database:  # noqa: SLF001 (internal reuse is intentional)
            existing_records[record["customer_id"]] = record

        if customer_id is not None:
            customers = Customer.objects.filter(id=customer_id)
            if not customers.exists():
                raise CommandError(f"No customer found with id={customer_id}")
        else:
            customers = Customer.objects.all()

        self.stdout.write("\nBuilding customer database...\n")

        processed = 0
        skipped = 0

        for customer in customers:
            if not customer.image:
                self.stdout.write(
                    self.style.WARNING(f"Skipped: {customer.name} (No Image)")
                )
                skipped += 1
                continue

            image_path = customer.image.path
            embedding = face_service.get_embedding_from_path(image_path)

            if embedding is None:
                self.stdout.write(
                    self.style.WARNING(f"Skipped: {customer.name} (No face detected in image)")
                )
                skipped += 1
                continue

            existing_records[customer.id] = {
                "customer_id": customer.id,
                "customer_name": customer.name,
                "phone": customer.phone,
                "vip": customer.is_vip,
                "embedding": embedding,
            }

            processed += 1
            self.stdout.write(self.style.SUCCESS(f"Added: {customer.name}"))

        final_records = list(existing_records.values())
        face_service.save_database(final_records)

        self.stdout.write(self.style.SUCCESS("\n======================================="))
        self.stdout.write(self.style.SUCCESS("Customer database created successfully!"))
        self.stdout.write(self.style.SUCCESS(f"Processed this run: {processed}, skipped: {skipped}"))
        self.stdout.write(self.style.SUCCESS(f"Total records saved: {len(final_records)}"))
        self.stdout.write(self.style.SUCCESS(f"Database file:\n{face_service.embeddings_path}"))
        self.stdout.write(self.style.SUCCESS("=======================================\n"))
