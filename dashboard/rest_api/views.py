from django.shortcuts import render

from rest_framework import viewsets

from .models import SensorNode
from .models import SensorData

from .serializers import SensorNodeSerializer
from .serializers import SensorDataSerializer

class SensorNodeViewSet(viewsets.ModelViewSet):
    queryset = SensorNode.objects.all().order_by('id')
    serializer_class = SensorNodeSerializer

class SensorDataViewSet(viewsets.ModelViewSet):
    queryset = SensorData.objects.all().order_by('id')
    serializer_class = SensorDataSerializer
