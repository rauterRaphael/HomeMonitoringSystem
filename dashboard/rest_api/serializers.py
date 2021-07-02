from rest_framework import serializers

from .models import SensorNode
from .models import SensorData

class SensorNodeSerializer(serializers.HyperlinkedModelSerializer):
    class Meta:
        model = SensorNode
        fields = ('nodeId', 'rssi', 'updated_at', 'motionDetected')

class SensorDataSerializer(serializers.HyperlinkedModelSerializer):
    class Meta:
        model = SensorData
        fields = ('fromNodeID', 'lightIntensity', 'temperature', 'batteryLevel')

