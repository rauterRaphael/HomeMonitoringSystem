from django.contrib import admin
from .models import SensorNode
from .models import SensorData

admin.site.register(SensorNode)
admin.site.register(SensorData)