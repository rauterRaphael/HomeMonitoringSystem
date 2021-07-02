from django.contrib import admin
from django.urls import include, path

from . import views

app_name = 'dashboard'
urlpatterns = [
    path('', views.dashboardView, name='index'),

    path('nodestatus', views.getNodeStatus, name='nodestatus'),
    path('nodedata', views.getNodeData, name='nodedata'),
    path('nodeswthdata', views.getNodesWithData, name='nodeswthdata')
]