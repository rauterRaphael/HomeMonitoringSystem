from django.db import models

# Create your models here.
class SensorData(models.Model):
    id              = models.AutoField(primary_key=True)
    fromNodeID      = models.IntegerField(default=0)
    timeCreated     = models.DateTimeField(auto_now_add=True)
    lightIntensity  = models.FloatField()
    temperature     = models.FloatField()
    batteryLevel    = models.FloatField()
    
    def __str__(self) -> str:
        return str(self.fromNodeID) + " - " + str(self.timeCreated)

class SensorNode(models.Model):
    id          = models.AutoField(primary_key=True)
    timeCreated = models.DateTimeField(auto_now_add=True)
    updated_at  = models.DateTimeField()
    nodeId      = models.IntegerField(default=0)
    rssi        = models.FloatField()
    motionDetected = models.IntegerField(default=0)

    def __str__(self) -> str:
        return str(self.nodeId) + " - " + str(self.updated_at)