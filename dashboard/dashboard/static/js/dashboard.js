$(document).ready(function () {
    $('#nodesWithData').change(function () {
        nodeSelected = parseInt($(this).val());
        renderNewGraph();
    });
});

var chartInit = false;
var nodeSelected = 0;
var nodePlotted  = 0;
var lightChart;
var tempChart;
var battChart;
var oldData;
var toggle = 0;

nodeSelected = 1;
renderNewGraph();

$(function () {
    getNodeStatus();
    getNodesWithData();
});

function getNodeStatus() {
    $.ajax({
        url: 'nodestatus',
        success: function (data) {
            var html = '';
            var row = '';
            for (var i = 0; i < data.nodes.length; i++) {
                var row = '';
                if (data.nodes[i].color == 0)
                    if((data.nodes[i].motion == 1 && toggle == 0) || data.nodes[i].motion == 0)
                        row += '<tr class="table-success"><td>';
                    else
                        row += '<tr class="table-light"><td>';
                else if (data.nodes[i].color == 1)
                    if((data.nodes[i].motion == 1 && toggle == 0) || data.nodes[i].motion == 0)
                        row += '<tr class="table-warning"><td>';
                    else
                        row += '<tr class="table-light"><td>';
                else if (data.nodes[i].color == 2)
                    row += '<tr class="table-danger"><td>';
                else
                    row += '<tr class="table-light"><td>';


                row += data.nodes[i].nodeID + '</td><td>' + data.nodes[i].updatedAt + '</td><td>' + data.nodes[i].rssi + '</td></tr>';
                html += row;
            }
            toggle = !toggle;
            $("#statustable tbody").html(html);

        }
    });
    setTimeout("getNodeStatus()", 500);
};

function renderNewGraph() {
    $.ajax({
        url: "nodedata",
        success: function (data) {
            for (var i = 0; i < data.data.length; i++) {
                if (data.data[i].nodeId == nodeSelected) {
                    if(_.isEqual(data.data, oldData) && nodeSelected == nodePlotted)
                        break;
                    if(chartInit == true){
                        lightChart.destroy();
                        tempChart.destroy();
                        battChart.destroy();
                    }
                    var lightChartctx = document.getElementById('lightChart').getContext('2d');
                    var tempChartctx = document.getElementById('tempChart').getContext('2d');
                    var battChartctx = document.getElementById('battChart').getContext('2d');
                    const lightData = {
                        labels: data.data[i].label,
                        datasets: [{
                            label: 'Light Intensity',
                            data: data.data[i].lightIntensity,
                            fill: true,
                            borderColor: 'rgb(75, 75, 192)',
                            tension: 0.1
                        }]
                    };
                    const tempData = {
                        labels: data.data[i].label,
                        datasets: [{
                            label: 'Temperature',
                            data: data.data[i].temperature,
                            fill: true,
                            borderColor: 'rgb(75, 192, 192)',
                            tension: 0.1
                        }]
                    };
                    const battData = {
                        labels: data.data[i].label,
                        datasets: [{
                            label: 'Battery Level',
                            data: data.data[i].battLevel,
                            fill: true,
                            borderColor: 'rgb(192, 75, 102)',
                            tension: 0.1
                        }]
                    };
                    lightChart = new Chart(lightChartctx, {
                        type: 'line',
                        data: lightData,
                    });
                    tempChart = new Chart(tempChartctx, {
                        type: 'line',
                        data: tempData,
                    });
                    battChart = new Chart(battChartctx, {
                        type: 'line',
                        data: battData,
                    });
                    chartInit = true;
                    oldData = data.data;
                    nodePlotted = nodeSelected;
                    break;
                }
            }
        }
    });
    setTimeout("renderNewGraph()", 5000);
};

function getNodesWithData() {
    $.ajax({
        url: 'nodeswthdata',
        success: function (data) {
            var sel = $("#nodesWithData");
            sel.empty();
            for (var i = 0; i < data.nodes.length; i++)
                if(data.nodes[i][0] == nodeSelected)
                    sel.append('<option selected value="' + data.nodes[i][0] + '">' + data.nodes[i][1] + '</option>');
                else
                    sel.append('<option value="' + data.nodes[i][0] + '">' + data.nodes[i][1] + '</option>');
        }
    });
    setTimeout("getNodesWithData()", 5000);
};

