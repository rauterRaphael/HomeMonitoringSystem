from django.shortcuts import render

from django.http import JsonResponse
from django.http import Http404

from django.contrib.auth.decorators import login_required

from rest_api.models import SensorNode
from rest_api.models import SensorData

from copy import deepcopy

from datetime import datetime

#@login_required
def dashboardView(request):
    return render(request, "dashboard.html")

def getColorCodeForEntry(lastUpdated):
    tz_info = lastUpdated.tzinfo
    diff    = datetime.now(tz_info)-lastUpdated
    seconds = diff.total_seconds()
    if seconds < 120:
        return 0, str(int(seconds)) + " seconds ago"
    elif seconds < 240:
        return 1, str(int(seconds)) + " seconds ago"
    elif seconds < 3600: 
        return 2, "more than 240 seconds ago"
    else: 
        return 3, "Node not active recently"

def getNodeStatus(request):
    nodes = []
    tableEntry = {
        "nodeID": 0,
        "updatedAt": 0,
        "rssi": 0,
        "motion": 0,
        "color": 0,
    }

    lastNodeEntries = []
    allNodes = SensorNode.objects.all()

    for node in allNodes:
        tz_info = node.timeCreated.tzinfo
        diff    = datetime.now(tz_info)-node.timeCreated
        seconds = diff.total_seconds()
        if seconds > 86400 * 31:
            node.delete()

    allNodes = SensorNode.objects.all()
    if allNodes is not None:
        allIds = list(dict.fromkeys([item.nodeId for item in allNodes]))
        for nodeId in allIds:
            lastNodeEntries.append((nodeId, max([item.id for item in allNodes if item.nodeId == nodeId])))

        for entry in sorted(lastNodeEntries, key=lambda tup: tup[0]):
            nodeEntry = SensorNode.objects.get(id=entry[1])
            tableEntry["nodeID"] = nodeEntry.nodeId
            tableEntry["rssi"] = nodeEntry.rssi
            tableEntry["motion"] = nodeEntry.motionDetected
            tableEntry["color"], tableEntry["updatedAt"] = getColorCodeForEntry(nodeEntry.timeCreated)
            nodes.append(deepcopy(tableEntry))

    nodeStatus = {"nodes": nodes}
    return JsonResponse(nodeStatus)

def getNodesWithData(request):
    nodes = []
    
    allData = SensorData.objects.all()

    for entry in allData:
        tz_info = entry.timeCreated.tzinfo
        diff    = datetime.now(tz_info)-entry.timeCreated
        seconds = diff.total_seconds()
        if seconds > 86400 * 31:
            entry.delete()

    allData = SensorData.objects.all()
    if allData is not None:
        nodes = list(dict.fromkeys([item.fromNodeID for item in allData]))
        nodes = [(item, "Node " + str(item)) for item in nodes]

    nodeStatus = {"nodes": nodes}
    return JsonResponse(nodeStatus)


def getNodeData(request):
    nodeData = {}
    plotData = []

    allData = SensorData.objects.all()
    if allData is not None:
        nodes = list(dict.fromkeys([item.fromNodeID for item in allData]))

        allData = SensorData.objects.all()

        for node in nodes:
            data = [item for item in allData if item.fromNodeID == node]
            nodeDataEntry = {
                "nodeId": node,
                "label": [],
                "lightIntensity": [],
                "temperature": [],
                "battLevel": []
            }
            for idx, dat in enumerate(data):
                tz_info = dat.timeCreated.tzinfo
                diff    = datetime.now(tz_info)-dat.timeCreated
                seconds = diff.total_seconds()
                #nodeDataEntry["label"].append(-len(data)+idx+1)
                #nodeDataEntry["label"].append(-int(seconds))
                nodeDataEntry["label"].append(dat.timeCreated.strftime("%d.%m-%H:%M"))
                nodeDataEntry["lightIntensity"].append(dat.lightIntensity)
                nodeDataEntry["temperature"].append(dat.temperature)
                nodeDataEntry["battLevel"].append(dat.batteryLevel)
            plotData.append(deepcopy(nodeDataEntry))

    nodeData = {"data": plotData}
    return JsonResponse(nodeData)