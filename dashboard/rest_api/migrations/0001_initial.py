# Generated by Django 3.2.4 on 2021-06-28 09:00

from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
    ]

    operations = [
        migrations.CreateModel(
            name='SensorData',
            fields=[
                ('id', models.AutoField(primary_key=True, serialize=False)),
                ('fromNodeID', models.IntegerField(default=0)),
                ('timeCreated', models.DateTimeField(auto_now_add=True)),
                ('lightIntensity', models.FloatField()),
                ('temperature', models.FloatField()),
                ('batteryLevel', models.FloatField()),
            ],
        ),
        migrations.CreateModel(
            name='SensorNode',
            fields=[
                ('id', models.AutoField(primary_key=True, serialize=False)),
                ('nodeId', models.IntegerField(default=0)),
                ('rssi', models.FloatField()),
            ],
        ),
    ]