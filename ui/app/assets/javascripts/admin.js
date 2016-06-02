// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

var spinner;

function drawFiledCompletedChart(data) {
    $("#filed_completed_chart").highcharts({
        chart: {
            type: "line"
        },
        title: {
            text: null
        },
        xAxis: {
            title: {
                text: "Date"
            },
            categories: data.categories
        },
        yAxis: {
            title: {
                text: "# of Migrations"
            },
            allowDecimals: false,
            floor: 0,
            minRange: 18
        },
        tooltip: {
            shared: true,
            crosshairs: true
        },
        lang: {
            noData: "no data"
        },
        series: [{
            name: "Filed",
            data: data.migrations_filed
        },{
            name: "Completed",
            data: data.migrations_completed
        }],
        credits: {
            enabled: false
        },
        plotOptions: {
            line: {
                softThreshold: false
            }
        }
    });
}

function updateFiledCompletedChart(weeks) {
    $.ajax({
        method: "GET",
        url: "/admin/refresh_filed_chart",
        data: {
            weeks: weeks
        },
        success: function(result) {
            drawFiledCompletedChart(result);
        }
    });
}

function drawApprovalTimeChart(data) {
    $("#approval_time_chart").highcharts({
        chart: {
            type: "line"
        },
        title: {
            text: null
        },
        xAxis: {
            title: {
                text: "Date"
            },
            categories: data.categories
        },
        yAxis: {
            title: {
                text: "Hours"
            },
            allowDecimals: false,
            floor: 0,
        },
        tooltip: {
            crosshairs: true,
            valueSuffix: " hours"
        },
        series: [{
            name: "Average Time",
            data: data.average_approval_times,
            connectNulls: true
        }],
        credits: {
            enabled: false
        }
    });
}

function updateApprovalTimeChart(weeks) {
    $.ajax({
        method: "GET",
        url: "/admin/refresh_approval_time_chart",
        data: {
            weeks: weeks
        },
        success: function(result) {
            drawApprovalTimeChart(result);
        }
    });
}

function updateMetrics(cluster) {
    $("#cluster_metrics_table").find("tbody").empty();
    $("#cluster_metrics_error").remove();
    spinner.spin($("#spinner_target")[0])
    $.ajax({
        method: "GET",
        url: "/admin/refresh_cluster_metrics",
        data: {
            cluster: cluster
        },
        success: function(result) {
            var tbody = $("#cluster_metrics_table").find("tbody")
            for (var db in result) {
                var first = true;
                for (var table in result[db]) {
                    var data = result[db][table]
                    var row = $("<tr>");
                    if (first) {
                        row.append($("<td>").text(db));
                        first = false;
                    } else {
                        row.append($("<td>"));
                    }
                    row.append($("<td>").text(table))
                    row.append($("<td>").text(data.times_altered))
                    row.append($("<td>").text(toHHMMSS(data.average_alter_time)))
                    row.append($("<td>").text(toHHMMSS(data.max_alter_time)))
                    row.append($("<td>").text(toHHMMSS(data.min_alter_time)))

                    tbody.append(row);
                }
            }
            spinner.stop();
        },
        error: function(data) {
            $("#cluster_metrics_table").after($("<p>")
                .text("Error loading data")
                .addClass("text-center")
                .attr("id", "cluster_metrics_error"));
            spinner.stop();
        }
    })
}

function toHHMMSS(sec) {
    var sec_num = parseInt(sec, 10);
    var hours   = Math.floor(sec_num / 3600);
    var minutes = Math.floor((sec_num - (hours * 3600)) / 60);
    var seconds = sec_num - (hours * 3600) - (minutes * 60);

    if (hours   < 10) {hours   = "0" + hours;}
    if (minutes < 10) {minutes = "0" + minutes;}
    if (seconds < 10) {seconds = "0" + seconds;}
    return hours+':'+minutes+':'+seconds;
}

$(document).ready(function(){

    spinner = new Spinner({color: "#1a2125", position: "relative", zIndex: 0});
    updateFiledCompletedChart($("#filed_completed_chart_control").val());
    updateApprovalTimeChart($("#approval_time_chart_control").val());
    $("#filed_completed_chart_control").change(function(event) {
        updateFiledCompletedChart(this.value);
    });
    $("#approval_time_chart_control").change(function(event) {
        updateApprovalTimeChart(this.value);
    })
    $("#cluster_filter_dropdown").change(function(event) {
        updateMetrics(this.value);
    });
    $(".select-menu").select2({
        allowClear: false,
        minimumResultsForSearch: Infinity
    });
    $('.select-search').select2({
        placeholder: "",
        allowClear: true,
    });
})