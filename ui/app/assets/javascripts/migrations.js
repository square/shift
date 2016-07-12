// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

function progress(percent, $element) {
    var progressBarWidth = percent * $element.width() / 100;
    $element.find('div')
        .animate({ width: progressBarWidth }, 500)
        .html(percent + "%&nbsp;");
}

function setProgress() {
    $(".progressBar").each(function(){
        var bar = $(this);
        var valor = Number(bar.attr("data-value"));
        progress(valor, bar);
    });
}

function toggleFilter() {
  if ($("#filters").is(":visible")) {
    $("#toggle_filter").html("show filters");
  } else {
    $("#toggle_filter").html("hide filters");
  };

  $("#filters").slideToggle( "fast", function() {});
}

function applyFilters() {
  var requestor = $("#requestor_filter option:selected").text();
  var cluster = $("#cluster_filter option:selected").text();
  var ddl_statement = $("#ddl_statement_filter").val();
  var params = "";

  if (requestor !== "" || cluster !== "" || ddl_statement !== "") {
    if (cluster !== "") {
      params += "&cluster=" + cluster;
    }
    if (requestor !== "") {
      params += "&requestor=" + requestor;
    }
    if (ddl_statement !== "") {
      params += "&ddl_statement=" + encodeURIComponent(ddl_statement);
    }
  }

  if (params === "") {
    window.location.href = '/';
  } else {
    document.location.search = params;
  }
}

function postComment(author, comment, migration_id) {
    $.ajax({
        method: "POST",
        url: "/comments",
        data: {
            author: author,
            comment: comment,
            migration_id: migration_id,
        },
        success: function(result) {
            location.reload();
        },
        error: function(data) {
        },
        async: true
    });
}

var tableStatsTemplate = '<table class="table">\
    <thead>\
        <tr>\
        <th class="text-center">Most Recent Alter Date</th>\
        <th class="text-center">Most Recent Alter Duration</th>\
        <th class="text-center">Average Alter Duration</th>\
        </tr>\
    </thead>\
    <tbody>\
        <tr>\
        <td class="text-center">@last_alter_date</td>\
        <td class="text-center">@last_alter_duration</td>\
        <td class="text-center">@average_alter_duration</td>\
        </tr>\
    </tbody>\
</table>'
function makeStatsPopover(popoverData) {
    var content;
    if (popoverData.last_alter_date == null) {
        content = '<div id="table_stats_loading"></div>'
    } else {
        content = tableStatsTemplate.replace("@last_alter_date", popoverData.last_alter_date)
            .replace("@last_alter_duration", popoverData.last_alter_duration)
            .replace("@average_alter_duration", popoverData.average_alter_duration)
    }
    $("#table_stats").popover({
        animation: false,
        html: true,
        title: "Table Stats",
        trigger: "hover",
        content: content
    });
    $("#table_stats").on("show.bs.popover", function() {
        popoverData.active = true;
    });
    $("#table_stats").on("shown.bs.popover", function() {
        new Spinner({color: "#1a2125", scale: 0.75, width: 4, top: "65%", zIndex: 1})
            .spin(document.getElementById("table_stats_loading"));
    })
    $("#table_stats").on("hide.bs.popover", function() {
        popoverData.active = false;
    });
    if (popoverData.active) {
        $("#table_stats").popover("show");
    }
}

function getTableStatsData(popoverData) {
    $.ajax({
        method: "GET",
        url: "/migrations/" + $("#migration-id").html() + "/table_stats",
        success: function(result) {
            popoverData.last_alter_date = result.last_alter_date;
            popoverData.last_alter_duration = isNaN(result.last_alter_duration) ? result.last_alter_duration : toHHMMSS(result.last_alter_duration);
            popoverData.average_alter_duration = isNaN(result.average_alter_duration) ? result.average_alter_duration : toHHMMSS(result.average_alter_duration);
            $("#table_stats").data("bs.popover").options.content = tableStatsTemplate
                .replace("@last_alter_date", popoverData.last_alter_date)
                .replace("@last_alter_duration", popoverData.last_alter_duration)
                .replace("@average_alter_duration", popoverData.average_alter_duration)
            if (popoverData.active) {
                $("#table_stats").popover("show")
            }
        }
    })
}

$(document).ready(function() {
    setProgress();
    $("[id$=_migration_request_cluster_name]").change(function(event){
        $.ajax({
            method: "GET",
            url: "/databases",
            data: {
                cluster: this.value
            },
            success: function(result) {
                result = result.databases;
                var selectTag = $("[id$=_migration_request_database]");
                selectTag.empty();
                selectTag.append($('<option/>'));
                result.forEach(function(database) {
                    selectTag.append($('<option/>').text(database));
                });
                selectTag.select2("val", "");
            },
            error: function(data) {
            },
            async: true
        });
    });

    $("#toggle_filter").click(function(event){
        toggleFilter();
    });

    $("#ddl_statement_filter").keyup(function(e) {
        if (e.which == 13) {
            applyFilters();
        }
    });

    $("#apply_filter").click(function() {
      applyFilters();
    });

    $("[id$=_migration_request_ddl_statement]").keyup(function(event){
        validateDdl("_migration_request_ddl_statement");
    });

    $("[id$=_migration_request_final_insert]").keyup(function(event){
        validateFinalInsert("_migration_request_final_insert");
    });

    $('.select-search').select2({
        placeholder: "",
        allowClear: true,
    });

    $("#post_comment").click(function(event){
        var author = $("#comment_field").attr("author");
        var comment = $("#comment_field").val();
        var migration_id = $("#comment_field").attr("migration_id");
        if (comment.length > 0) {
            postComment(author, comment, migration_id);
        };
    });

    $("#custom_options").on('shown.bs.collapse', function() {
        $("#custom_options_expand_icon").removeClass("glyphicon-chevron-down").addClass("glyphicon-chevron-up")
        $("#custom_options_expand_text").text("collapse")
    })

    $("#custom_options").on('hidden.bs.collapse', function() {
        $("#custom_options_expand_icon").removeClass("glyphicon-chevron-up").addClass("glyphicon-chevron-down")
        $("#custom_options_expand_text").text("expand")
    })

    $("#migration_request_submit").click(function(event){
      alertOnDdl("_migration_request_ddl_statement", "submit-migration-form")
    });

    // function to run on migration detail page
    if ($("#migration-detail").length) {
        var popoverData = {
            "active": false,
            "last_alter_date": null,
            "last_alter_duration": null,
            "average_alter_duration": null
        }
        // refresh the migration details every 15 seconds
        var interval = setInterval(function refreshDetail() {
            var previousPercent = parseInt($(".progressBar").attr("data-value"));
            var previousStatus = parseInt($(".progressBar").attr("status"));
            var migrationId = $("#migration-id").html();

            // stop refreshing when the migration is either done or canceled
            if ((previousStatus === 8) || (previousStatus === 9)) {
                clearInterval(interval);
                return;
            }

            $.ajax({
                url: location.protocol + "//" + location.host + "/migrations/" +
                     migrationId + "/refresh_detail",
                dataType: 'json',
                success: function(result) {
                    // don't refresh the whole partial if the status hasn't changed
                    if (previousStatus !== result["status"]) {
                        $("#migration-detail").html(result["detailPartial"]);
                        setProgress();
                    // don't update the copy percentage if it hasn't changed
                    } else if (previousPercent !== result["copy_percentage"]) {
                        var bar = $(".progressBar");
                        var valor = Number(result["copy_percentage"]);
                        progress(valor, bar);
                    }
                    makeStatsPopover(popoverData);
                },
                error: function(data) {
                  if (data.status == 404) {
                    clearInterval(interval);
                  }
                },
                async: true,
            });
        }, 15000);
        getTableStatsData(popoverData);
        makeStatsPopover(popoverData);
    };
})
