from django.contrib import admin
from django.urls import include, path

from rest_framework import routers
from . import views

router = routers.DefaultRouter()
router.register(r'node', views.SensorNodeViewSet, basename='node')
router.register(r'data', views.SensorDataViewSet, basename='data')

app_name = 'rest_api'
urlpatterns = [
    path('', include(router.urls), name='index'),
    path('api-auth/', include('rest_framework.urls', namespace='rest_framework'))
]