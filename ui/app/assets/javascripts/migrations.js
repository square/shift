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

var popoverActive = false;
function makeStatsPopover() {
    $("#table_stats").popover({
        animation: false,
        html: true,
        title: "Table Stats",
        trigger: "hover"
    });
    $("#table_stats").on("show.bs.popover", function() {
        popoverActive = true;
    });
    $("#table_stats").on("hide.bs.popover", function() {
        popoverActive = false;
    });
    if (popoverActive) {
        $("#table_stats").popover("show");
    }

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

    $("#migration_request_submit").click(function(event){
      alertOnDdl("_migration_request_ddl_statement", "submit-migration-form")
    });

    // function to run on migration detail page
    if ($("#migration-detail").length) {
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
                    makeStatsPopover();
                },
                error: function(data) {
                  if (data.status == 404) {
                    clearInterval(interval);
                  }
                },
                async: true,
            });
        }, 15000);
    };

    makeStatsPopover();
})
