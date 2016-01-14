// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

// disable or enable links in the bulk action dropdown menu depending
// on which (if any) migrations are selected
function updateActionList() {
    var all_actions = new Array();
    var migration_actions = new Array();
    $(".migration-checkbox").each(function() {
        if (this.checked) {
            var actions = $(this).closest("tr").find(".label").data("actions");
            migration_actions.push(actions);
            all_actions = $.merge(all_actions, actions);
        }
    });
    all_actions = $.unique(all_actions);

    if (all_actions.length === 0) {
        // don't allow any actions if no migrations are checked
        $("#bulk_action_menu_list").children("li").each(function (){
            $(this).children("span").removeClass("enabled").addClass("disabled");
        });
    } else {
        // only allow actions that are common among all the checked migrations
        var common_actions = migration_actions.shift().filter(function(v) {
            return migration_actions.every(function(a) {
                return a.indexOf(v) !== -1;
            });
        });

        $("#bulk_action_menu_list").children("li").each(function (){
            var action = parseInt($(this).attr("action"));
            if ($.inArray(action, common_actions) !== -1) {
                $(this).children("span").removeClass("disabled").addClass("enabled");
            } else {
                $(this).children("span").removeClass("enabled").addClass("disabled");
            }
        });
    }
}

function performBulkAction(action, migs) {
    $.ajax({
        method: "POST",
        url: window.location.href + "/bulk_action",
        dataType: 'json',
        contentType: 'application/json',
        data: JSON.stringify({
            bulk_action: action,
            migrations: migs,
        }),
        success: function(result) {
            if (result["error"] == true) {
                localStorage.setItem("error", "1");
            } else {
                localStorage.setItem("error", "0");
            }
            location.reload();
        },
        error: function(data) {
            localStorage.setItem("error", "1");
            location.reload();
        },
    });
}

function alertOnBulkStart(action, migs) {
    var alertMsg = "IMPORTANT: Starting migrations via bulk action queues them up to be run automatically. " +
      "If migrations belong to different clusters, they will run in parallel. If migrations " +
      "belong to the same cluster, they will be run sequentially starting with the oldest first " +
      "(since only one migration per cluster is allowed to run at a time). " +
      "Running migrations this way means that, unless you intervene to stop them (by dequeuing " +
      "them, canceling them, etc.), enqueued migrations will run start to finish entirely on their " +
      "own. There is obviously risk in this, so please be careful.<br/><br/>" +
      "As always, contact and admin if you have any questions.";
    event.preventDefault();
    $.confirm({
        title: 'WARNING',
        content: alertMsg,
        confirmButton: 'Continue',
        confirmButtonClass: 'btn-default',
        cancelButton: 'Go Back',
        cancelButtonClass: 'btn-info',
        animationSpeed: 200,
        animation: 'scale',
        animationBounce: 2.5,
        confirm: function(){
          // perform the bulk action
          performBulkAction(action, migs);
        },
        cancel: function(){
        }
    });
}

$(document).ready(function() {
    if (localStorage.getItem("error") == "1") {
        $("#bulk_error").show();
    }
    if (localStorage.getItem("error") == "0") {
        $("#bulk_success").show();
    }
    localStorage.removeItem("error")

    $("#clusters_selector").change(function(event, params){
        if (params.selected) {
            var cluster = params.selected;
            $.ajax({
                method: "GET",
                url: "/databases",
                data: {
                    cluster: cluster,
                },
                success: function(result) {
                    result = result.databases;
                    var selectTag = $("#databases_selector");
                    var optgroup = $('<optgroup cluster="' + cluster +'" class="db-optgroup">');
                    optgroup.attr('label', cluster);
                    result.forEach(function(database) {
                        optgroup.append($('<option value="' + cluster +':' + database +
                                          '" class="db-option"/>').text(database)); });
                        selectTag.append(optgroup);
                },
                error: function(data) {
                },
                async: true
            });
        } else if (params.deselected) {
            $("optgroup[cluster='" + params.deselected + "']").remove();
        }
    });

    $(".chosen-select").chosen({
        search_contains: true,
        placeholder_text_multiple: " ",
    });

    $("#databases_selector").change(function() {
        $( "#databases_selector option:selected" ).each(function() {
            $(this).addClass("highlighted");
        });
    });

    $("#ddl_statement").keyup(function(event){
        validateDdl("ddl_statement");
    });

    $("#final_insert").keyup(function(event){
        validateFinalInsert("final_insert");
    });

    $("#meta_request_submit").click(function(event){
        alertOnDdl("ddl_statement", "submit-meta-request-form")
    });

    $("#select_all").change(function(event){
        if(this.checked) {
            $(".migration-checkbox").prop("checked", true);
        } else {
            $(".migration-checkbox").prop("checked", false);
        }

        updateActionList();
    });

    $(".migration-checkbox").change(function(event){
        updateActionList();
    });

    $("#bulk_action_menu_list > li > span").click(function(event){
        if ($(this).hasClass("enabled")) {
            var action = $(this).parent().attr("action");
            var action_name = $.trim($(this).html());

            var migs = new Array();
            $(".migration-checkbox").each(function() {
                if (this.checked) {
                    var mig_id = $(this).closest("tr").find(".label").attr("mig_id");
                    var lock_version = $(this).closest("tr").find(".label").attr("lock_version");
                    migs.push({"id": mig_id, "lock_version": lock_version});
                }
            });

            if (action_name == "start" || action_name == "resume") {
                alertOnBulkStart(action, migs)
            } else {
                performBulkAction(action, migs);
            }
        }
    });
})
