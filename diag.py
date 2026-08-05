import os
from django.template import engines
engine = engines['django']
template = engine.get_template('face_recognition_app/analytics_dashboard.html')
print('Origin:', template.template.origin.name)
print('Size:', os.path.getsize(template.template.origin.name))
with open(template.template.origin.name) as f:
    c = f.read()
print('Has default:', '|default:"0"' in c)
